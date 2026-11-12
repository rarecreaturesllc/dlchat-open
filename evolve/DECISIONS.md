# Decisions (append only)

## 2026-11-07, cycle 001 start
- Scope: "Five now, online mode next". Cycle 001 builds five flagged improvements drawn from Signal, Session and SimpleX and writes a full online-mode design; online mode is built afterwards as its own dedicated job (it adds a network data flow, which an Evolve iteration may not).
- Online carrier: "iCloud and Public Nostr Relays. Default to Public Relays." Public Nostr relays are the default carrier; an iCloud (CloudKit) mailbox is the second option. Nostr needs a signing library (new dependency) - the owner's choice of Nostr is taken as the yes for that design; the library itself is named in the design for a final OK.

## 2026-11-07, cycle 001 close
- Owner: "Approve all five". approve: got-it-reply, backup-check, read-once, lock-now, undo-delete.
- Each flag removed in its own commit; behavior is now the default; merged into feat/dlchat-foundation (the owner's integration branch). Not pushed.
- Online mode (ONLINE_MODE.md) still waits on the owner's four decisions.

## 2026-11-07, online mode decisions (owner, via question boxes)
- secp256k1 library: "Yes, add it (Recommended)".
- Default: "Ask once, then on (Recommended)".
- Relays: "Three big public relays (Recommended)" (Damus, nos.lol, Primal; exact list shown before shipping).
- iCloud push: "Yes, offer iCloud push (Recommended)".
- Owner also asked for a chat screen ("where you can chat on the app"), Signal/Session style.
- 2026-11-07: real-relay smoke test approved ("Yes, run it"); iCloud push phase approved ("Build it now").
- 2026-11-07 real-relay test results: nos.lol and relay.primal.net accept and deliver back (end to end, sealed message opened). relay.damus.io accepts posts but refuses reading kind 1059 without NIP-42 AUTH and then rejects every AUTH ("relay needs serviceUrl to be configured before AUTH can work"), so it cannot carry DLChat; dropped from defaults. NIP-42 sign-in with mailbox keys kept for relays where it works. A replacement third relay needs the owner's OK to test.

- 2026-11-09 (owner): cycle 001 "Reply: got it" and Receive's "Copy text" removed. Receive offers only Acknowledged, which posts "Decrypted" (open lock) in Chat. Decrypted text never shows in Chat.
