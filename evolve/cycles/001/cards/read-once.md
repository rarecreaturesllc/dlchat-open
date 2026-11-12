# Read once messages            Flag: exp_read_once   Status: READY

**What changes for the user:** a "Read once" switch on Send. The receiver sees the message with "Read once: not kept", and it never enters their History or export.
**Why (evidence):**
- "I actually think one of the best parts about signal is the disappearing messages feature" - https://news.ycombinator.com/item?id=39463352, 2024-02-22
- "I mostly text on Signal with disappearing messages so I wouldn't be able to do this. Most people are fine with disappearing messages at 4 weeks, but a few people like to keep their chats forever." - https://news.ycombinator.com/item?id=48304901, 2026-05-28
- Competitor behavior: Signal view-once media and disappearing timers - research/signal.md, https://support.signal.org/hc/en-us/articles/360007320771-Set-and-manage-disappearing-messages
**Where to see it:** Send screen switch; Receive screen after opening, flag on.
**Risk / what it does not do:** uses spare frame flag bit 1 (bit 0 is duress), which is additive; builds 1-5 ignore the bit and keep the message. Cannot stop a screenshot or someone writing it down.
**Rollback:** delete branch evolve/001/read-once.
**Design:** a switch under the compose box on Send; Receive shows a warning-colour note and hides "Copy text" (review fix).
**Accessibility:** switch label and hint; note is text with an icon.
**Tests:** ReceiverTests.testReadOnceFlagIsBitOneAndIndependentOfDuress (DLCore); DecodeModelTests.testReadOnceIsShownNotKept (flag on: not recorded; flag off: no bit sent, recorded); ReadOnceUITests on and off.
**Screenshots:** read-once-on / read-once-off.
**Also from review:** wipe and duress PIN clear the switch so the app looks untouched; the hint says older versions keep it.
**Known limits:** Nearby keeps the sealed frame in its relay store (up to 24 h, inside the sealed vault) so it can pass it on to other phones; a read-once message skips the "already received" warning, because it is never recorded.
