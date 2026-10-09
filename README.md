# AIO-MOD Toolkit 3.5.2: license bypass

Patcher untuk menjalankan **AIO-MOD Toolkit 3.5.2** tanpa lisensi server.

Engine-nya binary Nuitka (CPython 3.14, aarch64). Setelah dipatch, engine jalan
di mode VIP dengan 18 menu aktif, dan tidak mengirim HWID ke server asli.

Dua target didukung: **Linux x86_64** (via qemu) dan **Termux/Android aarch64**
(native). Setiap platform punya patcher sendiri supaya satu tidak merusak yang
lain.

## Yang sudah diuji

| Platform | Versi OS | Hasil | Catatan |
|---|---|---|---|
| Linux x86_64, systemd | Ubuntu 24.04.5 | VIP | `/etc/hosts` + service systemd |
| Linux x86_64, tanpa systemd | Ubuntu 22.04.5 | VIP | `/etc/hosts` + fake server nohup |
| Termux aarch64 | Android 12 (Python 3.14.6) | VIP + Smali Patcher | non-root, hook runtime |
| Termux aarch64, HP fisik | Android, Python 3.14.x | VIP | non-root |

Cara uji tiap platform berbeda, jadi detailnya ada di README masing-masing:
[`linux/README.md`](linux/README.md) dan [`termux/README.md`](termux/README.md).

## Cara pakai

### Linux / VPS

```bash
sudo apt install qemu-user-static binutils curl unzip
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/linux
sudo ./bootstrap.sh
sudo aio
```

### Termux (non-root)

```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/termux
./bootstrap.sh
aio
```

Untuk tool yang kena gate kedua, pakai `AIO_HOOK=1 aio`. Lihat bagian
[Gerbang kedua](#gerbang-kedua-jobclaim) di bawah.

## Cara kerjanya

Engine aslinya bukan file `aio-mod` 13.8 MB dari upstream. File itu hanya
launcher, dan sering gagal decode engine di banyak lingkungan. Engine
sebenarnya adalah binary aarch64 27 MB hasil decode.

Patcher ini melakukan tiga hal:

1. Unduh engine 27 MB dari GitHub Release repo ini (tag `engine-v3.5.2`),
   verifikasi md5 (`785231328c…`), lalu pasang bersama lib yang cocok
   (`libpython3.14.so`, `libandroid-support.so`).
2. Jalankan fake license server yang membalas `POST /v1/device/check` dengan
   JSON VIP. `aio.scwill.store` diarahkan ke `127.0.0.1`.
3. Pasang fake verifier Ed25519 supaya tanda tangan license palsu bisa lolos.

Engine memilih backend kripto secara adaptif. Kalau paket `cryptography` ada,
ia memverifikasi lewat `Ed25519PublicKey.verify()` (implementasi Rust di
OpenSSL), bukan modul `Crypto.Signature.eddsa`. Artinya fake `eddsa.py` saja
tidak cukup. Patcher ini juga menimpa `cryptography/hazmat/primitives/
asymmetric/ed25519.py` supaya `verify()` jadi no-op.

## Gerbang kedua: `[Job/Claim]`

VIP tidak otomatis membuka semua tool. Sebagian tool, misalnya Smali Patcher,
memanggil endpoint kedua `POST /v1/job/claim`. Kalau gagal, hasilnya:

```
× GALAT   [Job/Claim] Server menolak claim SSL_PINNING_BYPASS (bukan VIP / offline).
```

Gate ini berjalan di sisi client. Bypass-nya lewat runtime monkeypatch fungsi
claim di engine: `_aio_job_claim`, `_aio_stamp_job_claim`,
`_aio_special_claim_apk`, `_aio_smart_build_token`, dan dua fungsi usage.

Dengan APK asli (F-Droid 11.9 MB), hasilnya engine memproses dua file DEX,
menjalankan patch, repack, zipalign, dan mempertahankan blok tanda tangan
V1/V2/V3. Keluarannya APK valid.

Satu syarat: hook hanya dimuat kalau stdin engine bukan tty. Di Linux ini
terjadi otomatis (systemd atau pipe). Di Termux, shell selalu tty, jadi pakai:

```bash
AIO_HOOK=1 aio
```

Mode itu menjalankan engine lewat `aio-session.py` yang memakai pipe, sehingga
hook dimuat dan tidak dimuat saat tty.

## Dependency Termux

Kalau install dari nol:

```bash
pkg install -y zip p7zip aapt openjdk-17 clang \
  python-pycryptodomex python-cryptography openssl-tool
pip install certifi requests
```

Beberapa catatan yang sudah kejadian di lapangan:

- Nama paketnya `python-pycryptodomex`, bukan `python-pycryptodome`.
- `certifi` dan `requests` tidak ada di repo Termux. Install lewat pip.
- `openssl-tool` berisi binary `openssl`. Paket `openssl` hanya library, tanpa
  binary, dan patcher butuh binary-nya.
- CA palsu harus ditambahkan ke `certifi/cacert.pem`, karena engine memakai
  certifi, bukan `/etc/tls/`. Patcher melakukannya otomatis.

## Troubleshooting

| Gejala | Penyebab |
|---|---|
| `[ Gratis PENGGUNA ]` + `Koneksi Gagal` | fake server tidak jalan. Cek `pgrep -f fakelicstls`. |
| `Tanda tangan respons server tidak valid`, `eddsa_hook.log` kosong | paket `cryptography` terpasang, engine pakai verifier Rust. Jalankan `./patch.sh install`. |
| `Tanda tangan respons server tidak valid` | fake `eddsa.py` tidak benar-benar terpasang, kalah oleh `.pyc` atau `.pyi`. |
| `TLSV1_ALERT_UNKNOWN_CA` di log fake server | CA palsu belum masuk `certifi/cacert.pem`. |
| Engine berhenti di `Sync resource toolkit...` | dependency kurang. Lihat bagian Dependency Termux. |
| `library "libpython3.14.so" not found` di Termux | `LD_LIBRARY_PATH` salah. Jangan pakai `/system/lib64` di Termux. |
| `ModuleNotFoundError: certifi` atau `requests` | `pip install certifi requests`. |
| `No module named '_cffi_backend'` | PyNaCl butuh cffi. Tidak wajib, fake server sekarang fallback ke `cryptography`. |
| `[Job/Claim] Server menolak claim` | jalankan dengan `AIO_HOOK=1 aio`. |
| Loading bar menumpuk newline | bar 92 kolom lebih lebar dari layar. Set `COLUMNS=80` atau perkecil font. |

## Struktur

```
termux/         patcher non-root (Android, native)
  bootstrap.sh    pemasang
  patch.sh        install / verify / revert
  files/          sitecustomize hook, wrapper, fake crypto
linux/          patcher sudo (systemd atau nohup, qemu)
shared/         fake TLS server + cert
FINDINGS.md     catatan reverse engineering
WALKTHROUGH.md  langkah analisis
```

## Batasan

- Menu Native Protector (`[10]`) belum jalan. Tool itu butuh compiler broker
  di server mereka, bukan sekadar gate lokal. Anda perlu kredensial `aioc_`
  asli untuk itu.
- Bypass ini bekerja di sisi client. Semua token yang dihasilkan palsu, dan
  hanya berlaku lokal.

## Konteks

Riset keamanan pada perangkat dan lingkungan sendiri, untuk memahami bagaimana
license gate pada binary Nuitka bekerja dan bagaimana verifikasi client-side
bisa dilewati. Catatan teknis lengkap ada di `FINDINGS.md`.
