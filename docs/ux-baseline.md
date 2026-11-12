# Expected Behaviors Baseline

Item text: `~/.claude/skills/new-app/references/ux-baseline.md`.
One row per item. N/A needs a reason; silence is not N/A. Missing rows
without a reason block Gate A.

Audit run in T020 (2026-11-03) from a code grep of `DLChat/` and prior screenshots. Platform: iPhone only, iOS 17+, portrait only, dark only (`DESIGN.md` line 94), no network, no accounts.

| Item | Status (present / missing / N/A) | Reason | Evidence (file:line or screenshot) |
| --- | --- | --- | --- |
| Drag-to-reorder for orderable lists | present | Group list has EditButton reorder plus VoiceOver Move up/down (T023) | `Screens/GroupListView.swift`; `GroupBookTests` |
| Long-press context menu on items | present | Group rows have context menus (T023). The History list was removed 2026-11-09 at the owner's request (messages live in each group's Chat) | `GroupListView.swift` |
| Swipe actions on rows | present | Trailing swipe deletes a group (with confirmation) (T023). Deleting a single message went with the History list (2026-11-09); retention and wipe still erase messages | `GroupListView.swift` |
| Pull-to-refresh | N/A | No remote data; the app has no network | `HygieneTests` network scan |
| Pinch / double-tap zoom | N/A | No photos, maps or canvases; QR codes are shown large and fixed, and the camera scanner is full screen | `Screens/QRView.swift`, `t013-qr.png` |
| Text fields: keyboard dismiss, Return, keyboard type, autofill | present | `scrollDismissesKeyboard`, `submitLabel`, `asciiCapable` for words, `numberPad` for PINs, autofill off (`textContentType(.none)`) and autocorrect off by design | `ReceiveView.swift:36-38,78`; `SafetyView.swift:64,71`; `GroupSetupView.swift:50,72-94` |
| Undo instead of confirm for destructive actions | present (by confirmation) | Undo is impossible for these: wipe is hold-to-confirm; a shorter retention and group removal ask first with a confirmation dialog (T025, T023), which the baseline allows when undo cannot work | `Components.swift` (`RetentionPicker`, `HoldToWipeButton`); `SafetyView.swift`; UI test `testShorterRetentionAsksFirst` (Remove PIN was dropped 2026-11-09: the PIN is required) |
| Autosave drafts | present | Draft survives kill and relaunch, stored in the sealed store | T008 acceptance; `Vault/ComposeModel.swift`; activity T008 |
| Shake / Cmd-Z undo and redo | N/A | Entry has its own Undo button for the last word. System shake undo is left out on purpose: a jostled phone in the field should not undo typing. No Cmd-Z: iPhone only, no hardware keyboard target (`docs/audit-opus.md`) | `ReceiveView.swift:59`; `PracticeView.swift:180` |
| Designed loading, empty, error and offline states | present (partly) | Offline is the normal state (no network). Empty states exist for Receive and Export; errors are shown for bad checksum, wrong key and repair. No skeletons, because nothing loads from remote; sealed-store reads are local and quick. Denied microphone and camera screens exist in code only, not seen in screenshots | `t009-receive-empty.png`; `SettingsView.swift` (empty export); activity T016 "Not verified" |
| Optimistic UI with rollback | N/A | No remote actions to fail; local writes happen before the UI moves on | No network code |
| Haptics on meaningful events only | present | Used for wipe warning, wrong PIN, tone sent, QR scanned, group created, phrase QR hold; none on taps or typing | `Components.swift:124`; `LockView.swift:68,71`; `TonesView.swift:103`; `QRView.swift:75,118`; `GroupSetupView.swift:161`; `RootView.swift:160` |
| Buttons show pressed, disabled and in-progress states; no double-submit | present (partly) | Pressed state (spring scale) and disabled states exist; there is no in-progress state because actions are instant. Double-submit guard on send not separately tested | `Components.swift:21`; `ReceiveView.swift:59` |
| Search on collections over ~15 items | N/A | The searchable History list was removed 2026-11-09 (owner's request); Chat shows each group's messages in order | `ChatView.swift` |
| Sort and filter, choice remembered | N/A | Chat is in time order with no sort or filter choice to remember; rooms are separate stores, not a filter (`docs/audit-opus.md`) | `ChatView.swift` |
| Back swipe works; deep links; state restoration | present (partly) | Sheets and navigation use system back and dismiss. Deep links are N/A on purpose: no URL scheme, so no link handler attack surface (`docs/audit-opus.md`). Drafts and groups restore after relaunch; the open screen does not (the lock screen asks for the PIN first) | Grep: no `onOpenURL`, no `SceneStorage` |
| Keyboard shortcuts and menu-bar commands | N/A | iPhone only, portrait only (`TARGETED_DEVICE_FAMILY = 1`) | `project.pbxproj` build settings |
| Share sheet, copy, export | present | ShareLink for text export; Copy text uses a local-only expiring pasteboard; QR for messages and phrase | `SettingsView.swift:46`; `Shared/Hygiene.swift:10`; `ReceiveView.swift:135` |
| Dark mode | present (dark only) | Dark appearance is forced on purpose for night use; light theme is a recorded later decision, so system light mode is not followed | `DESIGN.md` line 94; `.preferredColorScheme(.dark)` on every screen |
| Dynamic Type | present | System text styles; checked at accessibility-extra-extra-large on Compose, Receive, Tones, Listen, Nearby, Practice, Settings. T025: top bar stacks (icons row, pill below) and Send scrolls when it does not fit; button labels wrap instead of truncating | `t025-main-axxl.png`, `t025-main-axxxl.png` (before the fix, labels truncated); `RootView.swift` |
| Reduce Motion | present (partly) | The hold-to-wipe ring respects it; other animations are short springs of 0.2 s | `Components.swift:106,117`; `QRView.swift:81` |
| High contrast | present | With Increase Contrast on, pills, icon buttons, secondary buttons, chips, mode switch and fields get a 2 pt Soft edge (T025). Not seen on a device: no UI test turns Increase Contrast on | `Components.swift` (`colorSchemeContrast`); `SafetyView.swift`; `SettingsView.swift` |
| VoiceOver labels | present (partly) | Icon controls, tiles, progress and keypad are labelled; the duress flag has an accessibility action. No device VoiceOver pass done | Source lines in `compliance-checklist.md` row 13; `RootView.swift:179` |
| 44pt minimum targets | present | `DLSize.control` frames on bars; main buttons 72pt high | `SafetyView.swift:22`; `SettingsView.swift:22,116`; `DESIGN.md` line 156 |
| Every gesture has a non-gesture alternative | present | Hold-to-wipe has a VoiceOver action. The hidden duress press now has a visible toggle in Safety (T025); hold to show phrase has a label but no tap alternative on purpose (it must not stay visible) | `Components.swift`; `SafetyView.swift`; `QRView.swift:77`; launch blocker 10 |
| Safe areas, landscape, iPad, locale | present (partly) | Portrait iPhone only by design, so landscape and iPad are N/A. Safe areas respected in screenshots. English only in v1 (PRD non-goals), so locale and units do not apply to text; times use the system format | `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`; `prd.md` non-goals |
| Notifications opt-in in context | N/A | The app sends no notifications and requests no notification permission | Grep: no `UNUserNotificationCenter` in `DLChat/` |
| Settings: export, account deletion, privacy controls | present | Export as text, hold-to-wipe, retention, privacy and terms documents. No account deletion because no accounts exist (stated in Settings) | `SettingsView.swift`; `t019-settings.png` |
| Animations 150-300 ms, interruptible, spring | present | 0.2 s springs and ease-outs | `Components.swift:21`; `QRView.swift:81` |
| Onboarding skippable, under 3 screens | present | No onboarding; first run shows the practice drill option and the single radio-rules notice, which can be declined. First-run value comes before any sign-up (none exists) | `Shared/RadioNotice.swift`; T018 UI tests |
| Sensible defaults, remember last choices | present (partly) | Retention default 7 days and stored; nearby off by default. Whether the last-used group is reselected and the word count (10, 15, 20) for a new group are not remembered or not verified | `docs/data-inventory.md`; `GroupSetupView.swift` |

## Accessibility audit

`UXBaselineUITests.testAccessibilityAuditOnTheMainScreens` runs `performAccessibilityAudit()` on Send, Receive, Settings (top and scrolled) and Safety. It passes with three recorded exceptions:

1. Dynamic Type findings on buttons and text inside a `ViewThatFits` (top bar, `ButtonPair`, Send screen). The audit changes the text size, the layout swaps, and the audit reports the font as unsupported; which element it names varies by run. Not proven to be a false positive, only unexplained; the AXXL and AXXXL screenshots show the labels scaling. The audit did find one real problem, fixed here: button labels truncated at the largest sizes and a clipped placeholder in the Receive word field.
2. Contrast on disabled controls (dimmed Undo, Set PIN): exempt under WCAG 1.4.3.
3. Contrast on an element cut off by the screen edge or by the edge of the Settings scroll view (2026-11-09: the Notifications row at the bottom of Settings once the Call sign section pushed it down, and a note half-scrolled under the top of the sheet). The audit measured the half-hidden text against what lies past the edge. Settings is now audited at the top and twice more after scrolling, so every row is also checked fully on screen.

Not run: audit on the lock screen, Tones, QR, Nearby, Practice, group list, History and document screens; no VoiceOver pass on a device.

## Summary

Updated in T025. Of 31 rows: missing 0. Rows still "present (partly)" or open: VoiceOver pass, hardware-keyboard check and a device check of high contrast (see launch blocker 16). N/A with reasons: pull-to-refresh, zoom, optimistic UI, keyboard shortcuts, notifications, shake undo, sort and filter memory.