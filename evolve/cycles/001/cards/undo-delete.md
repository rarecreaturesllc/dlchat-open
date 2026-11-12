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
