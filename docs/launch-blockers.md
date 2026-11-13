# Launch blockers

| # | Blocker | Type (missing fact / failed check / legal review / approval) | Owner | Needed for | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | App Store encryption export compliance (ERN / CCATS self-classification) answers for custom crypto UI. For TestFlight the owner answered "None of the algorithms" (only iOS-provided crypto) on builds 1-3, and on 2026-11-07 asked for it to be automatic: `ITSAppUsesNonExemptEncryption = NO` in `Config/Info-extra.plist`. Whether the custom SIV composition counts as proprietary still needs a qualified answer before App Store release | legal review | Owner | App Store submission | OPEN (TestFlight answer set by owner) |
| 2 | Real-radio audio-tone reliability (clipping, squelch, VOX) cannot be tested in Simulator | failed check (untestable here) | Owner with two phones and two radios | Audio transport claim | OPEN |
| 3 | Multipeer/Bluetooth needs two physical iPhones | failed check (untestable here) | Owner | Bluetooth transport claim | CLOSED (Nearby removed 2026-11-08) |
| 4 | Business/legal inputs below are UNKNOWN; free app, no accounts, no collection | missing fact | Owner | App Store listing, privacy policy | OPEN |
| 5 | Attorney review: FCC rules on encrypted traffic (the personal radio service rules (47 CFR 95.1733(a)(3), 95.531, 95.587, 95.381) and the amateur radio rules (97.113(a)(4), 97.403)), non-US launch countries, App Review Legal guidelines. See blueprint section 13 | legal review | Owner | App Store release; not building or TestFlight | OPEN, narrowed 2026-11-12: voice radios use dropped (words and sound are for in person and chats, never pitched for radio); the only radio is Meshtastic on unlicensed bands, off until accepted, never sends in licensed mode. A JustAnswer lawyer (2026-11-12, informal) read: amateur radio, personal radio service, citizen band not allowed and family radio service rules doubtful for encrypted content; MURS and Part 15 (Meshtastic 902-928 MHz) allowed; developer liability low to medium; send the BIS/NSA open-source notification anyway; exclude Russia, Belarus, Iran, North Korea, Cuba, Syria and probably China from the App Store. Follow-ups pending |
| 6 | Independent cryptographer review of the SIV composition and protocol (and, since 2026-11-08, the anonymous support report: HPKE to the developer key inside the same gift wrap, `DLCore/SupportReport.swift`) | failed check (no review yet) | Owner | Any security claim beyond plain description | OPEN |
| 7 | Hosted privacy policy and support URLs; the repo is private | missing fact | Owner | App Store submission | OPEN |
| 9 | Owner read-aloud pass of the 1024-word list: say pairs aloud over a radio or phone and replace words that sound alike | human review | Owner | Freezing the list (changing it later breaks interop) | OPEN |
| 10 | Owner decision: the duress flag is a hidden 1-second press (blueprint), but the UX baseline wants a visible, non-gesture alternative. Loop only added a VoiceOver action. Recommended: keep the hidden gesture and add a toggle inside the Safety sheet. Built in T025 (toggle in Safety); owner can confirm | decision | Owner | Gate A (UX baseline) | RESOLVED in T025, owner to confirm |
| 11 | PIN lock weaknesses left by T011: rolling the device clock back shortens the wrong-PIN wait; no wipe button on the lock screen, group sheets or history; Face ID not built | failed check | Opus audit | Gate A | RESOLVED: T021, T022. Face ID stays out by decision (`docs/audit-opus.md`) |
| 12 | Camera QR scanning (message and phrase) cannot run in Simulator: DataScannerViewController is unsupported there. Owner test on a real iPhone: scan a message code and a phrase code from a second phone, deny camera once and see the note | failed check (untestable here) | Owner with two phones | QR transport claim | OPEN |
| 13 | Device loopback of the tone modem (T016): play a message from one iPhone speaker and hear it on a second iPhone microphone, then through two radios. The simulator has no speaker-to-mic path, and the route warnings (Bluetooth, headphones, car) were only unit tested. Also check the first-use microphone prompt, deny once and see the note, and that decode keeps up in a Release build | failed check (untestable here) | Owner with two phones | Audio transport claim (with 2) | OPEN |
| 14 | Nearby (T017) needs two physical iPhones: turn Nearby on in both, check the local network prompt, that a message sent from one opens on the other, that a third phone outside the group relays without reading, that turning it off or backgrounding stops advertising, and that Bonjour names `_dlchat._tcp` and `_udp` are accepted. Simulator Multipeer was not exercised. Also: an expired frame can be re-accepted from a neighbour and held another 24 h (the frame carries no readable send time), bounded by the 4-hop limit | failed check (untestable here) | Owner with two or three phones | Bluetooth/Nearby transport claim (with 3) | CLOSED (Nearby removed 2026-11-08) |
| 15 | At accessibility-extra-extra-large the main top bar (group pill, gear, shield) is crowded and the group name wraps mid-word; found in the T019 screenshot. Fixed in T025: top bar stacks and Send scrolls; screenshot `t025-main-axxl.png` | failed check | Opus audit | Gate A (UX baseline) | RESOLVED in T025 |
| 16 | UX baseline gaps found by the T020 audit (`ux-baseline.md`): no group reorder, no context menu or swipe actions on messages, no undo for removals (Remove PIN has no confirmation), no shake undo, no remembered sort or filter, no high-contrast handling, no deep links. Each needs an owner decision to build or to mark N/A with a reason. Built or marked N/A in T023 and T025 (see `ux-baseline.md`). Still not done: VoiceOver pass on a device, hardware-keyboard check, device check of Increase Contrast | decision | Owner | Gate A (UX baseline) | OPEN (device checks only) |
| 17 | Opus audit findings A1 to A12 (`docs/audit-opus.md`), including a demonstrated PIN lock bypass, first-group-only behavior and a duress wipe that can fail open. Tasks T021 to T026, all built; Opus re-check done 2026-11-04, four more defects found and fixed | failed check | Owner approves, Sonnet fixes, Opus re-checks | Gate A | RESOLVED, device checks stay under 2, 3, 12, 13, 14, 16 |
| 8 | License review of the frequency word list source (`first20hours/google-10000-english`, MIT repo, derived from a Google corpus); replace if unclear. EFF list CC BY attribution | legal review | Owner | Bundling the dictionary | OPEN |


## Unknown business and legal inputs

Never infer these from a reference app. Never invent them.

- Legal entity and trading name: Rare Creatures LLC (Colorado; owner confirmed 2026-11-12), rarecreatures.app
- Business location: Colorado, United States (owner, 2026-11-12)
- Launch countries/states: UNKNOWN
- Public business contact: UNKNOWN
- Privacy contact: UNKNOWN
- Minimum user age / children may use: UNKNOWN
- Pricing, billing, trials, renewal: UNKNOWN
- Refund and cancellation terms: UNKNOWN
- Data types and sensitive data: UNKNOWN
- Vendors, SDKs, analytics, AI providers, processors: UNKNOWN
- Retention or deletion exceptions: UNKNOWN

## ASSUMED intake values

- Name DLChat (user chose). Assets: Apple developer account only, icon/brand to be designed (ASSUMED).
- Transports in v1 scope per user: words, audio tones, Bluetooth/Multipeer, QR. Blueprint may stage them as slices.
- Security extras per user: safety number, replay protection, panic wipe, duress/room word, "extremely robust".
- No forward secrecy (shared static phrase); to be disclosed in-app.

## Online chat (added 2026-11-07)
- Privacy policy must name public Nostr relays as recipients of sealed messages, IP address and timing (docs/data-inventory.md), before any App Store release. App Store privacy labels change from "Data Not Collected" review: relays are third parties DLChat does not operate, the content is end-to-end encrypted; the IP address exposure must be described.
- Real public relays tested end to end with the owner's OK (2026-11-07); the smoke tests stay off unless DLCHAT_REAL_RELAYS=1, since they post to third-party servers.
- The secp256k1 dependency (21-DOT-DEV/swift-secp256k1 0.24.0, MIT) is listed in docs/asset-licenses.md; its license text must ship in the app's acknowledgements before release.

## Tor (added 2026-11-07)
- Licenses for Tor.framework (MIT), tor (BSD), OpenSSL (Apache 2.0), libevent (BSD) and liblzma must ship in the app's acknowledgements before release.
- Export compliance: the app now embeds OpenSSL and Tor. The answer given for earlier builds needs the owner's review (and possibly advice) before the next App Store release; not decided here.
- Privacy policy and App Store text must say Tor is on by default and can be turned off, what it hides (the address relays see) and what it does not (that the phone uses Tor, timing, and anything when it is off).
- Tested: Tor starts in the Simulator and the app's relay proxy reaches the Tor Project's checker through Tor with SafeSocks on (no DNS leak). Real relays over Tor (owner approved, 2026-11-07): the defaults relay.primal.net, nostr.bitcoiner.social and relay.nostrhub.fr each accept and deliver back a sealed test message, through Tor and directly. nos.lol was dropped from the defaults: it timed out on every Tor circuit tried. Live runs are not clean every time: across five runs relay.nostrhub.fr passed every time, while Primal (once over Tor) and nostr.bitcoiner.social (once direct, accepted but not delivered back within 10 s) each missed once; the app sends to all three and retries, so one miss is covered. Not yet tested: a physical iPhone, and Tor after the app has been in the background for a long time.
- tor.xcframework is not committed: run scripts/fetch-tor.sh after cloning, or the build fails.

## Meshtastic radio (added 2026-11-08)
- Built as our own implementation of the Meshtastic phone API (DLCore/Meshtastic.swift, DLChat/Meshtastic/): no Meshtastic code or generated files are included. It uses only interoperability facts (message and field numbers, port 256, Bluetooth UUIDs) taken from Meshtastic's public protocol description, whose files are GPL-3.0. Whether that keeps DLChat clear of the GPL is a legal question for the owner's counsel before an App Store release; not decided here.
- Not tested with real hardware: needs two Meshtastic radios (any current Heltec, RAK or LilyGO board on firmware 2.5 or later), paired to two iPhones in one group. Check: pairing PIN prompt, handshake, a message each way, out-of-range reconnect, licensed-mode block, a 200-character message, and that the Meshtastic app on a third phone shows nothing readable.
- Receiving works only while DLChat is open. Background receiving needs UIBackgroundModes bluetooth-central and App Review approval.
- Messages over about 233 bytes sealed (roughly 150–250 characters, depending on the text) are not sent by radio; Chat says so. No splitting yet.
- Radio law: DLChat refuses to send when the radio reports licensed mode. On licence-free bands, regional limits on transmit time still apply (for example in the EU).
- The Bluetooth permission string is new (NSBluetoothAlwaysUsageDescription) and is asked only when the radio is turned on.

## Picture invite screenshots (added 2026-11-08)
- Screenshots and smaller copies of a picture invite now open. Tested on simulated screenshots and one real Simulator screenshot; also on simulated screenshots recompressed as JPEG (quality 0.6–0.8, down to 75% size). Not yet on a physical iPhone's screenshot.
- The password is behind a hold on the invite screen so a screenshot does not carry it; a person can still screenshot while holding.
