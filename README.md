# DLChat

Offline, grid-down encrypted messaging for iPhone. A group shares a generated phrase of 10, 15 or
20 words. DLChat turns each message into gibberish words you can read aloud, audio tones you can
play into a radio, a QR code, or a packet sent over a Meshtastic radio or public Nostr relays
(through Tor by default). Only people who hold the phrase can read it.

## Status

Beta, distributed through TestFlight. Not on the App Store. The encryption design has **not**
been reviewed by an independent cryptographer, and the legal questions about sending encrypted
traffic over radio are still open (see `docs/launch-blockers.md`). Do not rely on DLChat where
your safety depends on it.

## Use at your own risk

DLChat is free, open source software provided **"as is", without warranty of any kind**, to the
extent permitted by law (see sections 15 and 16 of the license). You use it entirely at your own
risk.

**Radio laws are your responsibility.** Many radio services restrict or forbid encrypted or
obscured messages. In the United States, for example, amateur (ham) radio rules prohibit messages
encoded to hide their meaning, and FRS, GMRS and other services have their own rules. The radio
features in DLChat are off until you turn them on. By turning them on, you confirm you know and
will follow the laws that apply to the radio, band and country you use, and that you alone are
responsible for what you transmit.

## Building

```sh
sh scripts/fetch-tor.sh                      # once after cloning (Tor is not committed)
swift test --package-path Packages/DLCore    # core tests
open DLChat.xcodeproj                         # build the DLChat scheme in Xcode
```

Data the app sends and where it goes: `docs/data-inventory.md`. Third-party code and assets:
`docs/asset-licenses.md`.

## License

Copyright (C) 2026 Rare Creatures LLC

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. This program is distributed in the hope that it
will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the full text in [`LICENSE`](LICENSE).

Third-party components keep their own licenses (MIT, BSD, Apache 2.0, SIL OFL, CC BY); see
`docs/asset-licenses.md`.
