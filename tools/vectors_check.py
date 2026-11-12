"""Independent check of the DLChat v1 phrase, key and frame vectors (T003).

Uses only the Python standard library: hashlib/hmac for SHA-256, HMAC and
PBKDF2, HKDF written here from hmac, and a pure-Python ChaCha20 (RFC 8439)
that must reproduce the RFC section 2.4.2 vector before anything else runs.
Nothing here shares code with the Swift implementation in Packages/DLCore.

  python3 -I tools/vectors_check.py          check Packages/.../vectors.json
  python3 -I tools/vectors_check.py --write  regenerate that file, then check
"""
import hashlib
import hmac
import json
import struct
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS_PATH = ROOT / "Packages/DLCore/Sources/DLCore/Resources/words.txt"
VECTORS_PATH = ROOT / "Packages/DLCore/Tests/DLCoreTests/vectors.json"

KDF_SALT = b"DLChat/v1/kdf"
KDF_ROUNDS = 600000
MASK32 = 0xFFFFFFFF


# ---- ChaCha20, RFC 8439 ----------------------------------------------------

def _rotl(v, n):
    return ((v << n) & MASK32) | (v >> (32 - n))


def _quarter(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & MASK32; s[d] = _rotl(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & MASK32; s[b] = _rotl(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & MASK32; s[d] = _rotl(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & MASK32; s[b] = _rotl(s[b] ^ s[c], 7)


def chacha20_block(key, counter, nonce):
    state = ([0x61707865, 0x3320646E, 0x79622D32, 0x6B206574]
             + list(struct.unpack("<8I", key))
             + [counter & MASK32]
             + list(struct.unpack("<3I", nonce)))
    work = state[:]
    for _ in range(10):
        _quarter(work, 0, 4, 8, 12); _quarter(work, 1, 5, 9, 13)
        _quarter(work, 2, 6, 10, 14); _quarter(work, 3, 7, 11, 15)
        _quarter(work, 0, 5, 10, 15); _quarter(work, 1, 6, 11, 12)
        _quarter(work, 2, 7, 8, 13); _quarter(work, 3, 4, 9, 14)
    return struct.pack("<16I", *[(w + s) & MASK32 for w, s in zip(work, state)])


def chacha20_xor(key, counter, nonce, data):
    out = bytearray()
    for i in range(0, len(data), 64):
        block = chacha20_block(key, counter + i // 64, nonce)
        out += bytes(a ^ b for a, b in zip(data[i:i + 64], block))
    return bytes(out)


def rfc8439_selftest():
    key = bytes(range(32))
    nonce = bytes.fromhex("000000000000004a00000000")
    plain = (b"Ladies and Gentlemen of the class of '99: If I could offer you "
             b"only one tip for the future, sunscreen would be it.")
    expected = bytes.fromhex(
        "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b"
        "f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8"
        "07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736"
        "5af90bbf74a35be6b40b8eedf2785e42874d")
    if chacha20_xor(key, 1, nonce, plain) != expected:
        sys.exit("RFC 8439 section 2.4.2 ChaCha20 vector FAILED")


# ---- HKDF-SHA256 (RFC 5869) from hmac ---------------------------------------

def hmac_sha256(key, data):
    return hmac.new(key, data, hashlib.sha256).digest()


def hkdf(ikm, info, length=32):
    prk = hmac_sha256(b"\x00" * 32, ikm)
    okm, t = b"", b""
    counter = 1
    while len(okm) < length:
        t = hmac_sha256(prk, t + info + bytes([counter]))
        okm += t
        counter += 1
    return okm[:length]


# ---- Bits, MSB first -------------------------------------------------------

def bits_to_bytes(bits):
    padded = bits + "0" * (-len(bits) % 8)
    return bytes(int(padded[i:i + 8], 2) for i in range(0, len(padded), 8))


def bytes_to_bits(data, count):
    return "".join(f"{b:08b}" for b in data)[:count]


# ---- DLChat v1 -------------------------------------------------------------

def load_words():
    words = WORDS_PATH.read_text().split("\n")
    words = [w for w in words if w]
    assert len(words) == 1024
    return words


def phrase_from_entropy(entropy, n, words):
    secret_bits = 10 * n - 4
    secret = bytes_to_bits(entropy, secret_bits)
    assert len(secret) == secret_bits
    check = bytes_to_bits(hashlib.sha256(bits_to_bytes(secret)).digest(), 4)
    allbits = secret + check
    return [int(allbits[i:i + 10], 2) for i in range(0, 10 * n, 10)]


def normalize_room(room):
    """Trim, NFC, lowercase, NFC again: the same steps as Keys.normalizedRoom."""
    nfc = unicodedata.normalize
    return nfc("NFC", nfc("NFC", room.strip()).lower())


def derive_keys(phrase_text, room):
    master = hashlib.pbkdf2_hmac("sha256", phrase_text.encode(), KDF_SALT, KDF_ROUNDS, 32)
    room_key = hkdf(master, b"room/" + normalize_room(room).encode())
    return {
        "master": master,
        "room": room_key,
        "mac": hkdf(room_key, b"mac"),
        "enc": hkdf(room_key, b"enc"),
    }


def safety_words(master, words):
    v = int.from_bytes(hkdf(master, b"safety")[:4], "big")
    return [words[(v >> s) & 1023] for s in (22, 12, 2)]


def seal(keys, tag_bits, slot, flags, salt, body_bits):
    p = f"{slot:020b}{flags:02b}{salt:06b}{body_bits}"
    pbytes = bits_to_bytes(p)
    tag = hmac_sha256(keys["mac"], struct.pack(">I", len(p)) + pbytes)[:tag_bits // 8]
    nonce = hmac_sha256(keys["enc"], b"nonce" + tag)[:12]
    stream = chacha20_xor(keys["enc"], 1, nonce, bytes(len(pbytes)))
    ct = bytes(a ^ b for a, b in zip(pbytes, stream))
    ct_bits = bytes_to_bits(ct, len(p))
    frame = bits_to_bytes(bytes_to_bits(tag, tag_bits) + ct_bits)
    return tag, nonce, frame, tag_bits + len(p)


PHRASE_CASES = [(10, bytes(range(1, 13))), (15, bytes(range(40, 59))), (20, bytes(range(100, 125)))]
FRAME_CASES = [
    # phrase index, room, tagBits, slot, flags, salt, body bits
    (1, "", 64, 0, 0, 0, ""),
    (1, "", 64, 123456, 1, 37, "1011001110001"),
    (1, "bridge", 64, 1048575, 0, 63, "0" * 36),
    (1, "bridge", 128, 54321, 2, 5, "1" * 100),
    (1, "Bridge", 128, 54321, 2, 5, "1" * 100),
    (0, "", 128, 777, 1, 21, "01" * 40),
    (2, "north", 64, 9, 0, 9, "110" * 33),
    # Non-ASCII rooms: decomposed with padding and capitals, then the composed spelling (same keys)
    (1, " Cafe\u0301 ", 128, 4242, 1, 17, "10" * 30),
    (1, "caf\u00e9", 128, 4242, 1, 17, "10" * 30),
]


def build_vectors():
    words = load_words()
    phrases = []
    for n, entropy in PHRASE_CASES:
        entropy = bytes_to_bits(entropy, 10 * n - 4)
        entropy = bits_to_bytes(entropy)
        indices = phrase_from_entropy(entropy, n, words)
        text = " ".join(words[i] for i in indices)
        master = derive_keys(text, "")["master"]
        rooms = []
        for room in ("", "bridge", " Cafe\u0301 "):
            k = derive_keys(text, room)
            rooms.append({"room": room, "roomKeyHex": k["room"].hex(),
                          "macKeyHex": k["mac"].hex(), "encKeyHex": k["enc"].hex()})
        phrases.append({"words": n, "entropyHex": entropy.hex(), "indices": indices,
                        "phrase": text, "masterHex": master.hex(),
                        "safety": " ".join(safety_words(master, words)), "rooms": rooms})
    frames = []
    for pi, room, tag_bits, slot, flags, salt, body in FRAME_CASES:
        keys = derive_keys(phrases[pi]["phrase"], room)
        tag, nonce, frame, count = seal(keys, tag_bits, slot, flags, salt, body)
        frames.append({"phrase": pi, "room": room, "tagBits": tag_bits, "sentSlot": slot,
                       "flags": flags, "salt": salt, "bodyBits": body,
                       "tagHex": tag.hex(), "nonceHex": nonce.hex(),
                       "frameHex": frame.hex(), "frameBitCount": count})
    return {"phrases": phrases, "frames": frames}


def main():
    rfc8439_selftest()
    print("RFC 8439 2.4.2 ChaCha20 vector: ok")
    vectors = build_vectors()
    if "--write" in sys.argv:
        VECTORS_PATH.write_text(json.dumps(vectors, indent=2) + "\n")
        print(f"wrote {VECTORS_PATH.relative_to(ROOT)}")
    stored = json.loads(VECTORS_PATH.read_text())
    if stored != vectors:
        sys.exit(f"{VECTORS_PATH.relative_to(ROOT)} does not match the independent computation")
    print(f"{len(vectors['phrases'])} phrases, {len(vectors['frames'])} frames: match")


if __name__ == "__main__":
    main()
