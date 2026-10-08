#!/usr/bin/env python3
"""Cari tahu format msg PERSIS yang engine pakai buat verifikasi HMAC 'sig'.
Coba semua kombinasi: sort_keys, separators, dan sertakan/tidak ed25519_sig."""
import base64, hashlib, hmac, json, secrets, time

SIG_KID = "aio-license-2026-01"
KEY = b"aio-license"

def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

payload = {
    "ok": True,
    "hwid": "AIO3-test",
    "registered_at": "2026-06-24",
    "is_vip": True,
    "expires_at": "2069-06-09",
    "server_time": 1791444000,
    "nonce": "1cdd922245933922",
    "req_nonce": "8cc7eaa49e2e2bb931355e28b3a18997",
    "sig_alg": "Ed25519",
    "sig_kid": SIG_KID,
}

# tanda tangan ed25519 dummy (isi apa saja)
p_with = dict(payload)
p_with["ed25519_sig"] = b64u(b"\x00" * 64)

variants = {
    "sort,compact (kita)": json.dumps(payload, sort_keys=True, separators=(",", ":")).encode(),
    "nosort,compact": json.dumps(payload, separators=(",", ":")).encode(),
    "sort,default": json.dumps(payload, sort_keys=True).encode(),
    "nosort,default": json.dumps(payload).encode(),
    "sort,compact,+sig": json.dumps(p_with, sort_keys=True, separators=(",", ":")).encode(),
    "nosort,compact,+sig": json.dumps(p_with, separators=(",", ":")).encode(),
    "sort,compact,no_ok": json.dumps({k: v for k, v in payload.items() if k != "ok"},
                                      sort_keys=True, separators=(",", ":")).encode(),
}

print("Kemungkinan HMAC 'sig' yang engine cari:\n")
for label, msg in variants.items():
    h = hmac.new(KEY, msg, hashlib.sha256).hexdigest()
    print(f"  {label:24s} -> {h}")
print("\nKalau lu punya 'sig' dari server lu, cocokkan salah satu di atas.")
print("Server kita saat ini pakai: sort,compact (TANPA ed25519_sig).")
