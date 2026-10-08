# Fake cryptography.hazmat.primitives.asymmetric.ed25519 — bypass license verify.
#
# The AIO-MOD engine verifies the server Ed25519 signature with the
# `cryptography` package (Ed25519PublicKey.from_public_bytes(...).verify(...)),
# NOT pycryptodome. This module makes verify() always succeed so a fake/VIP
# response (or any response) is accepted.
#
# API-compatible with cryptography's ed25519 module for the verify path.

_ED25519_PUBLIC_BYTES_LEN = 32


def _hook_log(msg):
    try:
        with open("/tmp/eddsa_hook.log", "a") as f:
            f.write("[crypto-ed25519] " + msg + "\n")
    except Exception:
        pass


class Ed25519PublicKey:
    def __init__(self, key_bytes=None):
        self._key = key_bytes
        self._raw = key_bytes

    @classmethod
    def from_public_bytes(cls, data):
        _hook_log("from_public_bytes len=%d" % (len(data) if data else 0))
        return cls(data)

    @classmethod
    def from_public_key(cls, key):
        return cls(getattr(key, "_raw", None))

    def public_bytes(self, *a, **k):
        return self._raw or b"\x00" * _ED25519_PUBLIC_BYTES_LEN

    def public_bytes_raw(self):
        return self._raw or b"\x00" * _ED25519_PUBLIC_BYTES_LEN

    def verify(self, signature, data):
        _hook_log("verify BYPASS sig=%s" % (
            bytes(signature)[:8].hex() if signature else "none"))
        return None  # None = success

    def verify_raises(self, signature, data):  # pragma: no cover
        return None


class Ed25519PrivateKey:
    def __init__(self, key_bytes=None):
        self._key = key_bytes

    @classmethod
    def from_private_bytes(cls, data):
        return cls(data)

    def public_key(self):
        return Ed25519PublicKey()

    def sign(self, data):
        return b"\x00" * 64

    def private_bytes(self, *a, **k):
        return b"\x00" * 32


def generate_key():
    return Ed25519PrivateKey()
