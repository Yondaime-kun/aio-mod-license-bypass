# Fake cryptography.hazmat.primitives.asymmetric.ed25519 — BYPASS verifikasi.
#
# Kenapa file ini ada: engine AIO-MOD (Nuitka) memilih backend kripto secara
# adaptif. Kalau paket 'cryptography' terpasang, ia memverifikasi tanda tangan
# license lewat cryptography.Ed25519PublicKey.verify() (implementasi RUST),
# BUKAN lewat Crypto.Signature.eddsa. Akibatnya fake eddsa tak berpengaruh dan
# engine jatuh ke [ Gratis ]. Menimpa modul ini membuat verify() selalu lolos.
#
# API-compatible dgn cryptography 4x-50.x utk jalur Ed25519 (public/private key,
# sign/verify). Tidak butuh binding Rust.
import os as _os

_LOG = _os.environ.get(
    "AIO_CRYPTO_LOG",
    _os.path.join(_os.path.expanduser("~"), ".aio-patcher", "cryptography_hook.log"),
)


def _w(msg):
    try:
        with open(_LOG, "a") as f:
            f.write(msg + "\n")
    except Exception:
        pass


_w("=== fake cryptography ed25519 loaded ===")


class _FakePublicKey:
    def __init__(self, data=b""):
        _w("Ed25519PublicKey.__init__ len=%s" % (len(data) if data else 0))
        self._raw = data

    @classmethod
    def from_public_bytes(cls, data):
        _w("Ed25519PublicKey.from_public_bytes len=%s" % (len(data) if data else 0))
        return cls(data)

    def public_bytes(self, encoding=None, format=None):
        return self._raw

    def public_bytes_raw(self):
        return self._raw

    def verify(self, signature, data):
        _w("Ed25519PublicKey.verify() CALLED -> BYPASS")
        return None  # None = signature valid

    def verify_ph(self, *a, **k):
        return None

    def __eq__(self, other):
        return isinstance(other, _FakePublicKey) and other._raw == self._raw

    def __hash__(self):
        return hash(self._raw)

    def __copy__(self):
        return self

    def __deepcopy__(self, memo=None):
        return self

    def __repr__(self):
        return "<fake Ed25519PublicKey>"


class _FakePrivateKey:
    def __init__(self, data=b""):
        _w("Ed25519PrivateKey.__init__")
        self._raw = data
        self._pub = _FakePublicKey(b"\x00" * 32)

    @classmethod
    def generate(cls):
        _w("Ed25519PrivateKey.generate()")
        return cls()

    @classmethod
    def from_private_bytes(cls, data):
        return cls(data)

    def public_key(self):
        return self._pub

    def private_bytes(self, *a, **k):
        return self._raw or (b"\x00" * 32)

    def private_bytes_raw(self):
        return self._raw or (b"\x00" * 32)

    def sign(self, data):
        _w("Ed25519PrivateKey.sign() CALLED")
        return b"\x00" * 64

    def __copy__(self):
        return self

    def __deepcopy__(self, memo=None):
        return self


# Nama kelas yang dipakai cryptography
Ed25519PublicKey = _FakePublicKey
Ed25519PrivateKey = _FakePrivateKey


def __getattr__(name):
    # Jangan meledak kalau ada nama lain yang di-import modul ini.
    _w("ed25519.__getattr__(%s)" % name)
    return _FakePublicKey
