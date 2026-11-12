# DLChat — PRD

Status: APPROVED by owner 2026-11-02. Created 2026-11-02. Design and protocol: `docs/blueprint.md`.

## Purpose

Offline grid-down encrypted messaging. A group shares a generated phrase of 10, 15 or 20 words. Messages become gibberish words or audio tones on an open radio, or a QR or nearby-phone transfer, and only phrase holders can read them.

Platform: iPhone, iOS 17+, SwiftUI. Mode: lean.

## Product features

Words transport, tone modem, QR, Nearby with relay, copy/paste. Generated phrases with checksum, rooms, safety words, single-word repair, replay display, panic wipe, app PIN, duress PIN, duress flag, retention control, practice drill without radio, radio-rules notice.

## Out of scope (non-goals)

Servers, accounts, analytics, AI, voice encryption, user-invented phrases, non-English dictionaries in v1, any claim of legality or certification. Later list: `docs/blueprint.md` section 16.

## Core screen and user flow (Phase 3B design directions cover this)

1. Create a group: generate the phrase, show it, compare safety words. Or join by typing or scanning.
2. Send: pick group, type, see live word count, then read large word groups with progress as they are spoken. Other transports one tap away.
3. Receive: enter words with autocomplete and `?` for a missed word, see decoded English with sent time and any warnings. Or Listen, or Scan.
4. Panic wipe reachable from every screen.

Conditions: dark, stress, gloves, one hand, radio in the other.

## REA and Replica findings

No references, so REA and Replica recon, entrepreneur and clean room are NOT APPLICABLE. See `docs/rea-findings.md`.

## Atomic tasks

Verification: `V1` = `swift test --package-path Packages/DLCore`. `V2` = `xcodebuild test -project DLChat.xcodeproj -scheme DLChat -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`. Every UI task also runs smoke S1-S5.

| ID | Task | Depends on | Acceptance criteria | Verification | Status |
| --- | --- | --- | --- | --- | --- |
| T001 | DLCore package and Xcode project skeleton | - | App launches empty on simulator; no third-party dependencies; `V1` runs | V1, V2 | done |
| T002 | Build 1024-word radio list and dictionary | T001 | Exactly 1024 words, none sharing a phonetic key or edit distance 1; licenses in `asset-licenses.md`; SHA-256 pinned in test. The owner read-aloud pass is a separate human review item (launch blocker 9), not part of this task | V1 | done |
| T003 | Phrase, keys, Frame seal and open | T002 | Round trip for random input; any flipped bit fails; wrong key fails; vectors reproduced by independent `tools/vectors_check.py`. No third-party Python packages are installed and none may be added: use stdlib `hashlib`/`hmac` for PBKDF2 and HMAC, write HKDF from `hmac`, and a small pure-Python ChaCha20 (RFC 8439) that first passes the RFC 8439 section 2.4.2 test vector. Keystream is counter 1, as ChaChaPoly uses | V1 + script | done |
| T004 | TextCodec and WordCodec | T003 | Round trip on 10,000 random and listed sentences; ten sample messages within 10% of blueprint estimates or the difference recorded | V1 | done |
| T005 | Repair search | T004 | Recovers any single missing or wrong word; labelled; under 2 s on the slowest supported simulator run, Release | V1 | done |
| T006 | Vault and encrypted store | T003 | Keychain `ThisDeviceOnly`; files sealed and excluded from backup; wipe leaves no readable data, proven by test | V2 | done |
| T007 | Group create, join, safety words | T006 | Two simulators or test harness produce the same keys and safety words; bad checksum names the problem | V2, S1-S5 | done |
| T008 | Compose and read-out screen | T007 | Live word count; large groups; draft survives kill and relaunch | V2, S1-S5 | done |
| T009 | Decode screen | T008 | Autocomplete; `?`; repair offer; warning states shown; end-to-end XCUITest sends then decodes | V2, S1-S5 | done |
| T010 | Replay list, rooms, retention | T009 | Duplicate labelled; room isolates; retention purges on schedule | V2 | done |
| T011 | Panic wipe, PIN, duress PIN, duress flag | T006, T009 | Hold wipes; duress PIN wipes silently and looks normal; failures delay; flag visible only to receiver; VoiceOver alternative works | V2 | done |
| T012 | Hygiene | T009 | Third-party keyboards blocked; autocorrect off; switcher cover; local-only pasteboard; test greps for network APIs and fails on any | V2 | done |
| T013 | QR send, scan and phrase share | T007 | Generated frame round trips through generator and a CIDetector test; phrase QR only while held; scanning itself flagged device-only | V2 | done |
| T014 | ChannelSim | T001 | Reproducible seeded channel profiles: bandpass, clipping, noise, drift, chop | V1 | done |
| T015 | Modem encode and decode | T014 | At least 95% of 500 seeded frames decode at 12 dB SNR with clipping and 1% drift; numbers recorded in `claims-evidence.md` as simulated only; failure stops for Opus | V1 | done |
| T016 | AudioIO and Tones UI | T015, T009 | Plays and listens with route warnings; mic asked at first use; device loopback listed as owner test | V2, S1-S5 | done |
| T017 | Nearby and relay | T009 | Off by default; opaque frames only; dedupe and 24 h expiry unit tested; random display names; two-phone test listed as owner test | V1, V2 | done |
| T018 | Practice drill and radio-rules notice | T009 | Drill completes without radio; notice shows once at first radio use, and remains in Settings | V2 | done |
| T019 | Settings and documents | All above | Retention, wipe, export, policy, terms, licenses; copy says what is and is not protected | V2 | done |
| T020 | Safeguards and UX baseline | All above | Every row in `compliance-checklist.md` and `ux-baseline.md` has status and evidence | Audit | done |
| T021 | Lock above everything (audit A1, plus wipe on the lock screen) | T020 | Lock shows in its own window above every sheet and full-screen screen; UI test: leave with Settings open, return, Unlock is hittable and Settings is not; hold-to-wipe available on the lock screen | V2 | done |
| T022 | Lock and wipe hardening (audit A3, A4, A6, A9) | T021 | Duress and panic wipe report failure; on failure the app stays locked and the PIN is kept; panic-wipe failure is shown; duress PIN works during a wait; clock rollback re-arms the wait; wipe clears our pasteboard text and the notice flag; unit tests for each | V2 | done |
| T023 | Group screen (audit A2, blocker 16) | T021 | Pill opens a group list: choose the active group (Send, History and rooms follow it), reorder, swipe or context menu to remove with confirmation, view phrase and safety words behind a hold, add room, create and join. Removing deletes that group's Keychain items and messages. History rows can be deleted individually. Tests for each | V2 | done |
| T024 | DLCore edge fixes (audit A5, A10, A11) | T020 | Out-of-range clock clamps instead of throwing; incoming hop count capped to `startTTL`; room words trimmed and NFC-normalized in `Keys`; `tools/vectors_check.py` and existing vectors still pass, new vectors added for a non-ASCII room in both Swift and Python | V1 + script | done |
| T025 | UX baseline closure (blockers 10, 15, 16) | T023 | Safety sheet has the pressure-mark toggle with a one-line explanation; top bar holds at accessibility-extra-extra-large; confirmations for Remove PIN and shorter retention; increased-contrast edges; XCUITest `performAccessibilityAudit()` on the main screens passes or each exception is recorded; `docs/ux-baseline.md` updated with N/A reasons from `docs/audit-opus.md` | V2 | done |
| T026 | Copy and records (audit A7, A12) | T025 | Settings says the PIN guards the screen and adds no encryption, and that forensic recovery cannot be ruled out; `docs/data-inventory.md` matches the built app; `docs/compliance-checklist.md` rows re-checked against the fixes, without marking anything legally approved | V2 | done |

Each bounded run is 6 Ralph iterations; this plan needs several approved runs. Reaching a limit is not completion.

## Safeguard coverage

Applicable: 1, 2, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 19, 20 (wipe stands in for deletion, no account exists). NOT APPLICABLE by behavior: 3, 10 (free, no payment); 4, 5 (no web, cookies or tracking); 6 (no forms sent anywhere); 18 (no email). Recorded fully in T020.

## Human review and launch blockers

See `docs/launch-blockers.md`: radio rules attorney review, export classification, cryptographer review, field test, public URLs.
