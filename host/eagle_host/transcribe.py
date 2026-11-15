"""Pluggable transcription: faster-whisper if installed, otherwise a stub."""
from __future__ import annotations

import os
from pathlib import Path


class StubTranscriber:
    name = "stub"

    def transcribe(self, audio_path: Path | None) -> tuple[str, str, str | None]:
        """Returns (status, text, language)."""
        return "untranscribed", "", None


class FasterWhisperTranscriber:
    name = "faster-whisper"

    def __init__(self, model: str | None = None) -> None:
        from faster_whisper import WhisperModel  # type: ignore
        size = model or os.environ.get("EAGLE_WHISPER_MODEL", "base")
        self.model = WhisperModel(size, device="auto", compute_type="int8")
        self.name = f"faster-whisper:{size}"

    def transcribe(self, audio_path: Path | None) -> tuple[str, str, str | None]:
        if audio_path is None or audio_path.suffix != ".wav":
            return "untranscribed", "", None
        segments, info = self.model.transcribe(str(audio_path), vad_filter=True)
        return "done", " ".join(s.text.strip() for s in segments).strip(), info.language


def default_transcriber():
    try:
        return FasterWhisperTranscriber()
    except ImportError:
        return StubTranscriber()
