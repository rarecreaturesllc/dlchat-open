# Session (getsession.org) competitor research for DLChat

Researched 2026-11-07. Sources are public pages; content treated as data. Items marked (unverified) were not confirmed on a fetched page.

## 1. What Session is

- Privacy messenger run by the Session Technology Foundation (Swiss). Android, iOS, Desktop; beta via Play Store, TestFlight, GitHub; F-Droid repo. https://getsession.org/faq
- Free: "Session will always remain free to use"; a future paid tier, Session Pro, may exist. https://getsession.org/faq , https://docs.getsession.org/readme/advanced-features/session-pro.md
- Identity: no phone number or email. The app generates an Account ID on-device; display name is optional; optional permanent Session Names attach to an Account ID. https://getsession.org/faq , https://docs.getsession.org/session-network/session-protocol/account-ids-and-self-managed-keys.md
- Recovery password: the mnemonic seed form of the long-term private key, shown at account creation. No server can reset it. Contacts keep messaging the same Account ID after a restore. https://docs.getsession.org/session-network/session-protocol/account-restoration.md
- Restore limits (FAQ): messages from the last 14 days come back; contacts and groups come from a config message that expires after 30 days, so they are lost if no device synced in that window. https://getsession.org/faq
- Network: 1,500+ Session Nodes in 50+ countries, proof-of-stake with a crypto token (SESH), over 1,000,000 users claimed. https://docs.getsession.org/session-network.md

## 2. How messages travel

- Swarms: small groups of Session Nodes (FAQ says 5 to 7) responsible for a range of Account IDs. Messages are replicated across the swarm so one offline node loses nothing. https://docs.getsession.org/session-network/session-nodes/swarms.md , https://getsession.org/faq
- Send path: client finds the recipient's swarm from their Account ID, builds a message with recipient ID, timestamp, expiry time and storage namespace, and sends it by onion request to a random swarm node. That node forwards it to the rest of the swarm; each stores it until expiry. https://docs.getsession.org/session-network/session-protocol/onion-requests-and-message-routing.md
- Onion requests: layered encryption over TCP, each layer peeled by a different node, so no node knows both sender IP and content/recipient. Hop count not stated in the docs. Slower than other transports, unsuited to large transfers or real-time voice/video. Same URL as above.
- TTL: chat messages expire after two weeks by default; Disappearing Messages changes it. Same URL as above.
- Offline delivery: recipient polls its swarm when online and collects whatever has not expired. Docs do not describe this in detail (polling inferred from the FAQ's "slow mode polls the swarm"). https://getsession.org/faq
- Groups: end-to-end encrypted, up to 100 members, stored on the swarm network. https://getsession.org/faq
- Communities: public, self-hosted servers (SOGS) for hundreds or thousands of users. Messages live on that server, not the network, and are encrypted in transit to the server only, not end to end. https://docs.getsession.org/readme/advanced-features/communities.md , https://getsession.org/faq
- Attachments: up to 10 MB, encrypted on-device; the key travels inside the encrypted message; a File Server stores the ciphertext and cannot read it. EXIF stripped only for non-video files sent from Desktop. https://getsession.org/faq
- Push: two modes. Slow mode polls the swarm in the background (no Google/Apple involvement). Fast mode uses FCM/APNs, exposing IP and push token to Google/Apple; registration with the Foundation push server goes through onion requests. https://getsession.org/faq

## 3. Features and behaviors DLChat could learn from

Verified on a fetched page:
- Recovery password shown once at creation, "never share" warning, word order matters, no server reset. DLChat: show the phrase at creation, with an explicit "no reset exists" line. https://docs.getsession.org/session-network/session-protocol/account-restoration.md
- Honest restore limits stated up front (14 days messages, 30 days config). DLChat should state its own relay retention the same way. https://getsession.org/faq
- Message requests: a message from someone not in your contacts, or a deleted contact, lands in a requests inbox; the sender is not told. Fits unknown-sender handling on Nostr/iCloud carriers. https://getsession.org/faq
- Disappearing messages in two modes, "after Send" and "after Read" (read timer starts when the recipient reads); deletion covers both devices and the network copy. Maps to DLChat retention settings plus relay deletion. https://getsession.org/faq
- Per-message expiry carried inside the message and enforced by storage nodes (expiry timestamp in the envelope). Good model for relay events (Nostr NIP-40 expiration tag, my suggestion, not from Session). https://docs.getsession.org/session-network/session-protocol/onion-requests-and-message-routing.md
- Two notification modes with the privacy tradeoff explained in plain language (fast via Apple/Google vs slow via polling). DLChat can ship polling-by-default and an opt-in push mode. https://getsession.org/faq
- Calls limited to contacts, files encrypted client-side with key in the message. https://getsession.org/faq
- Read receipts and disappearing messages are user-configurable privacy settings. https://docs.getsession.org/readme.md
- Planned V2: linked devices see "new device linked" and can remove devices remotely; maybe approval before linking. https://www.privacyguides.org/news/2025/12/03/session-messenger-adds-pfs-pqe-and-other-improvements/

Not confirmed from fetched pages (check the Session help center https://sessionapp.zendesk.com/hc/en-us before copying): Account ID QR code, screenshot notifications, typing-indicator toggle, link previews off by default, app lock, notification-content privacy options, blocked contacts, note to self, current multi-device behavior (FAQ says deleting a contact applies across synced devices). I did not fetch the Zendesk pages.

## 4. Weaknesses and criticisms

- No perfect forward secrecy: removed in 2021 citing stability problems with the decentralized design; Privacy Guides does not recommend Session largely for this. FAQ: "not currently implemented", planned in Protocol V2. https://www.privacyguides.org/news/2025/12/03/session-messenger-adds-pfs-pqe-and-other-improvements/ , https://getsession.org/faq
- V2 (announced Dec 2025): rotating per-device keys for PFS plus ML-KEM post-quantum encryption; not finalized, details promised for 2026. https://www.privacyguides.org/news/2025/12/03/session-messenger-adds-pfs-pqe-and-other-improvements/ . I did not check whether it has shipped.
- Questions about how decentralized it is, and dependence on its own cryptocurrency (same Privacy Guides article).
- Cryptography claims disputed in public (Jan 2025 Hacker News thread, where a Session developer posted a rebuttal): https://news.ycombinator.com/item?id=42734505
- Notification delays and missed notifications in slow mode: Google Play reviewers report messages arriving 10-15 minutes late and no notifications unless the app is open; the Foundation's advice is to switch to Fast mode. Seen via search summary of https://getsession.org/android and review aggregators (https://grand-screen.com/apps/session-private-messenger/reviews/); GrapheneOS thread https://discuss.grapheneos.org/d/14422-session-messenger-slow-mode-notifications-not-working (page content did not load for me, title only).
- Communities are not end-to-end encrypted (see section 2).
- Account recovery depends fully on the phrase; group and contact data are lost after 30 days without a sync.
- Onion routing over TCP is slow and unsuited to big files or live audio/video.

## 5. User quotes (verbatim, as returned from the pages; short excerpts)

1. "Session breaks post-compromise security, forward secrecy and repudiation." jerm, 2024-06-21. https://discuss.privacyguides.net/t/remove-session-from-instant-messaging/18852?page=2
2. "The fact that they first had forwarded secrecy and then just removed it is beyond me and unacceptable." ph00lt0, 2024-06-17. Same URL.
3. "Session is the one holding it back from being a requirement quite frankly." fria, 2025-03-10. Same URL (context: Privacy Guides IM criteria).
4. "I like the ideas behind the Session[0] messenger: create an account with no authentication" tasuki, 2025-05-21. https://news.ycombinator.com/item?id=44055689 (opening of the comment; it may continue)
5. "I find https://getsession.org/ and it's Tor-like routing of messages quite interesting." Jigsy, 2025-11-13. https://news.ycombinator.com/item?id=45917789
6. "I noticed that more are using Session now and not Signal (no phone number or email required)" TheqO, 2026-08-29. https://news.ycombinator.com/item?id=49488235 (opening of the comment; it may continue)

Quotes 4 and 6 were returned as truncated excerpts by the fetch tool. No Reddit or App Store review text could be verified (Reddit blocked, store pages not fetched), so none are included.

## 6. Takeaways for DLChat (my reading, not Session's)

- Session's core trade, anonymous key-derived identity plus store-and-forward nodes with a default 14-day expiry, maps directly to "seed phrase plus Nostr relays". The per-message expiry timestamp is the piece to copy.
- Its biggest public criticism is no forward secrecy. DLChat's phrase-derived group key has the same exposure; consider key rotation or an honest note in settings.
- Its biggest user pain is notification latency. Plan for polling delay and say so in the UI, as Session's two-mode explanation does.
