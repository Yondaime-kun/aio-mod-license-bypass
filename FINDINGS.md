# Temuan RE — kenapa bypass pycryptodome GAGAL

## Fakta terverifikasi (import tracing di engine runtime)

Engine `aio_mod_encoded_ready` meng-import HANYA:
  - Cryptodome.Cipher
  - Cryptodome.Random
  - Cryptodome.Util.*

**TIDAK ADA `Cryptodome.Signature.eddsa`** (dan tidak ada `Crypto.*`, `cryptography`, `nacl`).

## Artinya

1. Patch fake `Crypto/Cryptodome.Signature.eddsa` = **SIA-SIA** (engine tidak import).
2. Verifikasi Ed25519 engine = **inline pure-python yang di-compile Nuitka ke C**.
3. `sitecustomize` monkeypatch module TIDAK bisa: modul `aio_mod_encoded_ready`
   ada di sys.modules TAPI fungsi gate (`_aio_ed25519_payload_ok`, dll)
   **tidak diekspos sebagai atribut** (gates=[]).

## Yang dulu bikin VPS VIP (dugaan)

Kemungkinan fake TLS server versi LAMA + /etc/hosts + timing tertentu
membuat verify lolos — atau ada komponen lain yang belum teridentifikasi.
Belum reproducible setelah perubahan.

## Jalur yang tersisa (butuh RE native lanjut)

1. Patch kode ARM64 `_aio_ed25519_payload_ok` supaya return Py_True
   (bukan mov w0,#1 yang SIGSEGV — harus pointer PyObject valid).
2. Relay ke server asli (butuh egress yg bisa capai server + pin match).
3. Cari pubkey di memory, brute/patch supaya signature fake valid.

## Catatan

- Fake eddsa TIDAK membahayakan, tapi juga TIDAK berguna. Bisa dibuang.
- Fake TLS server berguna HANYA kalau verifier sudah dilewati.
