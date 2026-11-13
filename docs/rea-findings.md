# REA findings

NOT APPLICABLE. The owner named no reference apps at intake, so there is no target. REA was not run. Phases 2B (sanitize and erase) and clean-room steps are skipped for the same reason.

## Discovery done instead (2026-11-02)

| # | Observation | Evidence | Verified or inferred | Limitation | Informs |
| --- | --- | --- | --- | --- | --- |
| 1 | BIP39 has many sound-alikes: 978 of 2048 words share a phonetic key, 806 edit-distance-1 pairs | `tools/wordlist_analysis.py` | Measured with a crude key | Key is not a hearing test | Blueprint section 5 |
| 2 | About 1441 words remain distinct after filtering BIP39 + EFF short | Same | Measured | Same | 1024-word list |
| 3 | Word-Huffman coding gives roughly 2 to 3 times fewer spoken words than UTF-8 | Same | Estimate; Zipf weights | Not the shipped dictionary | Text coding |
| 4 | personal radio service prohibits coded messages (95.1733(a)(3)); amateur radio prohibits obscuring (97.113(a)(4)) with safety-of-life allowance (97.403) | Cornell LII, read 2026-11-02 | Text read, not legal advice | US only; family radio service rules position unclear | Blueprint section 13 |
| 5 | Apple documentation tiers depend on OS-provided vs other encryption | App Store Connect Help, read 2026-11-02 | Text read | Secure messaging classification unresolved | Blueprint section 14 |
