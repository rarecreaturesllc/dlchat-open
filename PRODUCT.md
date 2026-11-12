# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI with CryptoKit. No network code, no AI, no third-party services. Chosen by the user at intake.

## Users

Neighborhood groups and preparedness-minded households using walkie-talkies during a grid-down event. Mostly non-technical, often stressed, frequently outdoors, in low light, one-handed or wearing gloves. Technical hobbyists (hams, preppers) are a secondary audience; the default flow serves the neighbor first.

## Product Purpose

DLChat lets people within walkie-talkie range talk privately on public airwaves with no internet. A group shares a generated secret phrase of 10, 15 or 20 words. The app derives a key from it, encrypts a message, and renders the result as gibberish words that can be read aloud, as audio tones played into a radio, as a QR code, or sent over Bluetooth. Only phrase holders can decrypt. Success: a neighbor with no setup beyond the phrase can send and read a message in under a minute.

## Positioning

Works over ordinary open radio with nothing but a spoken phrase: no accounts, no pairing, no servers, no network. A neighboring chat app that needs a network, a mesh, or an account cannot truthfully make that claim.

## Operating Context

Power or cell outage; neighbors on FRS/GMRS-style handhelds listening in on shared channels. Messages are spoken as word lists, played as tones into a radio mic, scanned in person, or relayed phone to phone. Phones run on limited battery. Eavesdroppers can hear everything on the channel.

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
