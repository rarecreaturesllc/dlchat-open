#!/usr/bin/env python3
"""Build the 1024-word radio list from BIP39 and the EFF short list.

Usage: tools/make_wordlist.py [output]   (default Packages/DLCore/Sources/DLCore/Resources/words.txt)

Deterministic: the same inputs always give the same list. The output is sorted
alphabetically, one word per line, and its SHA-256 is pinned in the DLCore tests.
Rules: lowercase a-z only, 4 to 8 letters, no brand, place or sensitive words,
no two words sharing a phonetic key, no two words one edit apart.
"""
import hashlib
import itertools
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "sources")
DEFAULT_OUT = os.path.join(HERE, "..", "Packages", "DLCore", "Sources", "DLCore", "Resources", "words.txt")
TARGET = 1024

# Brands, proper nouns, religions, body or sexual terms and anything a listener
# might hear as an alarming word on an open channel.
EXCLUDE = set("""
ebay yahoo xerox wifi islam satoshi santa roman mardi kung latin dutch olympic
panty thong womb femur ebook email aids gills hers cola coke mocha nacho taco
sushi salsa pasta bagel pistol bomb bullet cannon weapon rifle kill dead death
blood corpse nazi sexy porn drug cocaine opium
""".split())

def read(name, column=None):
    with open(os.path.join(SRC, name)) as f:
        return [l.strip() for l in f if l.strip()]

def key(w):
    for a, b in [("ph", "f"), ("ck", "k"), ("qu", "kw"), ("wr", "r"), ("kn", "n"), ("gh", ""),
                 ("wh", "w"), ("tch", "ch"), ("sh", "S"), ("ch", "C"), ("th", "T")]:
        w = w.replace(a, b)
    w = re.sub(r"c(?=[eiy])", "s", w).replace("c", "k").replace("z", "s").replace("v", "f")
    w = w.replace("d", "t").replace("b", "p").replace("g", "k")
    w = re.sub(r"(.)\1+", r"\1", w)
    return w[0] + re.sub(r"[aeiouy]", "", w[1:])

def lev(a, b):
    p = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        c = [i]
        for j, y in enumerate(b, 1):
            c.append(min(p[j] + 1, c[-1] + 1, p[j - 1] + (x != y)))
        p = c
    return p[-1]

def syllables(w):
    return max(1, len(re.findall(r"[aeiouy]+", w)))

def build():
    bip = read("bip39.txt")
    eff = read("eff_short_words.txt")
    both = set(bip) & set(eff)
    pool = set(bip) | set(eff)
    pool = [w for w in pool if re.fullmatch(r"[a-z]{4,8}", w) and w not in EXCLUDE]
    pool.sort(key=lambda w: (w not in both, abs(syllables(w) - 2), len(w), w))
    kept, keys = [], set()
    for w in pool:
        k = key(w)
        if k in keys:
            continue
        if any(abs(len(w) - len(x)) <= 1 and lev(w, x) <= 1 for x in kept):
            continue
        kept.append(w)
        keys.add(k)
        if len(kept) == TARGET:
            break
    return sorted(kept), len(pool)

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    words, pool_size = build()
    if len(words) != TARGET:
        sys.exit(f"only {len(words)} words qualify from a pool of {pool_size}; need {TARGET}")
    keys = [key(w) for w in words]
    assert len(set(keys)) == TARGET, "phonetic key collision"
    assert not any(lev(a, b) <= 1 for a, b in itertools.combinations(words, 2)), "edit distance 1 pair"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    data = ("\n".join(words) + "\n").encode()
    with open(out, "wb") as f:
        f.write(data)
    print(f"{len(words)} words from pool of {pool_size}; sha256 {hashlib.sha256(data).hexdigest()}")

if __name__ == "__main__":
    main()
