# Design directions (Phase 3B)

Built by Sonnet 2026-11-02. Three native SwiftUI concepts of the same flow: create group, compose with live word count, read-out, decode. Same sample data in all three (`DLChat/Shared/Mock.swift`); the words and "encryption" are placeholders, nothing is encrypted. The sample word list repeats some words ("yew"); the real 1024-word list has none.

Screenshots: `docs/design/screenshots/{A,B,C}-{create,compose,readout,decode}.png`, iPhone 18 Pro simulator (iOS 27.0), captured with `xcrun simctl io`, status bar fixed at 9:41. Reproduce: `-concept A|B|C -screen create|compose|readout|decode`. Run with no arguments to flip between concepts.

## A. Night Watch

- **World:** dim amber on near-black, for use in the dark without ruining night vision. Wide, heavy headings.
- **Interaction:** system tab bar (Send, Receive, Group). The read-out is a checklist of 3-word lines; the current line is boxed and finished lines dim and strike through. Tap a line or Next.
- **For:** people outdoors at night, preppers and hams who like instruments.
- **Tradeoffs:** one colour carries everything, so warning states lean on a red that clashes with the amber. Dark only: poor in direct sun. Strikethrough on read lines is heavy.

## B. Logbook

- **World:** warm paper, serif type, ink blue. A ledger of what the group has said; read-out set as numbered printed lines.
- **Interaction:** navigation stack from the group log; compose and decode are pushed screens. The calmest of the three, and reads like a document, not a gadget.
- **For:** daylight, older and less technical neighbors, a calm community feel.
- **Tradeoffs:** light only here, so it glares at night and drains OLED phones in the dark. Smaller buttons (56 pt) and a lot of reading: slowest under stress. Read-out shows all lines at once, so it is easier to lose your place.

## C. Console

- **World:** cool slate with signal green and rounded type. One giant action per screen, built for gloves.
- **Interaction:** Send/Receive switch at the bottom, 72 pt buttons, and a teleprompter that shows one group of three words enormous at a time, with progress and Back/Next. Group info lives in a top chip and a sheet.
- **For:** stressed, one-handed use; the fewest decisions per screen.
- **Tradeoffs:** most "app-like", so it looks closest to other chat apps. One group at a time means no overview of the whole message. The segmented switch is the smallest target on screen.

## Not done, said plainly

- Impeccable's `shape`, `critique` and `audit` were **not run**. In lean mode critique runs once on the approved concept. The brief was `PRODUCT.md` and `prd.md`. I read Impeccable's `ios.md` and `craft-floor.md` and applied them while building.
- One build holds all three concepts, not one git worktree per option, because they share a project and a native build is slow. All sit on `feat/dlchat-foundation`, in `DLChat/Concepts/{A,B,C}`; the losers are deleted after you pick.
- Screenshots are dark/light as each concept chooses. Dynamic Type at large sizes and VoiceOver were not checked. Targets are meant to be 44 pt or more but were not measured.
- Opus writes the recommendation (`docs/design/comparison.md`); it does not exist yet.

## Decision

Owner picked **C. Console** on 2026-11-02. A and B were deleted from the source tree (they remain in git history at commit 203d84b, and their screenshots stay in `docs/design/screenshots/`). Opus has not written `comparison.md`; the owner chose without it.
