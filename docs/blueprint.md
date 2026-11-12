# DLChat blueprint

Status: APPROVED by owner 2026-11-02. Author: Opus, Phase 3.
Owner decisions: build, disclose and get attorney review for radio rules; 1024 radio-distinct word list; default 15 words; real encryption replaces the mixed dictionary.
No code exists yet. Numbers marked *estimate* come from the throwaway model in
`tools/wordlist_analysis.py`, not from the app.

## 1. The important change from the original idea

The original idea was to mix the dictionary with the secret phrase, so each
English word always maps to a different word. That is a substitution cipher. A
listener logging a few hours of traffic can break it by frequency: the same
English word always produces the same spoken word.

The blueprint keeps what the idea was for and changes how it works:

1. English is compressed to bits using a fixed public dictionary.
2. The bits are encrypted with a key derived from the phrase.
3. The result is turned into words from a fixed public word list.

The same sentence sent twice sounds completely different. No secret lives in
the word list. Security comes from the key, which is the standard design rule
(Kerckhoffs's principle). To the user it still works as described: say gibberish
words, and only phrase holders get English back.

## 2. Threat model

| Threat | Defended? | How, or what the app tells the user |
| --- | --- | --- |
| Listener on the channel reads a message | Yes | Encryption |
| Outsider forges or alters a message | Yes | 64-bit tag on voice, 128-bit on data transports |
| Recorded message replayed later | Mostly | Seen-message list plus authenticated send time shown as "sent 3 days ago". Not silently rejected, because paper relays are legitimately late |
| Mistyped or misheard phrase | Yes | Checksum in the phrase, safety words to compare |
| Forced phone unlock | Partly | App PIN, duress PIN that wipes, panic wipe. Forensic recovery of erased flash is not ruled out; crypto-erase is the mitigation |
| Phone seized, past traffic was recorded | **No** | A shared phrase decrypts everything ever recorded. Stated in the app |
| Someone in the group lies or impersonates | **No** | Everyone holding the phrase is equal. Names are unverified. Stated in the app |
| Being noticed or located | **No** | Gibberish on an open channel stands out, and any transmission can be direction-found. Encryption hides content, not that you are talking. Stated in the app |
| Message length analysis | Partly | Minimum length and word padding; a long message still sounds long |
| Jamming | No | Physics |

The app never says "secure", "unbreakable" or "military-grade" (safeguard 12).
Copy describes what is protected and what is not.

## 3. Protocol v1 (frozen once shipped)

Everything in this section is part of the wire format. Changing a word list,
the dictionary or a constant breaks interoperability between phones, so hashes of
all data files are pinned in tests.

### Phrase

- Generated only, from `SecRandomCopyBytes`. No user-invented phrases in v1:
  human-chosen phrases are the most likely way this fails.
- Word list: 1024 radio-distinct words, 10 bits each (section 5).
- Lengths: **10, 15 (default), 20** words. The last 4 bits are a SHA-256 checksum.
  Secret strength: 96, 146, 196 bits.
- Why 15: over 128 bits, and the phrase is entered once per phone, in person.
  20 is offered but adds nothing practical. 10 is still far beyond brute force.
- Never sent over radio. Shared in person by reading it, writing it, or a QR code.
  Owner decision 2026-11-06: Create always shows the invite QR code (`dlchat://join?…#phrase`,
  readable by the iPhone Camera). "Send invite by message" was removed 2026-11-08 (it left the
  phrase in Messages and iCloud); the picture invite is the way to send one. The joiner sees the safety words and is told to compare
  them by voice; they prove the phrase arrived intact, not who sent it. Group details still
  show the QR only while held.
- 2026-11-07: picture invite (`PictureInvite`, `Scene` in DLCore). A painted night landscape
  unique to the group (seeded from SHA-256 of "DLChat/v1/scene" + phrase). Version 2 (same day,
  owner asked to hide the data in the picture): the stars carry it. The top 40% of the sky is a
  25 px grid with a fixed jitter; a bright star is 1, empty sky 0; decoy specks, Milky Way dust
  and more stars down behind the ridges hide the grid. 68 bytes (version, 8-byte salt,
  ChaChaPoly sealed text: word count, 20 x 10-bit word numbers, name up to 16 bytes, tag; the
  nonce comes from the password key, so it is not stored) plus 64 Reed-Solomon bytes = 1,056
  stars. Key: PBKDF2-SHA256 (600,000 rounds) of a 4-, 5- or 6-word password from the radio list
  (40, 50 or 60 bits) that the sender picks; the count is not stored and the unlock screen never
  says it, though anyone reading the code knows the choices are 4 to 6, so hiding it adds
  under 2 bits. The password is read aloud, never sent with the picture. Survives JPEG at
  quality 0.3 scaled to half size and a 200 x 100 px patch over the stars (tests); a crop is
  refused. Honest limit: 40 to 60 bits slowed by PBKDF2 resists casual guessing, not a
  well-funded attacker who has the picture; against that attacker, share the phrase in person.

### Keys

CryptoKit and CommonCrypto only, both part of iOS.

```
master   = PBKDF2-HMAC-SHA256(phrase, salt="DLChat/v1/kdf", 600000, 32 bytes)
roomKey  = HKDF-SHA256(master, info="room/" + roomWord)     # roomWord may be empty
macKey   = HKDF-SHA256(roomKey, info="mac")
encKey   = HKDF-SHA256(roomKey, info="enc")
safety   = HKDF-SHA256(master,  info="safety") -> 3 list words
```

A generated phrase does not strictly need a slow KDF. It is kept because it helps
when part of a phrase leaks, such as a partly overheard or partly photographed
one. It runs once per phrase; the derived key is cached in the Keychain.

### Encryption

SIV construction, encrypt and authenticate with one tag and no separate nonce.
This is what makes the 8-byte voice overhead possible; a standard AEAD costs 28
bytes, about 16 extra spoken words on every message.

```
tag    = HMAC-SHA256(macKey, len(P)_bits || P) truncated to tagBits
nonce  = HMAC-SHA256(encKey, "nonce" || tag) truncated to 12 bytes
stream = ChaChaPoly.seal(zeros, encKey, nonce).ciphertext   # discard its Poly1305 tag
frame  = tag || (P XOR stream)
```

- tagBits: 64 for voice, 128 for tones, Bluetooth and QR.
- Decrypt reverses this, recomputes the tag and compares in constant time. Nothing
  is shown on failure beyond "could not decrypt".
- No version, group id or marker in the clear. A frame is indistinguishable from
  random bits. Receivers try every stored group and room; new versions try new keys.
- **Custom composition warning:** this is a textbook SIV shape from standard
  parts, but this exact composition has had no external review. Independent test
  vectors are required (T003); third-party cryptographer review is a launch blocker.

### Plaintext P

| Field | Bits | Notes |
| --- | --- | --- |
| Send time | 20 | 5-minute slots since 2026-01-01 UTC, lasts about 10 years |
| Flags | 2 | Bit 0 = duress (see section 7), bit 1 reserved |
| Salt | 6 | Random; two people sending the same words sound different |
| Text | variable | Huffman tokens ending in an end marker |
| Padding | variable | Random, up to a word boundary, minimum 4 body words |

### Text coding

- Static Huffman code over about 4096 entries: common English from a frequency list,
  plus hand-added emergency vocabulary (rifle, bandage, generator, ammo), digits and
  an escape to spell any other word.
- Lowercase only on voice. No word list changes without a protocol version.
- *Estimated* spoken length with the 10-bit list and 64-bit tag:

| Message | Words said |
| --- | --- |
| yes | about 11 |
| need water at north gate | 16 |
| meet at the church at noon | 18 |
| doctor needed at the smith house now bring bandages | 24 |
| generator is out of fuel can you spare five gallons | 30 |

  Plain UTF-8 would need 2 to 3 times as many words. Better dictionary weights should
  shorten these somewhat. Voice UI shows a live word count while typing.

- 2026-11-07 (before any release, so no installed base to split): added ~120 everyday
  texting words and contractions near the top of the dictionary (hey, gonna, anybody,
  interested, i'm, don't…), kept a contraction's apostrophe so "I’m" is one word, and
  weighted spelled letters by English letter frequency. Measured: "hey guys im going
  outside and gonna go get food do you need anything else" 34 → 24 words; the 76-word
  breakfast message → 38. Emergency samples unchanged except "fuel low at the farm"
  14 → 15. Send shows which words will be spelled out. The 64-bit tag was not shortened.

### Error repair

Misheard words are the main failure on voice. The tag can act as a checker, so repair
adds nothing on air:

- Missing word marked `?`: try all 1024 values.
- Decrypt fails: optional "Try to repair" tests each single-word substitution, about
  20,000 candidates.
- Any repaired message is labelled with the word changed. A successful search costs
  about 14 bits of the 64-bit forgery margin, leaving roughly 50 bits.

### Replay handling

Keep a hash of every frame seen for the retention period. A duplicate shows "already
received" with the original time. Old send times are displayed, and an honest "clock
may differ" appears when a time is in the future.

## 4. Transports

Each is a separate way to move the same frame.

| Transport | Mechanism | Limits to state |
| --- | --- | --- |
| Words | Read and enter | Slow, needs a clear channel |
| Tones | MFSK modem in pure Swift, played by speaker into the radio mic | Unproven on real radios until field tested |
| QR | `CIFilter.qrCodeGenerator`, `DataScannerViewController` | In person |
| Nearby | MultipeerConnectivity, opt-in, foreground only, forwards frames it cannot read | Short range. Stops when the app is backgrounded. **Advertising reveals to nearby scanners that a DLChat phone is present**, so it is off by default |
| Copy/paste | `UIPasteboard` local-only with expiry | Trivial |

Tone modem starting point, to be finalized by simulation: 16-MFSK, 31.25 baud, 700 to
2575 Hz, Reed-Solomon with interleaving, about 60 bps net, around 10 seconds for a
64-byte frame including a VOX lead-in and sync preamble. Non-coherent detection
tolerates clipping and level changes better than phase modems.

A radio channel simulator is built before any UI (bandpass, clipping, noise, clock
drift, squelch chop), and modem acceptance is measured against it. **The simulator is
evidence about the modem, not about real radios.**

## 5. Word list decision

Measured on the published lists with a crude phonetic key:

| List | Words | Words with a sound-alike | Edit-distance-1 pairs |
| --- | --- | --- | --- |
| BIP39 | 2048 | 978 (48%) | 806 |
| EFF short | 1296 | 841 (65%) | 1080 |
| Filtered union | 1441 possible | 0 by this key | 0 |

**Recommendation:** ship a 1024-word list filtered from BIP39 and EFF short, preferring
one and two syllables. Costs about 10% more words than BIP39 but removes most
confusable pairs on a noisy FM channel. The phonetic key is crude; a human read-aloud
pass over the final list is a task (T002).

## 6. Stack decision

| Decision | Chosen | Rejected and why |
| --- | --- | --- |
| UI | SwiftUI, iOS 17+ | Older minimum adds work. Newer shuts out older phones, which matters in an emergency app |
| Crypto | CryptoKit + CommonCrypto only | libsodium: a dependency, and it does not remove the composition question. Also keeps export paperwork simplest |
| Core logic | `Packages/DLCore`, no UI imports, `swift test` on the Mac | Logic in the app target: slow, simulator-bound tests |
| Storage | Encrypted JSON files + Keychain | SwiftData or GRDB: small data, and a database leaves residue that defeats crypto-erase |
| Project | Hand-maintained `.xcodeproj` as in `next-cup` | xcodegen is not installed; not worth adding |
| Dependencies | **None** | Every dependency is a surface to audit in a security app |
| Network | **No URLSession, no sockets.** Multipeer only | A test greps for network APIs |

`replica-architect` was invoked but is not applicable: it requires a recon map (no
references here) and its stack table targets web backends. No output used.

## 7. Security features

- **Panic wipe:** always reachable. Press and hold 3 seconds, with a visible button and a
  VoiceOver action. Deletes all Keychain items and message files. Irreversible and needs
  no undo; the hold is the confirmation.
- **App PIN:** optional, 6+ digits, verified by PBKDF2, escalating delay on failures. Face
  ID is available only while no duress PIN is set, since a face can be forced.
- **Duress PIN:** looks like a normal unlock, silently wipes, shows an empty app. Since 2026-11-08 the
  Keychain looks the same with or without one (neutral item names, the duress slot always
  filled). It still protects against a person with a phone, not a forensics lab, which can
  read the store key directly.
- **Duress flag:** hidden send option. The text looks normal; the receiver sees "sender
  marked this as under duress". For when someone is forced to send "all clear".
- **Room word:** an extra word that derives separate keys within a group. Not a duress
  feature, despite the earlier grouping.
- **Safety words:** 3 words, one-way from the phrase. Compare in person or on air; 30 bits
  reveals nothing useful about a 96+ bit secret.
- **Hygiene:** third-party keyboards blocked, autocorrect off on plaintext, privacy cover in
  the app switcher, no backups of secrets or messages, local-only pasteboard for plaintext,
  no plaintext in logs, retention default 7 days (off, 1, 7, 30, forever).

## 8. Data model

All local. Only the owner of the phone can read or write.

| Entity | Fields | Where |
| --- | --- | --- |
| Group | id, name, wordCount, createdAt, lastUsedAt, sortIndex, rooms[] | Encrypted store |
| GroupSecret | groupId, phrase, master | Keychain, `WhenUnlockedThisDeviceOnly` |
| Message | id, groupId, room, direction, text, frame, transport, sentSlot, recordedAt, duress, repairedWord | Encrypted store |
| SeenFrame | sha256(frame), firstSeenAt | Encrypted store |
| RelayFrame | frame, ttl, expiresAt (24h) | Encrypted store, Nearby only |
| Draft | groupId, room, text | Encrypted store, autosaved |
| Settings | defaultWordCount, retention, sort, relayOn | UserDefaults (no secrets) |
| LockSecret | pinHash, duressHash, storeKey | Keychain, `WhenUnlockedThisDeviceOnly` |

Store: one ChaChaPoly-sealed JSON file under a Keychain key, `completeFileProtection`,
excluded from backup. Atomic writes. Wipe deletes the key first, then the files.

Indexes and queries: none needed; lists hold at most thousands of rows in memory.

## 9. Module API (no server exists)

```swift
// DLCore: pure, no UIKit or SwiftUI
Phrase.generate(words:) -> Phrase
Phrase.parse(_:) throws -> Phrase              // .unknownWord(i), .badChecksum
Keys(phrase:, room:)                           // slow; call off the main actor
Frame.seal(text:, flags:, sentAt:, keys:, tagBits:) throws -> Frame
Frame.open(_:, trying: [Keys]) -> Opened?
Repair.search(words:, trying:) -> Opened?
WordCodec.encode(_:) / decode(_:) throws
TextCodec.encode(_:) / decode(_:) throws
Modem.encode(_:) -> [Float]; ModemDecoder.feed(_:) -> [Data]
ChannelSim(profile:).apply(_:) -> [Float]      // test only
```

App: `Vault` (Keychain + store, wipe), `AudioIO` (AVAudioEngine), `NearbyLink` (Multipeer).

Permissions, each asked at first use only: microphone for Listen, camera for Scan, local
network for Nearby. No notifications in v1.

## 10. Folder structure

```
DLChat.xcodeproj
DLChat/            App, Screens/, Vault/, AudioIO/, NearbyLink/, Design/
DLChatTests/       App-level tests
DLChatUITests/     Core flow
Packages/DLCore/   Sources/DLCore (Crypto, Codec, Modem, Resources), Tests
tools/             wordlist_analysis.py, make_dictionary.py, vectors_check.py
```

## 11. State

`@Observable` app-level `Vault` and `Inbox`, screen state in views. No server state.
Slow work such as key derivation and repair runs off the main actor with visible progress.

## 12. Vendors and data flows

None. No analytics, crash SDK, AI or cloud. Bytes leave the phone only when the user
transmits: sound, a QR on screen, or a Nearby frame. See `data-inventory.md`.

## 13. Radio rules (not legal advice; needs review)

This affects the product premise, so it is stated plainly. US rules read 2026-11-02:

| Service | What the text says |
| --- | --- |
| GMRS | Prohibits "Coded messages or messages with hidden meanings" (47 CFR 95.1733(a)(3)). FCC staff have treated voice scrambling as coded messaging |
| Amateur (ham) | Prohibits messages "encoded for the purpose of obscuring their meaning" (97.113(a)(4)), but 97.403 allows "any means of radiocommunication" for immediate safety of life and property when normal systems are unavailable |
| FRS | No explicit code ban found in 95.333 or 95.533. Digital data rules (95.531, 95.587) cover built-in unit features limited to 1 second per 30 seconds. Whether acoustically played tones count is unclear |
| All voice shared channels | 95.381 blocks certifying radios with voice obscuring; it addresses radio hardware, not an app beside a radio |

I did not find a Part 95 emergency exception for coded GMRS traffic, and did not establish
the position for non-US users. **Most likely reading: using this on GMRS or ham in ordinary
times breaks FCC rules, even though the same act in a true emergency has at least a ham
exception.** The app itself transmits nothing on its own; the user holds the radio.

Product consequences:

- Practice runs over Nearby, QR and copy/paste, none of which use radio. A guided drill
  teaches this without keying up.
- The first radio use shows a short plain notice that rules vary and that encrypted traffic
  may be prohibited outside emergencies, and links to the sections above.
- Listing and app never claim this is legal or FCC-approved.
- App Review may push back; its Legal guidelines require compliance with local law. Attorney review is a
  launch blocker for the App Store, not for building or TestFlight.

## 14. Export compliance

Apple's table: encryption limited to what the OS provides needs no App Store Connect
documentation; industry-standard algorithms not in the OS need a French declaration;
proprietary ones need a CCATS. DLChat uses only iOS-provided primitives. Whether the custom
composition counts as proprietary, and the overall messaging-app classification, need a
qualified answer before submission (blocker).

## 15. Parts that bite

- **Interop is forever:** a dictionary or list tweak splits a neighborhood. Hashes pinned.
- **Bit packing:** frames are not byte aligned on voice. Property tests over random inputs.
- **Clocks:** phones drift during long outages; time is display-only, never a reason to reject.
- **Audio session:** route changes, Bluetooth headsets, interruptions; force the built-in speaker
  and mic and warn otherwise.
- **Simulator limits:** no mic-to-speaker path, no camera, unreliable Multipeer. Needs real phones.
- **Wrong room or group:** identical to noise, so the error must suggest checking the phrase and
  room rather than saying "corrupt".
- **Fat fingers:** an accidental panic wipe loses phrases irreversibly, so re-entry from paper is
  explained during setup.

## 16. Scope scoring (0-3 each; effort: 3 = cheap)

Owner asked for everything, so nothing is cut; the score sets the order. Evidence is the owner's
request or table stakes only, as there are no user reviews.

| Feature | Evidence | Impact | Effort | Fit | Total | Milestone |
| --- | --- | --- | --- | --- | --- | --- |
| Phrase, cipher, word codec | 3 | 3 | 2 | 3 | 11 | M1 |
| Group setup, compose, decode UI | 3 | 3 | 2 | 3 | 11 | M1 |
| Word repair | 2 | 3 | 3 | 3 | 11 | M1 |
| Vault, panic wipe | 3 | 3 | 2 | 3 | 11 | M2 |
| Safety words, replay, room word | 3 | 2 | 3 | 3 | 11 | M2 |
| PIN, duress PIN, duress flag | 3 | 2 | 2 | 3 | 10 | M2 |
| QR | 3 | 2 | 3 | 2 | 10 | M3 |
| Tone modem | 3 | 3 | 0 | 3 | 9 | M4 |
| Nearby and relay | 3 | 2 | 1 | 2 | 8 | M5 |

**Later:** read-aloud (TTS), on-device speech to words, repair of two words, plausible-sentence
encoding that sounds less like gibberish, phone cable for audio, group key ratchet for partial
forward secrecy (requires deleting old keys and the phrase, so needs its own design), per-person
signing, Android.

**Out of scope:** servers, accounts, AI, non-English dictionaries in v1, voice encryption, any
claim of legality or certification.
