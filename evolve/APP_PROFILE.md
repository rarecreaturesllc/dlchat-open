# DLChat app profile (cycle 001, 2026-11-07, from code and Simulator)

**What it is:** offline, account-free encrypted group messaging for iPhone (iOS 17+, SwiftUI, dark
only, portrait). A group shares a generated 10/15/20-word phrase; keys come from the phrase; messages
are sealed and travel as spoken words (read over any radio), audio tones (acoustic modem), QR codes,
Nearby (MultipeerConnectivity, phone to phone), or copy/paste. No servers, no network calls.
Free; TestFlight 0.1 (5).

## Screens (all reachable with `-seed-demo -reset-demo`, `-screen <name>` jumps)
- **Send (root):** compose box, spelled-word hint, "Show the words" read-out, then tones/QR/Nearby.
- **Read-out:** large words to read aloud, one group at a time, with repair words.
- **Receive / decode:** type or dictate heard words, fix suggestions, open with the group keys.
- **QR / scan, Tones / listen, Nearby:** the three machine transports.
- **Groups list and details:** active group pill, phrase behind hold-to-reveal, QR invite, picture
  invite, remove group.
- **New group / Join:** make phrase (10/15/20), invite QR + message link behind warning, picture
  invite; join by phrase, link, QR or picture (password words); safety words compared by voice.
- **Picture invite:** painted night scene whose stars carry the sealed phrase; 4-6 spoken words.
- **History:** received messages, search, "rooms" (sub-channels inside a group).
- **Safety:** app PIN, duress PIN (wipes), panic wipe.
- **Settings:** what is / is not protected, retention (off to days), export as text, practice drill,
  radio rules, hold-to-wipe, documents, version row (Experiments on test builds).
- **First-use radio rules notice.**

## Data
Sealed message log and drafts (file protection, excluded from backup); phrases and keys in the
Keychain; settings in UserDefaults. No analytics, no network.

## Gaps seen in the code (not yet checked against evidence)
- No online path: every message needs the sender and receiver near each other or on a radio.
- One phrase per group, no forward secrecy; no per-member identity, so "who sent this" is unknown.
- No delivery state (there is no channel back to know a message arrived).
- No disappearing per-message timer (retention is global).
- No verification step after joining beyond safety words at join time.
- No backup or move-to-new-phone path (by design: phrases are the backup).
- Notifications: none (no background delivery exists yet).

## Could not exercise in the Simulator
Real radio, two-phone Nearby, microphone tone reception in a real room.
