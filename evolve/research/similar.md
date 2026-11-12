# Apps similar to DLChat (survey, 2026-11-07)

Scope: 8 apps, skipping Signal/Session/SimpleX. Sources are each app's public page plus the Nostr NIP texts.
Gaps: several store listings returned 404 or thin pages. Where a page did not say, this file says "not stated". Learnings are my inferences from what the pages describe, not tested behavior.

## Nostr primer (for DLChat's online mode)

How encrypted Nostr messaging works in practice:

- NIP-44 is the cipher: secp256k1 ECDH, HKDF, ChaCha20, HMAC-SHA256, with padding buckets. It has no forward secrecy and no deniability, and timestamps and IPs stay visible. https://github.com/nostr-protocol/nips/blob/master/44.md
- NIP-59 gives three layers. A rumor is the unsigned message. A seal (kind 13) is the rumor encrypted and signed by the real author. A gift wrap (kind 1059) is the seal encrypted again and signed by a random one-time key. Kind 21059 is an ephemeral variant that relays do not store. https://github.com/nostr-protocol/nips/blob/master/59.md
- NIP-17 builds DMs on those two. A kind 14 chat message is wrapped separately for each recipient and for the sender. Each wrap uses a fresh random keypair, and timestamps are randomized up to 2 days back. Senders publish only to the recipient's kind 10050 DM relay list (keep it to 1-3 relays). A group is just the participant set, and every message is sent once per member, so it suits small groups. https://github.com/nostr-protocol/nips/blob/master/17.md
- NIP-65 (kind 10002) is the general relay list, with read/write markers. Publish to your own write relays and to the read relays of anyone you tag. Keep lists to 2-4 relays per category. https://github.com/nostr-protocol/nips/blob/master/65.md
- NIP-EE is MLS (RFC 9420) over Nostr. KeyPackages are kind 443 and Welcomes are kind 444, gift-wrapped and never signed. Group traffic is kind 445, NIP-44 encrypted with a key from the MLS exporter secret, and every event is signed by a fresh ephemeral key. Kind 10051 lists KeyPackage relays. NIP-EE is now marked "unrecommended" and superseded by the Marmot protocol. https://github.com/nostr-protocol/nips/blob/master/EE.md
- Marmot (the successor spec) lives at https://github.com/marmot-protocol/marmot and is still in development.

Fit with DLChat: the group already shares a secret phrase and has no accounts. Two options:
1. NIP-17-style gift wraps to per-member keys. This needs member pubkeys, which DLChat does not have today.
2. Derive a group key from the phrase, use it to NIP-44-encrypt kind-445-style events, and sign each event with a throwaway key.

Option 2 matches DLChat's no-account model. The cost is that anyone with the phrase can read all history, and there is no forward secrecy.

## 1. Briar
- URL: https://briarproject.org/
- Platforms: Android (Google Play, F-Droid). The site does not mention iOS. The site shows a "maintenance mode" news item dated 2026-07-09 and release 1.5.24 on 2026-10-30.
- Price: free and open source, donations accepted.
- Identity and contacts: not explained on the pages I fetched. The home page says messages are stored on the device and are end-to-end encrypted.
- Transport: Bluetooth, Wi-Fi, or Tor (internet). Messages sync device to device with no server. Briar Mailbox delivers when users are online at different times. https://briarproject.org/how-it-works/
- Learn:
  - Sync over whatever link is present (Bluetooth/Wi-Fi offline, Tor online) rather than one fixed channel. https://briarproject.org/how-it-works/
  - Store-and-forward is an opt-in helper device (Mailbox), not a central server. DLChat's Nostr relays play the same role. https://briarproject.org/how-it-works/
  - Maintenance mode shows that an iOS-first peer-to-peer messenger has a gap to fill. https://briarproject.org/

## 2. Bridgefy
- URL: https://www.bridgefy.me/
- Platforms: iOS 13+ and Android.
- Price: the app is free. SDK pricing is not stated.
- Identity and contacts: no account or phone number. Internet is needed only on first launch. Website accounts are for SDK developers.
- Transport: Bluetooth Low Energy mesh over about 100 m, hopping through other users' phones. A Broadcast section is readable by everyone nearby. Direct chats use the Signal protocol.
- Learn:
  - Label anything in a public or broadcast space as readable by all, so users do not confuse it with private chat. https://www.bridgefy.me/
  - "Internet only on first launch" is a good onboarding line for an offline app. https://www.bridgefy.me/
  - Quote the range as approximate (about 100 m, varies). DLChat could do the same for Nearby. https://www.bridgefy.me/

## 3. Berty (Wesh Network)
- URL: https://berty.tech/ and https://github.com/berty/berty
- Platforms: iOS and Android (README links both stores).
- Price: "Free forever and open-source". The README warns it should not yet be used for sensitive data.
- Identity and contacts: not stated on the pages fetched.
- Transport: BLE plus mDNS when offline, so no internet connection is required. It is peer-to-peer and serverless, with an optional rendez-vous server and OrbitDB-on-IPFS group sync. The site calls it an asynchronous mesh protocol.
- Learn:
  - Pair a proximity transport (BLE/mDNS) with an optional discovery server, and say plainly what the server can see. https://github.com/berty/berty
  - Put the "not yet for sensitive data" caveat in the README. DLChat's honesty page can state its own limits the same way. https://github.com/berty/berty

## 4. Meshtastic (iOS/macOS app)
- URL: https://meshtastic.org/docs/overview/ and https://meshtastic.org/docs/software/apple/
- Platforms: iOS, iPadOS, macOS, watchOS, visionOS app (docs v2.8). It needs a separate LoRa radio paired over Bluetooth, Wi-Fi, Ethernet or serial.
- Price: not stated on the pages fetched. There is a donate link.
- Identity and contacts: no accounts. Nodes share a named channel plus a key. Channel 0 uses the default key AQ==, and a node can hold up to 8 channels.
- Transport: LoRa mesh with nodes relaying packets, no internet. Nodes must share a modem preset.
- Delivery state: if a message asks for an acknowledgement and none arrives, it is retransmitted up to 3 times total for broadcasts and 5 for direct messages. The retry interval depends on airtime and traffic. https://meshtastic.org/docs/overview/
- Learn:
  - Opt-in acks with a bounded retry count (3 and 5) is a clear model for "sent, retried, failed". It maps to DLChat's radio and audio paths. https://meshtastic.org/docs/overview/
  - Channel = name + key is close to DLChat's group phrase. Warn the user that the default key is public. https://meshtastic.org/docs/overview/
  - Retry timing depends on airtime. DLChat's spoken-word and audio-tone transports could do the same. https://meshtastic.org/docs/overview/

## 5. Threema
- URL: https://threema.com/en
- Platforms: not named on the page fetched.
- Price: no price on the page fetched. A pricing page exists, plus a 30-day Threema Work trial.
- Identity and contacts: no phone number or email required. A unique Threema ID is the identity. How contacts are verified is not stated on the page fetched.
- Transport: internet only, through Swiss servers. Messages are removed from the servers after delivery, and contact lists stay on the device. https://threema.com/en
- Learn:
  - "Deleted from the server after delivery" is one line that could go in DLChat's relay explainer. https://threema.com/en
  - An ID instead of a phone number is the closest mainstream model to DLChat's no-accounts promise. https://threema.com/en
  - I could not read Threema's verification-level pages (404s), so check those directly before copying the pattern.

## 6. 0xchat
- URL: https://github.com/0xchat-app/0xchat-app-main (site https://0xchat.com/ was a stub)
- Platforms: Android, iOS, macOS, Linux, Windows (Flutter).
- Price: not stated. MIT-licensed.
- Identity and contacts: the Nostr keypair is the identity. Details are not stated in the README.
- Transport: Nostr relays. The README mentions chat, calling, discovery, user-center and Cashu wallet modules. It does not list NIP-17, groups or Bluetooth, so I cannot confirm those from the pages fetched.
- Learn:
  - Nostr relays are heavily spammed, so the project recommends self-hosted media. DLChat's online mode should plan for relay spam and keep payloads text-only. https://github.com/0xchat-app/0xchat-app-main
  - A modular split (chat, calling, discovery) is a reference for scoping. https://github.com/0xchat-app/0xchat-app-main

## 7. White Noise (Marmot protocol)
- URL: https://github.com/marmot-protocol/whitenoise (spec https://github.com/marmot-protocol/marmot)
- Platforms: Flutter app on a Rust core. Android is the clearest; iOS was reported as supported or in beta, and other desktop platforms as planned. Sources conflict.
- Price: not stated. It is open source.
- Identity and contacts: Nostr identity. Release v0.3.0 added external signers (Amber, NIP-55). https://newreleases.io/project/github/marmot-protocol/whitenoise/release/v0.3.0
- Transport: MLS group messaging over Nostr relays. Relays see ciphertext only. A v2 direction decouples Nostr identity from the transport layer, per talk coverage found via search.
- Learn:
  - MLS gives forward secrecy and post-compromise security, which a shared phrase plus NIP-44 does not. https://github.com/nostr-protocol/nips/blob/master/EE.md
  - Fresh ephemeral sender key per event hides who is posting from relays. https://github.com/nostr-protocol/nips/blob/master/EE.md
  - External-signer support keeps the key out of the app. DLChat has no keys to protect, but it could keep any Nostr key in the Keychain. https://newreleases.io/project/github/marmot-protocol/whitenoise/release/v0.3.0

## 8. Bitchat
- URL: https://github.com/permissionlesstech/bitchat
- Platforms: iOS and macOS native, Android via Play Store.
- Price: not stated on the page (links to store listings).
- Identity and contacts: no phone number or account. The mesh uses a persistent per-device identifier derived from your identity key.
- Transport: Bluetooth mesh up to 7 hops with automatic discovery. When Bluetooth is not available, DMs go over Nostr relays to the recipient's public key, with a BitChat-only encryption format (not NIP-17). Bluetooth is preferred; if neither works, messages are queued and sent when a connection appears.
- Delivery state: described as queue-and-send-on-connect. Receipts and "delivered" marks are not described on the page.
- Learn:
  - A transport-preference order (Bluetooth first, Nostr second, queue last) is the model for DLChat's fallback between Nearby and online. https://github.com/permissionlesstech/bitchat
  - Queue-then-auto-send means the user never re-sends by hand. https://github.com/permissionlesstech/bitchat
  - The persistent device identifier is a privacy tradeoff to avoid; DLChat's duress and panic wipe argue against it. https://github.com/permissionlesstech/bitchat

## Also seen: goTenna
- URL: https://gotenna.com/ (consumer Mesh product pages redirect here, and the products are moving to forterra.com).
- Pro line only: radios plus a Pro App with end-to-end PKI encryption, group messaging, location and mapping. No price is shown. Not counted in the 8 because it is now a professional product.
- Learn: radios, groups and map are bundled for teams, so DLChat's radio mode is a lighter alternative for small groups. https://gotenna.com/

## Cross-cutting findings

Delivery state and fallback, from what the pages actually say:
- Meshtastic is the only source that gives numbers: opt-in ack, 3 retries (broadcast), 5 (direct). https://meshtastic.org/docs/overview/
- Bitchat orders its transports (Bluetooth, then Nostr, then queue). https://github.com/permissionlesstech/bitchat
- Briar syncs over whichever link is available and uses Mailbox when peers are never online together. https://briarproject.org/how-it-works/
- No page showed per-message state wording (sent, delivered, failed). A sensible set for DLChat is: queued, sent on transport X, acked, failed after N tries.

Suggested DLChat behaviors (inferences):
1. Show which transport carried each message, plus a queued state when none is available.
2. Retry with a bounded count, and surface "failed after N tries" with a manual Resend.
3. In online mode, use ephemeral per-event signing keys and a small relay list (2-4, or 1-3 for DMs).
4. Randomize event timestamps like NIP-17 (up to 2 days back). It costs little.
5. Say plainly what relays and anyone with the phrase can see.

## Comparison

| App | Platforms | Price (public) | Identity | Transport | Offline | Store-and-forward |
|---|---|---|---|---|---|---|
| DLChat | iOS | n/a | shared phrase, no accounts | radio words, audio, QR, Nearby, picture invite; Nostr planned | yes | relays (planned) |
| Briar | Android | free | not stated | BT, Wi-Fi, Tor | yes | Mailbox |
| Bridgefy | iOS, Android | free app | none | BLE mesh | yes | not stated |
| Berty | iOS, Android | free | not stated | BLE, mDNS, IPFS | yes | optional servers |
| Meshtastic | iOS, Android (radio needed) | not stated | channel name + key | LoRa mesh | yes | not stated |
| Threema | not named | not stated | Threema ID | internet | no | server queue |
| 0xchat | mobile + desktop | not stated | Nostr key | Nostr relays | no | relays |
| White Noise | Android, iOS (conflicting) | not stated | Nostr key | MLS on Nostr | no | relays |
| Bitchat | iOS, macOS, Android | not stated | device key, no account | BT mesh, Nostr fallback | yes | queue |
