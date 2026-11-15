"""The host archive key: an X25519 private key in a PKCS#8 PEM file, mode 0600."""
from __future__ import annotations

import logging
import os
import stat
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from .chunkfile import raw_public
from .files import write_file

PASSPHRASE_ENV = "EAGLE_KEY_PASSPHRASE"
log = logging.getLogger(__name__)


def load_or_create_key(path: Path, passphrase: str | bytes | None = None) -> X25519PrivateKey:
    """Load the key, or create it (plus the 32-byte `.pub` to flash into the pendant).

    `passphrase` defaults to $EAGLE_KEY_PASSPHRASE. With one, the PEM is encrypted
    (BestAvailableEncryption); without one it is stored in clear, still owner-only.
    """
    path = Path(path)
    if passphrase is None:
        passphrase = os.environ.get(PASSPHRASE_ENV)
    password = passphrase.encode() if isinstance(passphrase, str) else passphrase
    if path.exists():
        if os.name == "posix" and stat.S_IMODE(path.stat().st_mode) & 0o077:
            log.warning("%s is readable by other users; chmod 600 it", path)
        return serialization.load_pem_private_key(path.read_bytes(), password=password)
    key = X25519PrivateKey.generate()
    encryption = (serialization.BestAvailableEncryption(password) if password
                  else serialization.NoEncryption())
    write_file(path, key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, encryption))
    write_file(path.with_suffix(".pub"), raw_public(key), overwrite=True)
    return key
