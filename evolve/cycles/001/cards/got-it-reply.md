# Reply "got it" in one tap            Flag: exp_got_it_reply   Status: READY

**What changes for the user:** after a message opens on Receive, a "Reply: got it" button puts a short acknowledgement ("Got it: <first words of their message>") in the Send box for the same group, ready to send by words, tones, QR or Nearby. The sender finally learns it arrived.
**Why (evidence):**
- "Message is stuck in sending mode and sometimes it takes 20-25 minutes for message to be sent." - Berty user, https://github.com/berty/berty/issues/4334, 2022-08-05
- "Maybe I'm missing something, but to me it seems Simplex has only delivery receipt and no read receipt at all." - SimpleX user, https://github.com/simplex-chat/simplex-chat/issues/687, 2022-05-22
- "I'd like the app to be able to queue messages until the recipient is reachable." - Meshtastic user, https://github.com/meshtastic/Meshtastic-Android/issues/1979, 2025-05-29
- Competitor behavior: SimpleX shows one check when a message reaches the relay and two when it reaches the device - https://simplex.chat/faq/
**Where to see it:** Receive screen after a message opens (`-screen decode` with demo data), flag on.
**Risk / what it does not do:** no automatic receipts (there is no back channel offline); the person still sends the reply. The reply quotes at most 3 words of the original so it stays short.
**Rollback:** delete branch evolve/001/got-it-reply; flag removal is one commit.
**Design:** primary button under "Copy text" (the main next step after reading); when that group has a draft, a plain note replaces it ("send or clear your draft in Send first") so a draft is never merged or moved to another room (review fix). Matches DESIGN.md button styles, no new tokens.
**Accessibility:** button label plus hint; 44pt via dlPrimary; the draft note is plain text read in order.
**Tests:** GotItTextTests.testQuotesAtMostThreeWords; GotItReplyUITests.testReplyGotItFillsSend (flag on: draft blocks, then exact reply text), testNoReplyButtonWithFlagOff.
**Screenshots:** got-it-reply-on / got-it-reply-off (UI test attachments).
**Risk / what it does not do:** no automatic receipts; a reply to a read-once message says only "Got it." (no quote, since drafts are saved).
