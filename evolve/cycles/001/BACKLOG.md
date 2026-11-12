# Backlog, cycle 001 (scores: evidence / impact / effort fit / identity fit, 0-3 each)

| # | Idea | Ev | Imp | Eff | Fit | Total | Decision |
|---|---|---|---|---|---|---|---|
| 1 | "Got it" reply after a message opens (delivery confirmation without a back channel) | 3 | 3 | 3 | 3 | 12 | BUILD `exp_got_it_reply` |
| 2 | Check my written copy of the phrase (backup check, never shows the phrase) | 3 | 2 | 3 | 3 | 11 | BUILD `exp_backup_check` |
| 3 | Read once messages (flag bit 1; receiver does not keep it) | 3 | 3 | 2 | 3 | 11 | BUILD `exp_read_once` |
| 4 | Lock now button when a PIN is set | 2 | 2 | 3 | 3 | 10 | BUILD `exp_lock_now` |
| 5 | Undo toast instead of instant delete in History (UX baseline) | 2 | 2 | 3 | 2 | 9 | BUILD `exp_undo_delete` |
| 6 | Online mode over Nostr relays, iCloud second | 3 | 3 | 0 | 3 | - | Needs your decision: design in ONLINE_MODE.md, own job (network data flow, dependency) |
| 7 | Hidden groups shown only after typing a password (SimpleX hidden profiles) | 2 | 2 | 1 | 3 | 8 | Needs your decision (persisted data) |
| 8 | Private notes / note to self (Signal, SimpleX) | 2 | 1 | 1 | 2 | 6 | Needs your decision (persisted data) |
| 9 | Per-message disappearing timer (Signal, Session, SimpleX) | 3 | 2 | 1 | 3 | 9 | Needs your decision (persisted data + wire format); read once covers part |
| 10 | Move to a new phone over Nearby (Signal transfer) | 3 | 2 | 0 | 2 | 7 | Needs your decision (persisted data, multi-hour) |
| 11 | Show which transport carried each message in History | 1 | 1 | 2 | 2 | 6 | Next up (persisted data) |
| 12 | Incognito keyboard | 1 | 1 | 3 | 3 | - | Already done: compose and receive fields disable autocorrect |
| 13 | Queue sends until a phone is reachable (Meshtastic request) | 3 | 2 | - | 3 | - | Already done: Nearby keeps and re-offers held messages |
| 14 | Safety words visible after joining (Signal safety numbers) | 2 | 1 | - | 3 | - | Already done: group details, behind a hold |

Lenses: ios-native only; Emil pass rows apply after building. UX baseline gaps found: undo instead of instant delete in History (#5). Everything else in the baseline that applies was already present (swipe actions, context menus, search, dark, Dynamic Type, VoiceOver labels).
