# Eagle Capsule chunk-sync protocol (v1)

This is the contract between the pendant firmware and the host. It covers how audio
is stored on the card and how the owner's PC pulls it off, over BLE GATT or over a
byte-stream UART through the pogo dock. The reference host implementation and a
simulated device are in [`host/`](../host/README.md). The tests there are the
executable form of this document.

Design rules:

1. **Nothing leaves the device unencrypted, and the device cannot read its own archive.**
   It holds only the host's X25519 *public* key.
2. **Nothing is released until the host says it has a verified, durable copy.** A chunk
   is marked ACKed only after an ACK carrying the SHA-256 of the exact bytes on the card.
   The one exception is ring overwrite when the card is full, which is counted (§2).
3. **Every transfer can resume.** The host can restart any FETCH at any byte offset.
4. **The clock is unreliable, and that is fine.** The device stamps monotonic time plus
   a boot ID. Wall-clock time is a best-effort extra that the host can reconstruct.
5. **Keep it small enough to write in C on a Cortex-M4 with 256 KB of RAM.**
   Fixed-size little-endian structs, no TLV parser, no CBOR.

All integers are little-endian. `u8/u16/u32/u64` are unsigned. Times are milliseconds.

---

## 1. Identifiers and time

| Field | Size | Meaning |
|---|---|---|
| `device_id` | 8 B | nRF52840 FICR `DEVICEID[0..1]`. Stable for the life of the chip. |
| `boot_id` | u32 | Random value from the TRNG at every boot. A **new** value on every reset of any kind (power-on, brownout, watchdog, soft reset), and never carried across one, because `mono_ms` restarts with it. `(device_id, boot_id, mono_ms)` names one instant. |
| `seq` | u32 | Chunk sequence number. Persisted on the card and incremented per chunk, never reused. The host does not rely on that: a replaced card or a reset counter can repeat a `seq`, so the host keys chunks by `(device_id, sha256)`. |
| `mono_ms` | u64 | Milliseconds since this boot (RTC on the 32.768 kHz LFXO). Restarts at 0 on every boot. |
| `utc_ms` | u64 | The device's best-known Unix time. `0` means unknown. Set only by the host's `SET_TIME` and lost on reset (the XIAO has no backup-powered RTC). |

---

## 2. Chunk files on the card

The device records continuously into **chunks** of 60 s, a compromise: shorter means
less audio lost to a crash (see §8) but more per-chunk overhead. Each chunk is written
**streaming**: outer header first, then audio frames encrypted and hashed as they come
out of the encoder, then the trailer and GCM tag. The device never holds a whole chunk
in RAM. "File" in this document means the chunk's byte string as stored.

The card is not a filesystem. It is a raw ring of fixed **256 KiB slots, one chunk per
slot** (FIRMWARE.md §8; a 60 s chunk is ~186 KB at 24 kbps, ~246 KB at 32 kbps). A
per-slot commit record `{seq, size, sha256, boot_id, acked, CRC}`, written after the
tag, is what LIST reads, so LIST never re-reads or re-hashes audio. A chunk closes early
on state changes (privacy, dock/undock, low battery, time-set) or when the next frame
would not fit the slot.

**ACK state is per chunk**, not a watermark. Out-of-order ACKs are normal: the host
leaves a chunk it cannot verify or decrypt un-ACKed and goes on to ACK later ones (§4
host rules). The device marks that one slot ACKed and stops listing it.

Ring-buffer policy: the ring always writes the **oldest** slot next. If that slot holds
a chunk that was never ACKed, it is overwritten anyway and a persistent `dropped`
counter, reported in `INFO`, is incremented. This is a policy choice. "Stop recording
when full" is the other option. With fixed 256 KiB slots a 32 GB card holds ~80 days
at any bitrate (`tools/feasibility.py`; fewer if many chunks close early). In practice this only triggers if
syncing has been broken for months.

---

## 3. Chunk file format

```
+-------------------------+  OUTER header, 52 B, in clear, used as AES-GCM AAD
| magic    "ECAP"   4s    |
| version  1        u8    |
| alg      1        u8    |  1 = X25519 + HKDF-SHA256 + AES-256-GCM
| reserved 0        u16   |  MUST be 0. Never carries metadata: it is readable on a found card
| seq               u32   |
| key_fp            8s    |  SHA-256(host_pub)[0:8], which host key this was sealed to
| eph_pub           32s   |  per-chunk ephemeral X25519 public key
+-------------------------+
| AES-256-GCM ciphertext  |  of the PLAINTEXT below, streamed
+-------------------------+
| GCM tag           16 B  |
+-------------------------+

PLAINTEXT (encrypted, so a found card reveals no timestamps or VAD activity either)
  INNER header, 44 B:
    device_id 8s | boot_id u32 | seq u32 | start_mono_ms u64 | start_utc_ms u64 (0 = unknown)
    sample_rate u32 | bitrate u32 (0 for PCM) | codec u8 (0 = PCM s16le, 1 = Opus)
    frame_ms u8 (20) | channels u8 (1) | flags u8 (see below)
  FRAMES:   repeated { len u16 (1..65534), bytes }   terminated by len = 0
  TRAILER:  frame_count u32 | duration_ms u32 | vad_seconds u16 | vad_bitmap[ceil(n/8)]
```

Fields that are only known when the chunk closes (frame count, duration, the per-second
VAD flags) go in the **trailer**, so the file can be written strictly front to back.
End uptime is `start_mono_ms + duration_ms`. The device-side VAD is a cheap energy gate.
It is **informational only**: it never suppresses recording, and the host does not use it
to order fetches (it is encrypted). Speech detection proper (Silero VAD) runs on the host.

**Inner `flags` (v1).** All extra per-chunk metadata is inside the ciphertext.

| Bit | Name | Meaning |
|---|---|---|
| 0 | `utc_valid` | `start_utc_ms` came from a `SET_TIME` in **this** boot. Never set from a retained or projected clock. |
| 1–2 | `state` | state when the chunk opened: 0 worn, 1 still, 2 docked, 3 reserved |
| 3 | `after_privacy` | the previous chunk was closed by the privacy switch (the privacy marker) |
| 4 | `safe_mode` | recorded in watchdog safe mode (FIRMWARE.md §9) |
| 5–7 | reserved | 0 |

The reference host (`host/eagle_host/chunkfile.py`) reads bit 0 and **ignores bits 1–7
today**, so firmware can set them in v1 without breaking it. It does not yet store them.

**Trailer extension (v2, not accepted by the host today).** The v1 host rejects any byte
after the VAD bitmap ("trailer does not match body") and any outer `version` other than 1.
So these fields are reserved for **`version = 2`**, which needs a host update first:

```
  TRAILER_EXT (after vad_bitmap, v2 only):
    ext_len u16 (bytes that follow; a v2 host skips what it does not know)
    close_reason u8   0 normal (60 s), 1 privacy, 2 dock, 3 undock, 4 low battery,
                      5 time-set, 6 slot full, 7 shutdown
    peak_dbfs i8 | noise_floor_dbfs i8          per-chunk level stats (VAD summary)
    prev_boot_id u32 | prev_last_mono_ms u64    retained hint: this boot began shortly after
                                                prev_boot_id reached prev_last_mono_ms (from
                                                __noinit RAM, so watchdog/soft resets only;
                                                0/0 = no hint)
```

Every v2 field is inside the ciphertext and covered by the GCM tag.

The outer `seq` is repeated inside the ciphertext, and the whole outer header is AAD.
So a file cannot be renamed or spliced into another slot without failing the GCM check.

---

## 4. Messages

A **frame** is `type u8` followed by the fixed fields for that type. Only `DATA` carries a
variable payload after its fields. Unknown trailing bytes on other frames are ignored
(this leaves room for forward compatibility). Host to device types are `0x01..0x7F`.
Device to host types are `0x80..0xFF`.

| Type | Dir | Fields (after the type byte) | Notes |
|---|---|---|---|
| `0x01 HELLO` | H to D | `proto u8, max_frame u16` | Starts a session and resets auth. `max_frame` is the largest frame the host accepts. |
| `0x81 INFO` | D to H | `proto u8, device_id 8s, boot_id u32, mono_ms u64, utc_ms u64, key_fp 8s, oldest_seq u32, next_seq u32, dropped u32, max_frame u16, free_kb u32, challenge 32s` | 88 B. `challenge` is a fresh ephemeral X25519 public key. `max_frame` is the agreed value: min(host, device). |
| `0x02 AUTH` | H to D | `mac 32s` | Proof that the host holds the archive private key (§6.3). |
| `0x82 AUTH_OK` | D to H | none | |
| `0x03 SET_TIME` | H to D | `utc_ms u64` | Device sets `utc_offset = utc_ms - mono_ms`. |
| `0x83 TIME_OK` | D to H | `boot_id u32, mono_ms u64, utc_ms u64` | The `(boot_id, mono_ms)` at which the time was applied. This is the host's **time anchor**. |
| `0x04 LIST` | H to D | `from_seq u32, max_items u16` | Inclusive start. |
| `0x84 LIST_ITEM` | D to H | `seq u32, size u32, sha256 32s` | One per stored chunk, ascending seq. The hash covers the whole file as stored. |
| `0x85 LIST_END` | D to H | `more u8` | If `more` = 1, LIST again from `last_seq + 1`. |
| `0x05 FETCH` | H to D | `seq u32, offset u32, length u32` | `length` = 0 means to end of file. The host should use windows (16 KB in the reference client). |
| `0x86 DATA` | D to H | `seq u32, offset u32, bytes...` | Each DATA frame is at most `max_frame` bytes. |
| `0x87 DATA_END` | D to H | `seq u32, next_offset u32` | Closes one FETCH window. `next_offset` = offset + bytes the device sent. If it has no bytes at `offset`, `next_offset = offset`. |
| `0x06 ACK` | H to D | `seq u32, sha256 32s` | "I have it, verified and durable. Release it." The device marks that slot ACKed. ACKs may arrive in any seq order. |
| `0x88 ACK_OK` | D to H | `seq u32` | Also returned for an already-ACKed or already-overwritten seq (idempotent). |
| `0xFF ERR` | D to H | `code u8, seq u32` | 1 bad request, 2 version, 3 not authenticated, 4 auth failed, 5 unknown chunk, 6 hash mismatch |

Before `AUTH_OK`, the device accepts only `HELLO` and `AUTH`. Everything else gets `ERR 3`.

### Session

```
HELLO ─────────────► INFO (challenge, key_fp, boot_id, mono, utc?)
AUTH(mac) ─────────► AUTH_OK
SET_TIME(now) ─────► TIME_OK(boot_id, mono)          host stores the anchor
LIST(0) ───────────► LIST_ITEM* LIST_END
for each item not already stored on the host:
   FETCH(seq, off, 16K) ─► DATA* DATA_END            repeat until size; append to .partial
   verify SHA-256(file) == LIST hash        else: discard, no ACK, retry next sync
   decrypt + parse (GCM tag)                else: keep on device, flag, no ACK
   check inner header (device_id, codec…)   else: keep on device, flag, no ACK
   write audio durably, then SQLite row (one transaction)
   ACK(seq, sha) ─────► ACK_OK                       device marks the slot ACKed
for each item already stored on the host (an earlier ACK_OK was lost):
   verify the archive file still matches    else: set it aside, re-download as above
   ACK(seq, sha) ─────► ACK_OK                       no re-download
```

### Resume after a disconnect

The host appends each DATA payload to `data/.partial/<device>-<seq>.part` as it arrives,
checking `offset == bytes_so_far`. After a reconnect it simply `FETCH`es from
`offset = size(.part)`. A `.part` larger than the LIST size is discarded. The device keeps
no transfer state, and any FETCH from any offset is valid. The final SHA-256 check covers
the joined file, so a bad resume is caught there.

An ACK lost in transit (host stored the chunk, device never saw the ACK) is handled by the
"already stored" branch: the host recognises `(device_id, sha256)` in its index, checks that
the archive file still exists and hashes to the value it recorded, and only then re-ACKs.

### Host rules

These are what "verified and durable" in `ACK` means. The reference client implements all of them.

* **Durable before ACK.** Audio is written to a temp file in the target directory, fsynced,
  renamed into place, and the directory is fsynced (new parent directories too). Then the
  SQLite row is committed (`synchronous=FULL`). Only then is the ACK sent.
* **Never overwrite.** Archive paths include `device_id`, `boot_id`, `seq` and a hash prefix,
  and an existing file with different content is an error, never replaced. Every path
  component derived from the device is formatted from integers or hex.
* **One bad chunk never blocks the rest.** Any failure on one chunk (device `ERR`, no FETCH
  progress, bad hash, GCM failure, inner `device_id` not equal to INFO's, unknown codec,
  unsupported `sample_rate`/`frame_ms`/`channels`, size over 8 MiB) means no ACK for that
  chunk. The host records why and moves on to the next one, which it still ACKs, so ACKs
  reach the device out of seq order (§2). The chunk stays on the device and is retried at
  the next sync.
* **Bounded transfers.** A FETCH window that makes no progress is retried from the last
  good offset at most 5 times. A `DATA_END` with `next_offset` equal to the requested
  offset before the LIST size is reached (the file is shorter than LIST claims) fails the
  chunk at once. LIST must be strictly ascending: the host stops listing on a repeated or
  empty page, and after `seq = 0xFFFFFFFF`.
* **Implausible clocks are ignored, not fatal.** A device `start_utc_ms` outside
  2020–2100 is treated as unknown and the chunk falls back to §7 rules 2–3.
* **Ephemeral key reuse is flagged.** The host records each chunk's `eph_pub`. A repeat
  means the device reused a GCM key and nonce (a broken TRNG). The chunk is still stored,
  and the host reports it.
* **One sync per data directory.** The host holds an exclusive OS lock on `data/.lock`.

---

## 5. Transports

The same frames go over both links. Only the framing differs.

### 5.1 BLE GATT

BLE is the **docked fallback** (no UART host answered) and the **on-demand** path
(FIRMWARE.md §5: a switch-flick gesture opens a 2 min window). It is off while worn.
At the 5 KB/s measured on this board a full 24 kbps day takes ~14 h, so BLE is not the
nightly path.

* One primary service, `bd6970b7-810b-4975-9ad6-c8479ca96def`.
  * **CTRL** `bd6970b8-…`: Write Without Response. One host to device frame per write.
  * **STREAM** `bd6970b9-…`: Notify. One device to host frame per notification.
* The link layer's CRC and ATT do the framing. No extra headers are needed.
* Require ATT_MTU ≥ 99: the host's minimum frame is `MIN_FRAME = 96` B
  (`host/eagle_host/protocol.py`; INFO itself is 88 B), plus 3 B of ATT header. The firmware should request **247 with Data
  Length Extension and 2M PHY**, giving `max_frame = 244` and 235 B of audio per DATA.
  The host sends `max_frame = ATT_MTU - 3` in HELLO.
* Flow control comes from BLE notifications plus the FETCH window. The device must not
  queue more notifications than the controller has TX buffers. It sends the next one
  when a TX-complete event arrives.
* Use LE Secure Connections bonding as well. The protocol's AUTH protects the destructive
  operations (§6.3), and link encryption additionally hides LIST metadata (sizes, counts)
  from sniffers and stops an active man-in-the-middle from injecting frames after AUTH.

### 5.2 UART (pogo dock), or USB CDC

* Each frame is sent as a SLIP packet (RFC 1055: `END=0xC0, ESC=0xDB, ESC_END=0xDC,
  ESC_ESC=0xDD`) of `frame || CRC-32(frame)` (IEEE 802.3 / zlib polynomial, little-endian).
  A leading `END` flushes line noise.
* A frame with a bad CRC is dropped silently. The host sees a timeout or an offset gap,
  discards the rest of that window (up to its `DATA_END`, or a timeout), and re-FETCHes from
  its last good offset. A lost `DATA_END` is a timeout handled the same way.
* The decoder drops any frame longer than 65,535 + 4 bytes without buffering it.
* `max_frame` is typically 1024 (sized to the device TX buffer). The 1 Mbaud 8N1 line rate
  is about 100 KB/s raw, 90+ KB/s of audio after framing. SLIP expands random ciphertext by
  about 0.8 %.
* The same framing works unchanged over the nRF52840's native USB as a CDC-ACM port, if the
  dock ever carries D+/D- (12 Mbit/s, roughly 10x the UART).

---

## 6. Encryption at rest

### 6.1 Provisioning

The host generates an X25519 key pair once. The **32-byte public key** is flashed into the
device, either in the firmware image or in a settings partition, and never leaves otherwise.
The private key stays on the PC, protected by a passphrase, the OS keyring or DPAPI, and backed
up offline: **lose it and the archive is unrecoverable**. The reference host writes it as a
PKCS#8 PEM with mode 0600, encrypted when `$EAGLE_KEY_PASSPHRASE` (or a passphrase argument)
is given. `key_fp = SHA-256(host_pub)[0:8]`
appears in INFO and in every file, so a mismatch is caught before any transfer.

### 6.2 Per-chunk ECIES (X25519 + HKDF-SHA256 + AES-256-GCM)

At chunk open, the device does:

```
eph_sk  <- TRNG (32 B);   eph_pub = X25519(eph_sk, 9)
shared  = X25519(eph_sk, host_pub)               reject if all-zero
okm     = HKDF-SHA256(ikm = shared, salt = eph_pub || host_pub,
                      info = "eagle-capsule/v1/chunk", L = 44)
key     = okm[0:32]   nonce = okm[32:44]          one key per chunk, so a fixed nonce is safe
write OUTER header; GCM init(key, nonce, aad = OUTER header)
... GCM update(plaintext) as audio arrives, writing ciphertext to the card ...
GCM finish -> append 16 B tag;  wipe key, eph_sk, GCM state
```

The device keeps no copy of `eph_sk` or `key` after the chunk closes, so **a captured
pendant or card reveals nothing**, including what it recorded earlier in the same boot.
The host recomputes `shared = X25519(host_sk, eph_pub)` and decrypts. The GCM tag
authenticates the contents. The SHA-256 in LIST is a separate check on the *ciphertext*,
because that is the only integrity check the device itself can perform (it cannot decrypt).

### 6.3 Host authentication (AUTH)

Without AUTH, anyone in BLE range could send `ACK` (which needs only the hash from `LIST`)
and destroy the archive, or push a wrong time. INFO carries `challenge = c_pub`, a fresh
ephemeral X25519 key for each HELLO. The host must answer:

```
shared = X25519(host_sk, c_pub)
k      = HKDF-SHA256(shared, salt = c_pub, info = "eagle-capsule/v1/auth", L = 32)
mac    = HMAC-SHA256(k, c_pub || device_id || boot_id)
```

The device computes the same value with `c_sk` and `host_pub`. Only the holder of the
archive key can sync, set the time, or delete. This needs no extra key material on the device.

### 6.4 What the nRF52840's CryptoCell-310 can do

Per the nRF52840 Product Specification (CRYPTOCELL chapter) and the nRF Connect SDK
`nrf_cc3xx` driver docs. **Re-check these against the exact NCS version you pin.**

| Primitive | CC310 hardware | Notes |
|---|---|---|
| TRNG + CTR_DRBG | yes | ephemeral keys, `boot_id`, challenges |
| X25519 (Curve25519 ECDH) | yes | 2 per chunk (keygen + ECDH) and 1–2 per connection |
| SHA-256 / HMAC-SHA256 | yes | file hash while writing; HKDF; AUTH |
| AES-128 (ECB/CBC/CTR/CCM/CMAC) | yes | **128-bit keys only** |
| AES-256 | **no** | software (nrf_oberon) |
| AES-GCM | **no** (GCM is CC312-only in `nrf_cc3xx`) | software (nrf_oberon), which can use CC310 AES-ECB only for 128-bit keys |
| ChaCha20-Poly1305 | yes, one-shot | older `nrf_security` docs say the cc3xx ChaCha20-Poly1305 does not support incremental (multi-part) operation. **VERIFY** on the pinned NCS. |

At 24–32 kbps the AEAD processes **3–4 KB/s**. Software AES-256-GCM on a 64 MHz M4 runs at
hundreds of KB/s, so it costs well under 1 % CPU. Acceleration does not matter for the bulk
cipher. It does help the X25519 operations (milliseconds on the CC310 vs. tens of milliseconds
in software, once a minute) and saves flash. `alg = 2` is reserved for
**X25519 + HKDF + ChaCha20-Poly1305**, with the same structure and a 12-byte nonce. It is
not a drop-in hardware path: a one-shot AEAD cannot stream a ~250 KB chunk through 4 KB
buffers, so it would run in software too, or need the v2 segmented format (§8) with each
~4 KB segment sealed one-shot. The host implements only `alg = 1`. Remember that the CC310 must be powered on (`NRF_CRYPTOCELL->ENABLE`) around each use,
or it adds idle current.

---

## 7. Time reconciliation (host side)

Each chunk is placed in time by the first rule that applies:

1. **`device`**: `start_utc_ms` in the inner header is non-zero (the device knew UTC).
2. **`reconciled`**: the host has an anchor `(device_id, boot_id, mono_a, utc_a)` for the
   chunk's boot, from any earlier or current `TIME_OK`. Then
   `utc = utc_a - (mono_a - start_mono_ms)`. The host takes `utc_a` as the midpoint of the
   SET_TIME round trip (BLE adds ±1 connection interval, about 15–50 ms).
3. **`unknown`**: no anchor exists for that boot. This happens when the device reset and
   then reset again before its next sync. The chunk is stored under
   `data/undated/<device_id>/boot-<id>/` with its monotonic offset. It is still ordered by `seq`. Its
   time is bounded by its neighbours' times, but it is not guessed.

Every sync pushes the time, so after a power loss the *current* boot is always
reconcilable, back to its first chunk. Drift: the LFXO is ±20 ppm, which is about 1.7 s per
day. If the firmware runs from the internal LFRC instead, expect ±250–500 ppm (20–40 s per
day). A host with two anchors in one boot can interpolate linearly. The reference client
uses the nearest anchor of the chunk's own `boot_id`, and only if the chunk's
`start_mono_ms` is at or before the latest anchor of that boot. A chunk claiming a later
monotonic time than the device has ever reported in that boot is inconsistent, so it is
filed as `unknown` and not projected. A result outside 2020–2100 is also `unknown`.

---

## 8. Known limitations and open items

* **A chunk interrupted by a brownout is unreadable as a whole.** Its GCM tag and commit
  record are never written, and the device has already lost the key. Up to one chunk
  (60 s) is lost per unclean power-off. **v1 decision:** accept that, and have the firmware
  close the chunk on a low-VBAT interrupt so it is rare. **v2:** split each chunk into
  independently sealed segments of about 4 KB (STREAM construction:
  `nonce = base XOR segment_index`, with a last-segment flag in the AAD), so only the open
  segment (~1.4 s at 24 kbps) is lost. That is a new `version`, not required before the v1
  firmware is frozen. The reference host does not parse segments.
* Recording continues during sync. The firmware must share the SD/SPI bus between the
  recorder (writes about 2–4 KB/s) and FETCH reads. A FETCH of the chunk currently being
  written is not allowed: the open chunk is not listed.
* AUTH proves the host's identity once per session but does not MAC each later frame. Over
  BLE, rely on LESC bonding for per-frame integrity. The UART dock requires physical access.
* **AUTH can be relayed, and chunks can be forged (v1 limitation).** The host answers AUTH
  for whatever challenge a peer presents, and nothing authenticates the device to the
  host. A rogue peripheral posing as the pendant can pass the real pendant's challenge to
  the host, relay the host's MAC back, and then send `ACK`s that delete the real archive
  before it is ever fetched. Separately, chunks are sealed only to `host_pub`, which is in
  every pendant's flash. Anyone holding it can make a chunk that decrypts and passes GCM.
  **Interim rule (implemented in the reference host):** the host sends AUTH and ACK only
  over a transport that declares `secure_link`: a BLE link bonded with LE Secure
  Connections to the paired pendant, or the wired dock UART. A relay cannot present the
  bonded pendant's identity. Any other link is refused unless the operator explicitly
  overrides it (tests and demos only). The host also limits what a forged chunk can do: it
  must carry INFO's `device_id`, and it can never overwrite an existing archive file.
  **TODO (v2):** (a) bind AUTH to the link, by adding a channel-binding value from the LESC
  pairing to the MAC input so that a relayed MAC fails on the other link; and (b) give each
  pendant a signing key at provisioning, pinned by the host. INFO (including the challenge)
  is then signed, so the host answers only its own devices, and each chunk carries a
  device signature or MAC so that forged chunks are rejected.
