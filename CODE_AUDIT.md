# DLChat Code Audit — 2026-11-07

Scope: `DLChat/` (app), `Packages/DLCore/Sources`, `Packages/TorKit/Sources`; 117 Swift files, about 14,100 lines including tests. Method: clean build for compiler warnings (6 found), three parallel read-only reviews (concurrency and API, dead code and duplication, bugs and security), a SwiftUI performance pass, and a UI/UX and Impeccable design critique against `DESIGN.md` and 23 current screenshots. Both Critical findings were confirmed by reading the cited lines. Status column: **Fixed** means changed in the commit that follows this report; everything else is open.

## 1. Executive summary

1. **[Critical] Microphone can stay on after Listen is closed** — §5.1 — `DLChat/AudioIO/ToneAudio.swift:133-167` — Fixed
2. **[Critical] Tor control-socket write can kill the app with SIGPIPE** — §5.2 — `Packages/TorKit/Sources/TorKit/Tor.swift:101` — Fixed
3. **[High] Overlapping queue flushes send the same message several times** — §5.3 — `DLChat/Online/OnlineModel.swift:72-75, 202-217` — Fixed
4. **[High] Chat re-reads and decrypts the whole store on every keystroke** — §7.1 — `DLChat/Screens/ChatView.swift:16-21` — Fixed
5. **[High] Deleted or expired messages come back from relays after a relaunch** — §5.4 — `DLChat/Online/OnlineModel.swift:164-166, 221-227` — Fixed
6. **[High] With retention "Don't keep", Chat drops sent and queued messages** — §5.5 — `DLChat/Vault/GroupBook.swift:164` — Fixed
7. **[High] Panic-wipe sequence written twice in RootView** — §9.1 — `DLChat/Screens/RootView.swift:45-54, 59-69` — Fixed
8. **[High] Nearby callbacks after a wipe can write the relay store again** — §5.6 — `DLChat/NearbyLink/NearbyModel.swift:90-119` — Fixed
9. **[High] Settings buries every control under two long lists** — §8.1 — `DLChat/Screens/SettingsView.swift:30-33` — Fixed
10. **[High] Swift 6 errors in waiting** — §3.1–§3.3 — `Hygiene.swift:7-41`, `PracticeModel.swift:13, 38` — Fixed

## 2. Quick wins

### 2.1 Unused key-set lookup on every relay event
- **Location:** `DLChat/Online/OnlineModel.swift:223`
- **What:** `let keySets = groups.keySets()` is never used (compiler warning).
- **Why:** A wasted Keychain round trip per event.
- **Action:** Delete it.
- **Severity:** Low — Fixed

### 2.2 Unused results warned by the compiler
- **Location:** `DLChat/Online/OnlineModel.swift:240`, `DLChat/NearbyLink/NearbyModel.swift:108`
- **What:** Unused `RecordResult` and an unused `assumeIsolated` result.
- **Why:** Warning noise hides real warnings.
- **Action:** `_ =` or `@discardableResult`.
- **Severity:** Low — Fixed

### 2.3 Orphaned and stale doc comments
- **Location:** `DLChat/Screens/RootView.swift:91` (belongs to `closeAll`), `DLChat/Design/Components.swift:80` (ModeSwitch is no longer Send/Receive), `DLChat/Online/OnlineModel.swift:179-184` (split by `@discardableResult`), `DLChat/Online/RelayPool.swift:202` (lists CLOSED, which has its own case)
- **What:** Comments contradict the code next to them.
- **Why:** Misleading for the next reader.
- **Action:** Move or correct each.
- **Severity:** Low

### 2.4 Unused colour token
- **Location:** `DLChat/Design/Tokens.swift:11`
- **What:** `dlHairline` is referenced nowhere.
- **Why:** Dead token.
- **Action:** Remove, or use it for dividers.
- **Severity:** Low

### 2.5 Tor folder included in backups
- **Location:** `DLChat/Online/OnlineModel.swift:44`, `Packages/TorKit/Sources/TorKit/Tor.swift:51-52`
- **What:** The Tor data folder is not marked `isExcludedFromBackup`, unlike the Vault folder.
- **Why:** Entry-guard state goes into iCloud/computer backups and outlives a wipe.
- **Action:** Exclude it after creating it.
- **Severity:** Low — Fixed

### 2.6 Chat hides compose errors
- **Location:** `DLChat/Screens/ChatView.swift:193-195`
- **What:** When `prepareNearby()` fails it sets `compose.problem`, which Chat never shows.
- **Why:** Send looks broken.
- **Action:** Show `compose.problem` above the composer.
- **Severity:** Low — Fixed

### 2.7 Duress mark persists into Chat
- **Location:** `DLChat/Screens/ChatView.swift:199-200`, `DLChat/Vault/ComposeModel.swift:21`
- **What:** Chat send resets `readOnce` but not `duress`.
- **Why:** After one long-press on Send, every later chat message is flagged "Sent under pressure", invisibly.
- **Action:** Clear `duress` after each Chat send.
- **Severity:** Medium — Fixed

## 3. Concurrency

### 3.1 Push handler sends non-Sendable userInfo and reports newData before fetching
- **Location:** `DLChat/Shared/Hygiene.swift:36-41`, `DLChat/Online/OnlineModel.swift:64-66, 140-144`
- **What:** Swift 6 error on `[AnyHashable: Any]`; returns `.newData` while the fetch is an unawaited Task.
- **Why:** iOS may suspend before the fetch finishes. Dormant while `CloudCarrier.isConfigured == false`.
- **Action:** `@MainActor` delegate; an awaitable fetch whose result decides `.newData`/`.noData`.
- **Severity:** High (dormant) — Fixed (completion-handler variant waits for the fetch)

### 3.2 Global mutable `Hygiene.lastCopied`
- **Location:** `DLChat/Shared/Hygiene.swift:7-28`
- **What:** Non-isolated static var.
- **Why:** Swift 6 error; the panic wipe relies on it.
- **Action:** Isolate to the main actor.
- **Severity:** High — Fixed

### 3.3 `PracticeModel.message` read from a detached task
- **Location:** `DLChat/Shared/PracticeModel.swift:13, 38`
- **What:** Main-actor static read off the actor (compiler warning).
- **Why:** Swift 6 error.
- **Action:** `nonisolated static let`.
- **Severity:** High — Fixed

### 3.4 NearbyLink is non-isolated but captured in main-queue closures
- **Location:** `DLChat/NearbyLink/NearbyLink.swift:9, 61, 69-72, 77`
- **What:** Mutable closures read and set on different threads.
- **Why:** Data race; Swift 6 errors.
- **Action:** `@MainActor` class with `nonisolated` delegate hops, as `MeshtasticLink` does.
- **Severity:** Medium

### 3.5 Tor start and pause are unordered
- **Location:** `DLChat/Online/OnlineModel.swift:97-124`, `Packages/TorKit/Sources/TorKit/Tor.swift:43-45`
- **What:** Off-then-on during bootstrap leaves the network disabled; a wipe mid-bootstrap stores a stale port.
- **Why:** Tor shows "could not connect" after 2 minutes, or relays fail until Tor is toggled.
- **Action:** Generation token; drop stale start results; resend `DisableNetwork=0` on re-enable.
- **Severity:** High — Fixed (generation token)

### 3.6 Duplicate event id leaks a continuation
- **Location:** `DLChat/Online/RelayPool.swift:125-143`
- **What:** `waiting[id] = continuation` overwrites an earlier waiter.
- **Why:** The first caller hangs forever.
- **Action:** Resume the existing waiter before replacing it.
- **Severity:** Medium — Fixed

### 3.7 Publish fan-out and timeouts ignore cancellation
- **Location:** `DLChat/Online/RelayPool.swift:65-70, 127-138`
- **What:** Plain `Task {}` fan-out, 100 ms polling for open, never-cancelled timeout tasks.
- **Why:** Wasted wakeups; work continues after the caller is gone.
- **Action:** Task group; continuation resumed from `isOpen`.
- **Severity:** Medium

### 3.8 Audio session activated on a global queue, deactivated on main
- **Location:** `DLChat/AudioIO/ToneAudio.swift:77-109, 172-212`
- **What:** `setActive(false)` runs on main while setup runs elsewhere.
- **Why:** Main-thread stalls; a quick stop/start can deactivate a fresh session.
- **Action:** One serial queue for all session calls.
- **Severity:** Medium

### 3.9 Detached tasks carry DLCore types not marked Sendable
- **Location:** `DLChat/Shared/PracticeModel.swift:35-40, 120-122`, `DLChat/Vault/DecodeModel.swift:168-169`, `DLChat/Vault/GroupModel.swift:66-77`
- **What:** `Keys`, `Phrase`, `PreparedGroup` cross into detached tasks.
- **Why:** Future Swift 6 errors.
- **Action:** Mark the value types `Sendable`.
- **Severity:** Medium

### 3.10 Mixed weak/strong capture in startTor
- **Location:** `DLChat/Online/OnlineModel.swift:112-123`
- **What:** Compiler warning: inner weak, outer implicit strong.
- **Why:** The weak capture does nothing.
- **Action:** Capture consistently.
- **Severity:** Low — Fixed

### 3.11 Audio tap captures non-Sendable converter and decoder
- **Location:** `DLChat/AudioIO/ToneAudio.swift:186-194`, `DLChat/AudioIO/AudioResampler.swift:18-35`
- **What:** Thread-confined today; Swift 6 errors later; allocates per buffer.
- **Why:** Future errors; churn on the audio thread.
- **Action:** Documented `@unchecked Sendable` box; preallocate.
- **Severity:** Low

## 4. API modernity

### 4.1 Token observers and fixed sleeps
- **Location:** `DLChat/Online/OnlineModel.swift:64-66`, `DLChat/AudioIO/ToneAudio.swift:55-57, 163-165`, `DLChat/Screens/QRView.swift:177-180`, `DLChat/Screens/RootView.swift:122-129`
- **What:** `addObserver(forName:)` tokens (one never removed) and fixed 300/600 ms sleeps.
- **Why:** Leaks and timing guesses.
- **Action:** `NotificationCenter.notifications(named:)` in a stored Task; present on `onDismiss`.
- **Severity:** Low

### 4.2 Relay sockets use `URLSession.shared` when Tor is off
- **Location:** `DLChat/Online/RelayPool.swift:19, 51-52`
- **What:** Persistent cookies, cache and HSTS state.
- **Why:** Can link sessions over time.
- **Action:** Always an ephemeral configuration.
- **Severity:** Low — Fixed

### 4.3 Verbose MainActor delegate pattern
- **Location:** `DLChat/Meshtastic/MeshtasticLink.swift:85-162`
- **What:** `nonisolated` plus `assumeIsolated` everywhere; correct only because the queue is `.main`.
- **Why:** Traps if the queue changes.
- **Action:** Comment tying it to `queue: .main`, or `@preconcurrency` conformance.
- **Severity:** Low

## 5. Bugs / logic errors

### 5.1 Microphone stays on if Listen closes during startup
- **Location:** `DLChat/AudioIO/ToneAudio.swift:133-167, 203-212`
- **What:** `start()` waits seconds for setup while `state` is `.idle`; a `stop()` meanwhile finds no engine and does nothing; setup then stores the engine and starts listening.
- **Why:** The microphone keeps recording after the person left the screen, which breaks "nothing it hears is saved or sent" in spirit and is a privacy exposure; a second start also leaks an engine.
- **Action:** A `.starting` state that rejects re-entry, plus a generation token: if stopped during setup, tear the new engine down.
- **Severity:** Critical — Fixed

### 5.2 SIGPIPE on Tor's control socket
- **Location:** `Packages/TorKit/Sources/TorKit/Tor.swift:101`
- **What:** Plain `write()` with no `SO_NOSIGPIPE`; nothing ignores SIGPIPE.
- **Why:** If the tor thread ever exits, the next command terminates the app.
- **Action:** Set `SO_NOSIGPIPE` on the fd; mark Tor dead on EOF.
- **Severity:** Critical — Fixed

### 5.3 Overlapping queue flushes duplicate messages
- **Location:** `DLChat/Online/OnlineModel.swift:72-75, 202-217`
- **What:** Each relay that connects starts another `flushQueue()`; each re-seals the same queued rows with a new salt.
- **Why:** Receivers get up to one copy per relay; the sender keeps extra copies.
- **Action:** One flush at a time.
- **Severity:** High — Fixed

### 5.4 Deleted or purged messages return from relays
- **Location:** `DLChat/Online/OnlineModel.swift:164-166, 221-227`, `DLChat/Vault/GroupBook.swift:143-157`
- **What:** Subscriptions reach back 3 days before the last sync; relays keep events 14 days; `seen` is memory-only.
- **Why:** After a relaunch, a message deleted in History or purged by retention is stored again as new. Read-once messages reappear too.
- **Action:** Persist deleted/purged/read-once identities until `Online.lifetime`, and skip them on receive.
- **Severity:** High — Fixed (identity hashes kept 17 days in the sealed store)

### 5.5 Retention "Don't keep" breaks Chat sending
- **Location:** `DLChat/Vault/GroupBook.swift:164`, `DLChat/Online/OnlineModel.swift:191, 205`
- **What:** `recordSent` returns early, so sent messages never show and offline messages are never queued.
- **Why:** Silent loss of offline sends.
- **Action:** Keep the outgoing queue outside retention, or warn in Chat.
- **Severity:** High — Fixed (queued kept until sent; sent shown for the session only)

### 5.6 Late Nearby callbacks after stop or wipe
- **Location:** `DLChat/NearbyLink/NearbyModel.swift:90-119`, `DLChat/NearbyLink/NearbyLink.swift:59-62, 75-78`
- **What:** Queued main-queue blocks still reach `receive(_:)` after `stopLink()`.
- **Why:** The relay store is rebuilt right after a panic wipe.
- **Action:** Clear the link's closures in `stop()` or check the sender's identity.
- **Severity:** High — Fixed

### 5.7 "Sending" forever if the app is suspended mid-publish
- **Location:** `DLChat/Online/OnlineModel.swift:191, 195-197`
- **What:** Recorded as "online/sending" before the publish; only "queued" rows are retried.
- **Why:** A killed send is never retried.
- **Action:** Record as queued first; upgrade after a relay accepts. Needs an in-flight set so the queue flush does not resend it mid-publish.
- **Severity:** Medium

### 5.8 Long chat messages are cleared and lost
- **Location:** `DLChat/Screens/ChatView.swift:192-206`, `Packages/DLCore/Sources/DLCore/Relay.swift:16`
- **What:** Wires over 1024 bytes are dropped by every carrier after the field is cleared.
- **Why:** Silent loss.
- **Action:** Check the size before clearing; say how much to shorten.
- **Severity:** Medium — Fixed

### 5.9 "Waiting for a connection" while online chat is off
- **Location:** `DLChat/Screens/ChatView.swift:150`, `DLChat/Online/OnlineModel.swift:191`
- **What:** With no carrier on, the bubble promises it will go out by itself.
- **Why:** It won't until online chat is turned on.
- **Action:** Say "not sent: online chat is off".
- **Severity:** Medium — Fixed

### 5.10 Send locked for up to 9 s per message
- **Location:** `DLChat/Screens/ChatView.swift:185, 196-205`
- **What:** `sending` disables Send until every relay answers or times out.
- **Why:** Back-and-forth chat stalls, worst over Tor.
- **Action:** Don't block the composer on publish.
- **Severity:** Medium — Fixed

### 5.11 Read-once sent offline looks sent
- **Location:** `DLChat/Online/OnlineModel.swift:186-193`
- **What:** Added to the screen before any carrier is checked; never queued.
- **Why:** Looks delivered when nothing took it.
- **Action:** Reflect the real result in its detail line.
- **Severity:** Medium

### 5.12 Nearby sends still recorded as "queued"
- **Location:** `DLChat/Screens/ChatView.swift:197-203`
- **What:** Only the radio passes `sentBy`; Nearby doesn't.
- **Why:** The later flush re-seals it and receivers see it twice.
- **Action:** Pass "nearby" when peers took it.
- **Severity:** Medium — Fixed

### 5.13 No date or replay warning on Chat bubbles
- **Location:** `DLChat/Screens/ChatView.swift:143-147`
- **What:** Time only, and no `Receiver.timeNote`.
- **Why:** A replayed old frame looks new; Receive warns, Chat doesn't.
- **Action:** Show the date when not today, plus the old/clock notes.
- **Severity:** Medium — Fixed (date)

### 5.14 Nearby keeps one unopened message and never feeds Chat
- **Location:** `DLChat/NearbyLink/NearbyModel.swift:19, 64`
- **What:** A second arrival overwrites the first.
- **Why:** Lost messages; Chat's status text is wrong for Nearby.
- **Action:** Store readable frames like the radio path does, or queue arrivals.
- **Severity:** Medium

### 5.15 Opening a Nearby message erases words being typed
- **Location:** `DLChat/Vault/DecodeModel.swift:124-130`
- **What:** `showHeard` clears `entered` and `typed`.
- **Why:** Half-written spoken messages are lost.
- **Action:** Keep and restore them.
- **Severity:** Low

### 5.16 Store failures read as "group gone"
- **Location:** `DLChat/Vault/GroupModel.swift:17, 54-64`, `DLChat/Screens/RootView.swift:242`
- **What:** `loadFailed` is never shown; the app opens New group.
- **Why:** The person believes every group was lost.
- **Action:** A clear "could not open your groups" state with retry.
- **Severity:** Medium

### 5.17 Tor control reads have no timeout; failure has no retry in Chat
- **Location:** `Packages/TorKit/Sources/TorKit/Tor.swift:86-90, 98-118`, `DLChat/Screens/ChatView.swift:92`
- **What:** A stalled tor leaves "Connecting" forever; Chat has no Try again.
- **Why:** Dead end.
- **Action:** Receive timeout on the socket; Try again in Chat; reset progress per attempt.
- **Severity:** Medium — Fixed (timeout, Try again, progress reset)

### 5.18 Picture invite can share a picture for the previous password
- **Location:** `DLChat/Screens/PictureInviteView.swift:71-80`
- **What:** A cancelled render still assigns `image`/`file`.
- **Why:** The friend gets a picture the shown words cannot open.
- **Action:** Check cancellation and the password after the await.
- **Severity:** Low — Fixed

### 5.19 Switching radios leaves the old Bluetooth connection open
- **Location:** `DLChat/Meshtastic/MeshtasticLink.swift:53-62, 116-123`
- **What:** `connect` replaces the peripheral without cancelling the old one.
- **Why:** Battery drain and stray callbacks.
- **Action:** Cancel a different existing peripheral; ignore foreign callbacks.
- **Severity:** Medium

### 5.20 Tor launch failure paths leave a half-started state
- **Location:** `Packages/TorKit/Sources/TorKit/Tor.swift:53-69`
- **What:** `control` is set before AUTHENTICATE succeeds.
- **Why:** Retries talk to an unauthenticated socket.
- **Action:** Set `control` only after authentication.
- **Severity:** Low — Fixed

## 6. Security

### 6.1 A failed duress wipe reveals itself
- **Location:** `DLChat/Vault/AppLock.swift:21-22, 129`, `DLChat/Screens/LockView.swift:72-74`
- **What:** Shows "Could not finish" instead of "Wrong PIN", after side state is already erased.
- **Why:** An observer learns a duress PIN was typed.
- **Action:** Same text as a wrong PIN; retry quietly.
- **Severity:** Low

### 6.2 PIN wait skippable by reboot plus clock change
- **Location:** `DLChat/Vault/AppLock.swift:155-172`
- **What:** After a reboot only wall-clock time counts.
- **Why:** One reboot per guess instead of up to an hour.
- **Action:** Require the full remaining wait after an uptime reset.
- **Severity:** Low

### 6.3 Relay event id marked seen before validation
- **Location:** `DLChat/Online/OnlineModel.swift:222-225`
- **What:** A forged event reusing a real id blocks the real one for the session.
- **Why:** One hostile relay can drop messages.
- **Action:** Insert into `seen` after a successful unwrap.
- **Severity:** Low — Fixed

### 6.4 Wipe deletes the Tor folder while tor still runs
- **Location:** `DLChat/Online/OnlineModel.swift:254-258`
- **What:** Tor's memory keeps guard state; the delete is unawaited.
- **Why:** Tor state is fully gone only after a restart.
- **Action:** Say so; await the delete.
- **Severity:** Medium

### 6.5 Network guard misses C sockets and other routes
- **Location:** `DLChatTests/HygieneTests.swift:68-86`
- **What:** No check for `socket`/`connect`, remote `Data(contentsOf:)`, `NWPathMonitor`, `UIApplication.open`.
- **Why:** False confidence.
- **Action:** Extend the list; allow-list TorKit explicitly.
- **Severity:** Low

## 7. Performance

### 7.1 Chat decrypts the store on every redraw
- **Location:** `DLChat/Screens/ChatView.swift:16-21, 91-100`
- **What:** `messages` is computed (disk read, Keychain, decrypt, decode) and read 3 times per body; the body redraws per keystroke because the composer lives in the same view.
- **Why:** Typing cost grows with history.
- **Action:** Cache in state, reload on `chatVersion`/transient/group change; move the composer into its own view.
- **Severity:** High — Fixed

### 7.2 PIN hashing on the main actor
- **Location:** `DLChat/Vault/AppLock.swift:120-151, 223-249`
- **What:** Two 200k-round PBKDF2 hashes synchronously per entry.
- **Why:** UI freezes 0.3–1 s per Unlock.
- **Action:** Hash off the main actor with a progress state.
- **Severity:** Medium

### 7.3 Repeated Keychain reads and full-store rewrites per event
- **Location:** `DLChat/Online/OnlineModel.swift:221-243`, `DLChat/Vault/GroupModel.swift:86-96`, `DLChat/Vault/GroupBook.swift:143-158, 286-293`, `DLChat/NearbyLink/NearbyModel.swift:57-69`
- **What:** Key sets rebuilt per event; each record rewrites the whole sealed store; Nearby frames rewrite it too.
- **Why:** Hitches during bursts.
- **Action:** Cache key sets; batch or debounce writes.
- **Severity:** Medium

### 7.4 Single ping for socket liveness
- **Location:** `DLChat/Online/RelayPool.swift:94-109, 206-219`
- **What:** Half-open sockets are not noticed; old tasks aren't cancelled.
- **Why:** Messages "published" into dead sockets.
- **Action:** Periodic ping; cancel the old task.
- **Severity:** Medium

## 8. SwiftUI / UI

### 8.1 Settings buries controls under explanations
- **Location:** `DLChat/Screens/SettingsView.swift:30-33`
- **What:** "What is protected" and "What is not" lists come before every control; online and radio need three scrolls.
- **Why:** Breaks "one primary action, nothing needing a second look"; iOS expects settings-shaped content first.
- **Action:** Controls first; the explanations in a collapsed section.
- **Severity:** High — Fixed

### 8.2 Receive has no clear first step
- **Location:** `DLChat/Screens/ReceiveView.swift:22-63`
- **What:** Six equal secondary buttons, with the word field (the main action) in the middle.
- **Why:** Under stress, the person must hunt for where to type.
- **Action:** Field and its helpers directly under the result and Listen/Scan; Nearby and History below. The first attempt was reverted: the word field clipped at the largest text sizes once it was on screen. Done with a shorter placeholder ("Type a word"); the contrast failures at the time were §8.6.
- **Severity:** Medium — Fixed

### 8.3 Chat status line
- **Location:** `DLChat/Screens/ChatView.swift:60-83`
- **What:** Long grey text; the dot centres on two lines instead of the first.
- **Why:** Looks unfinished; slow to scan.
- **Action:** Align the dot to the first line; shorter text.
- **Severity:** Low — Fixed

### 8.4 Fixed font sizes ignore Dynamic Type
- **Location:** `DLChat/Screens/GroupSetupView.swift:169, 182`, `DLChat/Screens/QRView.swift:139`, `DLChat/Screens/TonesView.swift:36, 89`, `DLChat/Screens/NearbyView.swift:36`, `DLChat/Screens/ChatView.swift:182`, `DLChat/Shared/Hygiene.swift:97`
- **What:** `.system(size:)` and raw text styles bypass `.dl(...)`.
- **Why:** Accessibility regression against DESIGN.md.
- **Action:** `.dl(...)` and `@ScaledMetric`.
- **Severity:** Medium — Fixed (ChatView)

### 8.5 DESIGN.md out of date on navigation
- **Location:** `DESIGN.md` (Layout, Navigation)
- **What:** Still describes the Send/Receive switch at the bottom; the tabs moved to the top with Chat.
- **Why:** The design source of truth disagrees with the app.
- **Action:** Update the two sections.
- **Severity:** Low — Fixed

### 8.6 Accessibility audit's contrast check is intermittent on the green buttons
- **Location:** `DLChatUITests/UXBaselineUITests.swift:100-127`, `DLChat/Screens/ReceiveView.swift` (Listen, Scan QR, Nearby phones)
- **What:** `performAccessibilityAudit` reports "Contrast failed" on dlGo-on-dlPanel buttons in some runs and not others, with identical code (4 failures in about 12 runs on 2026-11-07).
- **Why:** A flaky gate either blocks good changes or gets ignored.
- **Action:** Measure the real ratio of dlGo on dlPanel; if it clears 4.5:1, find out what the audit samples (animation still running after the tab switch is the likely cause) and wait for the UI to settle before auditing. Do not exempt contrast.
- **Cause found:** dlGo on dlPanel is 8.33:1. `TabSlider` set the selection inside `withAnimation`, so the whole screen cross-faded for 0.25 s and an audit that started mid-fade saw the buttons at partial opacity. Now only the capsule animates and the screen swaps at once (`DLChat/Design/Components.swift`, TabSlider). Five audit runs in a row passed afterwards.
- **Severity:** Medium — Fixed

## 9. Dead code / duplication / refactor

### 9.1 Panic-wipe sequence duplicated
- **Location:** `DLChat/Screens/RootView.swift:45-54, 59-69`
- **What:** The AppLock wipe closure and `wipeEverything()` repeat the same steps.
- **Why:** A new model added to one path but not the other leaves plaintext behind.
- **Action:** One shared function.
- **Severity:** High — Fixed

### 9.2 `enum Mock` is dead design-phase code
- **Location:** `DLChat/Shared/Mock.swift:3-53`
- **What:** Only `Mock.wordCount` is used, by a test of the mock itself.
- **Why:** 50 lines of fake encryption in the binary.
- **Action:** Delete it and that assertion; keep `Screen`, `Launch`, `chunked`.
- **Severity:** Medium

### 9.3 Sheet header copy-pasted across about 10 screens
- **Location:** `SettingsView.swift:23-28`, `SafetyView.swift:24`, `PracticeView.swift:19, 62`, `GroupSetupView.swift:51-57`, `QRView.swift:22, 110`, `NearbyView.swift:22`, `PictureInviteView.swift:25`, `RootView.swift:356`, `BackupCheck.swift:50`, `Experiments.swift:51`
- **What:** Title plus Done/Close restyled each time, with differing hit sizes.
- **Why:** Inconsistent targets.
- **Action:** A shared `SheetHeader`.
- **Severity:** Medium

### 9.4 Repeated logic in OnlineModel
- **Location:** `DLChat/Online/OnlineModel.swift:69, 136-138, 162-163, 224` (master keys ×4), `186-189` and `236-238` (read-once message built twice), `207-211` (wire built twice)
- **What:** Same computations in several places.
- **Why:** Drift risk.
- **Action:** Helpers.
- **Severity:** Medium — Fixed (master keys)

### 9.5 RootView holds three screens and a 300-character line
- **Location:** `DLChat/Screens/RootView.swift:166, 248-392`
- **What:** `SendView` and `TeleprompterView` live inside RootView; the tab switch is one line.
- **Why:** Hard to review.
- **Action:** Split files; multi-line switch.
- **Severity:** Medium

### 9.6 AppLock duplicates the failure-record block and misreports storage errors
- **Location:** `DLChat/Vault/AppLock.swift:144-149, 159-164, 179, 188`
- **What:** Copied rate-limit block; storage failure shown as "too short".
- **Why:** Wrong guidance; drift.
- **Action:** Helper; a `couldNotSave` case.
- **Severity:** Medium

### 9.7 Duplicated small components and literals
- **Location:** circle icon buttons (`SettingsView.swift:224-237`, `SafetyView.swift:94-126`), `note`/status helpers (`SettingsView.swift:177-184`, `ChatView.swift:62-88`), warning labels (`ReceiveView.swift:163-185` and 3 more), raw radii/paddings (`ChatView.swift:56, 135-136, 177-179`, `GroupSetupView.swift:50-172`, `LockView.swift:38, 57`), "Create or join a group first" ×3, group-removal strings ×2
- **What:** Design elements re-implemented outside `Design/`.
- **Why:** Token changes don't propagate.
- **Action:** Shared components and tokens.
- **Severity:** Low

### 9.8 Launch arguments parsed in release views
- **Location:** `DLChat/Screens/RootView.swift:20, 390`, `ReceiveView.swift:16-17`, `SettingsView.swift:10-11`, `PracticeView.swift:76`
- **What:** Screenshot hooks re-parse `ProcessInfo.arguments` without `#if DEBUG`.
- **Why:** Test behaviour ships.
- **Action:** Parse once; gate with `#if DEBUG`.
- **Severity:** Low

### 9.9 Unused persisted field and repeated ordering code
- **Location:** `DLChat/Vault/GroupBook.swift:10, 228` (`lastUsedAt`), `77, 93-95, 111-112, 221`
- **What:** Write-only field; sort/renumber four ways.
- **Why:** Clutter.
- **Action:** Remove; one helper.
- **Severity:** Low

### 9.10 CloudCarrier dormant but wired at launch
- **Location:** `DLChat/Online/OnlineModel.swift:23-66, 126-174`, `DLChat/Screens/SettingsView.swift:78-83`
- **What:** Intentionally gated; observer still registered and never removed; mis-indented.
- **Why:** Untested live code.
- **Action:** Register only when configured; fix indentation.
- **Severity:** Low

## 10. Cross-cutting recommendations

- Give every async start/stop pair a generation token (Tor, audio listen, relay connect); stale completions must not install state.
- Treat "queued" as the only pre-delivery state and republish the original sealed bytes rather than re-sealing, so receivers can dedupe.
- Keep secrets-adjacent IO (Vault, Keychain, PBKDF2) off the main actor and cache key sets per group change.
- Route all styling through `Design/` (tokens, `SheetHeader`, status line, warning label); screens add no styling of their own.
- Before Swift 6 mode: isolate NearbyLink, mark DLCore value types `Sendable`, finish §3.1.

## 11. What was NOT audited

- DSP and decoding correctness in `Modem`, `ReedSolomon`, tone timing, and `Scene` painting.
- CloudCarrier behaviour beyond its gate (disabled).
- Test coverage quality (tests were run, not reviewed).
- Build settings, signing, entitlements and the Xcode project structure.
- Third-party code: swift-secp256k1 and the prebuilt Tor binary.
- Real-device behaviour: radios, Bluetooth range, Tor on cellular, background suspension.

## 12. Verification

- **§5.1** — `DLChat/AudioIO/ToneAudio.swift:133-167`: `guard state != .listening` is the only re-entry check; `await withCheckedContinuation` spans setup; `stop()` at 203 only acts on a non-nil `engine`.
- **§5.2** — `Packages/TorKit/Sources/TorKit/Tor.swift:101`: plain `write(control, ...)`; grep for `SIGPIPE|NOSIGPIPE` in `DLChat` and `Packages/*/Sources` returned nothing.
- **§5.3** — `DLChat/Online/OnlineModel.swift:72-75`: `if count > 0 { Task { await self?.flushQueue() } }` on every count change; `202-217` re-seal each queued row.
- **§5.4** — `DLChat/Online/OnlineModel.swift:164-166`: `since: last - 3 days`; `seen` is an in-memory `Set`.
- **§5.5** — `DLChat/Vault/GroupBook.swift:164`: `recordSent` returns when retention is off.
- **§5.6** — `DLChat/NearbyLink/NearbyLink.swift:59-62, 75-78`: `DispatchQueue.main.async` into closures not cleared by `stop()`.
- **§7.1** — `DLChat/Screens/ChatView.swift:16-21`: computed `messages` calls `groups.chatMessages`, which calls `GroupBook.messages` → `loadStore()` → `Vault.readStore()` (`Vault.swift:45-51`, ChaChaPoly open).
- **§8.1** — `DLChat/Screens/SettingsView.swift:30-33`: protected/not-protected bullets precede the first Toggle.
- **§9.1** — `DLChat/Screens/RootView.swift:45-54` and `59-69`: the same discard/clear/wipe/Hygiene calls in two places.
