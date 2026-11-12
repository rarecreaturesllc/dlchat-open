# Design system (Phase 3C)

Approved direction: **C. Console**, picked by the owner 2026-11-02. Source of truth: `DESIGN.md`. Code: `DLChat/Design/Tokens.swift` and `Components.swift`; screens in `DLChat/Screens/RootView.swift`.

## Process, said plainly

| Step | What actually happened |
| --- | --- |
| `/impeccable document` (DESIGN.md) | Not run as a command. I wrote `DESIGN.md` by hand in its format after asking the owner three questions (North Star, colour rules, component feel). No `.impeccable/design.json` sidecar: it renders web HTML and this is native. |
| `/impeccable critique` | Run once on the approved concept, native method (design review only, no detector, no sub-agents). Score 24/40. Snapshot in `.impeccable/critique/`. |
| `/impeccable extract` | Not run as a command. I extracted tokens and components into Swift by hand. |
| `/impeccable polish` | Loaded and followed by hand: critique P1 and P2 findings fixed, then two screenshot rounds and one live interaction check. Snapshot not closed: the file moved, so the fingerprint no longer matches. |

## Tokens

Colours, radii, spacing and sizes are in `Tokens.swift`. Contrast, computed from the hex values: Console White on Night Slate 16.1:1, Haze Blue 8.5:1, Signal Green 9.7:1, Danger Coral 6.8:1 (5.9:1 on Panel Slate). Panel Slate against Night Slate is only about 1.15:1, so fields carry a Haze Blue edge. Measured from values, not from rendered pixels.

## Components and states

| Component | Default | Pressed | Disabled | Focus | Error / empty / loading |
| --- | --- | --- | --- | --- | --- |
| `DLButtonStyle` (primary, secondary, danger) | yes | 97% spring | 40% opacity | n/a | no loading state yet |
| `dlField` | Haze Blue edge | n/a | not designed | Signal Green 2pt edge | not designed |
| `WordChip` | yes | n/a | n/a | n/a | missing word in coral |
| `ModeSwitch` | yes | spring | n/a | n/a | n/a |
| `GroupPill` | yes | none | n/a | n/a | n/a |
| `HoldToWipeButton` | yes | fill over 3 s | n/a | n/a | n/a |
| `ButtonPair` | stacks when text is large | n/a | n/a | n/a | n/a |

Gaps: no loading skeletons, offline or error screens, or toast/undo yet. They belong to the screens that need them in Phase 4 and 5B.

## Evidence

Simulator screenshots (iPhone 18 Pro, iOS 27.0) in `docs/design/screenshots/final-*.png`, including Accessibility XXL text. Checked at XXL: labels wrap or stack instead of truncating, except the Receive result card, which is long but scrolls.

## Not verified

- VoiceOver was not run; labels, hints and the wipe action are written but unheard.
- Hold-to-wipe was built but not exercised in the simulator.
- Receive suggestions were built but not seen working: injected typing lagged and the strip was never shown with a match.
- The keyboard's predictive bar still shows suggestions ("please", "play") on the Receive field. Autocorrect is off; the bar is a simulator and keyboard setting not yet addressed.
- Reduce Motion and Increase Contrast were not tested.
- Two taps were needed to focus the field on a fresh launch via the simulator tool; not investigated.
- Mock word count formula gives 30 words for the doctor message; the blueprint estimates 24. The mock is replaced in T004.
- iPad, landscape and a light appearance were not designed or tested.
