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
