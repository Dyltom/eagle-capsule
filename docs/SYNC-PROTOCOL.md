# Eagle Capsule chunk-sync protocol (v1)

This is the contract between the pendant firmware and the host. It covers how audio
is stored on the card and how the owner's PC pulls it off, over BLE GATT or over a
byte-stream UART through the pogo dock. The reference host implementation and a
simulated device are in [`host/`](../host/README.md). The tests there are the
executable form of this document.

Design rules:

1. **Nothing leaves the device unencrypted, and the device cannot read its own archive.**
   It holds only the host's X25519 *public* key.
2. **Nothing is deleted until the host says it has a verified, durable copy.** A chunk
   is deleted only after an ACK carrying the SHA-256 of the exact bytes on the card.
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
| `boot_id` | u32 | Random value from the TRNG at every boot. Changes on every reset or power loss. |
| `seq` | u32 | Chunk sequence number. Persisted on the card and incremented per chunk, never reused. `(device_id, seq)` is the global key of a chunk. |
| `mono_ms` | u64 | Milliseconds since this boot (RTC on the 32.768 kHz LFXO). Restarts at 0 on every boot. |
| `utc_ms` | u64 | The device's best-known Unix time. `0` means unknown. Set only by the host's `SET_TIME` and lost on reset (the XIAO has no backup-powered RTC). |

---

## 2. Chunk files on the card

The device records continuously into **chunks**. The default is 60 s, which is a
compromise: shorter means less audio lost to a crash (see §8) but more files and more
per-chunk overhead. Each chunk is one file, written **streaming**: header first, then
audio frames as they come out of the encoder. The device never holds a whole chunk in RAM.

Suggested card layout: `/EC/<seq / 1000>/<seq>.ECC`, plus an append-only `/EC/INDEX`
of `{seq u32, size u32, sha256[32], state u8}` records so that LIST never re-reads or
re-hashes audio. `seq` naming works even when the date is unknown.

Ring-buffer policy: when the card is full, the device deletes the **oldest** chunk
even if it was never ACKed, and increments a persistent `dropped` counter that is
reported in `INFO`. This is a policy choice. "Stop recording when full" is the other
option. At 16 kbps a 32 GB card holds about 6 months, so in practice this only
triggers if syncing has been broken for months.

---

## 3. Chunk file format

```
+-------------------------+  OUTER header, 52 B, in clear, used as AES-GCM AAD
| magic    "ECAP"   4s    |
| version  1        u8    |
| alg      1        u8    |  1 = X25519 + HKDF-SHA256 + AES-256-GCM
| reserved 0        u16   |
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
    frame_ms u8 (20) | channels u8 (1) | flags u8 (bit0 = start_utc valid)
  FRAMES:   repeated { len u16 (1..65534), bytes }   terminated by len = 0
  TRAILER:  frame_count u32 | duration_ms u32 | vad_seconds u16 | vad_bitmap[ceil(n/8)]
```

Fields that are only known when the chunk closes (frame count, duration, the per-second
VAD flags) go in the **trailer**, so the file can be written strictly front to back.
The device-side VAD is a cheap energy gate. It is **informational only**: it never
suppresses recording. Speech detection proper (Silero VAD) runs on the host.

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
| `0x87 DATA_END` | D to H | `seq u32, next_offset u32` | Closes one FETCH window. |
| `0x06 ACK` | H to D | `seq u32, sha256 32s` | "I have it, verified and durable. Delete it." |
| `0x88 ACK_OK` | D to H | `seq u32` | Also returned for an already-deleted seq (idempotent). |
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
   write audio + SQLite row (one transaction)
   ACK(seq, sha) ─────► ACK_OK                       device unlinks the file
for each item already stored on the host (an earlier ACK_OK was lost):
   ACK(seq, sha) ─────► ACK_OK                       no re-download
```

### Resume after a disconnect

The host appends each DATA payload to `data/.partial/<device>-<seq>.part` as it arrives,
checking `offset == bytes_so_far`. After a reconnect it simply `FETCH`es from
`offset = size(.part)`. A `.part` larger than the LIST size is discarded. The device keeps
no transfer state, and any FETCH from any offset is valid. The final SHA-256 check covers
the joined file, so a bad resume is caught there.

An ACK lost in transit (host stored the chunk, device never saw the ACK) is handled by the
"already stored" branch: the host recognises `(device_id, seq, sha256)` in its index and
just re-ACKs.

---

## 5. Transports

The same frames go over both links. Only the framing differs.

### 5.1 BLE GATT

* One primary service, `bd6970b7-810b-4975-9ad6-c8479ca96def`.
  * **CTRL** `bd6970b8-…`: Write Without Response. One host to device frame per write.
  * **STREAM** `bd6970b9-…`: Notify. One device to host frame per notification.
* The link layer's CRC and ATT do the framing. No extra headers are needed.
* Require ATT_MTU ≥ 99 (INFO is 88 B + 3). The firmware should request **247 with Data
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
* A frame with a bad CRC is dropped silently. The host sees a timeout or an offset gap and
  re-FETCHes from its last good offset.
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
up offline: **lose it and the archive is unrecoverable**. `key_fp = SHA-256(host_pub)[0:8]`
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
| ChaCha20-Poly1305 | yes | the hardware-accelerated AEAD on this chip |

At 16–32 kbps the AEAD processes **2–4 KB/s**. Software AES-256-GCM on a 64 MHz M4 runs at
hundreds of KB/s, so it costs well under 1 % CPU. Acceleration does not matter for the bulk
cipher. It does help the X25519 operations (milliseconds on the CC310 vs. tens of milliseconds
in software, once a minute) and saves flash. If a hardware AEAD is wanted anyway, `alg = 2`
is reserved for **X25519 + HKDF + ChaCha20-Poly1305**, with the same structure and a 12-byte
nonce. Remember that the CC310 must be powered on (`NRF_CRYPTOCELL->ENABLE`) around each use,
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
   `data/undated/boot-<id>/` with its monotonic offset. It is still ordered by `seq`. Its
   time is bounded by its neighbours' times, but it is not guessed.

Every sync pushes the time, so after a power loss the *current* boot is always
reconcilable, back to its first chunk. Drift: the LFXO is ±20 ppm, which is about 1.7 s per
day. If the firmware runs from the internal LFRC instead, expect ±250–500 ppm (20–40 s per
day). A host with two anchors in one boot can interpolate linearly. The reference client
uses the nearest anchor.

---

## 8. Known limitations and open items

* **A chunk interrupted by a brownout is unreadable as a whole.** Its GCM tag is never
  written, and the device has already lost the key. Up to one chunk (60 s) is lost per
  unclean power-off. Mitigations, best first: (a) firmware closes the chunk on a low-VBAT
  interrupt; (b) v2 splits each chunk into independently sealed segments of about 4 KB
  (STREAM construction: `nonce = base XOR segment_index`, with a last-segment flag in the
  AAD), so only the open segment is lost; (c) shorter chunks.
* Recording continues during sync. The firmware must share the SD/SPI bus between the
  recorder (writes about 2–4 KB/s) and FETCH reads. A FETCH of the chunk currently being
  written is not allowed: the open chunk is not listed.
* AUTH proves the host's identity once per session but does not MAC each later frame. Over
  BLE, rely on LESC bonding for per-frame integrity. The UART dock requires physical access.
