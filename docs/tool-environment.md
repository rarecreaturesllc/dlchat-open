# Tool environment

Verified: 2026-11-02. Mode: lean. Platform profile: iPhone, native SwiftUI (Xcode 27.2, iOS 27.0 simulator "iPhone 18 Pro" booted).

| Tool | Available | Version | How verified |
| --- | --- | --- | --- |
| Replica | YES (plugin `replica-skill@replica-skill`) | plugin 1.0.0 | `replica-architect` invoked 2026-11-02: requires a recon map, none exists, web-backend stack table not applicable. No output used. recon, entrepreneur NOT APPLICABLE (no references) |
| REA (MCP tools answer, not just skill installed) | YES, MCP `rea` connected | n/a | tools listed in session; NOT USED, no reference targets |
| Claude Code `/goal` | NOT AVAILABLE headless | claude 2.1.310 | Not in this session's skill list and not a `claude -p` option. Documented alternative: each Ralph iteration has acceptance criteria quoted from prd.md and a `--max-budget-usd` cap set by the owner |
| Ralph fresh-context shell loop | YES, adapted | coleam00/ralph-loop-quickstart f6a7781 (read in full; plain shell, no hooks, no network) | `ralph/ralph.sh` passes `bash -n`; not yet run. Headless sessions must run with `--setting-sources project`: the user-level `rtk` hook rewrites commands and defeats `--allowedTools` (probed, fixed 2026-11-02). Differences from upstream: pinned Sonnet, narrow `--allowedTools`, no network tools, 6-iteration cap, stall stop, dollar cap |
| Impeccable (`/impeccable` listed in session) | YES | 4.6.0 per tools.md (npm, checked 2026-10-17) | `/impeccable` is in the session skill list; installed at `~/projects/.claude`, so no per-project install was run |

Impeccable hooks (from `~/projects/.claude/settings.local.json`, kept): `SessionStart`, `PostToolUse` on `Edit|Write`, `Stop`. No restart was needed.

## Section F — design, accessibility, quality layer

| Skill | Available | Version / source | How verified |
| --- | --- | --- | --- |
| ui-ux-pro-max (design decisions) | YES | vendored in `~/.claude/skills` | Ran `search.py --design-system` 2026-11-02. Kept only: dark OLED, high contrast, low emission. Rejected as wrong fit: enterprise web pattern, Google Fonts, editorial type (PRODUCT.md: native SF, system colors) |
| fixing-accessibility (edit-time a11y) | YES | vendored in `~/.claude/skills` | listed in session skills |
| web-quality-audit + siblings (evidence) | N/A for this app | | Native iOS app, no rendered web pages. Native evidence comes from `ios-accessibility`, `swiftui-performance-audit`, and Simulator checks |

## Other environment

- GitHub CLI authenticated as the owner. A private working repo exists with owner approval.
- Node v24.22.0, Python 3.9.6.
- Branch: `feat/dlchat-foundation` (`propose_branch` unavailable, used `git switch -c`).

Missing tool or credential = BLOCKED, never PASS.
