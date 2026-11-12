# Claims and evidence

Every material claim (UI, landing page, store listing, metadata, email) needs
a row before launch.

| Claim | Where it appears | Evidence | Verified by | Status |
| --- | --- | --- | --- | --- |
| Tone modem decodes at 12 dB SNR with clipping and 1% clock drift | Not yet shown in the UI (T016); would appear in store text and the Tones screen | SIMULATED ONLY. `ModemTests.test500SeededFramesDecodeAtTwelveDBWithClippingAndOnePercentDrift`: 500/500 seeded bursts decoded (24 to 48 byte payloads, drift +1% and -1% alternating, clip gain 3, 300-3000 Hz passband, 0 to 0.4 s lead silence). SNR is the RMS of the filtered signal over the whole clip (silence included) against Gaussian noise through the same passband. Extra sweep, 100 bursts each: 9, 0, -3, -6 dB all 100/100. No real radio, VOX, squelch, speaker or mic path tested (launch blocker 2) | `swift test --package-path Packages/DLCore`, 2026-11-03 | SIMULATED ONLY: do not claim radio reliability |
