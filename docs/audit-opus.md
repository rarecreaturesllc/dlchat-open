# Opus audit (Phase 5 and Gate A)

Date: 2026-11-03. Auditor: Opus 5.5. Method: read the security, storage and copy code plus `docs/`, re-used the verified test results, and ran one temporary UI test (A1; not committed). Not a third-party security review and not legal advice.

## Verdicts

- **Gate A (engineering work package complete): NOT MET.** The task list is finished, but A1 to A3 are defects in approved behavior and `docs/ux-baseline.md` still has unresolved rows.
- **Gate B (ready for release): NOT READY.** Depends on Gate A plus the owner items listed at the end.
- `replica-test` and `replica-diff`: NOT APPLICABLE. No reference app or spec exists to compare against.

## Findings

| # | Severity | Finding | Evidence | Fix |
| --- | --- | --- | --- | --- |
| A1 | High | **The PIN lock can be bypassed.** The lock is an overlay on the root view, so any open sheet or full-screen screen stays on top of it. Leave the app with Settings open and return: Settings still works, including plain-text message export. The same applies to read-out, QR, Nearby, Safety and group setup | Temporary UI test: `settingsVisible=true unlockHittable=false doneHittable=true`. `docs/design/screenshots/audit-lock-bypass.png`. `RootView.swift:90` | Show the lock in its own window above everything, like `PrivacyCoverWindow`. Add a UI test |
| A2 | High | **Only the first group is usable.** Send, History and rooms always use `groups.first`. After saving there is no way to see a phrase or safety words again, so a later neighbor cannot be added from this phone. No group can be removed, though `data-inventory.md` lists "Remove group". The group pill opens "New group" | `ComposeModel.swift:39`, `HistoryView.swift:31,96`, `RootView.swift:77`; no remove function exists | Group screen: choose, view phrase and safety words behind a hold, add room, remove with confirmation, reorder |
| A3 | High | **A failed wipe can open the app with data intact.** The duress path ignores the wipe result and unlocks anyway. Panic wipe then removes the PIN even if the wipe failed. `wipeFailed` is never shown | `AppLock.swift:118-124`, `RootView.swift:44-50`, no UI reads `wipeFailed` | Wipe returns a result; retry; stay locked on failure; show failure on panic wipe; keep the PIN unless it succeeded |
| A4 | Medium | The duress PIN is refused during a wrong-PIN wait, up to an hour, which is when someone under pressure may need it | `AppLock.swift:112-117` | Check the duress PIN before the wait |
| A5 | Medium | **A phone with a wrong clock cannot send.** A date before 2026-01-01 throws `sendTimeOutOfRange`. Clocks can reset after a dead battery in a long outage, and the blueprint says time is display-only | `Frame.swift:44` | Clamp the slot; the receiver already shows odd times |
| A6 | Medium | Rolling the clock back shortens the wrong-PIN wait (blocker 11) | `AppLock.swift:112` | Store the last failure time and re-arm if the clock moved back |
| A7 | Medium | Copy does not say the PIN only guards the screen and adds no encryption, or that "erases" cannot rule out forensic recovery | `SettingsText.swift:10,13-19`; `Vault.swift` | Add both in plain words |
| A8 | Medium | Choosing a shorter retention deletes messages at once with no confirmation. Remove PIN also drops the duress PIN with no confirmation | `GroupBook.swift:97-102`, `SafetyView.swift:41` | Confirm both (no undo is possible) |
| A9 | Low | Copied plain text stays on the pasteboard up to 60 s after a wipe. The radio notice "seen" flag also survives a wipe | `Hygiene.swift:10-14`, `RootView.swift:44-50` | Clear both in wipe |
| A10 | Low | Relay hop count is not capped and there is no per-phone limit, so a hostile nearby phone can push long-lived or flooding frames and evict others. Frames stay unreadable | `NearbyModel.swift:57-70`, `Relay.swift` | Cap to `startTTL`; document the flooding limit |
| A11 | Low | Room words are lowercased but not Unicode-normalized in key derivation. Two keyboards could produce different keys. This is part of the wire format, so it must be fixed before freezing | `Keys.swift` | Apply NFC and trim in `Keys` |
| A12 | Medium | `data-inventory.md` still says "Planned" and lacks the UserDefaults items, pasteboard and export. It lists a deletion mechanism that does not exist (A2) | `docs/data-inventory.md` | Refresh from the built app |

## What held up

- **Protocol matches blueprint section 3.** PBKDF2 at 600,000 rounds, separate MAC and encryption keys, tag over bit length plus plaintext, nonce from the tag, ChaCha20 keystream, constant-time compare. An independent script reproduces the vectors.
- **Choices the loop pinned look sound:** 4-bit checksum, phrase text as the KDF password, empty HKDF salt, 4-byte length prefix, no cleartext marker. These go to the cryptographer as-is (blocker 6).
- **Repair** on a marked `?` is automatic and a wrong word only when asked. Both are labelled. Margin is as the blueprint states.
- **No logging** calls in the app or DLCore. No network APIs outside the one Multipeer file. Nearby is off by default, requires session encryption, uses random names, and rejects streams and resources.
- **Hashing** computes both PIN hashes on each entry, so timing does not reveal a duress PIN.
- **Legal copy** avoids legality and certification claims.

## Safeguard rows audited

| Row | Severity | Result |
| --- | --- | --- |
| 1 Privacy | Medium | NEEDS REVIEW stands. Text matches behavior except A7 and A9. Hosted URL and contact missing |
| 2 Terms | Low | NEEDS REVIEW stands; needs a lawyer and an entity |
| 7 Unnecessary data | Medium | Downgraded to NEEDS REVIEW until A12 is fixed |
| 9 Dark patterns | None | PASS (engineering) stands |
| 12 Claims | Medium | NEEDS REVIEW stands, plus A7 |
| 17 Children | Low | NEEDS REVIEW stands; owner decides age rating and markets |
| 20 Deletion | High | Downgraded to **FAIL** until A2 and A3 are fixed |

## Proposed resolutions for open blockers

- **Blocker 10, duress mark:** keep the hidden press, and add a toggle plus a one-line explanation inside the Safety sheet. That gives a visible alternative without marking the compose screen.
- **Blocker 11, PIN lock:** covered by A1, A3, A4, A6. Add a wipe button to the lock screen, since someone may only have that screen. Face ID stays out: a face can be forced, and the blueprint disables it when a duress PIN exists.
- **Blocker 15, top bar:** use `ViewThatFits` so the group pill takes its own row at large text sizes.
- **Blocker 16, UX baseline:** this changes the earlier suggestion, because the A2 group screen makes several items cheap.
  - **Build:** group reorder, swipe and context menus on groups and History rows (deleting a single message also helps privacy), confirmations (A8), high-contrast edges, and an XCUITest `performAccessibilityAudit()` for labels, targets and rendered contrast.
  - **Mark N/A with reasons:** shake undo (entry has an Undo button, and a jostled phone in the field should not undo), remembered sort and filter (History is newest first with search), deep links (no web or URL surface on purpose; a link handler would add attack surface).

## Owner items before Gate B

Attorney review (5), cryptographer review (6), export classification (1), read-aloud pass and word-list freeze (9), business facts and hosted URLs (4, 7, 16), age rating and markets (row 17), license review (8), real-phone and radio tests (2, 3, 12, 13, 14).

## Re-check after T021 to T026 (2026-11-04, Opus 5.5)

Method: re-ran every suite, read the diffs, and wrote failing tests first for what the task tests missed. Not a third-party security review and not legal advice.

**Findings A1 to A12:** fixed in code and covered by tests, except where listed under "Not verified". A10 is partly fixed: hop count is capped, there is still no per-phone limit, so a hostile nearby phone can still flood and evict relay frames (unreadable). Recorded, not a Gate A item.

**New defects found in the fixes, now fixed (R1 to R4):**

| # | Severity | Finding | Proof | Fix |
| --- | --- | --- | --- | --- |
| R1 | High | Moving the lock above open screens (T021) meant a duress PIN or lock-screen wipe left those screens open. With the read-out open the app **crashed**. An open History sheet would have kept showing decrypted messages after the wipe (read from code, not run) | New UI test crashed the app before the fix | Every screen closes without animation after a finished wipe; History clears its list; read-out tolerates empty words |
| R2 | Medium | Removing the active group wrote its draft back to the sealed store when Send switched groups, so "removal deletes the draft" was false in the real app | New unit test failed | `ComposeModel.flush` skips a group that no longer exists |
| R3 | Low | The room choice carried over when switching groups | New unit test failed | Cleared on switch |
| R4 | Medium | History listed every group's messages although T023 and its footer say it follows the active group. Also, a failed removal from the group detail screen showed nothing | Read from code; new unit test covers the filter | History filters to the active group (export still covers all); failure note added |

**Weak checks, stated plainly:**

- The accessibility audit test ignores **every** Dynamic Type finding on buttons and static text, so it does not really test Dynamic Type; screenshots at large sizes are the only evidence. It also runs on 4 screens only.
- No test exercises the failed-wipe message on screen: the Vault wipe cannot be made to fail in a test.
- If the Keychain delete succeeds and the store save then fails during removal, the group stays listed without keys. The detail screen says so and removal can be retried.

**Not verified:** VoiceOver, Increase Contrast on screen, hardware keyboard, drag reorder and swipe by hand, switching among several groups in the UI, device console, anything on a real phone or radio.

**Rows:** 7 and 20 are NEEDS REVIEW (no FAIL remains). 20 waits on a real-device wipe check; 7 on the device console.

**Verdicts:**

- **Gate A (engineering work package complete): MET**, by the definition in the workflow: all approved tasks are built and verified, external and review items are recorded, and `docs/ux-baseline.md` has no unexplained missing rows. Final `/impeccable audit` run 2026-11-06: 15/20 (Good), no P0 or P1, 4 P2 and 3 P3 findings (`docs/design/impeccable-audit.md`). `replica-test` and `replica-diff` stay NOT APPLICABLE.
- **Gate B (ready for release): NOT READY.** Owner items above are all still open.
