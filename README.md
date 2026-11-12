# DLChat

Offline, grid-down encrypted messaging for iPhone. A group shares a generated phrase of 10, 15 or
20 words. DLChat turns each message into gibberish words you can read out, a sound another phone
can hear, a QR code, or a packet sent over your own Meshtastic radio or public Nostr relays
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

**Radio rules are your responsibility.** The Meshtastic radio feature is off until you turn it on
and accept its notice. By turning it on, you confirm you will use a radio and region setting that
are allowed where you are, and that you alone are responsible for what your radio transmits.
DLChat will not send while the radio is set to licensed mode. If you choose to use DLChat together
with any radio equipment, you are responsible for following the laws and license conditions for
that equipment and band.

## Building

```sh
sh scripts/fetch-tor.sh                      # once after cloning (Tor is not committed)
swift test --package-path Packages/DLCore    # core tests
open DLChat.xcodeproj                         # build the DLChat scheme in Xcode
```

Data the app sends and where it goes: `docs/data-inventory.md`. Third-party code and assets:
`docs/asset-licenses.md`.

## License

Copyright (C) 2026 Rare Creatures LLC. DLChat is developed and published by Rare Creatures LLC.

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. This program is distributed in the hope that it
will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the full text in [`LICENSE`](LICENSE).

Third-party components keep their own licenses (MIT, BSD, Apache 2.0, SIL OFL, CC BY); see
`docs/asset-licenses.md`.
