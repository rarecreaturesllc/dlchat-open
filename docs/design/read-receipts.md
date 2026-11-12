# Read receipts (opt-in, per group)

Owner request 2026-11-09: "can we make read receipts enabled on the chat if the group accepts it?"

## Consent model

DLChat groups have no member list and no accounts: anyone holding the phrase is in the group, and
no phone can know who else is. So "the group accepts it" cannot be a vote counted by the app.
Instead each person accepts for themselves, per group:

- **Off by default.** Group details > Read receipts > "Send and see read receipts".
- **Both ways or not at all.** With it on, your phone reports which messages you've seen and you see
  "Read by N" on your own messages. With it off you send none and ignore any that arrive.
- **N counts only people who turned it on.** Someone with it off, or on an older build, never
  appears, so "Read by 1" in a group of five does not mean four ignored you.
- Turning it on starts fresh: only messages received after that are ever reported.

## What a receipt says and who sees it

- Sent while the group's Chat is on screen, the app is active and unlocked, after a 2-second pause
  (a burst of arrivals is one receipt; a glance past the tab is none).
- Holds: a version, the reader's random 16-bit tag for this group (new each time they turn receipts
  on), and up to 15 40-bit message references (a hash of room, time slot, salt, flags and text). No
  text, no name, no call sign, no time beyond the frame's 5-minute slot.
- Reports only plain chat messages that arrived by radio or relays. Not: messages decrypted on
  Receive, Encrypt Words / Encrypt Sound bubbles (the explicit "Decrypted" note from Acknowledged
  covers those, by hand), read-once messages (never stored), or anything with retention "Don't keep".
- Shown as "Read by N" in the line under your sent message. No per-person list: the tags are random
  and the app has no names to show (the call-sign branch could add names later).

## Wire format and older builds

A receipt is an ordinary sealed frame (128-bit tag, as chat messages), sealed under the group master
with a room word nobody can type (`"\0read"`). It travels exactly like a chat message: radio
broadcast and the group's daily relay mailbox, inside the same gift wrap.

- Older builds try only real room keys, cannot open it, and drop it silently. Nothing new shows.
- A full receipt (15 refs) is about 100 bytes, under the radio's 233.
- Not queued: if no route takes it, it is dropped rather than sent later with a misleading time.

## Privacy costs (stated in the app)

- **Activity:** group members learn roughly when you had DLChat open on that chat.
- **Traffic:** each receipt is one more sealed post. Relays (through Tor by default) see an extra
  small post to the group mailbox shortly after a message. With the radio on, your radio transmits,
  and Meshtastic headers carry your radio's node number in the clear, so anyone listening on the mesh
  can see that radio answer soon after a group message.
- **Linkable inside the group:** the reader tag lets members tell that two receipts came from the
  same phone until it is turned off and on again.

## Wipe

Settings live in the sealed store (`receipts` per group; `receiptRef`, `receiptSent`, `readBy` on
messages). Panic wipe, duress PIN and Remove group erase them with everything else. Receipts already
sent stay on relays as sealed posts like any message (up to 14 days).

## Not built (possible follow-ups)

- A "someone turned on read receipts, turn on too?" prompt in Chat.
- Names on receipts via call signs.
- Receipts for read-once messages.
