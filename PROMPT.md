# Per-iteration instructions (dlchat)

You are a fresh session. Do exactly ONE task, then stop.

1. Read `CLAUDE.md`, `prd.md`, `docs/blueprint.md`, `DESIGN.md`, the tail of `activity.md`, and `docs/launch-blockers.md`.
2. Pick the first task in the `prd.md` table whose Status is `pending` and whose dependencies are all `done`. A task whose dependency is `ABANDONED` or `blocked` is not ready; skip it.
3. Treat that task's acceptance criteria and verification command as your goal. You are bounded by a per-iteration dollar cap set by the owner; if you are running out, stop cleanly, mark the task `ABANDONED` with the reason, and commit. State the criteria at the start, and check them against real command output at the end.
4. Implement only that task. Follow `docs/blueprint.md`; if the blueprint is wrong or incomplete, do not redesign: write the problem to `activity.md` and `docs/launch-blockers.md` and output `<promise>BLOCKED</promise>`.
5. Run the task's verification command exactly as written in `prd.md` and `CLAUDE.md`, one command per call: no `cd`, no `&&` chains, no pipes. Headless sessions cannot answer approval prompts, so a refused command stays refused. If the working tree already has uncommitted files for this task from an earlier attempt, review and finish them instead of starting over.
   Run the task's checks: UI tasks also boot the simulator (iPhone 18 Pro), capture a screenshot with `xcrun simctl io`, and check there are no errors. Apply `DESIGN.md`; build UI only from `DLChat/Design`.
   Smoke checks S1-S5 mean: S1 the app launches without a crash; S2 the task's core flow completes (use a scripted `xcrun simctl launch` with `-seed-demo -screen <name>`, and the simulator tools if allowed); S3 no error or fault log lines from the app; S4 no failed network requests (the app has none, so N/A); S5 the screen holds at the default size and at `xcrun simctl ui booted content_size accessibility-extra-extra-large` (reset it to `large` afterwards). Save screenshots under `docs/design/screenshots/` and report what you could not check.
6. Rules: no third-party dependencies, no network APIs (no URLSession, no sockets; Multipeer only in T017), no real crypto written from scratch (CryptoKit and CommonCrypto only), no secrets or real phrases in logs, tests or screenshots. Never weaken a test to pass. Write whole files, no TODO placeholders.
7. Update the task's Status in `prd.md` to `done` only when every acceptance criterion is met by real output. Otherwise mark it `ABANDONED` with the reason.
8. Append to `activity.md`: date, task id, commands run, results, elapsed time, and anything unverified. Record any new data flow in `docs/data-inventory.md` and any new asset in `docs/asset-licenses.md`.
9. Make one commit for this task only: `git add` the changed files by name (one call), then `git commit -m "<one line>" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"` (one call, plain quotes, no heredoc, no `$(...)`). Compound or substituted commands may be refused headless. End the message with the Co-Authored-By line from CLAUDE.md or the session. Do not push, init, or change remotes.

Stop after the commit. If every task is `done` or `ABANDONED`, output `<promise>COMPLETE</promise>`.
