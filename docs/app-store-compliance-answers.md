# App Store compliance answers for DLChat 1.0

Drafted 2026-11-10 for the owner to check and enter. This is a draft by Claude, not legal
advice. The owner's position, in his words: nothing here is illegal, how the app is used is up
to the user, and it works with Meshtastic within the legal frameworks that apply.

## 1. Radio rules (FCC) and App Review

DLChat is not a radio and has no transmitter. It turns a message into words, tones or a QR code,
and it can talk over Bluetooth to a Meshtastic radio the user already owns. The person holding
the radio decides whether and where to transmit, and is responsible for the rules of the service
they use.

What we can say truthfully to App Review (this text is also in
`store/ios/metadata/review_information/notes.txt`):

- DLChat does not transmit on any radio band by itself.
- Meshtastic radios use license-free ISM bands (in the US, 902 to 928 MHz under FCC Part 15),
  where encrypted data is allowed. Meshtastic already encrypts its own channels.
- Reading words aloud or playing tones over a voice radio is the user's choice. Some radio
  services restrict coded messages outside emergencies (in the US, GMRS under 47 CFR
  95.1733(a)(3) and amateur radio under 97.113(a)(4); amateur rule 97.403 allows any means of
  communication for the immediate safety of life when normal systems are down).
- The app shows a notice the first time the user picks a radio method. It says rules vary by
  country and service and that the user must follow them.
- The listing and the app never say DLChat is "legal everywhere" or "FCC approved".

Still open, and only the owner can close it: `docs/launch-blockers.md` row 5 asks for an
attorney's read of the GMRS and amateur rules and of countries outside the US. The owner has
said to proceed. If App Review asks about Guideline 5 (Legal), send the points above.

## 2. Encryption export compliance (the App Store Connect questions)

What the app ships:

- Message sealing built from Apple CryptoKit primitives (AES, HMAC/HKDF, HPKE) in a SIV-style
  design described in `docs/blueprint.md`. All the algorithms are published standards. The way
  they are combined is our own.
- Tor with its own OpenSSL, and secp256k1 for the online chat relays. These are standard
  algorithms that do not come from iOS.

Suggested answers, question by question:

| Question in App Store Connect | Suggested answer |
| --- | --- |
| Does your app use encryption? | Yes |
| Does it qualify for an exemption in Category 5, Part 2 of the US EAR? | No. Its main purpose is private messaging, so the usual exemptions (authentication only, copy protection, banking) do not fit |
| Does it use proprietary encryption not accepted as standard by international bodies? | No. Every algorithm is a published standard (AES, SHA-2, HKDF, HPKE, X25519, secp256k1, TLS inside Tor) |
| Does it use standard encryption instead of, or in addition to, Apple's? | Yes (OpenSSL inside Tor, and secp256k1) |
| Will it be available in France? | No. France is off the country list |

What follows from those answers (corrected 2026-11-10 after filing them):

- The owner answered these in App Store Connect on 2026-11-10: standard algorithms only, not
  available in France. App Store Connect then asked for no documentation and issued no code.
- Apple's documentation says to set `ITSAppUsesNonExemptEncryption` to `NO` when the app only
  uses encryption that is exempt from the documentation upload requirement, and to `YES` only
  when documentation is required (Apple then issues a code for `ITSEncryptionExportComplianceCode`).
  So the key stays `NO`. A build with `YES` and no code is rejected at upload; build 20 was.
  An earlier version of this file said the key should be `YES`. That was wrong.
- This holds only while France stays off the country list. France was removed from Pricing
  and Availability on 2026-11-10 (174 countries). Adding France back needs the French
  encryption declaration first.
- US side: a mass-market app with standard encryption is normally self-classified as 5D992.c.
  That needs no licence, but Apple's page notes that an annual self-classification report to
  the Bureau of Industry and Security may be required. Check this with an adviser.
- The one judgement call is whether our own way of combining standard algorithms counts as
  "proprietary". The owner answered no, because every primitive is a standard. If Apple or an
  adviser disagrees, the path is a CCATS request to BIS.

## 3. Things this document does not settle

- No independent cryptographer has reviewed the design (`docs/launch-blockers.md` row 6). The
  listing makes no security claim beyond describing what the app does.
- No privacy policy or support page is published yet (row 7). App Store Connect requires a
  privacy policy URL before submission.
- App Privacy answers, age rating, price and countries are entered by the owner on the website.
