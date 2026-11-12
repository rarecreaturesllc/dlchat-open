#!/bin/bash
# Fresh-context Ralph loop for DLChat. Adapted from coleam00/ralph-loop-quickstart
# (commit f6a7781): same idea, one fresh `claude -p` session per iteration.
# Changes: pinned Sonnet, narrow tool permissions, no network tools, a hard cap of
# 6 iterations (lean mode), a stall stop, and per-iteration logs.
#
# --setting-sources project: the owner's user-level `rtk` hook rewrites commands (git, swift) so
# they no longer match --allowedTools; headless sessions then refuse them. Probed 2026-11-02.
#
# Usage: RALPH_BUDGET_USD=<dollars per iteration> ralph/ralph.sh [iterations]
#        (run from the repo root; never above 6)
set -u

MODEL="claude-sonnet-5-5"
# /goal is not available headless, so each iteration is bounded by a dollar cap instead.
# The owner sets it per run: RALPH_BUDGET_USD=5 ralph/ralph.sh 6. No default on purpose.
BUDGET="${RALPH_BUDGET_USD:?Set RALPH_BUDGET_USD (max dollars per iteration) before running}"
CAP=6
N="${1:-$CAP}"
[ "$N" -gt "$CAP" ] && { echo "Capped at $CAP iterations per approved run."; N=$CAP; }

[ -f PROMPT.md ] && [ -f prd.md ] && [ -f activity.md ] || { echo "Run from the repo root."; exit 1; }
mkdir -p ralph/logs

ALLOW=(Read Edit Write Glob Grep
  "Bash(swift:*)" "Bash(xcodebuild:*)" "Bash(xcrun simctl:*)" "Bash(python3:*)"
  "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git add:*)" "Bash(git commit:*)"
  "Bash(cd:*)" "Bash(ls:*)" "Bash(mkdir:*)" "Bash(mv:*)" "Bash(shasum:*)" "Bash(wc:*)" "Bash(grep:*)")
DENY=("Bash(git push:*)" "Bash(sudo:*)" "Bash(rm -rf:*)" WebFetch WebSearch)

for ((i = 1; i <= N; i++)); do
  before=$(git rev-parse HEAD)
  start=$(date +%s)
  echo "=== Iteration $i of $N ($(date '+%H:%M:%S')) ==="
  out=$(claude -p "$(cat PROMPT.md)" --model "$MODEL" --max-budget-usd "$BUDGET" --output-format text \
    --setting-sources project \
    --allowedTools "${ALLOW[@]}" --disallowedTools "${DENY[@]}" < /dev/null 2>&1) || true
  echo "$out" > "ralph/logs/iter-$i.log"
  echo "$out" | tail -15
  echo "--- iteration $i took $(( $(date +%s) - start ))s ---"

  [[ "$out" == *"<promise>COMPLETE</promise>"* ]] && { echo "All tasks complete after $i iteration(s)."; exit 0; }
  [[ "$out" == *"<promise>BLOCKED</promise>"* ]] && { echo "Blocked: see activity.md and docs/launch-blockers.md."; exit 2; }

  if [ "$(git rev-parse HEAD)" = "$before" ]; then
    # Lean mode: one iteration without a commit stops the run and escalates to Opus.
    echo "No commit this iteration. Stopping; escalate to Opus with ralph/logs/iter-$i.log."
    exit 3
  fi
  sleep 2
done
echo "Iteration limit ($N) reached. Reaching the limit is not completion; review activity.md."
exit 1
