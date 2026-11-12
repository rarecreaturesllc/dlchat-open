# Internet Messages and the Chat drawer

Owner request 2026-11-09: a universal Chat drawer, and one-to-one "Internet Messages" with anyone who
has DLChat, stronger on privacy than Signal. Build both route A (public Nostr relays) and route B
(DLChat's own onion relays); build 16 ships only with both. Full option comparison: the "Internet
Messages and the universal chat drawer" design doc in the project.

## Chat drawer

Chat opens on a list of every conversation in four sections, each with a privacy label:
DL Group Chats, Internet Messages, Meshtastic Public, Meshtastic Nodes. Tapping a row opens that chat
under a "Chats" back bar. Chat remembers the open conversation across tabs; tapping the Chat tab again
returns to the drawer. Sections collapse (remembered in UserDefaults, no content).

## Protocol (DLCore `Direct*`)

- **Invite** `dlchat://contact#<base64url>`: magic `DLC1`, X25519 identity (32), ML-KEM-768 public key
  (1184), random secret (32), route flag, optional onion queue (relay URL, send id), name. One use,
  24 hours. A fresh identity per contact, so contacts cannot link two people's chats to one phone.
- **Short invite link** (build 17) `dlchat://contact#<base64url(0x01 + invite secret)>`, about 60
  characters instead of about 1,700 (the ML-KEM key is random and does not compress). When the invite's
  route uses public relays, the inviter seals the full invite (outer seal, 4 KB bucket) with
  `HKDF(secret, "invite-link-seal")` and posts it as a kind-1059 gift wrap through Tor to a daily
  mailbox from `HKDF(secret, "invite-link-mailbox")`, expiring with the invite. The accepter fetches it,
  opens it, checks it holds the same secret, then accepts the full invite as before: same keys, same
  post-quantum first step. The share sheet sends the short link once a relay took the sealed invite,
  else the full one. The QR code keeps the full invite, so accepting in person needs no fetch.
  A private-relays-only invite keeps the full link (posting it would touch public relays). Full links
  still open.
- **Handshake**: the accepter makes its own identity, `SK = HKDF(X25519(idB, idA), salt: invite secret)`,
  and starts the ratchet as initiator with a KEM encapsulation to the invite's ML-KEM key. Its first
  message (a hello carrying its identity, route, queue and name) is sealed with a key from the invite
  secret and sent to the invite's mailbox/queue. Both phones then show 6 safety words from both identities (3 until build 17; the first three are unchanged).
- **Ratchet**: Signal's Double Ratchet (X25519, HKDF-SHA256, HMAC chains, ChaCha20-Poly1305, header as
  AD, up to 1000 skipped keys). Post-quantum step: every new sending chain also encapsulates an ML-KEM-768
  secret to the peer's newest KEM key and mixes it into the root KDF with the DH output; every message
  carries the sender's newest KEM key and its chain's ciphertext (~2.3 KB). Four old KEM keys are kept.
  State changes only when a message opens. CryptoKit ML-KEM needs iOS 26 / macOS 26; older systems get
  `needsNewerSystem` rather than a classical-only fallback.
- **Outer seal**: per contact, ChaCha20-Poly1305 with a fixed key from the contact secret, padded to
  4, 8 or 16 KB. Max text 4000 bytes.
- **Route A (public relays)**: a NIP-59-style kind-1059 event from a throwaway key, blurred time, to a
  mailbox that changes daily and differs per contact and direction (HMAC of the day under a per-direction
  root). One relay pool per contact (own sockets and Tor circuit).
- **Route B (private relays)**: `relay/` (Go standard library). One-way queues: the reader creates a
  queue with an Ed25519 key, gets a receive id and a send id, gives the send id to one contact.
  Reads, acknowledgements and deletes are signed. Relays run only as onion services; clients long-poll
  through Tor, one Tor isolation per queue.
- **Routes**: each person picks how messages reach them (private, public, both). Default: public
  relays (owner decision 2026-11-09) until a DLChat relay runs; the owner plans one on a home computer. A sender always uses
  the receiver's pick. Private without a reachable relay falls back to public for that contact. The
  same envelope sent by two routes is one message (fingerprint).
- **No push**: messages arrive while DLChat is open (owner decision: nothing that tells Apple about
  messages). Disappearing messages: 7 days by default.

## Not done yet

- DLChat's relays are not deployed: `DirectModel.defaultPrivateRelays` is empty until the owner sets up
  two servers (`relay/deploy/setup.sh`) and the onion addresses are added.
- No queue rotation, no small groups (MLS), no background fetch.
- Independent cryptographic review before any "stronger than Signal" claim (launch blocker).
