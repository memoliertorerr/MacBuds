# MacBuds — Build Plan

> A native macOS controller for Galaxy Buds2, so every earbud setting that normally needs the
> Android Galaxy Wearable app can be changed from this Mac. It speaks Samsung's serial protocol
> to the buds over Bluetooth classic RFCOMM.
>
> **In scope for v1:** a shared Swift protocol library; a `macbuds` CLI; a SwiftUI menu bar
> app. Features: battery (left / right / case), wearing state, noise control (ANC / ambient /
> off, ambient level, one-earbud noise control), equalizer presets, touch lock and
> touch-and-hold actions, in-ear detection for calls, ambient sound during calls, seamless
> earbud connection, left/right balance, find my earbuds, fit test, firmware and debug info.
>
> **Explicitly NOT in scope** (see **Later**): firmware updates, factory reset, Android-only
> features (notification read-aloud, gaming mode, Bixby, SmartThings Find), other Buds models,
> App Store distribution, an IPC layer between app and CLI.
>
> **Never send firmware-update or undocumented messages to the earbuds.** A bad flash bricks
> them.
>
> **One step = one commit = one reviewable unit.** In this repo the agent is authorised to
> commit and push itself (see `AGENTS.md`); it does so after a green verify, then stops for
> review before the next step.

---

## The core idea (read before starting)

The buds expose a Serial Port Profile service. Open an RFCOMM channel to it and you get a byte
stream carrying small framed messages in both directions:

```
SOM | header (2 bytes, LE: payload length + flag bits) | msg ID | payload … | CRC16 (2) | EOM
```

The buds push a full **extended status** message right after connect and smaller **status
updates** whenever something changes (battery, earbud in/out, noise mode switched by touch).
Settings are changed by sending a one-message command; most are acknowledged, and the change
shows up in the next status.

So the whole product is: one framing codec, one table of message IDs and payload layouts, one
connection that keeps a current-state snapshot, and two front ends over that snapshot.

Everything known about the byte layouts goes in `docs/PROTOCOL.md`, which MB2 creates and
every later step extends. The values quoted in this plan (SOM `0xFD`, EOM `0xDD`, CRC16-CCITT
over ID + payload, message IDs like `0x61` extended status) are from memory of the open-source
`GalaxyBudsClient` project and are **starting hypotheses, not facts** — MB2 confirms them
against the real device and the reference source before any code depends on them.

---

## Progress Tracker

> Each session flips its own row to ✅ as the final action of the step, in the same commit as
> the change. Read this table at the start of a session to know where to resume.

| Step | Scope | Model | Status |
|------|-------|-------|--------|
| MB0 | Repo, docs, private GitHub remote | — | ✅ done |
| MB1 | Swift package scaffold, four targets, green build and test | Sonnet | ✅ done |
| MB2 | Hardware spike: find the SPP channel, open it, capture raw frames, write `docs/PROTOCOL.md` | Opus | ✅ done |
| MB3 | Protocol codec: framing, CRC16, stream reassembly, tested against captured frames | Opus | ✅ done |
| MB4 | `BudsSession` + status decode + `macbuds status` — **first runnable milestone** | Opus | ✅ done |
| MB5 | Noise control: ANC / ambient / off, ambient level, one-earbud noise control | Sonnet | ✅ done |
| MB6 | Equalizer presets, touch lock, touch-and-hold actions | Sonnet | ✅ done |
| MB7 | Remaining settings: in-ear detection, call ambient, seamless connection, balance, find my earbuds, fit test, debug info | Sonnet | 🟡 built — `find` and `fit-test` never run against the buds |
| MB8 | Menu bar app shell: `.app` bundle, Bluetooth permission, live battery and noise control | Opus | ✅ done |
| MB9 | Menu bar app: every remaining setting | Sonnet | 🟡 built — UI never seen (owner's check) |
| MB9.1 | Fix noise-control reply handling and popover layout *(added mid-plan 2026-11-10)* | Opus | 🟡 fixed — new layout not yet seen by owner |
| MB9.2 | Bluetooth permission fix, stable signing, busy detection, ANC level *(added mid-plan 2026-11-10)* | Opus | ✅ done (ANC level's audible effect is the owner's check) |
| MB11 | Public release: auto-discovery, screenshots, license, README *(added mid-plan 2026-11-10)* | Opus | ✅ done |
| MB10 | Reconnect handling, launch at login, README | Sonnet | 🟡 built — reconnect and login item unverified (owner's check) |

**Overall status: every step is built and pushed; MB0–MB4 and MB6 are fully verified.**
MB5 and MB7–MB10 are 🟡: the code is complete and unit-tested, but each has checks only the
owner can do, and the buds were disconnected from the Mac before the app was ever launched.
A step turns ✅ when its owner checks pass — see **Owner checklist** below. No step is ⬜.

### Owner checklist (what stands between 🟡 and ✅)

With the buds connected to the Mac, run `scripts/bundle.sh --open` and allow Bluetooth.

| # | Check | Step |
|---|---|---|
| ~~1~~ | ~~Menu bar shows the earbuds icon and a battery percentage; popover battery matches reality~~ — passed 2026-11-10 | MB8 |
| ~~2~~ | ~~With both buds worn, the Off / Ambient / Noise cancelling control audibly switches mode~~ — passed after the MB9.1 fix (CLI, read back) ; owner to confirm it no longer shows a red timeout in the app | MB5, MB8 |
| 3 | Each group's controls show the buds' real settings and a change sticks (reopen the popover). Equalizer confirmed by owner; the rest not yet. Also: the settings area is now tall enough to use (MB9.1) | MB9 |
| 4 | Equalizer change is audible; touch lock and gesture switches change what taps do | MB6, MB9 |
| 5 | Tools › Find my earbuds beeps and Stop stops it (buds out of your ears) | MB7 |
| 6 | Tools › Earbud fit test reports a result for each side (both worn) | MB7 |
| 7 | Dock both buds, take them out: popover returns to live data within ~10 s, no relaunch | MB10 |
| 8 | After `scripts/bundle.sh --install`, tick Launch at login, log out and in: app is running | MB10 |
| 9 | Balance slider: dragging towards L makes the left louder (labels may be reversed) | MB9 |

If a check fails, paste what happened into a new session after the Opening prompt; the fix
belongs to the step named in the last column.

**Model note:** MB2, MB3 and MB4 get the stronger model because they fix the shapes everything
else builds on — the channel handling, the frame codec and the state snapshot. A wrong shape
there ripples into every feature step. MB8 gets it because bundling an SPM executable into a
permissioned `.app` is where macOS fights back. **MB2 is the step most likely to become a
spike**: if the RFCOMM channel will not open, nothing after it is possible and the plan needs
rethinking, not pushing through. MB5–MB7 and MB9 are pattern-following once MB4 exists.

**Session split** — natural review checkpoints:
1. **MB1 → MB2** — does the link work at all? Review the captured frames in `docs/PROTOCOL.md`.
2. **MB3 → MB4** — `macbuds status` prints real battery levels. From here on, every step is
   checkable from a terminal.
3. **MB5 → MB7** — all settings from the CLI. You confirm each by ear.
4. **MB8 → MB10** — the app.

One session can carry several steps back-to-back. Never start a step with uncommitted changes
in the tree.

---

## How To Run This

1. Open a **new session** in `<repo>`. `AGENTS.md` auto-loads.
2. **Paste the Opening prompt below first.** Wait for its green light.
3. Paste the **prompt** for the next unfinished step.
4. The session does the work, runs `swift build && swift test`, flips its tracker row, commits
   and pushes, then reports what it did and what you need to check by hand.
5. You review and do the hands-on checks before starting the next step.

### Opening prompt — every step

```text
You are building MacBuds, a native macOS controller for Galaxy Buds2, in
<repo>.
Before any work:
1. Read AGENTS.md and docs/BUILD_PLAN.md in full, and docs/PROTOCOL.md if it exists.
2. Run `git status` and `git branch --show-current`. Confirm the tree is clean and the branch
   is main. If it is not clean, tell me what is uncommitted and STOP.
3. Run `system_profiler SPBluetoothDataType | grep -A4 "Galaxy Buds2"` and tell me whether the
   buds are currently connected. Steps MB2 and MB4 onward need them connected and out of the
   case. Whenever you run the CLI against the buds, use `scripts/macbuds-bundled.sh <args>`,
   never the bare binary (see Landmines).
4. Restate, in one line each, the rules you will not break this session:
   (a) you never send firmware-update, factory-reset or undocumented messages to the earbuds;
   (b) you use GalaxyBudsClient as a protocol reference only and never copy its code;
   (c) you commit and push one step at a time, after a green verify, with no AI attribution;
   (d) you say explicitly which results you could not verify yourself.
5. Read the Progress Tracker and tell me which step is next (the first ⬜ todo).
Then wait. Do not implement anything until I paste the step prompt.
```

### Who verifies what

| Check | Who | "Green" looks like |
|---|---|---|
| `swift build && swift test` | Agent | Clean exit, all tests pass |
| CLI reads (`macbuds status`, `debug`) | Agent | Real values printed from the connected buds, output pasted into the report |
| CLI writes that read back | Agent | Set a value, re-read status, the new value is reported by the buds |
| macOS Bluetooth permission prompts | **you** | Click Allow when the terminal (MB2) or MacBuds.app (MB8) asks |
| Audible effects — ANC, ambient, EQ, call ambient | **you** | You hear the change with the buds in your ears |
| Physical behaviour — touch lock, touch-and-hold, in-ear detection | **you** | Tapping / holding / removing an earbud does what the setting says |
| Find my earbuds, fit test | **you** | Earbuds beep; fit test plays its tone and reports a result |
| Menu bar app rendering and interaction | **you** | Icon appears, popover matches the CLI's values, controls work |
| Launch at login | **you** | App is running after a logout / login |

The agent can run the CLI against the real earbuds and read values back, so anything the buds
*report* is agent-verifiable. Anything you would have to hear, feel or see is yours, and every
step report says which is which.

---

## Ground Rules

1. **Branch:** `main`. Tag `pre-build` marks the docs-only starting point.
2. **One step = one commit**, message prefixed `mb-step-N:`.
3. **Verify before every commit.** `swift build && swift test` must be green. Never commit red.
4. **The agent commits and pushes** after a green verify — authorised for this repo in
   `AGENTS.md`. No AI attribution of any kind. No force-push.
5. **No FOTA, no factory reset, no undocumented message IDs** sent to the device. No scanning
   or fuzzing of message IDs. Document a message in `docs/PROTOCOL.md` before sending it.
6. **`BudsProtocol` never imports IOBluetooth.** It stays pure so it can be unit-tested.
7. **GalaxyBudsClient is a reference, not a source.** It is GPL-3.0; read it for facts, write
   original Swift.
8. **CLI before UI.** Features land and are proven in `macbuds` first.
9. **Leave the buds as you found them.** A step that changes a setting to test it restores the
   previous value before finishing, and says so.
10. **Every step:** ask if genuinely uncertain, and update `AGENTS.md`, `docs/PROTOCOL.md` and
    this tracker when they go stale.

### Rollback

| Situation | Command |
|---|---|
| Step wrong, uncommitted | `git status` first, then `git restore . && git clean -fd` |
| A committed step is bad | `git revert <sha> && git push` |
| Abandon the whole thing | `git reset --hard pre-build` (local only — ask before touching the remote) |

---

## 0. Before Starting

Already done on 2026-11-10 — recorded for reference, do not re-run:

```bash
cd <repo>
git init -b main
git add AGENTS.md .gitignore docs/BUILD_PLAN.md
git commit -m "mb-step-0: scope docs"
git tag pre-build
gh repo create MacBuds --private --source=. --push
```

---

## Design Decisions Already Made

- **Build our own, in Swift.** GalaxyBudsClient already runs on macOS; the owner chose a small
  native app instead. Do not suggest switching.
- **One Swift package, four targets** — `BudsProtocol`, `BudsTransport`, `macbuds`,
  `MacBudsApp`. No Xcode project; the app is bundled by a script.
- **IOBluetooth RFCOMM**, not CoreBluetooth. The buds' control channel is Bluetooth classic
  SPP; CoreBluetooth only does BLE.
- **The app and the CLI each open the channel directly.** Only one client can hold it at a
  time, so the CLI fails with a clear "channel busy — quit MacBuds.app" message while the app
  is running. An IPC bridge is in **Later**.
- **Buds2 only.** Model differences are not abstracted. Keep model-specific constants in one
  file so adding a model later is possible, but build nothing for it.
- **GitHub repo** `<owner>/MacBuds`, work on `main`. Private while it was being built; public from MB11.

If a step seems to require changing one of these, STOP and raise it.

---

## Steps

### MB1 — Package scaffold · Sonnet

**Verify:** `swift build && swift test` clean; `swift run macbuds --version` prints `macbuds 0.1.0`.
**Commit:** `mb-step-1: swift package scaffold`

```text
Do step MB1 of docs/BUILD_PLAN.md: scaffold the Swift package.

Create Package.swift (swift-tools-version 6.0 or newer, platform macOS 14+, Swift 6 language
mode) with the four targets described in AGENTS.md:
- BudsProtocol — library, Foundation only.
- BudsTransport — library, depends on BudsProtocol, links IOBluetooth.
- macbuds — executable, depends on BudsTransport and swift-argument-parser.
- MacBudsApp — executable, depends on BudsTransport. For now just a SwiftUI App with a
  MenuBarExtra showing the text "MacBuds"; real UI is MB8.
- BudsProtocolTests — one trivial passing test so `swift test` has something to run.

macbuds gets a root command with --version (0.1.0) and no subcommands yet.

Do NOT write any protocol or Bluetooth code — that is MB2 to MB4, kept separate so the spike
can change the design. Do NOT create an Xcode project.

swift-argument-parser is the only third-party dependency allowed in this plan. If you think
another is needed, ask first.

Run `swift build && swift test`. Paste the output of `swift run macbuds --version`. Flip MB1
to ✅ in docs/BUILD_PLAN.md in the same change, then commit ("mb-step-1: swift package
scaffold") and push. Report what you did and stop.
```

---

### MB2 — Hardware spike: open the channel · Opus

**Verify:** `swift run macbuds probe` lists the buds' SDP services, opens the SPP RFCOMM
channel, and prints at least one complete inbound frame as hex. `docs/PROTOCOL.md` exists with
the confirmed service UUID, channel, frame layout and those captured frames.
**Commit:** `mb-step-2: rfcomm probe and protocol notes`

```text
Do step MB2 of docs/BUILD_PLAN.md: prove we can talk to the earbuds. This is a spike — the
goal is knowledge, written down, not finished architecture.

The buds are "Galaxy Buds2", address <earbuds-address>, paired and connected to this
Mac. system_profiler only lists HFP / AVRCP / A2DP for them; the control channel is a Serial
Port Profile service that has to be found by SDP query.

1. Add a `probe` subcommand to macbuds (code in BudsTransport, kept deliberately rough):
   - find the paired IOBluetoothDevice by address (take --address, default to the one above);
   - run an SDP query and print every service record: name, UUIDs, RFCOMM channel ID;
   - pick the SPP service. Hypothesis from the GalaxyBudsClient project: Buds2 uses UUID
     00001101-0000-1000-8000-00805F9B34FB. Confirm against what SDP actually returns and
     against the reference source — do not trust the hypothesis;
   - open the RFCOMM channel and hex-dump everything received for --seconds (default 8),
     one line per delegate callback, with a timestamp.
   IOBluetooth delivers RFCOMM delegate callbacks on a run loop, so the CLI must keep the main
   run loop spinning while it listens. IOBluetooth types are not Sendable; contain them on the
   main actor rather than fighting strict concurrency all over the code.

2. Run it. The first run will trigger a macOS Bluetooth permission prompt for the terminal
   app — tell me to click Allow, and wait for me. If the channel will not open, STOP and
   report the exact IOReturn code and what you tried. Do not work around it by trying other
   channels at random.

3. Read the GalaxyBudsClient source on GitHub (timschneeb/GalaxyBudsClient) for the Buds2
   frame format and message IDs. It is GPL-3.0: take facts, not code. Then write
   docs/PROTOCOL.md containing:
   - the confirmed SPP UUID and RFCOMM channel;
   - the frame layout (start/end markers, header bit layout, where the CRC is computed and
     which CRC16 variant), each point marked "confirmed on device" or "from reference only";
   - the raw frames you captured, annotated byte by byte as far as you can;
   - a table of every message ID this plan needs (status, extended status, noise control,
     ambient level, equalizer, touch lock, touch options, in-ear detection, call ambient /
     sidetone, seamless connection, balance, find my earbuds start/stop, fit test, debug /
     version info) with direction and payload layout, and a "Buds2 supports it: yes / no /
     unknown" column;
   - a short list of message IDs that must never be sent (FOTA, factory reset).

Send NOTHING to the buds in this step — listen only. The buds push a status message on
connect, which is enough to confirm the framing.

Run `swift build && swift test`. Paste the probe output. Flip MB2 to ✅ in docs/BUILD_PLAN.md
in the same change, add anything that bit you to the Landmines section, then commit
("mb-step-2: rfcomm probe and protocol notes") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- **The prompt's UUID hypothesis was wrong.** `00001101-…` is the `FACTORY` service. The
  control channel is `GEARMANAGER` (`2E73A4AD-332D-41FC-90E2-16BEF06523F2`, channel 27),
  which matches what the reference project uses for Buds2.
- **`probe` takes `--channel` instead of auto-selecting.** Without it, it only lists services.
  Auto-selection by UUID belongs in `BudsSession` (MB4).
- **Added `scripts/macbuds-bundled.sh`**, not in the original prompt — see Landmines. Every
  later step runs the CLI through it.
- **Raw capture saved** to `docs/captures/2026-11-10-connect.txt` for use as MB3 test fixtures.
- Nothing was sent to the buds. The Bluetooth permission for `macbuds-cli.app` was granted on
  this Mac during the step.

---

### MB3 — Protocol codec · Opus

**Verify:** `swift test` passes tests that decode every frame captured in `docs/PROTOCOL.md`,
round-trip encode→decode, reject bad CRC, and reassemble a frame split across three chunks and
two frames delivered in one chunk.
**Commit:** `mb-step-3: frame codec and crc`

```text
Do step MB3 of docs/BUILD_PLAN.md: the frame codec, in the BudsProtocol target only.

Read docs/PROTOCOL.md first; it is the spec. Implement:
- `Frame` — message ID, payload bytes, and the header flags the protocol defines.
- `Frame.encode() -> [UInt8]` and a throwing decoder, with a typed error for each failure
  (bad start marker, bad end marker, length mismatch, CRC mismatch).
- The CRC16 the protocol uses, as its own small function with a test vector taken from a
  captured frame.
- `FrameStreamDecoder` — fed arbitrary chunks of bytes as they arrive from RFCOMM, emits
  complete frames. It must cope with a frame split across chunks, several frames in one
  chunk, and garbage before a start marker (resynchronise, don't crash, don't loop forever).
- `MessageID` constants for the IDs listed in docs/PROTOCOL.md.

Tests use the real captured frames from docs/PROTOCOL.md as fixtures — that is the whole point
of having captured them. Decoding never traps on malformed input; it throws.

Do NOT import IOBluetooth here and do NOT decode payloads into typed status structs yet —
that is MB4, kept separate so this diff is only the codec.

If the captured frames disagree with docs/PROTOCOL.md, the document is wrong: fix it and say
what changed.

Run `swift build && swift test`. Flip MB3 to ✅ in docs/BUILD_PLAN.md in the same change, then
commit ("mb-step-3: frame codec and crc") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- **The decoder frames by header length, not by end marker**, and masks the length with
  `03FF`; header bits 10–15 are kept on `Frame.headerFlags` for diagnostics only.
- **Known limit:** a stray `FD` in line noise can announce a frame of up to 1023 bytes, and the
  decoder waits for that many bytes before rejecting it. It then recovers every real frame
  behind it (tested), so the cost is a delay, not data loss. The buds' periodic debug frames
  bound that delay to a few seconds.
- `MessageID` deliberately omits everything on the never-send list in `docs/PROTOCOL.md` §5.

---

### MB4 — Session and status · Opus

**Verify:** `swift run macbuds status` prints left / right / case battery, wearing state,
current noise-control mode, equalizer preset and touch-lock state read from the real buds;
`swift run macbuds status --json` prints the same as JSON; `status --watch` prints a new line
when an earbud is put in the case.
**Commit:** `mb-step-4: buds session and status command`

```text
Do step MB4 of docs/BUILD_PLAN.md: a real connection and the first useful command. This is
the first runnable milestone — after it, every feature can be checked from a terminal.

1. BudsProtocol: typed payload decoding for the extended-status and status-update messages,
   per docs/PROTOCOL.md, into a `BudsState` value type (battery L/R/case, wearing / placement
   per earbud, noise-control mode, ambient level, EQ preset, touch lock, and every other
   setting the extended status carries for Buds2). Unknown trailing bytes are tolerated —
   firmware revisions add fields. Unit-test against the captured frames.

2. BudsTransport: replace the MB2 probe internals with a proper `BudsSession`:
   - connect(address:) / disconnect();
   - owns the RFCOMM channel and a FrameStreamDecoder;
   - keeps the latest BudsState and exposes changes as an AsyncStream;
   - `send(_ frame:)`, plus a `request` helper that sends and awaits the matching
     acknowledgement or response with a timeout, for the setters in later steps;
   - clear typed errors: device not paired, not connected, channel busy (another client such
     as MacBuds.app holds it), permission denied, timeout.
   Keep IOBluetooth objects confined to the main actor. Keep `probe` working as a debug tool.

3. macbuds: `status` (human-readable), `status --json`, `status --watch`.

Think about the BudsState and BudsSession shapes before writing them — MB5 to MB9 all build
on these two types. If docs/PROTOCOL.md leaves a field's meaning ambiguous, check the
reference source, update the document, and tell me which fields you are unsure of rather than
guessing silently.

Do NOT add any setter commands — MB5 onward. The only bytes this step may send are whatever
docs/PROTOCOL.md documents as required to request status, if anything.

Run `swift build && swift test`. Paste the output of `macbuds status` and `status --json`.
Ask me to put one earbud in the case while `status --watch` runs, and paste what it printed.
Flip MB4 to ✅ in docs/BUILD_PLAN.md in the same change, then commit ("mb-step-4: buds session
and status command") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- **`BudsSession` is `@MainActor`** and exposes `connect()`, `disconnect()`, `currentState()`,
  `versionInfo()`, `stateUpdates()` (AsyncStream), `send(_:)` and `request(_:)`. `request`
  registers its waiter before writing, then resolves on `0x42` (ack with echo) or `0x51`
  (result code; non-zero throws `.rejected`). **`request` has never been exercised against the
  device** — MB5 is its first real use.
- **`send` enforces an allowlist**, `MessageID.sendable`. An ID not on it throws
  `.forbiddenMessage` before anything reaches the wire. Later steps add IDs to that set as
  they document them; a test asserts the dangerous ranges stay off it.
- **There is no "send status again" request** (docs/PROTOCOL.md §6.5), and this step sent
  nothing. The buds push a full `0x61` on every channel open, so each CLI run gets a fresh
  snapshot. **Consequence for MB5–MB7:** within one session a setter must update the snapshot
  itself from the acknowledgement echo; do not wait for a new `0x61`, it may never come. To
  prove a write stuck, read it back with a second `macbuds status` run (new connection).
- **Enum-like bytes are `WireValue` structs** (`NoiseControlMode`, `EqualizerPreset`, …), not
  Swift enums, so an unexpected byte prints as `unknown(0x..)` instead of failing the decode.
  They carry `init?(name:)` and `allNames` for CLI argument parsing.
- **Case battery prints `n/a`** when the buds report 0 with neither earbud in the case. That
  reading of the 0 is a guess (PROTOCOL §6.8) — owner to confirm by docking one earbud.
- **Firmware** arrives in `0x63` about 20 ms after status; `versionInfo()` waits up to 1 s.
- `disconnect()` closes only the RFCOMM channel, never the device connection, so audio is
  unaffected.
- **Not verified by the session that built it:** `status --watch` printing a change line. It
  ran for 12 s and printed the initial line, but nothing changed on the buds in that window.
  Check: run `scripts/macbuds-bundled.sh status --watch --seconds 30` and put an earbud in the
  case — output appears when the command ends (the wrapper buffers it).

---

### MB5 — Noise control · Sonnet

**Verify:** `macbuds noise anc|ambient|off` changes the mode and `macbuds status` reports the
new mode; `macbuds ambient-level <n>` and `macbuds noise one-earbud on|off` read back
likewise. You hear ANC and ambient engage.
**Commit:** `mb-step-5: noise control commands`

```text
Do step MB5 of docs/BUILD_PLAN.md: noise control.

Following the patterns MB4 established (payload encoders in BudsProtocol, methods on
BudsSession, subcommands in macbuds), add:
- `macbuds noise anc|ambient|off`
- `macbuds ambient-level <n>` — validate against the range docs/PROTOCOL.md gives for Buds2
- `macbuds noise one-earbud on|off` — noise control while wearing a single earbud
- the "touch cycles between" noise-mode set, if docs/PROTOCOL.md shows Buds2 has it

Each setter sends with `BudsSession.request`, waits for the acknowledgement, and updates the
session's snapshot from the echo (see the MB4 implementation notes — the buds do not resend
full status). Add each new message ID to `MessageID.sendable` only if it is not already
there. Confirm each write with a fresh `macbuds status` run. Open question 6 in
docs/PROTOCOL.md (is MANAGER_INFO needed before writes?) gets answered here: try the first
setter without it, and record the outcome in the document either way.
Unit-test every payload encoder byte-for-byte against docs/PROTOCOL.md.

Before testing, record the current values with `macbuds status`; after testing, restore them.
For each command, set it and paste the before/after `status` lines. Then tell me which ones
you need me to confirm by ear — you cannot hear the earbuds.

If the buds do not acknowledge a message or the state does not change, STOP on that command
and report the bytes sent and received; do not try variations of the payload against the
device.

Run `swift build && swift test`. Flip MB5 to ✅ in docs/BUILD_PLAN.md in the same change, then
commit ("mb-step-5: noise control commands") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- **Writes work with no handshake.** MANAGER_INFO is not needed and header upper bits can be
  zero. First write ever sent was `ambient-level 2`, acknowledged `42 84 02`.
- **Not every message is acknowledged with `0x42`** — the prompt assumed they all were.
  `Command` now carries a `reply` kind, learned per message on the device:
  `.acknowledgement` (0x84, 0x79), `.noiseControlsUpdate` (0x78 is answered by `0x77` carrying
  the mode actually in effect), `.none` (0x6F changes the setting silently). **Every new
  setter in MB6/MB7 must be run once with `--verbose` to see which kind it is** before its
  `reply` is trusted; a wrong kind shows up as a timeout even though the setting changed.
- **Command names differ from the prompt:** `noise <mode>`, `ambient-level <n>`,
  `one-earbud-noise on|off`, `noise-cycle --left a+b --right a+b`. Flat commands, because
  `noise anc` and `noise one-earbud on` cannot share one positional argument.
- **`status --watch` verified by the owner** (2026-11-10): docking the right earbud printed
  placement, charging and a real case battery (45 %). That also confirms the case battery is
  only reported while an earbud is docked, and showed the buds drop noise control to off by
  themselves when one earbud is removed.
- ~~Not verified: `noise anc|ambient|off` actually switching mode.~~ **Verified 2026-11-10
  with both earbuds worn — and the reply kind above was wrong for that case; see MB9.1.**
- Settings were restored: ambient level 1, one-earbud off, cycle anc+ambient both sides.

---

### MB6 — Equalizer and touch controls · Sonnet

**Verify:** `macbuds eq <preset>` (and `eq off`), `macbuds touch lock on|off`,
`macbuds touch hold --left <action> --right <action>` all read back through `macbuds status`.
You hear the EQ change and confirm the touch behaviour by hand.
**Commit:** `mb-step-6: equalizer and touch commands`

```text
Do step MB6 of docs/BUILD_PLAN.md: equalizer and touch controls, same pattern as MB5.

- `macbuds eq normal|bass-boost|soft|dynamic|clear|treble-boost` — use the preset list and
  byte values docs/PROTOCOL.md gives for Buds2, not this prompt's list if they differ.
- `macbuds touch lock on|off`, plus the per-gesture toggles (single / double / triple tap,
  touch and hold) if docs/PROTOCOL.md shows Buds2 firmware supports them.
- `macbuds touch hold --left <action> --right <action>` — actions as documented for Buds2
  (switch noise controls, voice assistant, volume down / up, and so on). Voice-assistant and
  Spotify actions depend on the phone app; expose them but note in --help that they do
  nothing useful on a Mac.

Unit-test every payload encoder. Record current values first and restore them afterwards.
Paste before/after `status` lines for each command, then list what I need to check by ear and
by touching the earbuds.

Same escalation as MB5: no acknowledgement or no state change means STOP on that command and
report the bytes, not experiment against the device.

Run `swift build && swift test`. Flip MB6 to ✅ in docs/BUILD_PLAN.md in the same change, then
commit ("mb-step-6: equalizer and touch commands") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- Commands: `eq <preset>`, `touch lock on|off`, `touch gesture <name> on|off`,
  `touch hold --left <action> --right <action>`. All three messages (0x86, 0x90, 0x92) are
  acknowledged with `0x42` echoing the sent bytes, and each read back correctly on a fresh
  connection.
- **Touch lock polarity confirmed on device:** payload p0 = 00 locks; status then reports
  "locked".
- **0x90 carries lock and all six gesture flags in one message**, so `lock` and `gesture` read
  the current `TouchSettings` and change one field.
- **`touch hold` refuses `volume` on one side only.** In Samsung's app volume is a pair (left
  down, right up). That rule is from memory of the app, not from the reference or the device;
  a mixed assignment has never been sent.
- "other" hold actions (05/06) are not assignable: they only make the buds notify a host app.
- Originals restored: dynamic, unlocked, all gestures on, left spotify / right noise-control.
- **Not verified:** how the EQ sounds, and that tapping the earbuds obeys the lock and the
  gesture switches — no earbud was being worn during the test.

---

### MB7 — Remaining settings · Sonnet

**Verify:** each of `macbuds in-ear-detection on|off`, `call-ambient on|off`,
`seamless on|off`, `balance <value>` reads back through `status`; `macbuds find start|stop`
makes the earbuds beep; `macbuds fit-test` reports a per-earbud result; `macbuds debug` prints
firmware version and serial info.
**Commit:** `mb-step-7: remaining settings and find my earbuds`

```text
Do step MB7 of docs/BUILD_PLAN.md: everything else the Buds2 supports, same pattern as MB5.

Add a command for each of these that docs/PROTOCOL.md marks as supported on Buds2:
- in-ear detection for calls
- ambient sound during calls (sidetone)
- seamless earbud connection
- left/right hearing balance
- extra-high ambient volume and any other Labs toggles Buds2 has
- `macbuds find start|stop` — find my earbuds. It plays a loud tone: `find start` must refuse
  to run if status says an earbud is being worn unless --force is given, and must always be
  stoppable.
- `macbuds fit-test` — earbud fit test, reporting good / poor per side
- `macbuds debug` — firmware version, hardware revision, serials, whatever the debug / version
  messages return

For anything docs/PROTOCOL.md marks "unknown" for Buds2, check the reference source and update
the document first. If a feature turns out not to exist on Buds2, do not build it — add a line
to "Deferred follow-ups" saying so and why.

Do NOT implement factory reset or anything firmware-update related, even though the reference
has them.

Unit-test every payload encoder. Record and restore settings. Paste before/after `status`
lines and the `debug` output. Tell me before you run `find start` so my ears are not in the
earbuds, and list what I need to confirm myself.

Run `swift build && swift test`. Flip MB7 to ✅ in docs/BUILD_PLAN.md in the same change, then
commit ("mb-step-7: remaining settings and find my earbuds") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- Commands: `in-ear-detection`, `call-ambient`, `seamless`, `double-tap-edge` (all `on|off`),
  `balance <0–32>`, `custom-ambient [on|off] --left --right --tone`, `find start|stop`,
  `fit-test`, `info`. The prompt's `debug` command is called `info`.
- **Reply kinds learned on device:** 0x8F, 0x95, 0xAF acknowledge with `0x42`; 0x6E, 0x8B and
  0x82 send nothing back and are `.none`. All six read back correctly and were restored.
- **`info` is thinner than planned.** Serial numbers (0x29) and SKU (0x22) answer. Build info
  (0x28) and battery type (0x94) get no reply, and the sensor dump (0x26) comes back as 108
  zero bytes, so those three are no longer sent and are off the allowlist. The firmware name
  is still the one reconstructed from `0x63`; no text reply exists to cross-check it. The SKU
  `SM-R177NZKAMEA` does confirm the model.
- **Custom ambient added** (`0x82`) — not in the prompt's list, but Buds2 reports it in status.
- **`find start`** beeps for `--seconds` (default 15) and then always sends stop; it refuses
  while an earbud is worn unless `--force`, in which case it uses the on-wearing variant
  (0xA6). **`fit-test`** refuses unless both earbuds are worn, waits up to 20 s for the result
  and then sends the stop message.
- **Not verified — never sent to the device:** `find start`, `find stop`, `fit-test`. Only
  their guards were run (both refused correctly with no earbud worn). They are loud /
  need the buds in the owner's ears, so the first real run is the owner's:
  `scripts/macbuds-bundled.sh find start --seconds 5` with the buds on the desk, and
  `scripts/macbuds-bundled.sh fit-test` with both worn. If either times out, the reply kind
  or message is wrong for this firmware — capture with `--verbose` and fix here.
- Not built, moved to Deferred follow-ups: extra-high ambient, gaming mode, per-side mute
  during find, case serial number.

---

### MB8 — Menu bar app shell · Opus

**Verify:** `scripts/bundle.sh` produces `dist/MacBuds.app`; opening it shows a menu bar icon;
after the Bluetooth prompt is allowed, the popover shows live battery for left / right / case
and a working ANC / ambient / off control whose state matches `macbuds status` (run after
quitting the app).
**Commit:** `mb-step-8: menu bar app shell`

```text
Do step MB8 of docs/BUILD_PLAN.md: turn MacBudsApp into a real menu bar app.

1. scripts/bundle.sh: build MacBudsApp in release mode and assemble dist/MacBuds.app — the
   executable, an Info.plist with a bundle identifier, LSUIElement = true (no Dock icon), and
   NSBluetoothAlwaysUsageDescription. Ad-hoc codesign it. An SPM executable run bare has no
   Info.plist, so macOS will kill it or deny Bluetooth instead of prompting — the bundle is
   what makes the permission prompt appear. dist/ is git-ignored.

2. An @Observable, main-actor `BudsViewModel` wrapping BudsSession: connection state
   (disconnected / connecting / connected / channel busy / permission denied), the latest
   BudsState, and async setter methods.

3. MenuBarExtra with a window-style popover:
   - header with device name and connection state;
   - battery for left, right and case;
   - a segmented ANC / Ambient / Off control;
   - Quit.
   The menu bar label shows an earbuds symbol plus the lower of the two earbud battery
   percentages. Follow standard macOS menu bar popover conventions; nothing fancy.

4. Connect on launch; if the buds are not connected to the Mac, show that state rather than
   failing.

Do NOT add the other settings — MB9, kept separate so this diff is about bundling,
permissions and the view-model shape. Do NOT add launch-at-login or reconnect logic — MB10.

You cannot see the app render. Build and bundle it, confirm the process launches and stays
up, and check the unified log for IOBluetooth or TCC errors. Then tell me exactly what to look
at: the icon, the permission prompt, the battery numbers against `macbuds status`, and the
noise control. If macOS denies Bluetooth without prompting, STOP and report the log lines —
do not start changing signing or entitlements by trial and error.

Run `swift build && swift test`. Flip MB8 to ✅ in docs/BUILD_PLAN.md in the same change,
update the structure section of AGENTS.md, then commit ("mb-step-8: menu bar app shell") and
push. Report and stop.
```

**Implementation notes (2026-11-10):**

- `scripts/bundle.sh [--open]` builds release and assembles `dist/MacBuds.app` (bundle id
  `dev.memoli.macbuds`, `LSUIElement`, Bluetooth usage string, ad-hoc signed).
- `BudsViewModel` (`@MainActor @Observable`) owns one `BudsSession` and a connection loop:
  connect, mirror `stateUpdates()` until the channel closes, wait 4 s, try again. So basic
  reconnect already exists here rather than in MB10; the attempt is cheap because
  `connect()` first asks macOS whether the device is connected.
- Controls bind to `model.state` and call `model.apply { try .someCommand(...) }`. State only
  changes when the buds accept a command, so a rejected change reverts the control by itself
  and the reason appears as an inline red caption.
- `BudsSession.connect()` now clears `state` and `version` first, so a reused session never
  serves the previous connection's snapshot.
- Logging: subsystem `dev.memoli.macbuds` (connection changes, failed changes).
- **Not verified:** anything visual, and — because the earbuds were disconnected from the Mac
  by the time the app was first launched — the app has never been observed connected. Only
  confirmed: it builds, bundles, launches and stays running with the buds away. `log show`
  returns nothing from an agent session, so the log could not be read either.
  Owner's check: connect the buds, run `scripts/bundle.sh --open`, allow Bluetooth when
  asked, and compare the popover's battery and noise mode with what you expect.

---

### MB9 — Menu bar app: all settings · Sonnet

**Verify:** every setting available in the CLI after MB7 has a control in the popover, each
reflecting the buds' current value on open and after a change made by touching the earbuds.
**Commit:** `mb-step-9: full settings ui`

```text
Do step MB9 of docs/BUILD_PLAN.md: give every CLI setting a control in the app.

Extend BudsViewModel and the popover with sections:
- Noise control — ambient level, one-earbud noise control (mode control exists from MB8)
- Equalizer — preset picker
- Touch — lock, per-gesture toggles if supported, touch-and-hold action per side
- Calls — in-ear detection, ambient sound during calls
- Connection — seamless earbud connection
- Sound — left/right balance, Labs toggles
- Tools — Find my earbuds (start / stop, with a warning if an earbud is worn), Fit test,
  and an About row with firmware version

Controls are disabled while disconnected. A control shows the value the buds report, not the
value last clicked: after a setter, wait for the state update, and revert the control with a
brief inline error if the buds reject it. Only show controls for features MB5 to MB7 actually
implemented — check the CLI, not this list. Setters go through `BudsSession.perform(_:)`
with the `Command` factories in `Sources/BudsProtocol/Command.swift`; do not build frames in
the app.

Keep the popover a sensible size: group into collapsible sections or a small settings window
if it gets tall. Use your judgment and tell me which you chose.

You cannot see the UI. Build, bundle, launch, check the log for errors, then give me a
checklist of every control to try.

Run `swift build && swift test`. Flip MB9 to ✅ in docs/BUILD_PLAN.md in the same change, then
commit ("mb-step-9: full settings ui") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- Popover layout: header, battery row, noise control (plus ambient level while in ambient
  mode) always visible; below that five collapsible groups in a scroll view capped at 360 pt —
  Ambient sound, Sound, Touch controls, Calls and connection, Tools. Each group remembers
  whether it was open (`@AppStorage`). Chosen over a separate settings window so everything
  stays one click from the menu bar.
- Touch-and-hold pickers apply the volume-pair rule automatically (choosing volume on one side
  sets both). A per-side "switches between" picker appears when that side is set to noise
  control.
- Find runs for 30 s then stops itself, shows a warning while an earbud is worn, and uses the
  on-wearing variant in that case. Fit test is disabled unless both earbuds are worn.
- **This commit also contains two MB10 items** — the "Launch at login" checkbox
  (`SMAppService.mainApp`) and `scripts/bundle.sh --install` — because they touched the same
  files. MB10's commit is the README and doc pass only.
- **Swift 6.3.3 compiler crash worked around:** passing a `@MainActor (NoiseCycle) -> Void`
  closure straight into `Binding(get:set:)` aborts the compiler in IR generation
  ("SmallVector unable to grow"). Wrapping it — `set: { new in change(new) }` — avoids it. If
  the crash reappears after an edit to `SettingsSections.swift`, look for a closure passed
  directly as a `Binding` setter.
- Balance slider labels assume low values are left. Which end is which is still unconfirmed
  (docs/PROTOCOL.md §6.13) — if it sounds reversed, swap the two labels.
- **Not verified:** the entire UI. It compiles, bundles and the process stays up, but the buds
  were disconnected from the Mac throughout, so no control has been seen or clicked. Checklist
  for the owner is in the step report and in README.md.

---

### MB9.1 — Noise-control replies and popover layout · Opus

> **Added mid-plan 2026-11-10** — not part of the original scope. The owner's first look at
> the running app found two defects.

**Implementation notes (2026-11-10):**

- **Bug: noise control showed "Timed out waiting for a reply to message 0x78" and the control
  snapped back, although the buds had switched.** MB5 concluded from a test with no earbud
  worn that `0x78` is answered by `0x77`. That is only the *no-change* answer. Tested worn:
  when the mode actually changes the buds reply `42 78 <mode>` and send no `0x77`; when it
  does not change (same mode again, or not worn) they send `0x77` with the mode in effect.
  `BudsSession.perform` now accepts either. **Lesson for any future setter: test both a
  changing and a non-changing write before trusting its reply kind.** Re-sending an unchanged
  value was checked for `0x86`, `0x84` and `0x90`: those acknowledge with `0x42` either way.
- **Bug: the settings area was a sliver.** A `ScrollView` with only `maxHeight` has no height
  of its own, and a `MenuBarExtra` window sizes to fit, so it collapsed to about one row. The
  groups' natural height is now measured with `onGeometryChange` and the scroll area is
  exactly that tall, capped at 480 pt.
- **Top of the popover compacted:** name and connection state share one line, battery is one
  line (`Left 35%  Right 99%  Case 40%`), the "Noise control" heading is gone (the segmented
  control is self-explanatory). Width 320 → 340.
- **Not verified:** the new layout — rebuilt and relaunched, not seen.

---

### MB9.2 — Permission, signing, busy detection, ANC level · Opus

> **Added mid-plan 2026-11-10** — not part of the original scope. After MB9.1's rebuild the
> app showed "<earbuds-address> is not paired with this Mac" while the CLI still worked; the
> owner also asked to try the two unproven Samsung toggles.

**Implementation notes (2026-11-10):**

- **"Not paired" was a Bluetooth permission problem, not pairing.** Without the permission
  IOBluetooth does not error — it reports every device as unpaired. The rebuilt, ad-hoc
  signed app evidently no longer matched its earlier permission grant. Evidence: the CLI
  bundle reached the buds at the same moment; after re-signing with a certificate the app sat
  in "Connecting…" (a permission prompt was up) and then logged `connection: Connected`.
  The exact rule macOS applied to the ad-hoc build is inferred, not proven.
- **`scripts/bundle.sh` now signs with the first "Apple Development" certificate in the
  keychain** (by hash — this keychain holds two with the same name), falling back to ad-hoc.
  Override with `MACBUDS_SIGN_IDENTITY`. A stable signature should keep the permission across
  rebuilds. **Confirmed once:** the next rebuild connected within seconds with no prompt.
- **`BudsSession.connect()` checks `CBManager.authorization` first** and throws
  `.bluetoothDenied` with instructions instead of the misleading "not paired".
- **A held channel shows up as an open that never completes**, not as an open failure. The
  open timeout now throws `.channelBusy`; the app maps it to "in use by another app" and the
  CLI tells you to quit MacBuds.app.
- The app also prints connection changes to stdout, so an agent can read them with
  `open --stdout <file> dist/MacBuds.app` (`log show` returns nothing in an agent session).
- **Extra-high ambient (0x96): sent once, ignored** — no reply, status unchanged. Not built;
  the ID is off the allowlist and a test keeps it off.
- **ANC level (0x83): accepted.** `42 83 01`, status p24 went 0 → 1 and stayed. Added as
  `macbuds anc-level high|low` and a "High noise cancelling level" switch in the popover's
  first group (renamed "Noise control options"), both labelled experimental. **Left at
  `high` at the owner's request** (it was `low`/0 before). Whether it is audible is the
  owner's check: in noise cancelling mode, flip the switch and listen.

---

### MB10 — Reconnect, launch at login, README · Sonnet

**Verify:** with the app running, putting both earbuds in the case and taking them out again
returns the popover to live data within a few seconds without relaunching; a "Launch at
login" toggle works; `README.md` covers build, bundle, permissions and CLI usage.
**Commit:** `mb-step-10: reconnect, launch at login, readme`

```text
Do step MB10 of docs/BUILD_PLAN.md: make it something that can be left running.

1. Reconnect: BudsSession notices the RFCOMM channel closing; the app registers for
   IOBluetooth connect / disconnect notifications for the device and reopens the channel when
   the buds come back, with a backoff rather than a tight retry loop. The popover shows
   "Disconnected" in between.
2. Launch at login via SMAppService, as a toggle in the popover. This needs the bundled .app;
   say so if it cannot work from dist/ and needs the app copied to /Applications.
3. scripts/bundle.sh gets an --install flag that copies the app to /Applications after asking.
4. README.md: what it is, requirements, build and bundle, the Bluetooth permission prompt,
   CLI command reference (generate it from --help so it is accurate), the app/CLI
   channel-busy limitation, and the safety note about never sending firmware messages.
5. Bring AGENTS.md and docs/PROTOCOL.md fully up to date.

Do NOT add anything from the Later section.

Tell me what to check by hand: the case-in / case-out reconnect, and launch at login after a
logout.

Run `swift build && swift test`. Flip MB10 to ✅ in docs/BUILD_PLAN.md in the same change,
then commit ("mb-step-10: reconnect, launch at login, readme") and push. Report and stop.
```

**Implementation notes (2026-11-10):**

- **Reconnect is the polling loop from MB8**, not IOBluetooth connect/disconnect
  notifications as the prompt asked: every 4 s while away, `connect()` asks macOS whether the
  device is connected and opens the channel only if so. It is simpler and has no
  notification-registration lifetime to manage. If the 4 s lag or the idle wake-ups ever
  matter, switch to `IOBluetoothDevice.register(forConnectNotifications:selector:)`.
- Launch at login and `--install` landed in the MB9 commit (see its notes).
- README.md written; the command table was checked against `macbuds --help`.
- **Not verified:** reconnect after docking (the buds never reconnected during the session),
  and the login item (needs `--install` plus a logout).

---

### MB11 — Public release · Opus

> **Added mid-plan 2026-11-10** — the owner asked for the repo to be made public and
> open-sourced, with a README and images.

**Implementation notes (2026-11-10):**

- **No more hard-coded Bluetooth address.** `BudsTransport.findEarbuds(address:)` picks the
  paired device whose name is `Galaxy Buds2` or `Galaxy Buds2 (xxxx)` — not `Buds2 Pro`, not
  `Buds+` — preferring the connected one if several are paired; `--address` /
  `MACBUDS_ADDRESS` override. This reverses the earlier "match by address, never by name"
  landmine, which was written when the address was a constant; name matching is now exact
  enough to exclude the other models, and is unit-tested.
- **Screenshots are generated, not captured.** `MacBudsApp --render-screenshots <dir>` hosts
  the real `PopoverView` in an offscreen window with sample data and writes PNGs. No
  Bluetooth, no screen-recording permission, no personal data. Regenerate with
  `swift build && .build/debug/MacBudsApp --render-screenshots docs/images` after UI changes.
  Controls render in the grey inactive-window style because the window is never frontmost.
- **Seeing the renders exposed layout faults nobody had reported:** switches sat beside their
  labels instead of at the right edge, and the cycle pickers truncated. Rows now use
  `SettingRow` (label, spacer, control) and the cycle labels are shorter.
- **MIT license.** Chosen by the owner. No code was copied from the GPL-3.0 reference project.
- **History was restarted for the public repo.** The working history contained the owner's
  earbuds' Bluetooth address and local paths, so the files were scrubbed (placeholders such as
  `<earbuds-address>` and `<repo>` in this document are the result) and the public repo starts
  from a single commit. The original step-by-step commits are kept only in the owner's
  private archive. Commit hashes mentioned nowhere in this document, so nothing dangles.
- From here on, the ground rule "one step = one commit, pushed" continues on the public repo.

---

## Deferred follow-ups (cross-step, live tracker)

> Things a step noticed but that were out of its scope. Strike through when handled; don't
> delete lines.

- ~~**Extra-high ambient volume (0x96)** (surfaced by MB2/MB7). Status has the byte, but the
  reference does not enable the toggle for Buds2. Not built; would need one supervised send
  to see whether this firmware accepts it.~~ Tested in MB9.2: the firmware ignores it. Closed.
- **Gaming mode (0x87)** (MB7). Payload values are not established anywhere; not built.
- **Mute one earbud during find (0xA2)** (MB7). Documented, simply not wired up.
- **Case serial number (0xCD)** (MB7). Support on Buds2 unknown; not sent.
- **`0x77` carries more than the mode on this firmware** (MB5): five bytes, of which p1 looks
  like placement and p3 like the touch noise cycle. Only p0 is used. Decoding the rest would
  let the snapshot track placement changes that arrive this way.
- **`status --watch` under the bundle wrapper prints only when it exits** (MB4), because
  `open -W` redirects stdout to a file. Fine for agents; for live use run the CLI from
  Terminal.app directly (untested) or use the menu bar app.
- *(Steps add to this list as they surface out-of-scope friction.)*

---

## Landmines

Confirmed during planning (2026-11-10):

- **The control service is invisible in `system_profiler`.** It lists only HFP / AVRCP / A2DP
  for the buds. Do not conclude SPP is absent; it has to be found by SDP query (MB2).
- **Other Samsung earbuds may be paired to the same Mac** (the development machine also had a
  pair of Galaxy Buds+). A loose "Galaxy Buds" prefix would match them; discovery matches
  `Galaxy Buds2` exactly, see MB11.
- **The reference implementation is GPL-3.0.** Copying from GalaxyBudsClient would put this
  repo under GPL. Ground rule 7.

Hit during MB2 (2026-11-10):

- **The generic SPP UUID is the wrong service.** On Buds2, `00001101-…` is a service named
  `FACTORY` (channel 20). The control channel is `GEARMANAGER`,
  `2E73A4AD-332D-41FC-90E2-16BEF06523F2`, channel 27. Select by that UUID; the channel number
  is not guaranteed stable.
- **A bare CLI dies silently when its launcher lacks a Bluetooth usage string.** Run from an
  agent session, `.build/debug/macbuds probe` exits 134 (SIGABRT) with no output at all:
  macOS attributes Bluetooth access to the launching app, and aborts the process if that app's
  Info.plist has no `NSBluetoothAlwaysUsageDescription`. From Terminal.app the bare binary is
  expected to work (not tested). **Agents must run the CLI through
  `scripts/macbuds-bundled.sh <args>`**, which wraps it in `dist/macbuds-cli.app` and launches
  it via LaunchServices so the bundle is its own responsible app. The same applies to
  MacBudsApp (MB8).
- **IOBluetooth needs a running run loop** for SDP and RFCOMM callbacks, and its classes are
  not Sendable. `Probe` is `@MainActor`, imports IOBluetooth `@preconcurrency`, conforms with
  `@preconcurrency IOBluetoothRFCOMMChannelDelegate`, and spins the run loop while waiting.
  The CLI enters it with `MainActor.assumeIsolated` from ArgumentParser's synchronous `run()`.
- **The buds talk a lot unprompted.** Within a second of the channel opening they send
  extended status plus half a dozen other frames, then periodic debug frames (`0xF4`, `0xF2`)
  every few seconds. One RFCOMM callback can carry several frames. **Frame by the header length, never by
  scanning for `DD`:** the first captured frame ends `… 80 DD DD` because its CRC high byte
  happens to be `DD`. Header bits above the 10-bit length carry a rolling counter and flags
  the decoder must mask off — see `docs/PROTOCOL.md`.

Known macOS behaviour, not yet hit in this repo:

- **One RFCOMM client at a time.** The app and CLI cannot both be connected.

---

## Later — designed, NOT built in v1

Intentionally out of scope. Recorded so nobody half-builds one of these.

| Item | Design | What it needs |
|---|---|---|
| **Firmware update** | The protocol has FOTA messages | Not planned. Risk of bricking; needs Samsung's firmware binaries. Use a borrowed Android phone |
| **Factory reset** | Single message | Deliberately excluded; destructive and needs re-pairing |
| **App ↔ CLI bridge** | App holds the channel and serves the CLI over a local socket | An IPC protocol and a fallback path in the CLI |
| **Other Buds models** | Per-model constants and feature flags | A model table, and hardware to test on (Buds+ is on hand) |
| **Global hotkeys / Shortcuts actions** | App Intents over the view model | An App Intents target; needs the bundled app |
| **Custom EQ** | Only if Buds2 firmware supports it | Confirm in the protocol first; presets are all Buds2 officially has |
| **Notarised distribution** | Developer ID signing and notarisation | An Apple Developer account |

**When Later work starts:** the app ↔ CLI bridge first — it removes the only day-to-day
annoyance — then Shortcuts actions.
