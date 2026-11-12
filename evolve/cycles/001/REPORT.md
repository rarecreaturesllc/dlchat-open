# Evolve cycle 001 - DLChat                                   2026-11-07

**Result:** 5 READY, 0 deferred, 0 abandoned. Branch `evolve/001/candidate` (from `evolve/001/base`, which
is `feat/dlchat-foundation` at 0.1 (5) plus the Experiments registry). All five flags are off in App
Store builds. Nothing pushed, nothing uploaded.
Seeds: signal.org, simplex.chat, getsession.org (+ 8 similar apps). Research: `evolve/research/`.

| Iteration | Flag | Status | Change | Evidence |
|---|---|---|---|---|
| Reply "got it" in one tap | `exp_got_it_reply` | READY | After a message opens, one tap puts "Got it: <first words>" in Send | 3 quotes + SimpleX receipts |
| Check my written copy | `exp_backup_check` | READY | Type the phrase from paper; told match or which word numbers differ, never the phrase | 2 quotes + Session recovery UX |
| Read once | `exp_read_once` | READY | Send switch; receivers show it and never keep it (frame flag bit 1) | 2 quotes + Signal view-once |
| Lock now | `exp_lock_now` | READY | Lock button in the top bar when a PIN is set | Signal manual lock + 1 quote |
| Undo a deleted message | `exp_undo_delete` | READY | History delete waits 8 s behind an Undo toast | UX baseline gap |

## How to test
- Simulator: the candidate is installed and open. Launch with all flags on:
  `xcrun simctl launch --terminate-running-process booted com.harrisonfischberg.dlchat -seed-demo -reset-demo -evolve_all YES`
- On a test build (Debug or TestFlight): Settings, scroll to the version row at the bottom, long-press it
  (VoiceOver: "Open experiments" action). One switch per flag, "Turn all on", "Reset".
- Tests: see "Verification" below.

## Verification
- Opus review (`REVIEW.md`) found 3 FIX FIRST branches; all fixed and re-tested:
  got-it reply no longer merges into a draft; undo finishes when the app leaves the foreground and gives
  VoiceOver/Switch Control 20 s; read once is cleared by wipe/duress, hides Copy, honest hint; a reply to a
  read-once message does not quote it. Backup check now announces its result.
- The full run also caught a real picture-invite bug (not part of the five): about 1 fresh picture in 5
  had one faint star misread (Reed-Solomon repaired it, so invites still opened). Fixed in the reader:
  0 of 120 fresh pictures misread now, and heavy JPEG cases read with 0 bad bytes (were 2-10). Commit
  006f92a on the candidate; it should go to the main line whatever you decide about the five.
- Final runs on the candidate: DLCore 93/93 three times in a row; app unit tests 111/111 with all flags
  off; UI tests 30/31 with all flags off and 30/31 with all flags on - the one failure both times was the
  got-it test itself (it cleared the draft unreliably); after fixing the test it passes on its own runs
  (it passes the flag via `-evolve_all`). The Undo toast was then lifted clear of the search field and
  its test re-run green. Not re-run as one full suite after those two last test-only/layout fixes.

## The cards
# Check my written copy of the phrase            Flag: exp_backup_check   Status: READY

**What changes for the user:** in group details, "Check my written copy" lets you type the phrase from your paper; DLChat says it matches, or which word numbers differ, without ever showing the phrase.
**Why (evidence):**
- "I was knocked out of sessions, couldn’t find my recovery password and had a heck of a time trying to get back in without knowing where my recovery password that I saved&copied was. So I had to restart sessions all over again. But lost contact with my friend(s)." - Session App Store review "Session", https://apps.apple.com/us/app/id1470168868?see-all=reviews, 2026-10-08
- "I'm pretty technically inclined and I lose my Signal history every time I get a new phone because I just can't remember to transfer it." - https://news.ycombinator.com/item?id=33514755, 2022-11-08
- Competitor behavior: Session shows a recovery password and asks users to save it, with stated restore limits - research/session.md (docs.getsession.org)
**Where to see it:** Groups list, group details, flag on.
**Risk / what it does not do:** checks one group at a time; does not store that a check happened (no persisted data).
**Rollback:** delete branch evolve/001/backup-check.
**Design:** secondary button in group details next to the other phrase tools; sheet matches Settings sheets. Result uses dlGo / dlWarn with an icon, never colour alone.
**Accessibility:** result announced to VoiceOver (review fix), success/warning haptic, field 44pt+, autocorrect off.
**Tests:** BackupCheckTests (match ignores case and spacing; reports word numbers, never words; word count), BackupCheckUITests on and off.
**Screenshots:** backup-check-on / backup-check-result / backup-check-off.

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

# Lock now            Flag: exp_lock_now   Status: READY

**What changes for the user:** when an app PIN is set, a lock button in the top bar locks DLChat at once, instead of waiting for the app to go to the background.
**Why (evidence):**
- Competitor behavior: Signal Screen Lock, and on Android a manual lock from the notification tray - https://support.signal.org/hc/articles/360007059572
- "Have a frankly unreasonable threat model? No problem, this thing is nuke proof." - SimpleX App Store review "Pinnacle.", https://apps.apple.com/us/app/id1605771084?see-all=reviews, 2025-01-30
**Where to see it:** Send screen top bar after setting a PIN in Safety, flag on.
**Risk / what it does not do:** hidden when no PIN is set (locking without a PIN would do nothing).
**Rollback:** delete branch evolve/001/lock-now.
**Where to see it (corrected):** top bar on both Send and Receive, after setting a PIN in Safety.
**Design:** same round 44pt control as Settings and Safety, lock.fill icon, rigid haptic on tap.
**Accessibility:** label "Lock now"; increased-contrast ring like its neighbours.
**Tests:** LockNowUITests (hidden without a PIN; locks; PIN unlocks; absent with flag off); PanicAndLockUITests unchanged and passing.
**Screenshots:** lock-now-on / lock-now-off.

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

# Undo a deleted message            Flag: exp_undo_delete   Status: READY

**What changes for the user:** deleting a message in History hides it with an "Undo" toast for about 6 seconds; it is erased only when the toast ends.
**Why (evidence):** UX baseline table-stakes gap (~/.claude/skills/new-app/references/ux-baseline.md: "Destructive actions use undo (toast with Undo, ~5-8s) instead of instant delete"); History deletes instantly today (DLChat/Screens/HistoryView.swift delete(_:)).
**Where to see it:** History, swipe or long-press a message, flag on.
**Risk / what it does not do:** if History closes or the app is wiped during the window, the delete completes at once (never left half-done).
**Rollback:** delete branch evolve/001/undo-delete.
**Design:** bottom toast in the panel style with a dlGo "Undo" (44pt); ease-out 200 ms fade.
**Accessibility:** delete and restore announced; Undo lasts 8 s, or 20 s with VoiceOver or Switch Control (review fix).
**Tests:** UndoDeleteUITests.testUndoRestoresAndTimeoutErases (undo restores; timeout erases; reopening proves it), testFlagOffDeletesAtOnce.
**Screenshots:** undo-delete-on / undo-delete-off.
**Also from review:** leaving the app (which also locks it) finishes the delete, so a later kill cannot bring it back.



## Needs your decision (touch a contract, not built)
1. **Online mode** - full design in `evolve/ONLINE_MODE.md` (Nostr relays default, iCloud second, same sealed
   frames, throwaway key per post, daily-rotating mailbox). Four decisions listed at its end: the
   secp256k1 package, on by default or not, default relays, iCloud push from the start.
2. Hidden groups behind a password (SimpleX hidden profiles) - persisted data.
3. Private notes / note to self (Signal, SimpleX) - persisted data.
4. Per-message disappearing timer (all three seeds) - persisted data + wire format; read once covers part.
5. Move to a new phone over Nearby (Signal transfer) - persisted data, multi-hour.

## Next up
- Show which way each message travelled in History (needs a stored field).
- Receive screen: tapping away should put the keyboard away (UX baseline; today only dragging does).

## Reply with
`approve: <slug>, <slug> / reject: <slug> (why) / change: <slug> (what)`
Slugs: got-it-reply, backup-check, read-once, lock-now, undo-delete. Then `/app-evolve close`.
Merging into your main branch and pushing will need a separate yes; App Store submission stays yours.
