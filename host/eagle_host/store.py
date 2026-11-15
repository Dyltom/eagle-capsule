"""SQLite index (chunks, time anchors, transcripts + FTS5) and the daily Markdown rollup."""
from __future__ import annotations

import os
import sqlite3
import time
from datetime import datetime
from pathlib import Path

from .files import open_private, write_file

SCHEMA_VERSION = 2
UTC_MIN, UTC_MAX = 1_577_836_800_000, 4_102_444_800_000    # 2020-01-01 .. 2100-01-01: anything else is a bad clock

SCHEMA = """
CREATE TABLE IF NOT EXISTS chunks (
    id            INTEGER PRIMARY KEY,
    device_id     TEXT    NOT NULL,        -- hex, from INFO; the chunk's inner header must match
    seq           INTEGER NOT NULL,        -- not unique: a replaced card or reset counter can reuse it
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
    sha256        TEXT    NOT NULL UNIQUE, -- of the encrypted file as stored on the device
    file_sha256   TEXT    NOT NULL,        -- of the archive file we wrote; checked before any re-ACK
    eph_pub       TEXT    NOT NULL,        -- chunk's ephemeral X25519 key; a repeat means key/nonce reuse
    path          TEXT    NOT NULL UNIQUE, -- relative to the data dir
    imported_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS chunks_day ON chunks(day, start_utc_ms);
CREATE INDEX IF NOT EXISTS chunks_seq ON chunks(device_id, seq);
CREATE INDEX IF NOT EXISTS chunks_eph ON chunks(eph_pub);
CREATE TABLE IF NOT EXISTS anchors (       -- (boot, monotonic) <-> UTC pairs learned at sync time
    device_id TEXT NOT NULL, boot_id INTEGER NOT NULL, mono_ms INTEGER NOT NULL, utc_ms INTEGER NOT NULL,
    PRIMARY KEY (device_id, boot_id, mono_ms)
);
CREATE TABLE IF NOT EXISTS transcripts (
    id         INTEGER PRIMARY KEY,
    chunk_id   INTEGER NOT NULL REFERENCES chunks(id),
    engine     TEXT NOT NULL,
    status     TEXT NOT NULL,               -- done | untranscribed | error
    language   TEXT,
    text       TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    UNIQUE (chunk_id, engine)
);
CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(text, content='transcripts', content_rowid='id');
CREATE TRIGGER IF NOT EXISTS transcripts_ai AFTER INSERT ON transcripts BEGIN
    INSERT INTO transcripts_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS transcripts_ad AFTER DELETE ON transcripts BEGIN
    INSERT INTO transcripts_fts(transcripts_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;
"""


def utc_ok(utc_ms: int | None) -> bool:
    return utc_ms is not None and UTC_MIN <= utc_ms <= UTC_MAX


class Index:
    def __init__(self, path: Path) -> None:
        os.close(open_private(path, os.O_RDWR | os.O_CREAT))   # SQLite's journal inherits this 0600
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version != SCHEMA_VERSION and self.db.execute(
                "SELECT 1 FROM sqlite_master WHERE name='chunks'").fetchone():
            self.db.close()
            raise RuntimeError(f"{path} uses index schema v{version or 1}; this client needs "
                               f"v{SCHEMA_VERSION}. Sync into a new data dir.")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript(SCHEMA)
        self.db.execute(f"PRAGMA user_version={SCHEMA_VERSION}")

    def close(self) -> None:
        self.db.close()

    # ------------------------------------------------------------ time
    def add_anchor(self, device_id: str, boot_id: int, mono_ms: int, utc_ms: int) -> None:
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO anchors VALUES (?,?,?,?)", (device_id, boot_id, mono_ms, utc_ms))

    def resolve_utc(self, device_id: str, boot_id: int, mono_ms: int, device_utc_ms: int) -> tuple[int | None, str]:
        """A sane device-stamped UTC wins. Else project from an anchor of the same boot, but only if
        the chunk lies inside the mono range that boot has shown us (at or before its latest anchor)."""
        if utc_ok(device_utc_ms):
            return device_utc_ms, "device"
        anchors = self.db.execute("SELECT mono_ms, utc_ms FROM anchors WHERE device_id=? AND boot_id=?",
                                  (device_id, boot_id)).fetchall()
        if anchors and mono_ms <= max(a["mono_ms"] for a in anchors):
            a = min(anchors, key=lambda a: abs(a["mono_ms"] - mono_ms))
            utc = a["utc_ms"] - (a["mono_ms"] - mono_ms)
            if utc_ok(utc):
                return utc, "reconciled"
        return None, "unknown"

    # ------------------------------------------------------------ chunks
    def find_chunk(self, device_id: str, sha_hex: str) -> sqlite3.Row | None:
        return self.db.execute("SELECT * FROM chunks WHERE device_id=? AND sha256=?", (device_id, sha_hex)).fetchone()

    def eph_pub_seen(self, eph_hex: str) -> bool:
        return self.db.execute("SELECT 1 FROM chunks WHERE eph_pub=?", (eph_hex,)).fetchone() is not None

    def remove_chunk(self, chunk_id: int) -> None:
        with self.db:
            self.db.execute("DELETE FROM transcripts WHERE chunk_id=?", (chunk_id,))
            self.db.execute("DELETE FROM chunks WHERE id=?", (chunk_id,))

    def add_chunk(self, row: dict, transcript: tuple[str, str, str, str | None]) -> None:
        engine, status, text, lang = transcript
        now = int(time.time())
        with self.db:  # one transaction: the chunk is either fully indexed or not at all
            cur = self.db.execute(f"INSERT INTO chunks ({','.join(row)}, imported_at) "
                                  f"VALUES ({','.join('?' * len(row))}, ?)", (*row.values(), now))
            self.db.execute("INSERT INTO transcripts (chunk_id, engine, status, language, text, created_at) "
                            "VALUES (?,?,?,?,?,?)", (cur.lastrowid, engine, status, lang, text, now))

    def search(self, query: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT c.*, t.text FROM transcripts_fts f JOIN transcripts t ON t.id = f.rowid "
            "JOIN chunks c ON c.id = t.chunk_id WHERE transcripts_fts MATCH ? "
            "ORDER BY c.start_utc_ms", (query,)).fetchall()

    def day_rows(self, day: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT c.*, t.status, t.text FROM chunks c LEFT JOIN transcripts t ON t.chunk_id = c.id "
            "WHERE c.day = ? ORDER BY c.start_utc_ms, c.boot_id, c.start_mono_ms", (day,)).fetchall()


def write_rollup(index: Index, data_dir: Path, day: str, tz=None) -> Path:
    rows = index.day_rows(day)
    folder = data_dir / "undated" if day == "undated" else data_dir / day.replace("-", "/")
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
    write_file(out, ("\n".join(lines) + "\n").encode("utf-8"), overwrite=True)
    return out
