# SimpleX Chat: competitor research for DLChat

Researched 2026-11-07. Sources are public pages (fetched via a summarizing tool, so
wording is paraphrase except the quotes in section 5). Page content treated as data.

## 1. What it is

- Privacy messenger billed as "the only messaging network without any user identifiers"
  (https://simplex.chat). No user IDs, not even random ones; contacts and groups live
  on-device only.
- Platforms: iOS (App Store + TestFlight beta), Android (Google Play, F-Droid), desktop
  (Linux, macOS, Windows), terminal CLI, TypeScript SDK, bots API (https://simplex.chat).
  Mobile profiles can link to desktop, but only on the same network; true multi-device for
  one profile is called "a complex and unsolved problem" (https://simplex.chat/faq/).
- Funding/pricing: app is free, no consumer prices. FAQ says SimpleX Chat Ltd is funded by
  private investors, VC and donations; business model "work in progress", planned
  freemium (https://simplex.chat/faq/). Homepage now mentions equity crowdfunding on
  Wefunder and big communities paying for their own servers (https://simplex.chat).
  Security audits by Trail of Bits, 2022 and 2024 (https://simplex.chat).
- Identity (https://simplex.chat/docs/guide/making-connections.html):
  - One-time invitation link: single-use, carries no profile, both sides know who they
    connect to, initial request uses the double ratchet. Anyone who intercepts it before use
    can connect.
  - Contact address: reusable (social media, signature). Only the requester knows who they
    reach; owner has no proof of identity; request is E2E encrypted but without the
    ratchet until accepted; spam-prone. Used only for the first request; deleting it keeps
    existing contacts.
  - QR shown in person or on a video call (scan on mobile, paste on desktop). Compare
    security code (SHA256 of both public keys) to detect link substitution.

## 2. How messages travel

- SMP relays ("routers"): independent, anyone-can-run servers that accept, buffer and
  deliver fixed-size packets. Clients talk only to routers, never to each other
  (https://github.com/simplex-chat/simplexmq/blob/stable/protocol/overview-tjr.md).
- Unidirectional queues: each queue is one-way, created by the recipient, with separate
  send/receive credentials. A conversation = two queues; each contact gets its own set.
  Queues and servers can be rotated without losing the contact (same overview doc).
- Private message routing (two-hop): sender's router proxies to the recipient's router.
  Proxy sees sender IP not recipient; destination sees recipient IP not sender. Per-message
  random IDs/keys and extra E2E layer prevent correlation (same doc). On by default,
  Advanced network settings (https://simplex.chat/docs/guide/privacy-security.html).
- Offline recipient: relay holds the packet until fetched. Default server config expires
  undelivered messages after 21 days (`expire_messages_days: 21`) and notification
  records after 24 h (https://simplex.chat/docs/server.html). Overview doc says routers
  keep data mostly in memory, no access logs, delete on request.
- Self-hosting: VPS + domain, install script (Ubuntu), Docker or Linode; optional Tor
  onion address, info page, control port, CSV stats (https://simplex.chat/docs/server.html).
  Self-hosting gives control but weaker metadata protection vs a passive observer (overview doc).
- Presets vs custom: apps ship three preset servers (smp11/12/14.simplex.im). Custom
  servers can be added next to or instead of presets, with optional password and a QR to
  share. Changing servers only affects NEW contacts; existing ones move via "Change
  receiving address" on the contact/member info page (server.html).
- XFTP: separate scheme for large files, each fixed-size chunk with its own address and
  credentials (overview doc). FAQ: files can be received for 2 days after sending.
- Transport isolation (beta): separate connection per profile (default) or per contact;
  "Protect IP address" on by default; Tor via SOCKS/Orbot (privacy-security page).
- Notifications use a push server: iOS bolt icon should be green; status at
  status.simplex.chat (https://simplex.chat/faq/).

## 3. Features and behaviors DLChat could learn from

- Incognito per connection: random name generated for each new contact/group; last choice
  remembered. Profile > Share profile > Incognito, or picked before "Connect"
  (https://simplex.chat/docs/guide/chat-profiles.html). DLChat: random callsign per group.
- Multiple chat profiles, all receiving at once; switch from profile picture; "Your chat
  profiles" > Add profile (chat-profiles page).
- Hidden profiles: swipe right (iOS) on a profile > Hide, set "Password to show"; reveal by
  typing the full password into the "Your chat profiles" search bar (chat-profiles page).
  Strong fit for DLChat's duress mark / hidden groups.
- One-time link or QR connect: "Open new chat" > "Connect"; "Your profile" row shows which
  identity you will use; can include a message with address requests (making-connections page).
- Security code verification: contact name > "Verify security code"; scan the QR, tap
  "mark verified", or read aloud over a call; same for group members
  (https://simplex.chat/docs/guide/privacy-security.html). Read-aloud fits DLChat's voice use.
- Self-destruct passcode: I believe SimpleX Lock has one, but I could NOT confirm it in the
  docs pages fetched (guide index, privacy-security, managing-data do not mention it).
  Treat as unverified; check the app's Privacy & security settings before citing.
- Database passphrase and export: Chat data > "Database passphrase & export". Random
  passphrase in Keychain by default; user must set their own to export; turning off
  "Save passphrase in Keychain" means asking at every launch and limited notifications;
  lost passphrase is unrecoverable; import replaces the current DB; export stops chat until
  "Run chat" is toggled (https://simplex.chat/docs/guide/managing-data.html).
- Disappearing messages: contact name > Contact preferences > Disappearing messages > "Delete
  after"; sender timer starts at send, recipient's at read; in groups only the owner can
  enable; single message via long-press on Send > "Disappearing message"
  (https://simplex.chat/docs/guide/send-messages.html).
- Timed local deletion: Chat data > "Delete messages after", per profile with per-chat
  override; local only, does not delete for others (managing-data page).
- Live messages: lightning button in the composer, partial text sent every few seconds,
  checkmark to finish (send-messages page). Good analogue to live radio reading.
- Delivery receipts: one check = reached relay, two = reached recipient device; can be
  disabled per contact or globally; read receipts deliberately not planned
  (https://simplex.chat/faq/). Maps well to DLChat's sent/heard states.
- Local-only notes: forward any message to "Private notes" (send-messages page).
- Delete for everyone: both sides must enable; works within 24 h; otherwise a "deleted
  message" placeholder the recipient can reveal (faq).
- Network/server UI: server settings expose address+password, enable/disable presets,
  share via QR; transport isolation and private routing toggles live under Advanced network
  settings (server.html, privacy-security page). No public per-user "server status screen" is
  documented beyond status.simplex.chat for push. A "Your servers" screen with a per-relay
  green/red state is a gap DLChat's Nostr relay list could fill.
- Operator info block: servers can publish name, location, hosting, contacts, conditions
  (server.html). Good model for showing who runs a relay.
- Swipe actions on profiles (hide/mute) and long-press menus are used throughout (chat-profiles page).

## 4. Known weaknesses and criticisms

- Battery on Android: instant mode keeps a background service always active and was
  reported to drain more than Signal/Threema/Element; periodic mode saves battery but
  delays calls (https://discuss.privacyguides.net/t/hows-simplex/16593?page=2 and
  https://lemmy.nekusoul.de/post/464900, as surfaced in search). FAQ itself says Android
  needs "Unrestricted" battery and Tor adds drain (https://simplex.chat/faq/).
- Notifications: iOS push needs a status-bolt check and sometimes toggling Off/Local then
  back on (faq). UnifiedPush requested in
  https://github.com/simplex-chat/simplex-chat/issues/1081 (via Privacy Guides thread).
- Onboarding: non-technical friends needed help to configure and send a connection link
  (https://stacker.news/items/225727, per search summary; page text itself did not load).
  Signal's contact adding is described as easier (Privacy Guides thread above).
- Concept load: profiles vs incognito vs one-time links vs addresses; group contact
  verification unclear (Lemmy thread via search, https://lemmy.nekusoul.de/post/27994).
- No true multi-device; desktop link needs same network (faq). No web client, no
  built-in stickers cited as adoption blockers (search summary).
- Changing servers affects only new contacts; existing contacts need manual per-contact
  address change (server.html).
- Metadata honesty: relays are trusted somewhat; targeted attacks not fully prevented
  (overview doc). Self-hosting alone leaves a passive observer able to see more.
- Single-use links can be intercepted before use; contact addresses attract spam
  (making-connections page).

## 5. Verbatim quotes (all from one public thread, Privacy Guides forum)

Source: https://discuss.privacyguides.net/t/hows-simplex/16593?page=2 and ?page=3.
Text returned by a fetch tool and not re-checked against the raw page; verify before
publishing. No Reddit/HN/App Store pages were retrieved, so none are included.

1. "I have noticed significant battery consumption even though I don’t use the app often."
   (M-A9NPV, 2024-09-26) https://discuss.privacyguides.net/t/hows-simplex/16593?page=2
2. "My tests with AccuBattery showed that the phone cannot enter into deep sleep when simplex is in instant mode."
   (yipii, 2024-09-26) https://discuss.privacyguides.net/t/hows-simplex/16593?page=2
3. "I find SimpleX too hard to use for my nontechnical associates."
   (camp, 2024-09-24) https://discuss.privacyguides.net/t/hows-simplex/16593?page=2
4. "Currently, you need to use periodic pool, which kind of prevent calls from working."
   (yipii, 2024-09-25) https://discuss.privacyguides.net/t/hows-simplex/16593?page=2
5. "SimpleX do things differently, and can properly explain why, and that makes it interesting."
   (yipii, 2024-10-06) https://discuss.privacyguides.net/t/hows-simplex/16593?page=3

## 6. Takeaways for DLChat

- Copy: hidden-profile-by-password search-bar reveal, per-connection random names,
  read-aloud security code, delivery two-check semantics, per-chat disappearing timer with
  clear "timer starts at read", local private notes, explicit DB passphrase and export wording.
- Avoid: instant-vs-periodic battery trade-off exposed as a user choice; four overlapping
  identity concepts; server changes that silently apply only to new contacts.
- Online-mode lesson: show relay list with status and operator info; make relay swap affect
  existing groups, since the phrase (not the server) is the identity.
