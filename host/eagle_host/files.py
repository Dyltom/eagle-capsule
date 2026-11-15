"""Private, durable file writes and the data-dir lock.

Everything the host writes is readable by the owner only (dirs 0700, files 0600), and an
archive file is on disk (fsynced, renamed into place, directory fsynced) before it is indexed.
"""
from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path

if os.name == "nt":
    import msvcrt
else:
    import fcntl


class DataDirLocked(Exception):
    """Another sync is already using this data dir."""


def fsync_dir(path: Path) -> None:
    if os.name == "nt":   # directories cannot be opened on Windows; NTFS journals the rename itself
        return
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def make_private_dirs(path: Path) -> None:
    """mkdir -p with mode 0700, fsyncing the parent of every directory it creates."""
    missing = []
    while not path.exists():
        missing.append(path)
        path = path.parent
    for d in reversed(missing):
        try:
            d.mkdir(mode=0o700)
        except FileExistsError:
            continue
        fsync_dir(d.parent)


def open_private(path: Path, flags: int) -> int:
    return os.open(path, flags | getattr(os, "O_BINARY", 0), 0o600)


def _fsync_file(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_file(path: Path, data: bytes, *, overwrite: bool = False) -> None:
    """Temp file in the same dir -> fsync -> rename into place -> fsync the dir.

    Without `overwrite`, an existing file is never replaced: identical content is accepted
    (an earlier run wrote it and stopped before indexing), anything else raises FileExistsError.
    """
    path = Path(path)
    make_private_dirs(path.parent)
    if not overwrite and path.exists():
        if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(data).digest():
            raise FileExistsError(f"refusing to overwrite {path}")
        _fsync_file(path)
        fsync_dir(path.parent)
        return
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if not overwrite and os.path.lexists(path):
            raise FileExistsError(f"refusing to overwrite {path}")
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    fsync_dir(path.parent)


class DirLock:
    """Exclusive, non-blocking OS lock on a file. The OS drops it if the process dies."""

    def __init__(self, path: Path) -> None:
        self.path, self.fd = Path(path), None

    def __enter__(self) -> DirLock:
        fd = open_private(self.path, os.O_RDWR | os.O_CREAT)
        try:
            if os.name == "nt":
                msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
            else:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            raise DataDirLocked(f"{self.path} is held by another sync") from None
        self.fd = fd
        return self

    def __exit__(self, *exc) -> None:
        if os.name == "nt":
            os.lseek(self.fd, 0, os.SEEK_SET)
            msvcrt.locking(self.fd, msvcrt.LK_UNLCK, 1)
        os.close(self.fd)
        self.fd = None
