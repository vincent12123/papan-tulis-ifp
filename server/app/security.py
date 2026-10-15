"""Admin PIN: scrypt hashing and the rules for a new PIN (SPEC 5.8)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import itertools
import os

_N, _R, _P = 2**14, 8, 1
PIN_KEY = "pin_hash"


def hash_pin(pin: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(pin.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(digest).decode()


def verify_pin(pin: str, stored: str | None) -> bool:
    if not stored or not stored.startswith("scrypt$"):
        return False
    try:
        _, salt_b64, digest_b64 = stored.split("$")
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
    except ValueError:
        return False
    actual = hashlib.scrypt(pin.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=len(expected))
    return hmac.compare_digest(actual, expected)


def pin_problem(new_pin: str) -> str | None:
    """Indonesian validation message for a new PIN, or None when it is fine."""
    if not new_pin.isdigit() or len(new_pin) < 6:
        return "PIN baru minimal 6 angka."
    digits = [int(c) for c in new_pin]
    steps = {b - a for a, b in itertools.pairwise(digits)}
    if steps <= {0} or steps == {1} or steps == {-1}:
        return "PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang."
    return None
