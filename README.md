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
| **Linux x86_64** (Ubuntu 24.04.5 LTS, kernel 6.8.0-101) | — | ✅ **VIP** | `/etc/hosts` + `fakelics.service` (systemd) + qemu-aarch64 |
| **Linux x86_64** (Ubuntu 22.04.5 LTS, kontainer **tanpa systemd**) | — | ✅ **VIP** | `/etc/hosts` + fake server via **nohup** + qemu-aarch64 |
| **Termux aarch64** (Android 12 ARM64 native, container redroid) | Python 3.14.6 | ✅ **VIP** | shim `sitecustomize` + `iptables` REJECT IP license |
| **Termux aarch64** (HP fisik user, **non-root**) | Python 3.14.x | ✅ **VIP** | shim `sitecustomize` + fake `cryptography` ed25519 |

**Status per platform (jujur):**

- **Linux x86_64**: terbukti VIP, **dari lingkungan bersih** — `git clone` →
  `bootstrap.sh` → `aio`. Bootstrap otomatis mengunduh engine 27MB + libpython
  yang cocok dari GitHub Release repo ini, menyiapkan fake Termux FS, qemu,
  fake TLS server, runner, dan redirect. Diuji di dua VPS berbeda (satu dengan
  systemd, satu kontainer tanpa systemd).
- **Termux aarch64 (Android 12 ARM64)**: **VIP tercapai**, terverifikasi ulang
  dari nol (`patch.sh revert` → `install` → `aio` → `★ VIP MEMBER ★`),
  tanpa langkah manual. Engine 27MB dijalankan **native** (tanpa qemu).
  Penyebab lama "Gratis" sudah ditemukan & diperbaiki: (1) fake
  `Crypto.Signature.eddsa` **tidak benar-benar terpasang** (kalah oleh `.pyc`/
  `.pyi`); (2) CA palsu tidak ada di `certifi/cacert.pem`; (3) dependency engine
  belum lengkap; (4) `LD_LIBRARY_PATH=/system/lib64` merusak link di Termux.
- **Termux di HP fisik (non-root)**: ✅ **VIP — TERKONFIRMASI user**
  ("Finally vip"). Akar masalah yang dulu bikin selalu Gratis: paket
  **`cryptography`** terpasang → engine memilih verifier **Rust**
  (`Ed25519PublicKey.verify()`) dan **mengabaikan** fake
  `Crypto.Signature.eddsa`. Fix = fake `cryptography/hazmat/primitives/
  asymmetric/ed25519.py` (`verify()` no-op), terpasang otomatis oleh
  `patch.sh install` (Step 1b). Detail: `FINDINGS.md` §3.

### Lapis kedua: `[Job/Claim]` (tool tertentu)

VIP **tidak** otomatis membuka semua tool. Sebagian tool (Patcher Smali, dll)
memanggil endpoint kedua `POST /v1/job/claim` dan gagal dengan:

```
× GALAT   [Job/Claim] Server menolak claim SSL_PINNING_BYPASS (bukan VIP / offline).
```

Gate ini **client-side** dan sudah **terbukti dilewati end-to-end** lewat
**runtime monkeypatch** 7 fungsi engine (`_aio_job_claim`,
`_aio_stamp_job_claim`, `_aio_special_claim_apk`, `_aio_smart_build_token`,
`_aio_server_usage_check`, `_aio_server_usage_mark`, `_require_vip_feature`).

Hasil tes dgn APK asli (F-Droid 11.9 MB): engine memproses 2 DEX, menjalankan
patch, repack, zipalign, preserve V1/V2/V3 → **keluaran APK valid**
(11.9 MB). Log hook: `_aio_job_claim HOOKED args=('SSL_PINNING_BYPASS', …)`.
Error `[Job/Claim] Server menolak claim` tidak muncul sama sekali.

Catatan: hook hanya aktif kalau stdin **bukan** tty (di VPS dijalankan via
subprocess + steering file). Detail: `FINDINGS.md` §5 & §9, `WALKTHROUGH.md`
bagian *Gerbang kedua*.

---

## Dua varian patcher (TERPISAH per platform)

Kerja di satu platform **tidak mengganggu** yang lain:

| Platform | Folder | Root? | Redirect server |
|---|---|---|---|
| **Termux (Android)** | `termux/` | ❌ non-root | shim Python (`sitecustomize`) |
| **Linux / VPS (x86_64)** | `linux/` | ✅ sudo | `/etc/hosts` + systemd/nohup |
| Komponen bersama | `shared/` | — | fake TLS server + certs |

## Prinsip kerja

1. Engine sebenarnya adalah **file 27 MB** yang di-decode (dynamic aarch64),
   **bukan** file `aio-mod` 13.8 MB yang diunduh dari release upstream — yang
   terakhir itu **launcher/installer** dan gagal mengunduh/decode engine di
   banyak lingkungan. Patcher ini mengunduh engine 27 MB langsung dari
   **GitHub Release repo ini** (`aio-mod-engine`, md5 `785231328c…`) dan
   menyertakan lib yang cocok (`libpython3.14.so`, `libandroid-support.so`).
2. **Fake license server** (`shared/fakelicstls.py`) membalas
   `POST /v1/device/check` dengan JSON `{"ok":true,"is_vip":true, ...}`.
   Field `req_nonce` **wajib** sama dengan header `X-Req-Nonce` yang dikirim
   engine, kalau tidak engine menolak (*"Tanda tangan respons server tidak
   valid"*). Dijalankan dengan Python bernacl kalau tersedia (kalau tidak,
   `ed25519_sig` dummy tetap diterima engine — engine hanya mengecek
   keberadaan field itu).
3. Engine menghubungi `aio.scwill.store:8443` → diarahkan ke `127.0.0.1`.
4. Fake `Crypto/Cryptodome.Signature.eddsa` dipasang sebagai lapisan tambahan
   (di engine versi ini verifikasi sebenarnya inline, jadi ini opsional).

## Pakai

### Linux / VPS (sudo)
```bash
sudo apt install qemu-user-static binutils curl unzip   # python3-pynacl opsional
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/linux
sudo ./bootstrap.sh
sudo aio
```
Detail: [`linux/README.md`](linux/README.md)

### Termux (non-root) — TANPA sudo
```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/termux
./bootstrap.sh
aio
```
> Termux Android 12 ARM64 **sudah VIP** (lihat *Status tested*). Di HP fisik,
> patcher memilih jalur otomatis (non-root) — kalau masih Gratis, lihat
> [`termux/README.md`](termux/README.md) bagian "Kalau masih Gratis".
> Detail: [`termux/README.md`](termux/README.md)

## Troubleshooting

| Gejala | Penyebab / cek |
|---|---|
| `[ Gratis PENGGUNA ]` + `Koneksi Gagal` | fake server hidup? `pgrep -f fakelicstls` |
| `Tanda tangan respons server tidak valid` (dengan `eddsa_hook.log` kosong) | **paket `cryptography` ada** → engine pakai verifier Rust → `./patch.sh install` (Step 1b) |
| `Tanda tangan respons server tidak valid` (lainnya) | fake `eddsa.py` **tidak benar-benar terpasang** (`.pyc`/`.pyi` menang) → `./patch.sh install` |
| `TLSV1_ALERT_UNKNOWN_CA` di log fake server | CA palsu belum masuk `certifi/cacert.pem` |
| Engine berhenti di `Sync resource toolkit...` | dependency kurang → `pkg install zip unzip p7zip aapt openjdk-17 clang` |
| `library "libpython3.14.so" not found` (Termux native) | `LD_LIBRARY_PATH` salah — JANGAN pakai `/system/lib64` di Termux |
| `library "libpython3.14.so" not found` (Linux) | lib dari release belum terpasang di `/system/lib64` (Linux) |
| `library "libandroid-support.so" not found` | `libandroid-support.so` belum ada di samping libpython |
| `pkg install` → `apt ... required file not found` | shim apt menimpa paket apt → `cp -f $PREFIX/bin/apt.asli $PREFIX/bin/apt` |
| `[Job/Claim] Server menolak claim …` | gate lapis-2 (client-side) — lihat `FINDINGS.md` §5 |
| Loading bar numpuk newline | bar 92 char > lebar layar → `COLUMNS=80` / perkecil font |

## Struktur
```
├── termux/       patcher non-root (Android)
├── linux/        patcher sudo (systemd/nohup + qemu)
├── shared/       fake TLS server + certs
├── FINDINGS.md   catatan RE
└── WALKTHROUGH.md
```
