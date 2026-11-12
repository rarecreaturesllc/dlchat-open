# Online mode design (cycle 001, 2026-11-07)

Owner decision: public Nostr relays by default, an iCloud (CloudKit) mailbox as the second carrier.
Goal: in normal times DLChat works like Signal (type, send, it arrives), while the phrase, picture
invite, words, tones, QR and Nearby keep working unchanged when the internet is gone.

Sources: research/similar.md (Nostr primer with NIP links, Bitchat fallback order), research/session.md,
research/simplex.md, research/signal.md.

## 1. The key idea: the carrier never sees a message

Every DLChat message is already a sealed frame (ChaChaPoly under keys from the group phrase, 128-bit
tag for machine transports). Nearby already moves those exact bytes. The online carriers move the same
bytes too, so **no new message cryptography** is needed: a relay or iCloud holds random-looking data
it cannot open. Dedupe, rooms, duress mark, read once and repair all keep working because the frame
is the same.

## 2. Nostr carrier (default)

**Event shape (blends with ordinary private DMs):**
- `kind: 1059` (the NIP-59 gift wrap kind every NIP-17 DM uses), so DLChat traffic looks like normal
  encrypted DMs. https://github.com/nostr-protocol/nips/blob/master/59.md
- `pubkey` and signature: a **fresh throwaway key for every event**, so a relay cannot link two posts
  to one sender (the White Noise / NIP-EE practice).
- `p` tag: the group's **mailbox key for the day**, derived as
  `HMAC-SHA256(groupKey, "DLChat/v1/mailbox " + UTC date)` used as a secp256k1 secret, published as its
  x-only public key. It rotates daily, so a relay cannot follow a group across days by its address.
- `created_at`: randomized up to 2 days back, like NIP-17, so the time of sending blurs.
  https://github.com/nostr-protocol/nips/blob/master/17.md
- `expiration` tag (NIP-40): 14 days, matching Session's message lifetime. Relays may ignore it.
- `content`: base64 of the sealed frame, padded to fixed size buckets so length says less.

**Receiving:** subscribe (`REQ`) on every configured relay for `#p` = today's and the previous two
days' mailbox keys of every group, `since` now minus 3 days. Frames go through the existing
`RelayStore` dedupe and the existing open path.

**Relays:** a default list of 3 well-known public relays, editable in Settings (add your own, like
SimpleX's self-hosted servers). Publish to all, read from all; a relay's `OK` reply means "reached a
relay" (SimpleX's single check). The "got it" reply (exp_got_it_reply) is the second check, sent by a
person rather than a device, so nothing reports reading automatically.

**Code:** `URLSessionWebSocketTask` for NIP-01 (`EVENT`, `REQ`, `CLOSE`, `OK`, `EOSE`); no network
library. Signing needs BIP-340 Schnorr over secp256k1, which Apple's CryptoKit does not offer.
**Dependency for your OK:** one Swift package for secp256k1 Schnorr (e.g. 21-DOT-DEV/swift-secp256k1,
MIT, wraps bitcoin-core's libsecp256k1). License and maintenance to be checked at the moment of adding.
Writing Schnorr by hand is not an option.

## 3. iCloud carrier (second)

CloudKit public database, record type `Frame { mailbox: String, payload: Bytes, expires: Date }`,
same daily mailbox value. Query by mailbox; a `CKQuerySubscription` gives **real push notifications
without a server of ours**, which Nostr cannot (iOS ends sockets in the background). Costs: needs the
iCloud capability (new entitlement), the person signed in to iCloud, and Apple can link posts to an
iCloud account and see timing. Expired records are deleted by the app that reads them and by a
scheduled cleanup; Apple's quotas are free at this scale.

## 4. Which way a message goes (one Send button)

Bitchat's order, adapted: **Nearby** if a phone is in range, then **online** (every enabled carrier) if
there is a network, otherwise the Send screen offers words, tones and QR as today. Each message in
the sender's view shows how it left ("Online, 3 relays took it" / "Nearby, 2 phones" / "Read out").
Offline sends queue and go out when a carrier appears (the Meshtastic request).

## 5. What it protects and what it does not (to go in Settings, plain words)

- Relays and Apple see: that this phone's IP address posted something at roughly some time, its size
  bucket, and a mailbox key that changes daily. Never the text, the group or the phrase.
- Not matched from Session: onion routing. A relay sees your IP address. A VPN or Tor-capable
  network hides it; DLChat will say so rather than imply anonymity.
- No forward secrecy, same as today: anyone with the phrase can read every past message they can
  still fetch (relays keep up to 14 days). Later: per-member keys or MLS (Marmot) would add it, a
  separate design.
- Relays can drop messages; publishing to 3 and the queue covers most of it, the "got it" reply tells
  you for sure.

## 6. Notifications (the biggest complaint theme)

Honest default: with Nostr only, messages arrive while DLChat is open, plus occasional background
refresh (iOS decides when). Real push needs either the iCloud carrier (CloudKit subscriptions) or a
push server of ours (Session's "fast mode"). Recommended: turn on iCloud for push if the person is
signed in; Nostr still carries every message.

## 7. Settings and safety

- Settings > Online: on/off, carriers (Nostr relays list, iCloud), what relays can see.
- First run asks once, in context, before going online (not at launch).
- Wipe and duress: stop all sockets, forget relay settings, delete our iCloud records we can delete.
  Copies already on relays expire on their own (14 days) and cannot be recalled; say so.
- docs/data-inventory.md gains: relay hosts (sealed frames, IP, timing), iCloud (sealed frames,
  iCloud account link, timing). Privacy policy text updated before release.

## 8. Plan (own job after this cycle; rough sizes)

1. DLCore `OnlineEnvelope`: mailbox derivation, event build/serialize/id, padding; test vectors
   (NIP-01 id, NIP-44-sized buckets, mailbox rotation). Half a day.
2. Signing via the approved package; verify incoming event ids and signatures. Couple of hours.
3. `RelayPool`: sockets, subscribe, publish, OK tracking, reconnect with backoff, mock relay in tests.
   A day.
4. Send/receive wiring, carrier order, queue, delivery labels; UI tests with a local mock relay. A day.
5. Settings screen, first-run question, data inventory and privacy text. Half a day.
6. iCloud carrier with push. A day.
7. A real-relay smoke test with synthetic messages, only with your OK at that moment (it posts to
   third-party servers).

## Decisions this needs from you
1. The secp256k1 package (above).
2. Online on by default after the first-run question, or off until turned on.
3. Default relays (proposed: three large public relays; listed for your OK before shipping).
4. Whether iCloud push is offered from the start.
