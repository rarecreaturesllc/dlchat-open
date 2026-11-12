# Signal research (for DLChat)

Researched 2026-11-07. Notes: support.signal.org returned HTTP 403 to direct fetch, so support-article facts come from search-result excerpts of those exact URLs (not full page reads). signal.org home was read directly. Items marked (unverified) were not confirmed on an official page.

## 1. What Signal is
- Free messaging app from an independent nonprofit; end-to-end encrypted text, voice messages, photos, video, GIFs, files, stickers, group chats, voice/video calls, no ads or trackers. Source: https://signal.org
- Platforms: Android, iPhone and iPad, Windows, Mac, Linux. Source: https://signal.org
- Pricing: free; funded by grants and donations (donate page linked from home). Source: https://signal.org
- Identity: registration requires a phone number verified by SMS code. Optional usernames (launched Feb 2024) let people start chats without seeing your number; you can share a username, a QR code or a link, and reset the QR/link without changing the username. Number visibility setting is all-or-nothing (Settings > Privacy > Phone Number). Signal still needs a number to sign up. Sources: https://support.signal.org/hc/en-us/articles/6829998083994 , https://signal.org/blog/phone-number-privacy-usernames/ , https://mjtsai.com/blog/2024/02/21/signal-usernames (quotes Signal blog: "you will still need a phone number to sign up for Signal").
- Recent: Android phones/tablets can now be linked devices (Android 8.20, Aug 2026). https://signal.org/blog/linked-devices-and-android-tablets/

## 2. Features DLChat could learn from
Safety numbers / verification
- Each 1:1 chat has a unique safety number to verify that chat; compare in person or over another channel; it verifies the channel, not identity. A change usually means new device/reinstall. Why: DLChat could show a per-group "fingerprint" derived from the phrase so members can confirm they hold the same phrase. https://support.signal.org/hc/en-us/articles/360007060632
- Safety-number change notices were reworked so verified status is less noisy. Why: avoid alert fatigue on key changes. https://signal.org/blog/verified-safety-number-updates/

Disappearing messages
- Timer removes messages on both devices; anyone in the chat can change it; syncs across linked devices; a default timer can be set for new chats. Why: maps to DLChat retention settings; a default-for-new-groups is cheap to copy. https://support.signal.org/hc/en-us/articles/360007320771-Set-and-manage-disappearing-messages , https://signal.org/blog/disappearing-by-default/ , https://signal.org/blog/disappearing-messages/

Note to Self
- A chat with yourself, usable as a cross-device clipboard, with disappearing messages (timer starts at once). Why: a private scratchpad for storing phrases/frequencies in DLChat without a group. https://support.signal.org/hc/articles/360043272451

Screen security / incognito keyboard / screen lock
- Screen Lock requires device PIN/biometrics to open the app, separate from the Signal PIN; Android can lock manually from the notification tray. Why: DLChat has a PIN lock; quick "lock now" is worth matching. https://support.signal.org/hc/articles/360007059572
- Incognito Keyboard asks the OS to skip keyboard learning; page admits keyboards may ignore the flag. Why: honest wording about best-effort; on iOS, DLChat can set secure/no-autocorrect traits. https://support.signal.org/hc/articles/360055276112-Incognito-Keyboard
- Screen Security hides app content in the app switcher / blocks screenshots (third-party description only, no official page found). (unverified) https://freedom.press/training/locking-down-signal/

Registration lock / PIN
- Signal PIN is separate from the SMS code and the screen lock; Registration Lock makes re-registering a number need the PIN; forgotten PIN may lock you out up to 7 days; lock expires after 7 days of inactivity (per search excerpt); Support never asks for your PIN. Why: in DLChat, the equivalent is a recovery story for a forgotten PIN versus panic wipe, and scam-proof wording. https://support.signal.org/hc/en-us/articles/360007059792 , https://support.signal.org/hc/en-us/articles/5440120029082-Re-registering-using-your-Signal-PIN

Linked devices
- Up to 5 linked devices; they unlink if the primary phone is offline 30 days; on link you can sync chats and the last 45 days of media; link is by QR scan. Why: DLChat could add an iPad via QR/Nearby with the same phrase. https://support.signal.org/hc/articles/360007320551 , https://signal.org/blog/a-synchronized-start-for-linked-devices/

Groups and admin
- Group links with optional admin approval; link can be reset or turned off; permission "Add Members" can be limited to admins. Why: DLChat groups are phrase-gated; an admin concept (who may rotate the phrase) is the gap. https://support.signal.org/hc/articles/360007319331-Group-chats , https://support.signal.org/hc/articles/360051086971 , https://signal.org/blog/group-links/

Stories
- Stories (24h posts) with audience set by "All Except" or "Only Share With"; can be turned off in Settings. Why: low priority; the opt-out and per-audience selection pattern is the lesson. https://support.signal.org/hc/en-us/articles/5008009166234-Stories

Message requests
- Messages from non-contacts land as a request: block, delete or accept, with name/photo shown. Why: needed once DLChat has an online Nostr mode and strangers can reach you. https://support.signal.org/hc/articles/360007459591

Sealed sender
- Hides the sender's identity from the server by putting the sender certificate inside the encrypted envelope; on by default; delivery token limits abuse. Why: directly relevant to Nostr relays (relays see metadata); a sealed-style wrapper (like NIP-17 gift wraps) is the equivalent. https://signal.org/blog/sealed-sender/

Backups / transfer
- Secure Backups (end-to-end encrypted, recovery key, restore without the old phone) and direct phone-to-phone transfer by QR; warns that an interrupted transfer may lose history, so enable backups first; iOS added local encrypted backups and a Wi-Fi Aware transfer in Sep 2026. Why: DLChat has no server, so a phrase/recovery-key export and a Nearby device-to-device transfer fit its model. https://support.signal.org/hc/en-us/articles/10074659364122-Backups-and-Device-Transfers-on-Signal , https://www.helpnetsecurity.com/2026/09/30/signal-encrypted-backups-ios-8-30/

Notifications privacy
- Notification content choices: name, content and actions; name only; no name or content. Why: DLChat should default to "no name or content" and mention that iOS notification data can persist (HN thread on FBI recovering deleted Signal messages from iPhone notification data, Apr 2026). https://support.signal.org/hc/en-us/articles/360043273491-Notification-Options , https://news.ycombinator.com/item?id=47716490

View-once media
- Sender picks view-once before sending; sender keeps no copy; receiver's copy is removed on open, on timer, or after 45 days. Why: matches a "read once then burn" picture-invite or message mode. https://support.signal.org/hc/articles/360038443071

Reactions / replies
- Not read on an official page in this pass. (unverified, skipped)

Username links and QR
- Username, QR code, or a link that does not contain the username text; resettable without changing the username. Why: DLChat could share a rotating invite QR that can be revoked. https://support.signal.org/hc/en-us/articles/6829998083994 , https://signal.org/blog/phone-number-privacy-usernames/

Call features
- Call links: shareable links to start a group call without the participants being contacts. Why: a link/QR-started session echoes DLChat's QR invite. https://support.signal.org/hc/en-us/articles/7860719423002-How-to-create-and-share-call-links , https://signal.org/blog/call-links/

## 3. What Signal cannot do versus an offline / no-account app
- Needs a phone number to register, even with usernames; the number is tied to a SIM and often to a real identity (https://mjtsai.com/blog/2024/02/21/signal-usernames).
- Needs internet and a central server run by Signal; no radio, audio-tone, QR, Bluetooth or Wi-Fi peer-to-peer delivery. Sealed sender hides identity but timing/IP correlation is still possible (https://signal.org/blog/sealed-sender/).
- Account recovery depends on SMS and a PIN; the 2022 Twilio breach exposed some numbers, prompting advice to turn on registration lock (https://www.phonearena.com/news/Hackers-could-have-obtained-1900-Signal-users-numbers-Signal-warns-affected-users-what-to-do_id141943).
- Linked devices hang off a primary phone and unlink after 30 days offline (https://support.signal.org/hc/articles/360007320551).
- Notification content can still leave traces in iOS system storage (https://news.ycombinator.com/item?id=47716490).
- No duress PIN or panic wipe found in the pages read (not confirmed absent). No picture invite or spoken-word fallback.
- Sharing is by number/username, so the contact graph is on Signal's servers (contact discovery) (unverified in this pass).

## 4. User quotes (verbatim, linked)
1. "most people think that Signal is bulletproof out of the box, and it's clearly not." (david_shaw, Hacker News, thread on FBI recovering deleted Signal messages; page shows "7 months ago", article dated 2026-04-09) https://news.ycombinator.com/item?id=47716490
2. "Just curious, how come at least once a month signal bugs me to turn on notifications?" (pigggg, Hacker News, same thread, same date basis) https://news.ycombinator.com/item?id=47716490
3. "The front end of Signal, and its user interface, is absolutely wonderful." (Iphoneaphobia, App Store review, 08/08/2024) https://apps.apple.com/us/app/signal-private-messenger/id874139669?see-all=reviews
4. "Signal still requires registering with a phone number, which can be used to identify you." (Anonymous User 51869, App Store review, "Jun 8", year not shown on page) https://apps.apple.com/us/app/signal-private-messenger/id874139669?see-all=reviews
5. "Do not download, install, and use this app!" (iReviewAppsOccasionally, App Store review, 03/08/2025) https://apps.apple.com/us/app/signal-private-messenger/id874139669?see-all=reviews
(Quotes 1-2 were returned by a summarizing fetch tool, not read raw; re-check exact wording on the thread before publishing.)
