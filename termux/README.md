# Termux (Android) — patcher NON-ROOT

Bypass AIO-MOD Toolkit di Termux **tanpa root**. Tidak memakai `sudo`,
`/etc/hosts`, iptables, atau systemd.

## Pakai

```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/termux
./bootstrap.sh       # install paket + download engine + terapkan bypass
aio                  # jalankan
```

## Kalau masih `[ Gratis PENGGUNA ]`

```bash
./diagnose.sh
```

Bagian yang **paling sering** jadi penyebab:

1. **Fake server tidak punya PyNaCl** — server harus menandatangani respons
   Ed25519 sungguhan. Install:
   ```bash
   pkg install python-pynacl
   ./patch.sh install
   ```
2. **Redirect server** — non-root tidak bisa menulis `/etc/hosts`, jadi
   redirect dilakukan di `sitecustomize.py` (shim `getaddrinfo`). Pastikan
   file itu ada di **`~/release/`** (lokasi yang dipindai engine):
   ```bash
   ls -la ~/release/sitecustomize.py
   ```
3. **Fake `Crypto.Signature.eddsa`** — paket Termux `python-pycryptodomex`
   hanya menyediakan `Cryptodome`. Patcher otomatis membuat alias
   `Crypto -> Cryptodome`.

## File

| File | Fungsi |
|---|---|
| `bootstrap.sh` | install paket + unduh engine + panggil `patch.sh` |
| `patch.sh` | patcher utama (install/verify/revert), non-root |
| `diagnose.sh` | cek semua komponen + tunjukkan apa yang kurang |
| `deep-check.sh` | diagnosa mendalam (isi runner, load sitecustomize) |
| `files/sitecustomize.py` | spoof uid + redirect server + shrink bar |
| `files/eddsa_fake.py` | fake verifier pycryptodome |

## Perintah

```bash
./patch.sh install   # terapkan bypass
./patch.sh verify    # cek status
./patch.sh revert    # kembalikan seperti semula
./diagnose.sh
```

Patcher **idempotent** — aman diulang. File yang di-patch di-backup `.asli`.

## Catatan
- Loading bar engine lebarnya ~92 kolom; di layar HP bar-wrap jadi newline.
  Perkecil font / landscape, atau biarkan (murni kosmetik).
- Redirect server via Python berarti engine tidak perlu `/etc/hosts`.
