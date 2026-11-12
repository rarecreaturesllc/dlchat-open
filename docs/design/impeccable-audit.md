# Final Impeccable audit (Phase 6)

Date: 2026-11-06. Tool: Impeccable 4.6.0, `/impeccable audit` using the native iOS checks (`audit.native.md`, `ios.md`). Run by Opus 5.5. Nothing was changed by this audit.

Method:
- Read the source of `DLChat/Design` and `DLChat/Screens`, and scanned it for fixed sizes, raw colors, motion, gestures and truncation.
- Captured 8 screens in the iPhone 18 Pro simulator (iOS 27) with `-seed-demo`, at the default text size and at accessibility-extra-extra-large. The contact sheets are `docs/design/screenshots/final-audit-large-{a,b}.png` and `final-audit-acces-{a,b}.png`.
- Screens captured: Send, Receive, Groups, read-out, Play as sound, QR, Settings, Nearby.
- Not captured: lock screen, Practice, History, group detail, Safety, the Listen and Scan cameras, and any Increase Contrast or Reduce Motion run.

All evidence comes from the simulator; nothing was checked on hardware.

## Audit health score

| # | Dimension | Score | Key finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 3 | Labels, targets and text scaling hold up. The read-out word slide ignores Reduce Motion. VoiceOver was never run |
| 2 | Performance | 3 | Small, simple screens. Nothing was profiled; real-time tone decoding was not measured on a device |
| 3 | Appearance & Theming | 3 | All colors come from one token file. Dark only on purpose, but `PRODUCT.md` still says light is supported |
| 4 | Platform Conformance | 3 | System sheets, lists, swipe actions, context menus, confirmation dialogs, Toggle and SF Symbols are used. Close and Done controls are styled inconsistently |
| 5 | Adaptivity | 3 | iPhone, portrait only, by stated design (`DESIGN.md`). Long screens scroll at the largest text. iPad compatibility mode was not checked |
| **Total** | | **15/20** | **Good** |

## Platform conformance verdict

**Pass.** It reads as a native iPhone app, not a ported website.
- Sheets carry real navigation bars, lists use system swipe and context menus, and destructive choices use system confirmation dialogs.
- The custom Send/Receive switch replaces a segmented control. That was a deliberate owner choice for glove use (64 pt, high contrast), not drift.
- Full-screen screens (read-out, sound, QR, Nearby) use a custom header with a text "Close" instead of a navigation bar. That fits full-screen covers, but it looks different from the sheets' Done buttons.

## Executive summary

- Score 15/20 (Good). Issues: P0 0, P1 0, P2 4, P3 3.
- The top issues are: the read-out ignores Reduce Motion; at the largest text size the read-out progress bar shrinks to a sliver and button labels touch their edges; `PRODUCT.md` and `DESIGN.md` disagree on light mode.
- Next: `/impeccable animate` for Reduce Motion, `/impeccable adapt` for the largest text size, and an owner decision on light mode, then `/impeccable polish`.

## Findings

**[P2] The read-out slide ignores Reduce Motion**
- Location: read-out, `DLChat/Screens/RootView.swift:285` (`.move(edge: .trailing)` transition with `withAnimation(.snappy)` at 291 and 294); Practice uses the same pattern, `PracticeView.swift:116,119`.
- Category: Accessibility.
- Impact: every word group slides in from the side. People who turned on Reduce Motion to avoid exactly that still get it, on the screen they stare at longest.
- Guideline: HIG Motion, honor Reduce Motion with a crossfade.
- Recommendation: read `accessibilityReduceMotion`, the way `HoldToWipeButton` already does, and use `.opacity` only.
- Command: `/impeccable animate`.

**[P2] At the largest text size the read-out progress bar nearly disappears**
- Location: read-out header, `RootView.swift:270-275`; screenshot `final-audit-acces-a.png`, fourth phone.
- Category: Adaptivity / Accessibility.
- Impact: the counter, Safety button and a fixed-size "Close" take the whole row, so the bar shrinks to about a fifth of the width. The "3/5" text still carries the information, so this is not blocking.
- Recommendation: at accessibility sizes, put the bar on its own row (`ViewThatFits`, as the main top bar already does).
- Command: `/impeccable adapt`.

**[P2] Button labels run edge to edge at the largest text size**
- Location: `DLButtonStyle`, `DLChat/Design/Components.swift:16-21` (vertical padding only); also the mode switch, `Components.swift:81-85`; screenshot `final-audit-acces-a.png` ("Show the words", "Receive").
- Category: Adaptivity.
- Impact: text touches the rounded edges, which looks broken and is harder to read at a glance in the dark.
- Recommendation: add horizontal padding of `DLSpace.md` inside the button style and the switch.
- Command: `/impeccable adapt`.

**[P2] Light mode: the product brief and the design system disagree**
- Location: `PRODUCT.md` (Accessibility: "dark-first with light supported") vs `DESIGN.md` ("Dark only in v1", `preferredColorScheme(.dark)` in 12 places).
- Category: Theming.
- Impact: someone reading the brief expects a light theme that does not exist. Bright daylight outdoors is a real use, so this is a product decision, not just a typo.
- Recommendation: the owner decides. Either change `PRODUCT.md` to say dark only in v1, or plan a light theme later. No code change until then.
- Command: `/impeccable document` once decided.

**[P3] Close and Done controls look different across screens**
- Location: full-screen covers use `Button("Close")` with `.font(.headline)`, which is not the rounded house font (`RootView.swift:274`, `QRView.swift:20`, `TonesView.swift:22`, `NearbyView.swift:22`). Settings uses a plain text "Done"; Groups uses the system toolbar Done.
- Category: Conformance.
- Impact: small, but it makes the app feel assembled from parts.
- Recommendation: use `.font(.dl(.headline))` for Close, and use the toolbar Done in Settings like Groups.
- Command: `/impeccable polish`.

**[P3] The QR screen has no title**
- Location: `QRView.swift:15-22`; screenshot `final-audit-large-b.png`.
- Category: Conformance.
- Impact: Play as sound and Nearby open with a title; QR does not, so the screen starts without saying where you are.
- Recommendation: add the title "QR code" in the same header style.
- Command: `/impeccable polish`.

**[P3] "Missed one: add ?" wraps at the default text size**
- Location: Receive, `ReceiveView.swift`; screenshot `final-audit-large-a.png`.
- Category: Accessibility (copy).
- Impact: a two-line label next to a one-line "Undo" reads unevenly, and "add ?" is cryptic aloud.
- Recommendation: shorter copy, such as "Missed a word". VoiceOver already reads the chip as "Missing word".
- Command: `/impeccable clarify`.

## Patterns and systemic issues

- Motion: one screen honors Reduce Motion (the wipe bar) and the two slides do not. The pattern exists but is not applied everywhere.
- Header controls on full-screen covers are re-typed on each screen instead of coming from one component. That is why the fonts drift.

## Positive findings

- **Tokens:** raw hex appears only in `Tokens.swift`, and screens add no styling of their own.
- **Text styles:** all text uses scaled system text styles. The three display sizes use `@ScaledMetric`.
- **Scrolling:** every long screen scrolls at accessibility-extra-extra-large, so nothing is cut off for good.
- **Targets:** the smallest is 48 pt, primary actions are 72 pt, and the keypad keys are 64 pt. That is glove-friendly as briefed.
- **Gesture alternatives:** every gesture has a non-gesture or VoiceOver alternative. That covers hold to wipe, hold to reveal, the pressure mark (also a Safety toggle), swipe actions (context menus and actions) and reorder (Move up and down).
- **Increase Contrast:** components add edges when the user turns on Increase Contrast. This was not seen on screen.
- **Color discipline:** green stays reserved for the one primary action, and coral is used only for danger and missing words.

## Recommended actions

1. **[P2] `/impeccable animate`**: crossfade instead of slide under Reduce Motion on the read-out and Practice.
2. **[P2] `/impeccable adapt`**: give the read-out progress bar its own row at accessibility sizes, and add horizontal padding to buttons and the mode switch.
3. **[P2] Owner decision, then `/impeccable document`**: decide dark only or light later, and make `PRODUCT.md` and `DESIGN.md` agree.
4. **[P3] `/impeccable clarify`**: the "Missed one: add ?" label.
5. **[P3] `/impeccable polish`**: Close/Done consistency and the QR title, as the final step.

None of these block Gate A. They should be fixed before release screenshots are made.

## Fixes after the audit (2026-11-06)

The owner approved fixing the three code-level P2 findings.

| Finding | Fix | Where |
|---|---|---|
| Read-out slide ignores Reduce Motion | With Reduce Motion on, word groups crossfade (`.opacity`) instead of sliding. Correction: Practice never had a slide (no `.transition` or `.id`, the words change in place), so it needed no change | `RootView.swift`, `TeleprompterView` |
| Progress bar shrinks at the largest text | At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`) the counter, Safety and Close sit on one row and the bar gets a full-width row under them | `RootView.swift`, `TeleprompterView` header |
| Button labels touch their edges | `DLSpace.md` horizontal padding inside `DLButtonStyle` and each `ModeSwitch` segment | `Components.swift` |
| Knock-on: the padding split "Back" into "Bac / k" in its 140 pt slot | At accessibility sizes Back is uncapped and shares the row evenly with Next | `RootView.swift`, `PracticeView.swift` |

Evidence: 104 unit and 16 UI tests passed before the Back change; after it the app built and was checked by screenshot only. The contact sheet `docs/design/screenshots/audit-fixes-acces.png` shows the read-out, Send and Practice at accessibility-extra-extra-large. Reduce Motion was not switched on in the simulator, so the crossfade was checked by reading the code only.

Light mode: the owner decided dark only in v1 (2026-11-06); `PRODUCT.md` now matches `DESIGN.md`. The owner then approved the three P3 items (2026-11-06):

| Finding | Fix |
|---|---|
| Close and Done look different | Every custom-header Close now uses the house font `.dl(.headline)`, the same as the custom-header Done in Settings, Safety and Practice. Sheets with a system navigation bar (Groups, History) keep the system Done. Settings was not moved to a toolbar: it already matched the custom-header pattern |
| QR screen has no title | Header now reads "QR code", styled like "Play as sound" |
| "Missed one: add ?" wraps and is cryptic | Visible label "Missed one", VoiceOver label "Missed a word" (Receive and Practice, plus the Practice instruction). "Missed a word" still wrapped once buttons gained horizontal padding |

Evidence: 104 unit and 16 UI tests passed before the final label shortening; after it the app built and was checked by screenshot. Contact sheet `docs/design/screenshots/audit-polish.png` (QR, Receive, Play as sound at the default size). All audit findings are now closed.
