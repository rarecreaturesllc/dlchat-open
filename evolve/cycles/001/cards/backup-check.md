# Check my written copy of the phrase            Flag: exp_backup_check   Status: READY

**What changes for the user:** in group details, "Check my written copy" lets you type the phrase from your paper; DLChat says it matches, or which word numbers differ, without ever showing the phrase.
**Why (evidence):**
- "I was knocked out of sessions, couldn’t find my recovery password and had a heck of a time trying to get back in without knowing where my recovery password that I saved&copied was. So I had to restart sessions all over again. But lost contact with my friend(s)." - Session App Store review "Session", https://apps.apple.com/us/app/id1470168868?see-all=reviews, 2026-10-08
- "I'm pretty technically inclined and I lose my Signal history every time I get a new phone because I just can't remember to transfer it." - https://news.ycombinator.com/item?id=33514755, 2022-11-08
- Competitor behavior: Session shows a recovery password and asks users to save it, with stated restore limits - research/session.md (docs.getsession.org)
**Where to see it:** Groups list, group details, flag on.
**Risk / what it does not do:** checks one group at a time; does not store that a check happened (no persisted data).
**Rollback:** delete branch evolve/001/backup-check.
**Design:** secondary button in group details next to the other phrase tools; sheet matches Settings sheets. Result uses dlGo / dlWarn with an icon, never colour alone.
**Accessibility:** result announced to VoiceOver (review fix), success/warning haptic, field 44pt+, autocorrect off.
**Tests:** BackupCheckTests (match ignores case and spacing; reports word numbers, never words; word count), BackupCheckUITests on and off.
**Screenshots:** backup-check-on / backup-check-result / backup-check-off.
