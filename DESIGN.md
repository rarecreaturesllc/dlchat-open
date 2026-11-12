---
name: DLChat
description: The front panel of a handheld radio, for sending and reading private messages as spoken words.
colors:
  graphite: "#0A0C0E"
  panel: "#14181B"
  well: "#040506"
  hairline: "#2A3035"
  edge: "#3B4248"
  bone: "#E1E6E4"
  ash: "#97A19F"
  neon-green: "#39FF14"
  danger-coral: "#FF7366"
typography:
  display:
    fontFamily: "Manrope"
    fontSize: "54pt (scales, shrinks to fit)"
    fontWeight: 700
  readout:
    fontFamily: "SF Mono"
    fontSize: "42pt (scales, shrinks to fit)"
    fontWeight: 600
  title:
    fontFamily: "Manrope"
    fontSize: "Title 2 (22pt, scales)"
    fontWeight: 600
  body:
    fontFamily: "Manrope"
    fontSize: "Body (17pt, scales)"
    fontWeight: 400
  label:
    fontFamily: "Manrope"
    fontSize: "Headline (17pt, scales); Title 3 bold on bars; Footnote semibold on keys"
    fontWeight: 600
  legend:
    fontFamily: "SF Mono"
    fontSize: "Footnote or Caption (scales), uppercase, tracking 0.4"
    fontWeight: 600
rounded:
  tag: "3pt"
  inner: "4pt"
  key: "8pt"
spacing:
  xs: "8pt"
  sm: "12pt"
  md: "16pt"
  lg: "20pt"
stroke:
  hair: "1pt"
  field: "1.5pt"
  strong: "2pt"
motion:
  press: "spring, 200ms (a key going down 3%)"
  move: "snappy, 250ms (tab highlight, a new log line, the next three words)"
  exit: "ease-out, 200ms (leaving or settling back; a fifth shorter than move)"
components:
  bar-primary:
    backgroundColor: "{colors.neon-green}"
    textColor: "{colors.graphite}"
    rounded: "{rounded.key}"
    height: "64pt"
  bar-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.bone}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
    height: "64pt"
  bar-danger:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.danger-coral}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
    height: "64pt"
  key:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.bone}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
    height: "64pt, icon over label"
  readout:
    backgroundColor: "{colors.well}"
    textColor: "{colors.bone}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
  word-chip:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.bone}"
    border: "1pt {colors.hairline}"
    rounded: "{rounded.key}"
    height: "48pt"
  word-chip-missing:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.danger-coral}"
    border: "2pt {colors.danger-coral}"
    rounded: "{rounded.key}"
    height: "48pt"
  field:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.bone}"
    border: "1.5pt {colors.ash}; 2pt neon-green when focused"
    rounded: "{rounded.key}"
    padding: "18pt"
  bubble-mine:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.bone}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
    align: "trailing"
  bubble-theirs:
    backgroundColor: "{colors.well}"
    textColor: "{colors.bone}"
    border: "1pt {colors.edge}"
    rounded: "{rounded.key}"
    align: "leading"
  tag:
    backgroundColor: "the friend's call sign colour; outline only for YOU"
    textColor: "{colors.graphite}"
    rounded: "{rounded.tag}"
---

# Design System: DLChat

## Overview

**Creative North Star: "Faceplate"** (owner pick, 2026-11-10, from three directions on the design review page; it replaces "Blackout Signal")

DLChat looks and behaves like the front panel of a handheld radio: squared keys with fine bezels, a recessed readout for numbers, legends in small mono capitals, and every chat as a transmission log. It is used in the dark, outdoors, with one hand busy holding a radio, often by someone stressed. The system removes decisions rather than adding polish.

Everything sits on near-black graphite. Controls are slightly lighter panels with a hairline bezel. Two soft colours (graphite and bone) carry the screen; one loud neon green says "do this" or "this is live", and a single coral says "something is wrong or destructive". Motion is short and physical and never decorates.

**Key Characteristics:**
- Message on top in a compact box, the control deck straight under it: the readout, the keys, and one green bar.
- Controls are at least 48pt; bars and keys are 64pt, so gloves work.
- Dark only in v1 (a deliberate choice for night use). The app forces the dark appearance; a light theme is a later decision.
- Words are the content: when a word is being read aloud it is shown at display size.
- No gradients, no glass, no shadows and no glow.

## Colors

Graphite and bone, one neon green and one coral, each with exactly one meaning. Contrast figures are measured (WCAG).

### Primary
- **Neon Green** (#39FF14): the single primary action on a screen, live connection, progress and "verified" states. Graphite text on it is 14.4:1; green on graphite 14.4:1.

### Secondary
- **Danger Coral** (#FF7366): a missing word, a message that will not go out, and anything destructive (wipe). 7.4:1 on graphite, 6.7:1 on panel. Always paired with words or a warning triangle, never colour alone.

### Neutral
- **Graphite** (#0A0C0E): the screen background.
- **Panel** (#14181B): keys, modules, fields, chips, and the band behind your own lines in a log.
- **Well** (#040506): the recessed readout window only.
- **Bone** (#E1E6E4): main text and the selected tab. 15.5:1 on graphite, 14.2:1 on panel.
- **Ash** (#97A19F): secondary text, legends and field edges. 7.4:1 on graphite, 6.7:1 on panel.
- **Hairline** (#2A3035): module edges and the rule under each log row.
- **Edge** (#3B4248): the bezel of a key or secondary bar (1.9:1 on graphite: a bezel, never the only sign of a control; Increase Contrast swaps it for a 2pt Ash line).

Call sign colours (eight, `CallSignPalette`) carry graphite letters at 9.6:1 or better.

### Named Rules
**The One Loud Colour Rule.** Neon green means go, live or verified; coral means missing or destructive. Secondary bars and keys are bone on panel, never green, and navigation (the "Chats" back link) is bone, so green on screen always means the one next step.

**The Edge Rule.** A control's boundary cannot rely on Panel against Graphite alone (1.1:1). Fields carry a 1.5pt Ash edge; keys, bars and chips carry an Edge or Hairline bezel.

## Typography

**Text:** Manrope (bundled variable font, SIL Open Font License; `DLChat/Design/Fonts`), through `Font.dl(...)`, which scales with Dynamic Type. It is used for everything a person wrote or has to read as a sentence.
**Data and legends:** SF Mono (system), through `Font.dlMono(...)` and `.dlCaps(...)`. It is used only for data and panel legends: times, counts, the readout, tab labels, status and route lines, PIN digits.

### Hierarchy
- **Display** (Manrope bold, 54pt, shrinks to fit): the three words being read aloud, one per line.
- **Readout** (SF Mono semibold, 42pt, shrinks to fit): the number in a readout window.
- **Title** (semibold, Title 2): messages and screen headings.
- **Body** (regular, Body): instructions, notes and chat text.
- **Label** (bold Title 3 on bars; semibold Footnote on keys; semibold Headline elsewhere).
- **Legend** (SF Mono semibold, Footnote or Caption, uppercase, tracking 0.4): tabs, the readout's lines, Chat status, the route under a log line.

### Named Rules
**The System Text Rule.** All sizes follow Dynamic Type. Display and Readout also shrink with `minimumScaleFactor`, never truncate.

**The Mono Rule.** Mono is for data and legends. A sentence is never set in mono, and legends pass their text already uppercased while the accessibility label stays in normal case.

## Layout

A single column with 16pt side margins, 16pt between blocks, 8pt between keys in a row. On Send and Receive the message box is compact (four lines; longer text scrolls inside, so the deck never moves while typing) and the deck (readout, keys, primary bar) sits straight under it (owner request, 2026-11-11). With the keyboard open the page scrolls and the field stays in view. Rows of keys and side-by-side bars stack vertically at accessibility text sizes. The Send / Receive / Chat / Map slider sits at the top under the group key, which is at the top left; at the largest text sizes the group key gets its own row. Safe areas are always respected.

## Elevation & Depth

Flat. Depth comes from three tonal steps: the Well (recessed), Graphite (the panel face), Panel (a key standing proud). The only lift is a press: a 3% scale-down on a 200ms spring. No shadows, blur, glass or glow.

## Shapes

**The shape lock.** Keys, bars, modules and fields are 8pt continuous rounded rectangles. Anything nested 4pt inside one (the tab highlight, Chat's Send key, colour swatches) is 4pt. Tags (call signs, YOU, unread counts) are 3pt. There are no pills. The only circles are status lights and points on the map.

## Icons

SF Symbols only, outlined by default, in the text colour of their control. A key carries one symbol over its label; section headings carry none. Filled variants are for state (lock, read-once on) or a warning.

## Components

### Bars (`DLButtonStyle`)
- **Shape:** 8pt corners, 64pt minimum height, full width or split evenly.
- **Primary:** Neon Green fill, Graphite bold Title 3 label. One per screen, lowest on the page.
- **Secondary:** clear with an Edge bezel and a Bone label.
- **Danger:** Panel fill with a Danger Coral label, for wipe only.
- **Press / Disabled:** press scales to 97%. Disabled turns any bar into a Panel bar with Ash ink and a hairline, legible but plainly not ready. In-progress shows a label change, not a spinner.

### Keys (`DLKeyStyle`, `KeyLabel`, `KeyRow`)
A 64pt Panel key with an Edge bezel, one symbol over a Footnote label. Used in a row for the other carriers on Send (Encrypt words, Encrypt sound, Show QR code) and the other ways in on Receive (Listen, Scan QR, Open a sound file). The row stacks at accessibility sizes.

### Readout (`Readout`) (signature)
A Well window with an Edge bezel: a number in SF Mono and up to two legend lines. Send shows "19 WORDS TO SAY / TO MAPLE STREET"; Encrypt Sound shows the seconds of sound; the PIN pad uses the same window for the digits keyed so far. The number rolls when it changes; with Reduce Motion it changes at once.

### Chat bubbles (`LogRow`, `CallSignBadge`)
Every chat (group, Meshtastic, Internet Messages) is laid out like Messages (owner request, 2026-11-11): your messages on the right on a raised Panel key, everyone else's on the left in a recessed Well, both with an Edge bezel and 8pt corners. Sides differ by place and fill, never by colour alone. A friend's call sign tag (or radio name) heads their bubble where there is more than one other person; then what was said in Body, how it travelled in a caps legend ("SENT 3 RELAYS VIA TOR", "WAITING FOR A CONNECTION"), and the day and time in mono at the foot. A message that will not go out turns its legend coral with a warning triangle. Long press gives Copy, Reply, Delete; swipe right replies. A tap on encrypted words or an encrypted sound opens a small menu on that bubble (Copy, Decrypt) and nothing else; a tap outside closes it.

### Meters (`SegmentMeter`, `DLMeterStyle`)
The read-out's progress is one segment per group of three words, lit green up to the current one, with the count beside it. Playback and microphone level are a squared bar.

### Word chips
Panel fill, 8pt corners, 48pt height, semibold callout. Missing: Danger Coral label and a 2pt coral edge, labelled "?" and announced as "word N missing".

### Fields
Panel fill, 8pt corners, 18pt padding, Title 2 text. Focus: Neon Green 2pt edge. At rest: 1.5pt Ash edge (Edge Rule).

### Navigation
A four-segment slider at the top (Send, Receive, Chat, Map) with mono caps labels: the selected segment is a Bone key with Graphite text that slides between segments, so green stays reserved. The top bar holds only Lock and Settings, squared keys at top right. Groups, Internet Messages and Meshtastic chats are reached from the Chat tab alone; its drawer ends the group section with "Manage groups", which opens the group list as a sheet. Only the highlight animates when switching; the screen below swaps at once.

An open conversation goes back to the Chats list by its "Chats" link or by a swipe right from the left edge, which follows the finger (`EdgeSwipeBack`; Reduce Motion swaps at once). The connection status at the top of a chat is one folded line that opens only when tapped, over the messages, so the list never moves. Manage (the group list) is a small caps key in the DL Group Chats header.

### Hold-to-wipe
A Panel bar with a Danger Coral label. Pressing and holding for 3 seconds fills it left to right and then wipes with a warning haptic; releasing early cancels. VoiceOver gets a "Wipe everything now" action, because holding is a gesture. It is on the lock screen and in Safety, as before.

### Read-out
One group of three words at Display size, centered, with the segment meter and count at the top and Back/Next at the bottom. The group slides in from the trailing edge and the previous one fades out in 250ms; Reduce Motion uses a crossfade.

## Motion

Three tokens (`DLMotion`): `press` (200ms spring), `move` (250ms snappy) and `exit` (200ms ease-out, for leaving or settling back). Frequent actions (tab switch, typing, scrolling) use the platform default. Every animated change has a Reduce Motion path that changes at once or cross-fades. Nothing loops and nothing animates for decoration. Secret content (a held phrase or its QR code) may fade in but never fades out: it is gone the instant the finger lifts. Keys that draw their own face (PIN digits, the top bar, Chat's Send key) take `DLPressStyle`, the same 3% press as a bar. Haptics go through `Haptics` (tap, select, warn, success, error); success and error fire only once the outcome is known. Every component and gesture is listed in `docs/interaction-matrix.md`.

## Do's and Don'ts

### Do:
- **Do** keep one Neon Green primary action per screen, at the bottom.
- **Do** make every tappable control at least 48pt, bars and keys 64pt.
- **Do** put a visible edge on text fields (Ash, 1.5pt) and a bezel on keys.
- **Do** give every gesture a button alternative.
- **Do** keep copy plain and short, in sentence case: say what is protected and what is not.

### Don't:
- **Don't** use green or coral as decoration.
- **Don't** add pills, shadows, gradients, glass, blur or glow.
- **Don't** set sentences in mono.
- **Don't** hide the wipe action or make it a one-tap.
- **Don't** call anything "secure", "unbreakable" or "military-grade" in copy.
