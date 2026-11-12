# Competitors (cycle 001, 2026-11-07). Details and URLs: research/*.md

| App | URL | Identity | How messages travel | Price | Better than DLChat | Worse than DLChat |
|---|---|---|---|---|---|---|
| Signal | https://signal.org | Phone number (+ optional username) | Central server, internet only | Free (nonprofit) | Safety numbers, disappearing messages, view-once, note to self, linked devices, backups/transfer, notification privacy | Needs phone number and internet; server sees IP and timing; no offline path |
| Session | https://getsession.org | Account ID + recovery password, no phone | Onion-routed swarms, ~2-week storage | Free (Pro planned) | Recovery password UX, message requests, disappearing after send/read, no phone number | No forward secrecy (V2 announced, unverified); delayed notifications; groups capped at 100 |
| SimpleX | https://simplex.chat | No identifiers; one-time links | SMP relays, two-hop routing, self-hostable, 21-day relay retention | Free (donations, VC) | Security code read aloud, delivery receipts (1 check relay, 2 device), hidden profiles, private notes, server settings UI | Battery and notification complaints; onboarding complexity; no multi-device |
| Briar | research/similar.md | Contacts added in person / link | Tor, Wi-Fi, Bluetooth | Free | Local peer discovery praised | Android only, maintenance mode |
| Bridgefy / Bitchat | research/similar.md | Device keys | Bluetooth mesh; Bitchat falls back to Nostr relays then a queue | Free | Transport fallback order | Short range, security criticism (Bridgefy) |
| Meshtastic | research/similar.md | Node ID | LoRa radio mesh | Free app, hardware cost | Real radio range | Delivery unreliable beyond one hop (quotes) |
| Threema | research/similar.md | Random ID | Central server | Paid | No phone number, verification levels | Paid, server-based |
| 0xchat / White Noise | research/similar.md | Nostr keys | Nostr relays (NIP-17/44/59; MLS for White Noise) | Free | Relay-based no-account messaging - the planned online carrier | Key management burden, relay reliability |
