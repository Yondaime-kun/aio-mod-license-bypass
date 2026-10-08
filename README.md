# AIO-MOD Toolkit v3.5.2 — license bypass

Reverse-engineering write-up + patcher untuk **AIO-MOD Toolkit v3.5.2**
(release `willstore69/toolkit`), engine Python ter-*compile* Nuitka
(CPython 3.14, aarch64/Android-Termux) dengan license wall Ed25519.

Hasil: engine jalan di mode **`★ VIP MEMBER ★`** (18 menu), **tanpa** mengirim
HWID ke server asli.

> Riset keamanan pada perangkat/lingkungan sendiri.

---

## Status tested

| Platform | Versi | Status | Cara redirect |
|---|---|---|---|
| **Linux x86_64 (Ubuntu 24.04.5 LTS, kernel 6.8.0-101)** | — | ✅ **VIP terverifikasi** | `/etc/hosts` + `fakelics.service` (systemd) + qemu-aarch64 |
| **Termux aarch64 (Android)** | Python 3.14 | ⚠️ **belum VIP** — lagi dibenerin | shim `sitecustomize` (non-root) |

> Di Termux, fake server **harus** jalan pakai Python bernacl
> (`pkg install python-pynacl`). Kalau tidak, engine balas
> *"Tanda tangan respons server tidak valid"* → jatuh ke mode Gratis.

---

## Dua varian patcher (TERPISAH per platform)

Kerja di satu platform **tidak mengganggu** yang lain:

| Platform | Folder | Root? | Redirect server |
|---|---|---|---|
| **Termux (Android)** | `termux/` | ❌ non-root | shim Python (`sitecustomize`) |
| **Linux / VPS (x86_64)** | `linux/` | ✅ sudo | `/etc/hosts` + systemd |
| Komponen bersama | `shared/` | — | fake TLS server + certs |

## Prinsip kerja

1. **Fake license server** (`shared/fakelicstls.py`) menandatangani respons
   **Ed25519 sungguhan pakai PyNaCl** → engine menerima mode VIP.
   **Wajib** dijalankan dengan Python yang punya `nacl`:
   `pkg install python-pynacl` (Termux).
2. Engine menghubungi `aio.scwill.store:8443` → diarahkan ke server lokal.
3. Fake `Crypto/Cryptodome.Signature.eddsa` dipasang sebagai lapisan tambahan.

## Pakai

### Termux (non-root) — TANPA sudo
```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/termux
./bootstrap.sh
aio
```
Detail: [`termux/README.md`](termux/README.md)

### Linux / VPS (sudo)
```bash
sudo apt install qemu-user-static binutils curl unzip python3-pynacl
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/linux
sudo ./bootstrap.sh
aio
```
Detail: [`linux/README.md`](linux/README.md)

## Troubleshooting

| Gejala | Penyebab / cek |
|---|---|
| `[ Gratis PENGGUNA ]` + `Koneksi Gagal` | fake server hidup? `python -c "import nacl"` |
| `Tanda tangan respons server tidak valid` | fake server **harus** pakai Python bernacl |
| Loading bar numpuk newline | bar 92 char > lebar layar → perkecil font / landscape |
| Termux `Koneksi Gagal` | shim DNS di `sitecustomize` + fake server |

## Struktur
```
├── termux/       patcher non-root (Android)
├── linux/        patcher sudo (systemd/qemu)
├── shared/       fake TLS server + certs
├── FINDINGS.md   catatan RE
└── WALKTHROUGH.md
```
