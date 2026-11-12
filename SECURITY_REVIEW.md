# DLChat security review

Date: 2026-11-08 (fixes for all ten findings the same day). Branch `feat/dlchat-foundation`. Reviewed by Claude (code reading only) using four
installed skills: `threat-model` (bootstrap mode, no owner interview), `crypto-audit`,
`swift-security` and `constant-time-analysis`. `zeroize-audit` was installed but targets C, C++ and
Rust, so it was not applied to this Swift code.

This is a code review, not a certification. It does not show the app is secure. An independent
cryptographer and a device-forensics test are still needed before relying on it (see section 6).

## 1. What was looked at

| Area | Files |
| --- | --- |
| Key derivation | `Packages/DLCore/Sources/DLCore/Keys.swift`, `Phrase.swift` |
| Message sealing | `Frame.swift`, `Composer.swift`, `Receiver.swift`, `Repair.swift` |
| Online relays | `Online.swift`, `DLChat/Online/OnlineModel.swift`, `RelayPool.swift`, `CloudCarrier.swift` |
| Tor | `Packages/TorKit/Sources/TorKit/Tor.swift` |
| On-device storage | `DLChat/Vault/Vault.swift`, `Keychain.swift`, `GroupBook.swift`, `GroupModel.swift` |
| PIN and duress PIN | `DLChat/Vault/AppLock.swift` |
| Invites | `DLChat/Shared/GroupInvite.swift`, `PictureInvite.swift`, `PictureInviteView.swift`, `GroupSetupView.swift` |
| Device traces | `DLChat/Shared/Hygiene.swift` (clipboard, app switcher, keyboards), logging, UserDefaults |

## 2. How it is built (short)

- **Group key.** A random phrase of 10, 15 or 20 words (96, 146 or 196 bits of entropy from
  `SecRandomCopyBytes`). PBKDF2-HMAC-SHA256 with 600,000 rounds gives the master key; HKDF-SHA256
  splits it into room, MAC and encryption keys. Separate keys for separate jobs: good.
- **Messages.** A deterministic, SIV-style design: tag = HMAC-SHA256 over the plaintext (64 bits for
  spoken words, 128 for QR, tones, radio and online); the ChaCha20 nonce is derived from the tag. The
  tag is checked in constant time before anything is used. No version or marker in the clear.
- **Online.** The sealed frame is wrapped again with ChaCha20-Poly1305 under a separate group key,
  padded to a size bucket, and posted as a Nostr gift-wrap signed by a throwaway key to a mailbox key
  that changes daily. Tor is on by default and fails closed (no direct socket while Tor is starting).
- **On the phone.** One ChaCha20-Poly1305 sealed store file (Complete file protection, excluded from
  backup) whose key is in the Keychain (this device only, never synced). Wipe deletes that key
  first, so any leftover copy of the file is unreadable.
- **PIN.** Only guards the screen (the app says so honestly). Duress PIN wipes and looks like a
  normal unlock; both hashes are always computed so timing does not tell them apart.

## 3. Findings, most serious first

| # | Severity | Finding | Status |
| --- | --- | --- | --- |
| 3.1 | High | Group keys and PIN hashes survived deleting the app | **Fixed** |
| 3.2 | Medium | Picture invite password could be 4 words (40 bits) | **Fixed** |
| 3.3 | Medium | Relays could tell that two groups share a member | **Fixed** (part remains, see 3.3) |
| 3.4 | Medium | "Send invite by message" put the group key in chat history and backups | **Fixed** (removed) |
| 3.5 | Low | Online posts' expiry tag revealed the exact send time | **Fixed** |
| 3.6 | Low | A public relay could be added as plain `ws://` | **Fixed** |
| 3.7 | Low | Rooms note overclaimed secrecy | **Fixed** |
| 3.8 | Low | Keychain showed whether a duress PIN was set | **Fixed** (PIN guessing remains, see 3.8) |
| 3.9 | Low | Screen recording and mirroring showed decrypted messages | **Fixed** |
| 3.10 | Low | A web page or app can open DLChat's Join screen with an attacker's phrase | **Mitigated** (stronger warning) |

### 3.1 Group keys and PIN hashes survived deleting the app (High, fixed)

- **Where:** `DLChat/Vault/Keychain.swift`, `DLChat/Vault/Vault.swift`.
- **What:** iOS keeps an app's Keychain items after the app is deleted. Deleting DLChat removed the
  messages but left every group's master key, the store key and the PIN hashes on the phone. Someone
  who later examined the phone (forensic tools read the Keychain of an unlocked phone) could take the
  group keys and read the group's future messages, even though the person thought DLChat was gone.
  A reinstall also came up locked with the old PIN.
- **Fix:** `Vault.dropSecretsLeftFromEarlierInstall` runs at launch. UserDefaults and the store file
  are deleted with the app, so when neither is there it is a fresh install and the leftover Keychain
  items are deleted. An update keeps everything because its store file is still there.
- **Test:** `VaultTests.testReinstallDropsLeftoverSecretsButUpdateKeepsThem`.
- **Limit:** this cleans up on the next install, not at deletion (iOS gives apps no uninstall hook).
  Until DLChat is reinstalled, the keys stay in the Keychain. The in-app wipe remains the way to
  erase keys now. Edge case: someone updating from an older build who set a PIN but never saved any
  group has no store file, so that PIN is dropped (there is nothing behind it to protect).

### 3.2 Picture invite password could be 4 words (Medium, fixed)

- **Where:** `Packages/DLCore/Sources/DLCore/PictureInvite.swift:19`.
- **What:** the picture is meant to be sent over ordinary chat, where it may sit in backups for
  years. 4 random words is 40 bits. At 600,000 PBKDF2 rounds a high-end GPU tests roughly 15,000
  guesses a second, so the whole space is about 2.4 GPU-years: within reach of a funded attacker
  renting many GPUs.
- **Fix:** the minimum is now 5 words (50 bits, about 1,000 times more work), default 5. Pictures
  already made with 4 words still open.

### 3.3 Relays could tell that two groups share a member (Medium, fixed; part remains)

- **Where:** `DLChat/Online/OnlineModel.swift`, `DLChat/Online/RelayPool.swift`.
- **What:** all groups' mailboxes went over one socket per relay, and on relays that require sign-in
  the phone signed as every group's mailboxes there. So a relay could tell which groups share a member.
- **Fix:** one relay connection per group. Each one signs in only as its own group's mailboxes, and
  gives Tor its own SOCKS username, so Tor builds a separate circuit and the groups leave through
  different exits. Test: `OnlineModelTests.testEachGroupHasItsOwnSocketAndAsksOnlyForItsOwnMailboxes`.
- **What remains:** each connection still asks for 16 days of one group's mailboxes at once, so a
  relay can link one group's posts across days (it cannot read them). With Tor turned off, every
  connection comes from the phone's own address, so relays can still link the groups by address.
  Shrinking the lookback or adding cover traffic would cost battery and data; not done.

### 3.4 "Send invite by message" put the group key in chat history (Medium, fixed)

- **Where:** `DLChat/Screens/GroupSetupView.swift`.
- **What:** the invite link holds the phrase. Sent by Messages or another chat app, it stayed in that
  app's history and backups.
- **Fix:** the button is removed. Invites are the QR code shown in person, or the picture invite,
  which is locked with spoken words. Links still open (a scanned QR code is one).

### 3.5 Online expiry tag revealed the exact send time (Low, fixed)

- **Where:** `Packages/DLCore/Sources/DLCore/Online.swift`, `event(wire:keys:now:)`.
- **What:** `created_at` is blurred by up to 2 days, but the `expiration` tag was the exact send time
  plus 14 days, so anyone reading the relay later could recover the real send time.
- **Fix:** expiry now counts from the blurred time (blurred time + 16 days), still at least 14 days
  after sending. Test: `OnlineTests.testEachPostHasItsOwnAuthorAndABlurredTime`. Limit: the relay
  itself still sees when the post arrives.

### 3.6 A public relay could be added as plain ws:// (Low, fixed)

- **Where:** `DLChat/Online/OnlineModel.swift`, `setRelays`.
- **What:** a relay typed as `ws://` to a public server would carry mailbox keys and timing in clear
  text past the Tor exit or across Wi-Fi. Content stays sealed either way.
- **Fix:** plain `ws://` is accepted only for this phone, a home network address, `.local` or `.onion`.
  Test: `OnlineModelTests.testPlainWebSocketOnlyToLocalOrOnionRelays`.

### 3.7 Rooms note overclaimed secrecy (Low, fixed)

- **Where:** `DLChat/Screens/GroupListView.swift`.
- **What:** it said only people with the same room word can read a room. Room keys come from the
  group key plus the room word, so anyone in the group who guesses a short room word can read it.
- **Fix:** the note now says rooms keep chats apart but are not secret from the group.

### 3.8 Keychain showed whether a duress PIN was set (Low, fixed; PIN guessing remains)

- **Where:** `DLChat/Vault/AppLock.swift`, `DLChat/Screens/SafetyView.swift`.
- **What:** the PIN items were named `lock.pin` and `lock.duress`, and the duress item only existed
  once a duress PIN was set, so a forensic copy showed one existed.
- **Fix:** neutral names (`lock.1`, `lock.2`, `lock.3`), moved over at launch from the old names. The
  duress slot always holds 48 bytes once a PIN is set (random bytes no PIN can match when there is no
  duress PIN). Safety always offers "Set duress PIN" and no longer says whether one is set. Tests:
  `AppLockTests.testKeychainLooksTheSameWithOrWithoutADuressPIN`, `testOldItemNamesAreMovedAndStillWork`.
- **What remains:** a 6-digit PIN can still be guessed offline in minutes from a forensic Keychain
  copy. That reveals the PIN only: the PIN encrypts nothing, and anyone with that copy already has the
  store key. Longer PINs are already accepted. Making the PIN truly protect data would mean tying the
  store key to the Secure Enclave and the phone's own passcode; not done.

### 3.9 Screen recording showed decrypted messages (Low, fixed)

- **Where:** `DLChat/Shared/Hygiene.swift`, `DLChat/Screens/RootView.swift`.
- **What:** the app hid in the app switcher, but not during screen recording or AirPlay mirroring.
- **Fix:** while the screen is recorded, mirrored or shared, the app shows its privacy cover ("Hidden
  while the screen is recorded or shared"). iOS cannot block single screenshots; that is unchanged.
  Not testable in the Simulator; check on a phone with Control Center screen recording.

### 3.10 Join screen can be opened with someone else's phrase (Low, mitigated)

- **Where:** `DLChat/Screens/RootView.swift`, `GroupSetupView.swift`.
- **What:** any web page or app can open `dlchat://join#...`, landing the person on Join with an
  attacker's phrase. They still have to tap Join.
- **Fix:** the Join screen now says the invite came from a link that anyone can make, and to join
  only if the expected person reads the same three safety words aloud. Blocking links outright would
  also break scanning the invite QR code with the iPhone Camera.

## 4. Checked and fine (do not re-raise)

- **Randomness:** phrases, salts, PIN salts, picture passwords and nonces use `SecRandomCopyBytes`
  or CryptoKit. `UInt8.random` / `Double.random` use the system CSPRNG and only pick the 6-bit
  frame salt and the time blur.
- **Constant time:** frame tags and PIN hashes are compared without early exit. The
  `constant-time-analysis` skill's assembly analyzer is not bundled with the installed skill, so this
  was checked by reading code, not by analyzing compiled output. No path gives a remote attacker a
  timing measurement of decryption.
- **Key separation:** MAC, encryption, room, mailbox and online-wrap keys are separate HKDF outputs.
- **Authentication before use:** frames are checked before decoding; online events are checked for
  a valid id and signature before unwrapping.
- **Keychain:** every item is `WhenUnlockedThisDeviceOnly` and not synchronizable.
- **Store file:** sealed, Complete protection, excluded from backup; wipe drops the key first.
- **Tor:** control channel is a private socket pair, not a TCP port; SafeSocks on; fails closed.
- **Clipboard:** copied text is local-only and expires after 60 seconds. Third-party keyboards are
  refused. Autocorrect is off on message fields.
- **Logs:** only relay status lines are printed; no message text, phrase or key.

## 5. Hardening notes (weaker than ideal, no traced exposure)

- The PBKDF2 salt is a fixed string, so precomputation would cover every user at once. With 96+ bit
  phrases that is still far beyond reach. A per-group salt would need a new phrase format.
- Spoken messages have a 64-bit tag, and one-word repair tries about 1,000 candidates per word, so a
  forged message is accepted with odds of roughly 1 in 2^48 per try. Fine for voice, where each try
  costs a person reading words aloud.
- The deterministic design with a 6-bit salt means the same text sent twice within the same 5-minute
  slot has a 1 in 64 chance of producing the same words, so a listener could tell it was a repeat.
- The picture invite's look comes from a hash of the phrase, so two pictures for one group look alike.
- UserDefaults (not encrypted, included in backups) shows that online chat was used: relay list,
  last sync time.

## 6. Not covered

- The secp256k1 library (P256K), the Tor binary and Apple's crypto code: treated as trusted.
- A real forensic extraction of a test iPhone, before and after wipe, delete and reinstall.
- Radio: what a Meshtastic broadcast reveals about location and activity (the radio itself is seen
  by anyone listening).
- Fuzzing the frame, QR, tone and relay parsers.
- An independent cryptographer's review of the SIV-style frame design (custom construction).
