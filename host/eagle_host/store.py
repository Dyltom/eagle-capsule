"""SQLite index (chunks, time anchors, transcripts + FTS5) and the daily Markdown rollup."""
from __future__ import annotations

import sqlite3
import time
from datetime import datetime
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS chunks (
    device_id     TEXT    NOT NULL,
    seq           INTEGER NOT NULL,
    boot_id       INTEGER NOT NULL,
    start_mono_ms INTEGER NOT NULL,
    start_utc_ms  INTEGER,                 -- NULL when the time could not be recovered
    time_source   TEXT    NOT NULL,        -- device | reconciled | unknown
    day           TEXT    NOT NULL,        -- YYYY-MM-DD (local) or 'undated'
    duration_ms   INTEGER NOT NULL,
    codec         TEXT    NOT NULL,
    sample_rate   INTEGER NOT NULL,
    bitrate       INTEGER NOT NULL,
    speech_ratio  REAL    NOT NULL,
    vad_bits      TEXT    NOT NULL,        -- '0101...' one char per second
    sha256        TEXT    NOT NULL,        -- of the encrypted file as stored on the device
    path          TEXT    NOT NULL,        -- relative to the data dir
    imported_at   INTEGER NOT NULL,
    PRIMARY KEY (device_id, seq)
);
CREATE INDEX IF NOT EXISTS chunks_day ON chunks(day, start_utc_ms);
CREATE TABLE IF NOT EXISTS anchors (       -- (boot, monotonic) <-> UTC pairs learned at sync time
    device_id TEXT NOT NULL, boot_id INTEGER NOT NULL, mono_ms INTEGER NOT NULL, utc_ms INTEGER NOT NULL,
    PRIMARY KEY (device_id, boot_id, mono_ms)
);
CREATE TABLE IF NOT EXISTS transcripts (
    id         INTEGER PRIMARY KEY,
    device_id  TEXT NOT NULL,
    seq        INTEGER NOT NULL,
    engine     TEXT NOT NULL,
    status     TEXT NOT NULL,               -- done | untranscribed | error
    language   TEXT,
    text       TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    UNIQUE (device_id, seq, engine)
);
CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(text, content='transcripts', content_rowid='id');
CREATE TRIGGER IF NOT EXISTS transcripts_ai AFTER INSERT ON transcripts BEGIN
    INSERT INTO transcripts_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS transcripts_ad AFTER DELETE ON transcripts BEGIN
    INSERT INTO transcripts_fts(transcripts_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;
"""


class Index:
    def __init__(self, path: Path) -> None:
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    def close(self) -> None:
        self.db.close()

    # ------------------------------------------------------------ time
    def add_anchor(self, device_id: str, boot_id: int, mono_ms: int, utc_ms: int) -> None:
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO anchors VALUES (?,?,?,?)", (device_id, boot_id, mono_ms, utc_ms))

    def resolve_utc(self, device_id: str, boot_id: int, mono_ms: int, device_utc_ms: int) -> tuple[int | None, str]:
        """Device-stamped UTC wins; else project from the nearest anchor in the same boot."""
        if device_utc_ms:
            return device_utc_ms, "device"
        row = self.db.execute(
            "SELECT mono_ms, utc_ms FROM anchors WHERE device_id=? AND boot_id=? ORDER BY ABS(mono_ms-?) LIMIT 1",
            (device_id, boot_id, mono_ms)).fetchone()
        if row:
            return row["utc_ms"] - (row["mono_ms"] - mono_ms), "reconciled"
        return None, "unknown"

    # ------------------------------------------------------------ chunks
    def chunk_sha(self, device_id: str, seq: int) -> str | None:
        row = self.db.execute("SELECT sha256 FROM chunks WHERE device_id=? AND seq=?", (device_id, seq)).fetchone()
        return row["sha256"] if row else None

    def add_chunk(self, row: dict, transcript: tuple[str, str, str, str | None]) -> None:
        engine, status, text, lang = transcript
        now = int(time.time())
        with self.db:  # one transaction: the chunk is either fully indexed or not at all
            self.db.execute(f"INSERT INTO chunks ({','.join(row)}, imported_at) VALUES ({','.join('?' * len(row))}, ?)",
                            (*row.values(), now))
            self.db.execute("INSERT INTO transcripts (device_id, seq, engine, status, language, text, created_at) "
                            "VALUES (?,?,?,?,?,?,?)", (row["device_id"], row["seq"], engine, status, lang, text, now))

    def search(self, query: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT c.*, t.text FROM transcripts_fts f JOIN transcripts t ON t.id = f.rowid "
            "JOIN chunks c ON c.device_id = t.device_id AND c.seq = t.seq WHERE transcripts_fts MATCH ? "
            "ORDER BY c.start_utc_ms", (query,)).fetchall()

    def day_rows(self, day: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT c.*, t.status, t.text FROM chunks c LEFT JOIN transcripts t "
            "ON t.device_id = c.device_id AND t.seq = c.seq WHERE c.day = ? "
            "ORDER BY c.start_utc_ms, c.boot_id, c.start_mono_ms", (day,)).fetchall()


def write_rollup(index: Index, data_dir: Path, day: str, tz=None) -> Path:
    rows = index.day_rows(day)
    folder = data_dir / "undated" if day == "undated" else data_dir / day.replace("-", "/")
    folder.mkdir(parents=True, exist_ok=True)
    total_s = sum(r["duration_ms"] for r in rows) / 1000
    speech_s = sum(r["duration_ms"] * r["speech_ratio"] for r in rows) / 1000
    lines = [f"# {day}", "",
             f"{len(rows)} chunks, {total_s / 60:.1f} min recorded, ~{speech_s / 60:.1f} min with speech.", "",
             "| Time | Length | Speech | Clock | Audio | Transcript |", "|---|---|---|---|---|---|"]
    for r in rows:
        when = (datetime.fromtimestamp(r["start_utc_ms"] / 1000, tz).strftime("%H:%M:%S")
                if r["start_utc_ms"] is not None else f"boot {r['boot_id']:08x} +{r['start_mono_ms'] / 1000:.0f}s")
        text = r["text"] if r["status"] == "done" else f"_{r['status'] or 'untranscribed'}_"
        rel = Path(r["path"]).relative_to(folder.relative_to(data_dir)).as_posix()
        lines.append(f"| {when} | {r['duration_ms'] / 1000:.0f} s | {r['speech_ratio']:.0%} | {r['time_source']} "
                     f"| [{Path(r['path']).name}]({rel}) | {text.replace('|', '/')} |")
    out = folder / f"{day}.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out
