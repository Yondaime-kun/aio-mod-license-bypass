# Fake Crypto.Signature.eddsa — bypass license verify.
# Tidak butuh cffi/Cryptodome internal. API-compatible untuk mode rfc8032.
import os as _os
_EDDSA_LOG = _os.environ.get("AIO_EDDSA_LOG",
             _os.path.join(_os.path.expanduser("~"), ".aio-patcher", "eddsa_hook.log"))

class _Verifier:
    def verify(self, msg_hash, signature):
        try:
            with open(_EDDSA_LOG, 'a') as f:
                f.write(f"[eddsa] verify BYPASS sig={bytes(signature)[:8].hex()}\n")
        except Exception:
            pass
        return None  # None = sukses

class _Signer:
    def sign(self, msg_hash):
        try:
            with open(_EDDSA_LOG, 'a') as f:
                f.write("[eddsa] sign called -> fake sig\n")
        except Exception:
            pass
        return b"\x00" * 64

class _Key:
    def __init__(self, key=None):
        self.key = key

def new(key, mode=None, **kwargs):
    try:
        with open(_EDDSA_LOG, 'a') as f:
            f.write(f"[eddsa] new key={type(key).__name__} mode={mode}\n")
    except Exception:
        pass
    # Mode signing vs verifying ditentukan oleh tipe key.
    # Untuk license verify, engine pakai public key -> verifier.
    return _Verifier()

def import_public_key(encoded):
    return _Key(encoded)

def import_private_key(encoded):
    return _Key(encoded)

def generate(**kwargs):
    return _Key()
