# Evolve 001 review

Read-only review of `git diff evolve/001/base..evolve/001/<slug>` for the five branches, checked against the cards and the seven guardrails. Tests were not run: the simulator was in use by another process. Line numbers refer to the file on that branch.

| Branch | Verdict |
| --- | --- |
| got-it-reply | FIX FIRST |
| backup-check | SHIP |
| read-once | FIX FIRST |
| lock-now | SHIP |
| undo-delete | FIX FIRST |

All five branches pass these guardrails: with the flag off, behavior is the same as before; none changes the persisted schema or adds a permission, dependency, analytics or network call; each has flag-on and flag-off UI tests; no existing test is weakened.

---

## got-it-reply: FIX FIRST

1. **High: the reply is joined onto an unrelated draft, and the draft moves to the reply's room.** `DLChat/Screens/RootView.swift:87-88` sets `compose.room = room` and then `compose.text = text + " " + compose.text`.
   - Scenario: you have a draft "move to site B at 0600" for Main. You read a message from room `ops` and tap "Reply: got it". Send now holds "Got it: need water at... move to site B at 0600", set to room `ops`. One tap on Show the words sends both lines as one message, under a room the draft was never meant for.
   - The UI test shows this happening and still passes. The seeded draft is the same message, so the field ends up as "Got it: need water at... need water at north gate", and `GotItReplyUITests.swift` only checks `hasPrefix`.
   - The draft is not lost, so the "never overwrite" rule holds. The bug is that two messages are silently merged and one is moved to another room.
   - Fix: when the draft is not empty, do not merge. Either keep the draft and do not prefill (show "Finish or clear your draft first"), or save the old draft aside and put it back after the reply is sent. When a draft is kept, also keep its room.
2. **Medium: tapping twice adds the quote twice.** `RootView.swift:88` prepends again on every tap, so going back to Receive and tapping again gives "Got it: X Got it: X ...". Skip the prepend if the text already starts with the reply.
3. **Medium (shows up once branches are combined): the quote is saved to disk.** `compose.text` is autosaved to the sealed draft store (ComposeModel `scheduleSave`). The quote is the first 3 plaintext words of a received message.
   - With read-once merged into the candidate, replying to a read-once message writes part of it to disk, which breaks read-once.
   - With retention set to Off, the quote also stays on the phone after History would have dropped the message.
   - Fix: hide the button, or leave out the quote, when `message.readOnce` is set.
4. **Low: a doc comment ended up on the wrong function.** The `closeAll()` doc comment (line 81) now sits above `replyInSend`, because the new function was inserted between the comment and `closeAll`. Move it.
5. **Low: the card's quote format does not survive sending.** `TextCodec` drops ":" and "...", so the receiver sees "got it need water at". Any quoted word that is not in the dictionary is spelled out letter by letter, which makes the reply longer.

Also checked, no problem found:
- Switching groups works. `syncGroup()` flushes the old group's draft before loading the target group's draft, and the later `onChange(activeGroup)` does nothing.
- `replyTarget` cannot point at the wrong group: `refreshKeys` recomputes the message on screen whenever keys change.

## backup-check: SHIP

- **Low: the field is missing `.textContentType(.none)`.** At `DLChat/Shared/BackupCheck.swift:55`, the join-phrase field (`GroupSetupView.swift:127`) sets it but this field does not. Add it so QuickType never suggests or learns phrase words.
- **Low (accessibility): VoiceOver does not hear the result.** `BackupCheck.swift:66` makes the result appear below the button with no announcement. Post `.announcement` with `BackupCheck.message(result)` in `check()`.
- **Low: Return on the multi-line field adds a new line instead of checking.** `.onSubmit(check)` (line 58) is on a `.vertical` field. This does no harm, because non-letters are ignored, but the Done label is misleading.

Also checked, no problem found:
- The phrase is never shown. Messages give only word numbers and counts, and a unit test asserts the real word is absent.
- The word-by-word result could be used to guess the phrase one word at a time. This adds nothing new: the same screen already shows the phrase behind an unauthenticated hold (`GroupListView.swift` `HoldToReveal`).
- Nothing is persisted. Numbered paper copies ("1. badge 2. foam") work, because digits are ignored.
- The card's claims hold.

## read-once: FIX FIRST

1. **Medium (security): a duress wipe leaves the "Read once" switch on.**
   - `discard()` (`DLChat/Vault/ComposeModel.swift:139-150`) resets `duress` but not `readOnce` (line 23).
   - The duress PIN is meant to open "an empty app that looks normal". After a duress wipe, the Send screen still shows Read once switched on, which a fresh install never does. Anyone looking can tell the app was in use.
   - Fix: add `readOnce = false` to `discard()`.
2. **Medium (honesty): the sender's promise only holds if the receiver's phone also has the flag on.**
   - The receiver drops the message only when `Experiments.isOn(.readOnce)` (`DLChat/Vault/DecodeModel.swift:182`). That is false on every App Store build, on test builds with the flag off, and on builds 1-5.
   - Yet the Send hint (`RootView.swift:268`) says "Receivers see it once; it is not kept in their history" as fact. The card admits builds 1-5 but not same-version receivers with the flag off.
   - Fix: change the hint to "Asks receivers not to keep it. Older or other versions may still keep it", and say the same on the card.
3. **Medium (guardrail 3, every receive path checked):**
   - Typed words (`recompute`), repair (`run`), QR (`readScanned`), tones (`readHeard`) and Nearby opening (`readNearby`) all go through `show()`, so none records the message in History.
   - **Nearby still stores it.** `NearbyModel.receive` saves the sealed frame in the relay store for up to 24 h and passes it on (`NearbyModel.swift:60-62`), and the sender keeps its own copy (`:75-76`). The frame is ciphertext, but the group keys are on the same phone, so the message can be read from disk for 24 h.
   - This is a choice for the relay design, not a code bug. The card should say "not kept in History; a Nearby relay copy is held, sealed, for up to 24 h".
   - "Copy text" (`ReceiveView.swift:136`) is still offered on read-once messages, which puts the plaintext on the pasteboard. Consider hiding it.
4. **Low (security trade-off not stated): read-once turns off repeat detection.** Read-once messages skip `record`, so `heardBefore` is never set. Someone who recorded the tones can replay a read-once message later and it shows as new. Retention Off already says "a repeated message cannot be spotted"; the card and the receive note should say the same.
5. **Low: the switch stays on after sending,** unlike the pressure mark, which clears after sending. It errs toward keeping less, but the person may not expect every later message to be read-once. Decide on purpose, and say so on the card.

Also checked, no problem found:
- With the flag off, `flags` gives the same value as before, and `show()` is unchanged.
- Bit 1 fits the existing 2-bit field (`Frame.swift:41`, `flags < 4`), so this is a wire addition, not a schema change.
- The unit test covers flag on and flag off.

## lock-now: SHIP

No blocking findings.
- `lock.lock()` only sets `isLocked` when a PIN exists (`AppLock.swift:116-118`), so it cannot bypass anything. The existing `LockWindow` is modal for VoiceOver (`accessibilityViewIsModal`) and sits above every sheet.
- The button is 44pt, has a label, and handles Increase Contrast.
- It is hidden when no PIN is set (`RootView.swift:122,129`).
- The draft keeps autosaving while locked, and the duress-PIN path cancels the pending save through `discard()`.
- **Low: the card says "Send screen top bar".** The button is in the root top bar, so it shows on Receive too. Fix the card.

## undo-delete: FIX FIRST

1. **High: the delete is never finished if the app goes to the background and is closed.**
   - The delete waits on a 6 s `Task` (`DLChat/Screens/HistoryView.swift:142-143`) or on `onDisappear` (line 71). Neither runs when the app goes to the background and is then suspended or killed.
   - Scenario: someone is coming, you swipe a sensitive message away and press the side button. The app is suspended, iOS later ends it, and on the next launch the message is back in History in full.
   - The card claims "never left half-done" but only covers History closing and wipes.
   - Fix: in `HistoryView`, read `@Environment(\.scenePhase)` and call `commitPending()` when the phase is not `.active`. Add the same call wherever the app locks (lock-now).
2. **Medium (accessibility): 6 seconds is too short for VoiceOver users.** The announcement (line 141) says Undo is available, but moving focus down to the toast takes longer than 6 s for many VoiceOver and Switch Control users (WCAG 2.2.1, timing adjustable). Fix: keep the toast until it is dismissed, or make the wait much longer, when `UIAccessibility.isVoiceOverRunning || isSwitchControlRunning`.
3. **Low: the toast covers the last row.** The overlay (`.overlay(alignment: .bottom)`) can hide the last History row and its swipe target while it shows. Add a bottom `safeAreaInset` instead of an overlay.

Also checked, no problem found:
- The haptic now fires before the delete instead of after, which makes no difference.
- With the flag off, `reload()`'s filter and `commitPending` do nothing. A new delete commits the pending one first.
- After a wipe: if the History sheet is torn down by the `ReceiveView.id(groups.wipes)` reset before its own `onChange(wipes)` runs, `onDisappear` calls `deleteMessage` on the fresh store. `GroupBook.deleteMessage` only writes when it finds the id, so nothing reaches the new store.
- The `Task` inherits the main actor from the View, so there is no isolation problem.
