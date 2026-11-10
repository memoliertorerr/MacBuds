# Galaxy Buds2 (SM-R177) serial protocol reference

Protocol facts for `BudsProtocol`. Code is written from this document, not from the reference
project (see AGENTS.md rule 3).

## Conventions

- All byte values are hex unless a decimal is called out. Multi-byte integers are little-endian
  unless stated otherwise.
- **Payload offsets are zero-based and relative to the payload start**, i.e. the byte right
  after the message ID. "p0" is the first payload byte.
- Bit 0 is the least significant bit.
- Direction: **H→B** = host (Mac) to buds, **B→H** = buds to host.
- Every claim carries one of two labels:
  - **[device]** — confirmed on the owner's Buds2 in
    `docs/captures/2026-11-10-connect.txt` (listen-only capture, nothing was sent).
  - **[ref]** — taken from the reference project only
    (github.com/timschneeb/GalaxyBudsClient, commit `754b6fd`), not yet seen on this device.
- The first capture was listen-only. H→B messages confirmed on the device since then are
  listed in **section 4.0**; every other H→B layout is still [ref].
- "Revision" means p0 of the extended status message (0x61). The owner's buds report
  revision **0A** (decimal 10) [device].

---

## 1. Transport

| Item | Value | Status |
|---|---|---|
| Bluetooth | Classic (BR/EDR), RFCOMM | [device] |
| Second client | While one client holds the channel, another client's open neither succeeds nor fails — it never completes [device]. Treat an open timeout as "busy". | [device] |
| Control service SDP name | `GEARMANAGER` | [device] |
| Control service UUID | `2E73A4AD-332D-41FC-90E2-16BEF06523F2` | [device], matches [ref] |
| RFCOMM channel | 27 (decimal) on this unit — resolve via SDP by UUID, do not hard-code | [device] |
| Behaviour on open | Buds start sending frames immediately, without the host sending anything | [device] |

Other SDP records on the device — **not used** by this project:

| SDP name | RFCOMM ch (dec) | UUID | Note |
|---|---|---|---|
| `FACTORY` | 20 | `00001101-0000-1000-8000-00805F9B34FB` (generic SPP) | Not the control channel. Do not open. |
| (no name) | 21 | `E7AB2241-CA64-4A69-AC02-05F5C6FE2D62` | Unknown purpose. |
| `UUID128` | 26 | `B4A9D6A0-B2E3-4E40-976D-A69F167EA895` | Unknown purpose. |
| `SAMSUNGDEVICE` | 28 | `A23D00BC-217C-123B-9C00-FC44577136EE` | Unknown purpose. |
| `SPPSERVICE4` | 29 | `F8620674-A1ED-41AB-A8B9-DE9AD655729D` | [ref] calls this the "alternative"/SMEP channel; it uses different frame markers (FC … CC) and a property-based message set. Not needed. |
| (no name) | 2 | 0x1203 / 0x111E | Headset / hands-free audio profiles, owned by macOS. |

---

## 2. Frame layout

```
+------+---------+---------+--------+-----------------+---------+---------+------+
| SOM  | HDR lo  | HDR hi  | MSG ID | payload (N)     | CRC lo  | CRC hi  | EOM  |
| FD   | 1 byte  | 1 byte  | 1 byte | N bytes         | 1 byte  | 1 byte  | DD   |
+------+---------+---------+--------+-----------------+---------+---------+------+
```

| Field | Size | Meaning | Status |
|---|---|---|---|
| SOM | 1 | Always `FD` | [device] |
| Header | 2 | 16-bit little-endian value `H = byte1 \| (byte2 << 8)`; see below | [device] for length, see table for the rest |
| Message ID | 1 | See section 4 | [device] |
| Payload | N | `N = length − 3` | [device] |
| CRC16 | 2 | Over message ID + payload, sent low byte first | [device] |
| EOM | 1 | Always `DD` | [device] |

Total frame size on the wire = `length + 4` (SOM, two header bytes, EOM are not counted by
the length field). Smallest legal frame is 7 bytes (`length = 3`, empty payload).

### 2.1 Header bits

| Bits of H | Mask | Meaning | Status |
|---|---|---|---|
| 0–9 | `03FF` | **Length** = message ID (1) + payload (N) + CRC (2). | Low 8 bits [device] (all 14 captured frames, lengths 06…B8, parse and CRC-check with this rule). Bits 8–9 [ref] — no captured frame is longer than FF. |
| 10 | `0400` | Unknown. [ref] treats it as unused. | Set on the captured 0xC2 and 0x41 frames [device]; meaning unknown. |
| 11 | `0800` | Unknown. [ref] treats it as unused. | Set on the captured 0x61 and 0x63 frames [device]; meaning unknown. |
| 12 | `1000` | Message **type** flag (request vs response). | [ref], and the reference is internally inconsistent: its encoder sets the bit for *responses*, its decoder reads a set bit as *request*. On device it is set only on 0xC2 and 0x41 [device]; meaning unconfirmed. |
| 13 | `2000` | **Fragment** flag — frame is one piece of a larger transfer. [ref] uses it only for firmware and log dumps. | [ref]. Never set in the capture. |
| 14–15 | `C000` | Not described by the reference at all. On device it is a **2-bit rolling counter**: 0,1,2,3,0,1,… across all 14 consecutive frames regardless of message ID. | Values [device]; the interpretation "sequence number" is inferred. |

Header byte 2 of every captured frame, split out:

| Frame | Header bytes | Length | bits 15–14 (counter) | bit 13 | bit 12 | bit 11 | bit 10 |
|---|---|---|---|---|---|---|---|
| 0x61 | `28 08` | 28 | 0 | 0 | 0 | 1 | 0 |
| 0xC2 | `06 54` | 06 | 1 | 0 | 1 | 0 | 1 |
| 0x63 | `0D 88` | 0D | 2 | 0 | 0 | 1 | 0 |
| 0x41 | `29 D4` | 29 | 3 | 0 | 1 | 0 | 1 |
| 0xC2 | `06 14` | 06 | 0 | 0 | 1 | 0 | 1 |
| 0x27 | `0D 40` | 0D | 1 | 0 | 0 | 0 | 0 |
| 0x40 | `B8 80` | B8 | 2 | 0 | 0 | 0 | 0 |
| 0x27 | `0D C0` | 0D | 3 | 0 | 0 | 0 | 0 |
| 0xF4 ×4 | `1F 00`, `1F 40`, `1F 80`, `1F C0` | 1F | 0,1,2,3 | 0 | 0 | 0 | 0 |
| 0xF2 ×2 | `22 00`, `22 40` | 22 | 0,1 | 0 | 0 | 0 | 0 |

So the answer to "what are the upper bits of header byte 2": the top two bits are a frame
counter, and bits 2–4 of that byte (H bits 10–12) are flags whose exact meaning is not
established. A decoder must **mask the length with `03FF` and ignore bits 10–12 and 14–15**;
it must not reject a frame because they are non-zero.

For comparison, the reference project's own Buds2 revision-10 test fixture carries header
`28 10` for a 0x61 frame (bit 12 set, bits 10/11/14/15 clear) [ref] — different from this
device's `28 08`. Firmware versions evidently differ here; do not depend on these bits.

**What the host should put in the header** [ref]: the reference encoder writes the length in
bits 0–9 and leaves bits 10–15 zero for a normal request. It sets bit 12 only for the handful
of messages it sends as "response" type and bit 13 only for fragments — all of which are
firmware-update messages this project never sends. So every frame this project sends has
`byte1 = length`, `byte2 = 00` (lengths here never exceed FF). Whether this firmware wants a
counter in bits 14–15 from the host is an open question (section 6).

### 2.2 CRC16

| Property | Value | Status |
|---|---|---|
| Algorithm | CRC-16/XMODEM (a.k.a. CRC-16-CCITT "zero") | [device] |
| Polynomial | `1021` | [device] |
| Initial value | `0000` | [device] |
| Bit order | MSB first, no input reflection, no output reflection | [device] |
| Final XOR | none | [device] |
| Check value | CRC of ASCII `123456789` = `31C3` | computed |
| Covered bytes | Message ID + payload. Not SOM, not the header, not EOM. | [device] |
| Byte order on the wire | **Low byte first**, then high byte | [device] |

Equivalent receive-side check: CRC over (message ID, payload, CRC high byte, CRC low byte) —
i.e. with the two wire CRC bytes swapped — equals `0000`.

**Verification** (script computed the CRC over every frame in the capture; all 14 match):

| Frame | CRC bytes on wire | Wire value (LE) | Computed | Result |
|---|---|---|---|---|
| 0x61 (+0.199s) | `80 DD` | DD80 | DD80 | OK |
| 0xC2 (+0.199s) | `8B 7A` | 7A8B | 7A8B | OK |
| 0x63 (+0.222s) | `53 B1` | B153 | B153 | OK |
| 0x41 (+0.222s) | `87 90` | 9087 | 9087 | OK |
| 0xC2 (+0.362s) | `BA 49` | 49BA | 49BA | OK |
| 0x27 (+0.408s) | `43 F7` | F743 | F743 | OK |
| 0x40 (+0.482s) | `0A D5` | D50A | D50A | OK |
| 0x27 (+0.589s) | `28 17` | 1728 | 1728 | OK |
| 0xF4 (+3.566s) | `61 70` | 7061 | 7061 | OK |
| 0xF4 (+3.589s) | `71 12` | 1271 | 1271 | OK |
| 0xF4 (+4.332s) | `19 46` | 4619 | 4619 | OK |
| 0xF4 (+4.448s) | `6D E2` | E26D | E26D | OK |
| 0xF2 (+7.211s) | `92 0A` | 0A92 | 0A92 | OK |
| 0xF2 (+7.242s) | `36 09` | 0936 | 0936 | OK |

The reference project's Buds2 fixture frame also checks out with the same parameters
(wire `BE A3`, computed A3BE).

### 2.3 The `DD DD` after the first frame is not a stray byte

The first frame ends `… 00 00 80 DD DD`. Its CRC is DD80, sent low byte first as `80 DD`. The
first `DD` is the **CRC high byte**; the second `DD` is the EOM. The length field (28) puts
the EOM exactly at the second `DD`, and the next frame starts with `FD` right after it
[device].

Consequences for the stream decoder:

- **Frame by length, never by scanning for `DD`.** `DD` and `FD` are ordinary values and can
  appear in the payload or CRC.
- Read SOM, read two header bytes, take `length = H & 03FF`, wait until `length + 1` more
  bytes are buffered, then check that the last one is `DD` and that the CRC matches.
- One RFCOMM delegate callback can carry several frames [device] (the first callback holds
  two). Assume a frame can also be split across callbacks (not observed, but nothing prevents
  it) — keep a persistent buffer.
- On any failure (bad SOM, `length < 3`, bad EOM, bad CRC): drop bytes up to the next `FD`
  and try again. This is how [ref] resynchronises.

### 2.4 Worked examples for the encoder (computed, not yet sent to the device)

| Purpose | Bytes |
|---|---|
| Empty-payload request, ID 29 (serial number) | `FD 03 00 29 4B B5 DD` |
| ID 78, payload `00` (noise control off) | `FD 04 00 78 00 F0 81 DD` |
| ID 78, payload `01` (ANC) | `FD 04 00 78 01 D1 91 DD` |
| ID 78, payload `02` (ambient) | `FD 04 00 78 02 B2 A1 DD` |
| ID 86, payload `03` (EQ preset Dynamic) | `FD 04 00 86 03 5D 81 DD` |

Use these as encoder unit-test vectors. They follow the [ref] header rule (upper bits zero).

---

## 3. Captured frames, annotated

Source: `docs/captures/2026-11-10-connect.txt`. Both earbuds out of the case, listen only.
14 frames in 12 callbacks.

| # | Time | Callback bytes | ID | Name | Payload bytes |
|---|---|---|---|---|---|
| 1 | +0.199s | 0–43 | 61 | EXTENDED_STATUS_UPDATED | 37 |
| 2 | +0.199s | 44–53 | C2 | SPATIAL_AUDIO_DATA | 3 |
| 3 | +0.222s | 0–16 | 63 | VERSION_INFO | 10 |
| 4 | +0.222s | 17–61 | 41 | METERING_REPORT | 38 |
| 5 | +0.362s | 0–9 | C2 | SPATIAL_AUDIO_DATA | 3 |
| 6 | +0.408s | 0–16 | 27 | unnamed in [ref] (`UNKNOWN_39`) | 10 |
| 7 | +0.482s | 0–187 | 40 | USAGE_REPORT | 181 |
| 8 | +0.589s | 0–16 | 27 | unnamed in [ref] | 10 |
| 9 | +3.566s | 0–34 | F4 | unnamed in [ref] (`UNKNOWN_244`) | 28 |
| 10 | +3.589s | 0–34 | F4 | unnamed in [ref] | 28 |
| 11 | +4.332s | 0–34 | F4 | unnamed in [ref] | 28 |
| 12 | +4.448s | 0–34 | F4 | unnamed in [ref] | 28 |
| 13 | +7.211s | 0–37 | F2 | DEBUG_EVENT | 31 |
| 14 | +7.242s | 0–37 | F2 | DEBUG_EVENT | 31 |

### 3.1 Frame 1 — 0x61 EXTENDED_STATUS_UPDATED

```
FD 28 08 61 | 0A 03 37 60 01 00 11 00 00 03 BF 42 02 00 3A 01 3A 01 00 00
              03 66 00 01 00 10 00 00 00 01 11 02 00 00 00 00 00 | 80 DD | DD
```

Field meanings are [ref] (Buds2 branch of the reference decoder). Values are [device].

| Off | Byte | Field | Decoded value |
|---|---|---|---|
| p0 | 0A | Revision | 10 decimal |
| p1 | 03 | Ear type | 3. Meaning unknown; [ref] reads it and never uses it. (Its fixture also has 03.) |
| p2 | 37 | Battery left, percent | 55 % |
| p3 | 60 | Battery right, percent | 96 % |
| p4 | 01 | Coupled (both buds linked to each other) | yes |
| p5 | 00 | Main connection | 00 = right bud is primary (01 would be left) |
| p6 | 11 | Placement: high nibble left, low nibble right | left 1, right 1 = **both wearing** (see placement table in 4.2). The capture header only says "out of the case" — owner to confirm they were in the ears. |
| p7 | 00 | Case battery, percent | 0. Probably "not known" while neither bud is in the case, but that reading is a guess — see open questions. |
| p8 | 00 | Adjust sound sync (low-latency flag) | off |
| p9 | 03 | Equalizer mode | 3 = Dynamic (0 = off, see 4.6) |
| p10 | BF | Touch lock bit field | bit 7 = 1 → touch controls **enabled** (not locked). bits 0–5 all 1 → hold, triple tap, double tap, single tap, double-tap-in-call, hold-in-call all enabled. bit 6 = 0 (swipe; not a Buds2 feature). See 4.7. |
| p11 | 42 | Touch-and-hold action: high nibble left, low nibble right | left 4 = Spotify, right 2 = noise control (see 4.8) |
| p12 | 02 | Noise control mode | 2 = **ambient sound** (0 off, 1 ANC) |
| p13 | 00 | Voice wake-up (Bixby) | off |
| p14–15 | 3A 01 | Left bud colour/device ID, u16 LE | 013A = 314 decimal = Buds2 black |
| p16–17 | 3A 01 | Right bud colour/device ID, u16 LE | 013A = Buds2 black |
| p18 | 00 | Voice wake-up language | 0 |
| p19 | 00 | Seamless earbud connection, **inverted** | 00 = **enabled** |
| p20 | 03 | Find-my (FMM) config revision | 3 |
| p21 | 66 | Touch noise-control cycle bit field | right: ambient + ANC (off not in cycle); left: ambient + ANC. I.e. hold toggles ANC ↔ ambient on both sides. See 4.5. |
| p22 | 00 | "Speak seamlessly" | off |
| p23 | 01 | Ambient sound level | 1 (Buds2 range 0–2 [ref]) |
| p24 | 00 | Noise reduction (ANC) level | 0. [ref] treats 1 as "high"; whether Buds2 has ANC levels is unknown. |
| p25 | 10 | Hearing enhancement / L-R balance | 16 decimal = centre (range 0–32) |
| p26 | 00 | Extra-high ambient volume | off |
| p27 | 00 | Touch type (rev ≥ 2) | 0. Meaning unknown. |
| p28 | 00 | Noise control with one earbud (rev ≥ 3) | off |
| p29 | 01 | Customize ambient sound enabled (rev ≥ 5) | on |
| p30 | 11 | Custom ambient volume: high nibble left, low nibble right (rev ≥ 5) | left 1, right 1 |
| p31 | 02 | Custom ambient tone (rev ≥ 5) | 2 (range 0–4, 2 = middle) |
| p32 | 00 | Double-tap-edge volume ("outside double tap", rev ≥ 5) | off |
| p33 | 00 | Ambient sound during calls / sidetone (rev ≥ 6) | off |
| p34 | 00 | In-ear detection for calls / call path control, **inverted** (rev ≥ 7) | 00 = **enabled** |
| p35 | 00 | Spatial audio (rev ≥ 8) | off |
| p36 | 00 | Charging bit field (rev ≥ 10) | nothing charging (bit 4 left, bit 2 right, bit 0 case) |

Payload is exactly 37 bytes, which is the full revision-10 layout; no trailing bytes.

### 3.2 Frames 2 and 5 — 0xC2 SPATIAL_AUDIO_DATA

```
FD 06 54 C2 | 26 00 01 | 8B 7A DD
FD 06 14 C2 | 26 01 01 | BA 49 DD
```

| Off | Field | Frame 2 | Frame 5 |
|---|---|---|---|
| p0 | Event ID | 26 = "gyro bias existence" [ref] | 26 |
| p1 | unknown | 00 | 01 |
| p2 | unknown | 01 | 01 |

[ref] names event 26 but does not decode its data bytes. Head-tracking housekeeping; not
needed.

### 3.3 Frame 3 — 0x63 VERSION_INFO

```
FD 0D 88 63 | 00 00 01 81 01 01 81 01 00 00 | 53 B1 DD
```

| Off | Byte(s) | Field [ref] | Decoded |
|---|---|---|---|
| p0 | 00 | Left hardware revision, two nibbles | "rev0.0" |
| p1 | 00 | Right hardware revision | "rev0.0" |
| p2 | 01 | Left firmware variant: 00 → "E", anything else → "U" | U |
| p3 | 81 | Left firmware date: high nibble = year index, low nibble = month index | year index 8, month index 1 |
| p4 | 01 | Left firmware release index | 1 |
| p5–7 | 01 81 01 | Right firmware, same three fields | same |
| p8 | 00 | Left touch firmware version | 0 |
| p9 | 00 | Right touch firmware version | 0 |

Firmware string rule [ref]: `R177XX` + variant letter + `0A` + year letter + month letter +
release character, where year letters run O,P,Q,…,Z for index 0–11, month letters run A–L for
index 0–11, and the release character is index 0–9 → `0`–`9`, 10 and up → `A`–`Z`.
For this capture: **`R177XXU0AWB1`** on both buds. (A plausible Buds2 build name, but the
string is reconstructed, not read from the device as text — confirm against the 0x28 build
info or 0x22 SKU reply once requests are implemented.)

### 3.4 Frame 4 — 0x41 METERING_REPORT

```
FD 29 D4 41 | 02 11 35 00 | 37 00×16 | 60 00×16 | 87 90 DD
```

| Off | Bytes | Field [ref] | Decoded |
|---|---|---|---|
| p0 | 02 | Report revision | 2 |
| p1 | 11 | Connected sides: high nibble left, low nibble right (1 = connected) | both |
| p2–3 | 35 00 | Total battery capacity, i16 LE (present when revision ≥ 2) | 53. Unit unknown. |
| p4 | 37 | Left battery percent | 55 % (matches 0x61) |
| p5–8 | 00 00 00 00 | Left A2DP (music) use time, i32 LE | 0 |
| p9–12 | 00… | Left call (eSCO) use time | 0 |
| p13–16 | 00… | Left ANC-on time | 0 |
| p17–20 | 00… | Left ambient-on time | 0 |
| p21 | 60 | Right battery percent | 96 % (matches 0x61) |
| p22–37 | 00… | Right: same four i32 counters | 0 |

Time units unknown. The left block is present only if the left nibble of p1 is 1, likewise the
right block.

### 3.5 Frames 6 and 8 — 0x27 (no name in the reference)

```
FD 0D 40 27 | 01 5E 0A 06 43 10 42 4F 0F BF | 43 F7 DD
FD 0D C0 27 | 01 9E 0A 06 43 10 42 4F 0F BF | 28 17 DD
```

Payload meaning **unknown**. The two frames differ only in p1 (5E vs 9E). The reference has
no decoder for a B→H 0x27. Note that as an **H→B request** the reference documents 0x27
(tested on Buds+) as "disconnects the device" — it is on the never-send list (section 5).

### 3.6 Frame 7 — 0x40 USAGE_REPORT

p0 = 14 → 20 decimal items. Each item is 9 bytes: a 5-byte ASCII key padded with 00, then a
u32 LE value. `1 + 20 × 9 = 181` payload bytes [device]. Key meanings are [ref]; units are
not documented.

| Off | Key | Value (hex → dec) | Meaning [ref] |
|---|---|---|---|
| p1 | FBDA | FE → 254 | Wear both, noise control off (bucket A) |
| p10 | FBDB | 2B → 43 | same, bucket B |
| p19 | FBDC | 4C → 76 | same, bucket C |
| p28 | FLDA | 59 → 89 | Wear left only, noise control off (A) |
| p37 | FLDB | 15 → 21 | (B) |
| p46 | FLDC | 06 → 6 | (C) |
| p55 | FRDA | FF → 255 | Wear right only, noise control off (A) |
| p64 | FRDB | 42 → 66 | (B) |
| p73 | FRDC | 07 → 7 | (C) |
| p82 | NBDA | FE → 254 | Wear both, ANC (A) |
| p91 | NBDB | FE → 254 | (B) |
| p100 | NBDC | A7 → 167 | (C) |
| p109 | ABDA | FE → 254 | Wear both, ambient (A) |
| p118 | ABDB | FE → 254 | (B) |
| p127 | ABDC | 86 → 134 | (C) |
| p136 | WLOD | 82 → 130 | Wearing duration, left |
| p145 | WROD | FF → 255 | Wearing duration, right |
| p154 | WALD | FE → 254 | Wearing duration, both |
| p163 | BSCL | 4722 → 18210 | Left battery charging cycle. [ref]'s separate 0xCE decoder divides a similar counter by 10000; if the same scale applies this is ≈ 1.8 cycles — unconfirmed. |
| p172 | BSCR | 4779 → 18297 | Right battery charging cycle |

What the A/B/C suffixes distinguish is unknown. Telemetry only.

### 3.7 Frames 9–12 — 0xF4 (no name in the reference)

```
FD 1F 00 F4 | 01 00 00 00 11 5E 29 22 3C 24 23 47 01 F5 14 1B 00 00 07 04 00 00 01 00 5E 00 00 00 | 61 70 DD
FD 1F 40 F4 | 4C 08 00 00 60 60 A1 23 35 25 24 9E FF F9 0F 1B 2D 00 05 04 00 00 01 00 5E 00 00 00 | 71 12 DD
FD 1F 80 F4 | 01 00 00 00 11 1B CA 0A 00 00 1D 48 01 23 10 0A 00 00 07 04 00 00 01 00 1B 00 00 00 | 19 46 DD
FD 1F C0 F4 | 4E 08 00 00 60 37 89 15 00 00 25 74 FF DC 0E 0A 2D 00 07 04 00 00 02 00 1B 00 00 00 | 6D E2 DD
```

Payload meaning **unknown** — the reference lists ID F4 as unknown and has no decoder.
Observations only: 28-byte payload; frames arrive in pairs (23 ms and 116 ms apart); the pair
members differ in p0–p4 (`01 00 00 00 11` vs `4C/4E 08 00 00 60`); p24 is the same within a
pair (5E, then 1B). No interpretation is offered.

### 3.8 Frames 13 and 14 — 0xF2 DEBUG_EVENT

```
FD 22 00 F2 | 4C 4C 7C 20 00 C1 00 00×20 30 00 01 00 | 92 0A DD
FD 22 40 F2 | 52 15 7B 20 00 C1 00 00×20 30 00 01 00 | 36 09 DD
```

| Off | Field [ref] | Frame 13 | Frame 14 |
|---|---|---|---|
| p0 | Source bud as ASCII | 4C = "L" | 52 = "R" |
| p1–4 | Timestamp, u32 LE, milliseconds | 00207C4C = 2 128 972 ms (≈ 35.5 min) | 00207B15 = 2 128 661 ms |
| p5 | Event ID | C1 — not in the reference's event list, meaning unknown | C1 |
| p6 | Message type | 00 | 00 |
| p7–30 | Event data | 20 × 00, then `30 00 01 00`; meaning unknown | same |

[ref] states the event IDs and data are "mostly unknown". Debug telemetry.

---

## 4. Message table

"Buds2" column: **yes** = the reference's Buds2 feature list enables it (with minimum revision
where it gives one; this unit is revision 10, so all revision gates pass); **no** = the
reference does not enable it for Buds2; **unknown** = the reference is silent or ambiguous.
Unless marked [device], everything is [ref].

### 4.0 Writes confirmed on device

Sent from `macbuds` on 2026-11-10 (firmware `R177XXU0AWB1`) and read back on a fresh
connection. All were sent with header upper bits zero and **without** MANAGER_INFO (88) or any
other handshake — neither is needed (answers open questions 2, 3 and 6).

| ID | Message | Reply observed | Read-back |
|---|---|---|---|
| 84 | Ambient level | `42 84 <level>` | changed [device] |
| 79 | Touch noise cycle | `42 79` + the six flags | changed [device] |
| 6F | Noise control with one earbud | **nothing** — no 42, no 51 | changed [device] |
| 86 | Equalizer preset | `42 86 <preset>` | changed [device] |
| 90 | Touch lock + gesture flags | `42 90` + the seven flags | changed [device]. Confirms the polarity: p0 = 00 locks, and status p10 bit 7 clear = locked (answers open question 10). |
| 92 | Touch-and-hold action | `42 92 <left> <right>` | changed [device] |
| 8F | L/R balance | `42 8F <value>` | changed [device] |
| 95 | Double-tap edge volume | `42 95 <flag>` | changed [device] |
| AF | Seamless connection | `42 AF <inverted flag>` | changed [device]; inversion confirmed (payload 01 = off) |
| 6E | In-ear detection for calls | **nothing** | changed [device]; inversion confirmed |
| 8B | Ambient sound during calls | **nothing** | changed [device] |
| 82 | Customize ambient sound | **nothing** | changed [device] (tone 2 → 3 → 2) |
| 29 | Serial number request | reply ID 29, 22 ASCII bytes (11 left + 11 right) | — |
| 22 | SKU request | reply ID 22, 28 ASCII bytes: `SM-R177NZKAMEA` for each bud | — |
| 28 | Build info request | **no reply within 2 s** — not sent any more | — |
| 94 | Battery type request | **no reply within 2 s** — not sent any more | — |
| 26 | Sensor dump request | reply ID 26, 108 bytes, **all zero** except p2–p4 (firmware bytes `01 81 01`) — useless on this firmware, not sent any more | — |
| 96 | Extra-high ambient volume | **nothing**, and status p26 stayed 00 — **Buds2 firmware ignores it.** Removed from the allowlist. (Answers open question 11.) | unchanged [device] |
| 83 | ANC level (high/low) | `42 83 01` | status p24 changed 00 → 01 and persisted across reconnect [device]. The firmware accepts and stores it; **whether it alters the cancellation is not established** — owner to compare by ear. |
| A0 / A1 / A6 / 9D | Find my earbuds, fit test | **never sent yet** — implemented from [ref] only | — |
| 78 | Noise control mode | **Depends on whether the mode changes** (see 4.3): `42 78 <mode>` when it does, `77 <current mode> …` when it does not | changed [device], both earbuds worn, owner heard it switch |

### 4.1 Acknowledgement and response formats (B→H)

The reference never waits for an acknowledgement before sending the next message; it listens
for them as events. Which settings produce which reply on Buds2 is not recorded anywhere in
the reference and must be learned on device — see open questions.

| ID | Name | Dir | Payload | Notes |
|---|---|---|---|---|
| 42 | ACKNOWLEDGEMENT ("universal ack") | B→H | p0 = ID of the message being acknowledged; p1… = echo of the accepted parameters in that message's own layout | For the two inverted settings (6E, AF) the echoed byte is inverted the same way as the request. For 79 the echo is six booleans: left ANC, left ambient, left off, right ANC, right ambient, right off. For 90 the echo is p0 = touch-enabled flag then the six per-gesture flags. For 92 it is left option, right option. For A2 it is left mute, right mute. For 82 it is enabled, left level, right level, tone (plus two more bytes on newer models). |
| 51 | RESP (generic response) | B→H | p0 = ID of the original message; p1 = result code (00 = success); p2 = optional extra byte | Result codes: 00 success, 01 failed, 09 invalid parameter, 17 invalid state, 1B reject, 89 undefined message ID, 98 not allowed, 9C timeout (subset of a longer [ref] list). Treat any non-zero as failure. |

### 4.2 Status

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 61 | EXTENDED_STATUS_UPDATED | B→H | Full settings snapshot. Layout in 3.1 (that table **is** the Buds2 revision-10 layout). Fields gated by revision: p27 ≥ 2; p28 ≥ 3; p29–p32 ≥ 5; p33 ≥ 6; p34 ≥ 7; p35 ≥ 8; p36 ≥ 10. | Sent unsolicited right after the channel opens [device]. [ref] also sees it again on events such as case open/close and wear changes. The reference answers each one by sending 88 (manager info). | yes [device] |
| 60 | STATUS_UPDATED | B→H | p0 revision; p1 battery left %; p2 battery right %; p3 coupled (0/1); p4 main connection (00 right, 01 left); p5 placement, high nibble left / low nibble right; p6 case battery %; p7 charging bit field (bit 4 left, bit 2 right, bit 0 case) when revision ≥ 10 | Unsolicited, on battery/placement change. | yes [ref]; not seen in the 8-second capture |
| — | "Resend status" request | H→B | **None known.** The reference contains no message that asks for 61 or 60 again; it relies on the unsolicited ones. | — | unknown |
| 88 | MANAGER_INFO | H→B | p0 = 01; p1 = client type (01 Samsung phone, 02 other); p2 = Android SDK level (reference sends 22 hex = 34) | The reference sends this after every 61. Older reference notes say the buds "probably expect" it and that it may unlock phone-only features on old firmware. No reply documented. The capture shows the buds streaming status and telemetry without it [device]. | unknown whether required |
| A7 | UPDATE_TIME | H→B | p0–7 = Unix time in ms, i64 LE; p8–11 = UTC offset in ms, i32 LE (the reference's encoder has a bug and always sends zeros in p8–11) | Reference notes say the Android app sends this whenever it receives a 51. Not sent by the reference itself. | unknown |

Placement nibble values: 0 disconnected, 1 wearing, 2 idle (out of ear, out of case),
3 in open case, 4 in closed case.

### 4.3 Noise control

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 78 | NOISE_CONTROLS (set mode) | H→B | p0: 00 off, 01 ANC, 02 ambient sound. (03 = adaptive, newer models only — do not send.) | Two cases [device]. **Mode changes:** `42 78 <mode>`, and no 77. **Mode does not change** — it is already that mode, or no earbud is worn and the buds refuse: `77` carrying the mode in effect (e.g. `77 02 11 00 66 08` when asked for ambient while already in ambient; `77 00 23 01 66 08` when asked for anything with no earbud worn). A client must accept either. | yes [device] |
| 77 | NOISE_CONTROLS_UPDATE | B→H | p0 = mode now in effect (same values). [ref] describes p1 as an optional wearing state. **On this firmware the payload is five bytes** [device]. Samples: `00 23 01 66 08` (left idle, right in open case), `02 11 00 66 08` and `01 11 00 66 08` (both worn). p1 matches the placement byte (high nibble left, low nibble right), p3 matches the touch noise cycle byte; p2 was 01 when unworn and 00 when worn; p4 unknown. Only p0 is used by the code. | Sent when the mode changes on the buds (e.g. touch-and-hold) **and as the reply to 78** [device]. | yes |
| 84 | AMBIENT_VOLUME (ambient sound level) | H→B | p0 = level, 00–02 on Buds2 | 42 with p0 = 84, p1 = level | yes |
| 6F | SET_ANC_WITH_ONE_EARBUD (noise control with one earbud) | H→B | p0: 01 on, 00 off | **none** [device] | yes, revision ≥ 3 [device] |
| 79 | SET_TOUCH_AND_HOLD_NOISE_CONTROLS (touch cycle) | H→B | Six bytes on Buds2 revision ≥ 5: left ANC, left ambient, left off, right ANC, right ambient, right off — each 00/01. Exactly two of the three per side are 01. (Revision < 5: three bytes, one set for both sides.) See 4.5. | 42, echoing the six flags | yes |
| 82 | CUSTOMIZE_AMBIENT_SOUND | H→B | p0 enabled (00/01); p1 left level; p2 right level (00–02 on Buds2); p3 tone (00–04, 02 neutral) | 42 | yes, revision ≥ 5 |
| 96 | EXTRA_HIGH_AMBIENT (Labs: extra-high ambient volume) | H→B | p0: 01 on, 00 off. When on, ambient level range gains one step. | 42 | **unknown** — the status byte (p26) exists for Buds2, but the reference's Buds2 feature list does not enable this toggle |
| 80 / 81 | SET_AMBIENT_MODE / AMBIENT_MODE_UPDATED | H→B / B→H | p0 on/off | — | no (older models; Buds2 uses 78/77) |
| 98 / 9B | SET_NOISE_REDUCTION / NOISE_REDUCTION_MODE_UPDATE | H→B / B→H | p0 on/off | — | no (older models) |
| 83 | NOISE_REDUCTION_LEVEL (ANC high/low) | H→B | p0: 01 high, 00 low | 42 | no (not in Buds2 feature list) |

### 4.4 Calls, connection, balance, Labs

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 6E | SET_CALL_PATH_CONTROL (in-ear detection for calls) | H→B | p0 **inverted**: 00 = enabled, 01 = disabled | 42 (echo also inverted) | yes, revision ≥ 7 |
| 8B | SET_SIDETONE (ambient sound during calls) | H→B | p0: 01 on, 00 off | 42 | yes, revision ≥ 6 |
| AF | SET_SEAMLESS_CONNECTION (seamless earbud connection) | H→B | p0 **inverted**: 00 = enabled, 01 = disabled | 42 (echo also inverted) | yes |
| 8F | SET_HEARING_ENHANCEMENTS (L/R balance) | H→B | p0 = 00–20 hex (0–32 decimal), 10 hex = centre | not documented | yes. Which end is "left" is not stated in the reference. |
| 95 | OUTSIDE_DOUBLE_TAP (Labs: double-tap earbud edge for volume) | H→B | p0: 01 on, 00 off | 42 | yes, revision ≥ 5 |
| 87 | GAME_MODE (Labs: gaming mode) | H→B | One byte. Old reference notes describe it as a bit field driven by phone state ("game in foreground", "screen on"); exact values not pinned down. The reference lists the feature for Buds2 but contains no code that sends it. | unknown | unknown — do not implement until values are established |
| 85 | ADJUST_SOUND_SYNC | H→B | one byte, on/off | 42 | unknown |
| 9F | PASS_THROUGH ("relieve pressure with ambient") | H→B | p0 on/off | 42 | no (Buds Live only) |

### 4.5 Touch noise-control cycle (ID 79 and status p21)

Request payload per side is three flags in the order **ANC, ambient, off**:

| Cycle | Flags |
|---|---|
| ANC ↔ ambient | 01 01 00 |
| ANC ↔ off | 01 00 01 |
| Ambient ↔ off | 00 01 01 |

Left side first, then right. Status byte p21 reports the same thing as bits:

| Bit | Meaning |
|---|---|
| 0 | right: off in cycle |
| 1 | right: ambient in cycle |
| 2 | right: ANC in cycle |
| 4 | left: off in cycle |
| 5 | left: ambient in cycle |
| 6 | left: ANC in cycle |

Captured p21 = 66 → ANC ↔ ambient on both sides [device].

### 4.6 Equalizer

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 86 | EQUALIZER | H→B | p0 = preset byte below | 42 with p0 = 86, p1 = preset | yes |

| Byte | Preset | Samsung app name |
|---|---|---|
| 00 | Equalizer off | Normal |
| 01 | Bass boost | Bass boost |
| 02 | Soft | Soft |
| 03 | Dynamic | Dynamic |
| 04 | Clear | Clear |
| 05 | Treble boost | Treble boost |

The same byte is reported in status p9. Captured value 03 = Dynamic [device]. Byte 07 selects
a 9-band custom EQ on much newer models (with message 89); not a Buds2 feature — do not send.

### 4.7 Touch lock

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 90 | LOCK_TOUCHPAD | H→B | Buds2 revision ≥ 7, seven bytes, each 00/01: p0 = touch controls enabled (**01 = not locked, 00 = lock everything**); p1 single tap enabled; p2 double tap enabled; p3 triple tap enabled; p4 touch-and-hold enabled; p5 double tap during calls enabled; p6 touch-and-hold during calls enabled. (Revision 4–6: only p0–p4. Revision < 4: single byte, 01 = locked — note the opposite sense.) | 42 echoing the same bytes | yes — per-gesture flags revision ≥ 4, call flags revision ≥ 7 |
| 91 | TOUCH_UPDATED | B→H | p0 = touchpad locked flag | Notification | unknown on Buds2 |

Status byte p10 bit layout (Buds2):

| Bit | Meaning when 1 |
|---|---|
| 0 | touch-and-hold enabled |
| 1 | triple tap enabled |
| 2 | double tap enabled |
| 3 | single tap enabled |
| 4 | double tap during calls enabled (revision ≥ 7) |
| 5 | touch-and-hold during calls enabled (revision ≥ 7) |
| 6 | swipe (not a Buds2 feature) |
| 7 | touch controls enabled, i.e. **not** locked |

Captured p10 = BF → not locked, everything enabled [device]. The polarity of bit 7 is [ref]
(its fixture has 3F with "locked = true"); confirm on device by toggling.

### 4.8 Touch-and-hold action

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 92 | SET_TOUCHPAD_OPTION | H→B | p0 = left action; p1 = right action | 42 echoing both | yes |
| 93 | SET_TOUCHPAD_OTHER_OPTION | B→H | p0 = action byte (05 or 06) — buds report that a custom-action hold happened so the host app can react | — | yes |

| Byte | Action |
|---|---|
| 01 | Voice assistant |
| 02 | Switch noise control |
| 03 | Volume (the reference does not spell out direction per side; in Samsung's app left is down, right is up — unverified) |
| 04 | Spotify |
| 05 | "Other" (left) — host-defined action, reported via 93 |
| 06 | "Other" (right) — host-defined action, reported via 93 |

Status p11 carries the same values as nibbles (high = left, low = right). Captured 42 → left
Spotify, right noise control [device].

### 4.9 Find my earbuds

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| A0 | FIND_MY_EARBUDS_START | H→B | empty | not documented | yes |
| A6 | FIND_MY_EARBUDS_ON_WEARING_START | H→B | empty. Starts the beeping even if a bud is being worn; the reference uses this instead of A0 when available. | not documented | yes, revision ≥ 9 |
| A1 | FIND_MY_EARBUDS_STOP | H→B and B→H | empty. The buds also **send** A1 to the host when the search is stopped from the buds' side. | — | yes |
| A2 | MUTE_EARBUD | H→B | p0 = mute left (00/01); p1 = mute right (00/01) | 42 echoing both | yes |
| A3 | MUTE_EARBUD_STATUS_UPDATED | B→H | p0 = left muted; p1 = right muted | Notification | yes |

The beep is loud. The reference warns the user when a bud is being worn. This is an audible
effect — the owner's check.

### 4.10 Fit test

| ID | Name | Dir | Payload | Reply | Buds2 |
|---|---|---|---|---|---|
| 9D | CHECK_THE_FIT_OF_EARBUDS | H→B | p0: 01 start, 00 stop | result arrives as 9E | yes |
| 9E | CHECK_THE_FIT_OF_EARBUDS_RESULT | B→H | p0 = left result; p1 = right result. 00 bad fit, 01 good fit, 02 test failed | The reference sends 9D 00 again after receiving the result. | yes |

The reference shows a warning unless both buds are being worn.

### 4.11 Device information

All requests have an empty payload. The reply uses the same message ID as the request.

| ID | Name | Dir | Reply payload | Buds2 |
|---|---|---|---|---|
| 63 | VERSION_INFO | H→B request; B→H reply, also unsolicited on connect [device] | See 3.3 | yes [device] |
| 28 | DEBUG_BUILD_INFO | H→B / B→H | Whole payload is one ASCII string (build info) | yes (the reference requests it for every model newer than the original Buds) |
| 29 | DEBUG_SERIAL_NUMBER | H→B / B→H | p0–10 = left serial, 11 ASCII chars; p11–21 = right serial, 11 ASCII chars | yes |
| 22 | DEBUG_SKU | H→B / B→H | p0–13 = left SKU, 14 chars; p14–27 = right SKU, 14 chars (right part may be absent) | yes |
| 94 | BATTERY_TYPE | H→B / B→H | p0–1 = left battery type, 2 ASCII chars; p2–3 = right | yes |
| CD | CRADLE_SERIAL_NUMBER | H→B / B→H | p0–8 = case firmware version, 9 ASCII chars; p9–19 = case serial, 11 ASCII chars | unknown — the reference only requests it on models with a feature flag Buds2 lacks |
| 26 | DEBUG_GET_ALL_DATA | H→B / B→H | Sensor dump, layout below | yes |
| CE | SOC_BATTERY_CYCLE | B→H | 16 bytes: left then right, each a **big-endian** i64; divide by 10000 for cycle count | unknown; the request form is listed under "unknown debug" in the reference notes — do not send |
| B4 | FOTA_DEVICE_INFO_SW_VERSION | B→H | ASCII firmware version string | Do not request: the ID sits in the firmware-update range (section 5). Use 63/28/22 instead. |

Battery and case info comes from 61/60 (percentages, charging flags) and, in more detail,
from 26.

DEBUG_GET_ALL_DATA (26) reply layout for Buds2. All 16-bit fields are signed, little-endian.

| Off | Size | Field |
|---|---|---|
| p0 | 1 | Message version |
| p1 | 1 | Hardware revision, two nibbles |
| p2–4 | 3 | Firmware version, same three-byte encoding as 3.3 (variant: bit 0 of the first byte, 0 → E, 1 → U) |
| p5 | 1 | Touch firmware version |
| p6–11 | 6 | Bluetooth address of the bud answering |
| p12–17 | 6 | Bluetooth address of the peer bud |
| p18, p20, p22 | 2 each | Left accelerometer X, Y, Z |
| p24, p26, p28 | 2 each | Right accelerometer X, Y, Z |
| p30 / p32 | 2 each | Left proximity / left proximity offset |
| p34 / p36 | 2 each | Right proximity / right proximity offset |
| p38 / p40 | 2 each | Left / right thermistor, × 0.1 °C |
| p42 | 2 | Left battery state of charge, % |
| p44 | 2 | Left cell voltage, × 0.01 V |
| p46 | 2 | Left current, × −0.1 mA |
| p48, p50, p52 | 2 each | Right: state of charge, voltage, current (same scales) |
| p54 / p56 | 2 each | Left / right touch sensor absolute value |
| p58, p60, p62 | 2 each | Left touch sensor diff 0–2 |
| p64, p66, p68 | 2 each | Right touch sensor diff 0–2 |
| p70 / p71 | 1 each | Left / right hall sensor |
| p72 / p74 | 2 each | Left / right "PR" (meaning not given) |
| p76 / p78 | 2 each | Left / right "WD" (meaning not given) |
| p80 / p81 | 1 each | Left / right "cradle flag" |
| p82 / p83 | 1 each | Case battery % as seen by left / right bud |

Byte order of the two Bluetooth addresses is not checked here.

### 4.12 Unsolicited frames seen in the capture

| ID | Name [ref] | What it is | Safe to ignore? |
|---|---|---|---|
| 61 | EXTENDED_STATUS_UPDATED | Settings snapshot | **No** — this is the state source |
| 63 | VERSION_INFO | Hardware/firmware versions | Yes (useful for an "about" line) |
| C2 | SPATIAL_AUDIO_DATA | Head-tracking sensor housekeeping (event 26, gyro bias) | Yes |
| 41 | METERING_REPORT | Battery + usage-time counters | Yes |
| 27 | none (`UNKNOWN_39`) | Unknown; 10-byte payload | Yes, on the evidence that the reference ignores it too. Never *send* 27. |
| 40 | USAGE_REPORT | Usage statistics key/value list | Yes |
| F4 | none (`UNKNOWN_244`) | Unknown; 28-byte payload, arrives in pairs | Yes, same basis |
| F2 | DEBUG_EVENT | Per-bud debug event with timestamp | Yes. The reference notes say sending F2 to the buds returns an error. |

"Safe to ignore" means: decode the frame, verify the CRC, drop the payload, send nothing
back. The reference sends no acknowledgement for any of these, and the buds kept streaming
for the full 8 seconds with no reply from the host [device]. Unknown IDs must never crash the
decoder and never trigger a reply.

---

## 5. Never send

Blocklist for `BudsProtocol`'s encoder. The safest implementation is an **allowlist** of the
IDs documented as H→B in section 4; this list exists so the dangerous ones are explicitly
named and tested. Names and effects are [ref]; several effects were observed by the reference
author on Buds+ and are assumed, not verified, to apply to Buds2.

**Firmware update (FOTA) — the whole range B0–BE:**

| ID | Name |
|---|---|
| B0 | FOTA_V1_SESSION |
| B1 | FOTA_V1_CONTROL |
| B2 | FOTA_V1_DOWNLOAD_DATA |
| B3 | FOTA_V1_UPDATED |
| B4 | FOTA_DEVICE_INFO_SW_VERSION |
| B5 | FOTA_BACKGROUND_NEED |
| B6 | FOTA_BACKGROUND_READY |
| B7 | FOTA_CHANGE_HALL_IC_STATUS |
| B8 | unnamed, inside the FOTA range |
| B9 | FOTA_RESULT |
| BA | FOTA_EMERGENCY |
| BB | FOTA_OPEN (starts a firmware transfer; the reference notes also record it closing the audio channel) |
| BC | FOTA_CONTROL |
| BD | FOTA_DOWNLOAD_DATA |
| BE | FOTA_UPDATE |

**Factory reset, power, and connection:**

| ID | Name | Effect |
|---|---|---|
| 50 | RESET | **Factory reset.** Replies with ID 50, p0 = result code. |
| 52 | REBOOT | Forces a crash/reboot |
| 53 | POWEROFF | Hard shutdown; reference notes warn it may not recover until the buds are put in the case |
| 56 | RFTESTMODE | Puts the buds in an RF test/development mode; they disconnect and rename themselves |
| 27 | (unnamed) | Disconnects the buds |
| 72 | PAIRING_MODE | Forces pairing mode |
| 70 | MAIN_CHANGE | Forces primary-earbud role switch (p0: 01 left, 00 right) |
| 71 | PROFILE_CONTROL | Bluetooth profile control; effect not documented |
| 10 | SET_MODE_CHANGE | Mode switch; effect not documented |

**Self-test, factory and hidden commands:**

| ID | Name | Effect |
|---|---|---|
| AB | SELF_TEST | Runs the hardware self-test |
| 12 | HIDDEN_CMD_MODE | Enters the hidden factory command mode |
| 13 | HIDDEN_CMD_DATA | Executes a factory command (includes software reboot and identity-writing commands) |
| 15, 16, 17 | HIDDEN_FACTORYINFO_MODE1–3 | Factory info modes |
| 20 | SET_DEBUG_MODE | Debug mode switch |
| 4A | AGING_TEST_REPORT | Factory aging test |
| 4B | ACT_TEST_CMD | Factory test command |
| 8D | TAP_TEST_MODE | Tap test mode |
| 2A | ACC_SENSOR_LOGGING | Sensor logging |

**Log and core-dump triggers — the whole range 30–3D:**

| ID | Name | Effect |
|---|---|---|
| 30 | LOG_COREDUMP_COMMIT_SUICIDE | Deliberately crashes the firmware to produce a core dump |
| 31, 32, 33, 38 | LOG_COREDUMP_DATA_SIZE / DATA / COMPLETE / DATA_DONE | Core dump transfer |
| 34, 35, 36, 39 | LOG_TRACE_START / DATA / COMPLETE / DATA_DONE | Trace dump transfer |
| 37 | LOG_TRACE_ROLE_SWITCH | Forces a role switch during log download |
| 3A, 3B | LOG_SESSION_OPEN / CLOSE | Open drops the music stream |
| 3C | LOG_GET_CONFIG | — |
| 3D | LOG_SET_CONFIG | With an empty payload the reference notes record a CPU exception and reboot |
| 21 | DEBUG_MODE_LOG | — |

**Pairing data, keys and stored identity:**

| ID | Name | Effect |
|---|---|---|
| D4 | (dump bonded devices) | Makes the buds emit their bonded-device list **including Bluetooth link keys** (replies arrive as D6) |
| AA | COUPLING_HELPER_WRITE | Writes left/right coupling data |
| A9 | COUPLING_HELPER_READ | Returns addresses and internal data; not needed |
| AC | SET_FMM_CONFIG | Overwrites the SmartThings Find keys/tokens stored on the buds |
| AD | GET_FMM_CONFIG | Reads those secrets; not needed |
| CF | RESET_BATTERY_SOC_CYCLE | Resets the battery cycle counter |
| D0, D1, E0–E5 | (unnamed) | Unknown-effect debug triggers listed in the reference notes |

**Everything else:**

- ID 01 (the "alternative protocol" wrapper), 0F and 64 (hot command), 66/67 (Bixby keyword,
  hearing test result), 80–83 and 98 (older-model noise control), 7A–7E, C3, C5–C9 (features
  of newer models).
- **Any ID the reference lists as unknown, and any ID not given an H→B row in section 4.**
  AGENTS.md rule 2 already forbids these; the encoder should refuse them.
- Never set header bit 13 (fragment). Only firmware and log transfers use it.

---

## 6. Open questions

1. **Header bits 10 and 11.** Set on some B→H frames [device]; the reference calls them
   unused. Meaning unknown.
2. **Header bit 12 (type).** The reference's encoder and decoder disagree on its polarity,
   and on device it is set only on 0xC2 and 0x41. Unknown whether the buds care what the host
   sends here. Plan: send 0 (as the reference does for requests).
3. **Header bits 14–15 (rolling counter).** Clearly a counter in B→H frames [device]. Unknown
   whether the buds expect the host to count too. The reference sends 0 always, and its Buds2
   fixture also shows 0. First real request (suggest 29, serial number — read-only) will
   settle it.
4. **Length field width.** Reference code masks 10 bits; its older notes say 11. No captured
   frame exceeds FF, and bit 10 is demonstrably used as a flag on this device, so 10 bits (or
   fewer) is right — but bits 8–9 are unverified.
5. **Is there a "send status again" request?** None found. If the app needs a refresh it may
   have to rely on the unsolicited 61/60, or reconnect.
6. **Is MANAGER_INFO (88) needed?** The reference sends it after every 61. The buds stream
   happily without it for 8 seconds, but it is unknown whether settings writes are accepted
   without it, or whether it changes behaviour (the client-type byte may enable/disable
   phone-only features).
7. **Which reply each setting produces** (42 with echo, 51 with result code, both, or
   nothing), and how long to wait. To be recorded per message as each one is first sent.
8. **Case battery p7 = 00** with both buds out of the case. "Unknown while out of case" is a
   guess; the reference fixture shows a real value (51 %) with both buds worn.
9. **Placement p6 = 11 means "wearing"** per the reference. Owner to confirm the buds were in
   the ears during the capture; if they were lying on a desk, the table in 4.2 is wrong.
10. **Touch lock polarity** (p10 bit 7, and p0 of message 90): from the reference only.
11. **Extra-high ambient (96) on Buds2.** Status byte exists; reference does not enable the
    toggle for Buds2. Unknown whether the firmware accepts it.
12. **Gaming mode (87) payload values.** Not established.
13. **L/R balance direction** for 8F (which of 00 / 20 is full left).
14. **Ear type p1 = 03, touch type p27, ANC level p24:** meanings unknown for Buds2.
15. **Frames 27 and F4** (B→H): payloads entirely unknown.
16. **DEBUG_EVENT ID C1** and its data: unknown.
17. **Firmware string `R177XXU0AWB1`** is reconstructed from three bytes using the
    reference's letter tables; not yet cross-checked against a text reply (28 or 22).
18. **Volume touch action (03)** direction per side, and whether Spotify (04) does anything
    without a Samsung phone.
19. **CRADLE_SERIAL_NUMBER (CD)** support on Buds2: unknown.
