# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI with CryptoKit. No network code, no AI, no third-party services. Chosen by the user at intake.

## Users

Neighborhood groups, families and preparedness-minded households who want private messages that keep working when cell service or the internet is down. Mostly non-technical, often stressed, frequently outdoors, in low light, one-handed or wearing gloves. Technical hobbyists (hams, preppers) are a secondary audience; the default flow serves the neighbor first.

## Product Purpose

DLChat lets a group message privately in person, over the internet through Tor, or through their own Meshtastic radio. A group shares a generated secret phrase of 10, 15 or 20 words. The app derives a key from it, encrypts a message, and renders the result as gibberish words that can be read out, as a sound another phone can hear, as a QR code, or as a sealed packet for relays or the radio. Only phrase holders can decrypt. (Updated 2026-11-12: DLChat is no longer pitched for voice radios.)

## Positioning

Works with nothing but a shared phrase: no accounts, no servers of its own, and paths that keep working when the network is down (in person, QR, Meshtastic). A chat app that needs a working network or an account cannot truthfully make that claim.

## Operating Context

Power or cell outage, or simply wanting privacy from networks. Messages are read out as word lists or played as sound between phones nearby, shown as QR, posted through relays over Tor, or sent through the person's own Meshtastic radio.

## Capabilities and Constraints

- Fully offline and local-only. Phrases and history live on device; Keychain for secrets.
- Transports in scope (user's choice, may be staged by the blueprint): words, audio tones, Bluetooth/Multipeer, QR.
- Security in scope (user's choice): key derivation from the phrase, authenticated encryption, safety number, replay protection, panic wipe, duress/room word.
- No forward secrecy is possible with a shared static phrase; the app must say so plainly.
- Real-radio audio reliability and Bluetooth range cannot be verified in Simulator; they are recorded as untested until run on devices.
- App Store distribution requires encryption export-compliance answers.
- Free; no accounts; no analytics.
- Phrase length is 10, 15 or 20 words; the default is 15 (see `docs/blueprint.md`).

## Brand Commitments

Name: DLChat (user's choice). No logo, domain, or brand assets exist yet; an Apple developer account is available.

## Evidence on Hand

None. No reviews, testimonials, benchmarks, or usage data exist and none may be invented. No reference apps were chosen.

## Product Principles

1. Works with only a phrase and a radio; every extra transport is optional.
2. Never overstate security: state limits (no forward secrecy, device seizure) in plain words.
3. Usable under stress: one primary action per screen, large targets, readable in the dark.
4. Nothing leaves the device unless the user chooses to transmit it.
5. Fast to wipe: the panic action is always reachable.

## Accessibility & Inclusion

Glove, low-light, and high-stress use: large touch targets (44pt minimum, larger for primary actions), high contrast, dark only in v1 (owner decision 2026-11-06; a light theme for daylight use is a later decision), VoiceOver labels, Dynamic Type, Reduce Motion, and a visible non-gesture alternative for every gesture.
