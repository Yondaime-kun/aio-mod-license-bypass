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
| **Termux aarch64** (Android) | Python 3.14.6 | ⚠️ **belum VIP** — engine 27MB **SEGV/fallback** saat dijalankan native | shim `sitecustomize` (non-root) |

Catatan jujur per platform:

- **Linux x86_64**: terbukti VIP, **dari lingkungan bersih** — `git clone` →
  `bootstrap.sh` → `aio`. Bootstrap otomatis mengunduh engine 27MB + libpython
  yang cocok dari GitHub Release repo ini, menyiapkan fake Termux FS, qemu,
  fake TLS server, runner, dan redirect. Diuji di dua VPS berbeda (satu dengan
  systemd, satu kontainer tanpa systemd).
- **Termux (non-root)**: **belum tuntas.** Engine 27MB (dynamic, butuh
  `libpython3.14.so` + `libandroid-support.so` versi spesifik) berjalan tapi
  jatuh ke mode *Gratis* dengan pesan `Tanda tangan respons server tidak valid`,
  dan kadang `signal 11` saat dipaksa memakai libpython dari release. Server
  fake terbukti benar (nonce cocok, `sig` valid, `is_vip:true`), engine identik
  dengan yang sukses di Linux, tapi verifikasi tetap gagal di lingkungan
  Termux native. Bagian yang belum terpecahkan: kompatibilitas ABI engine
  27MB dengan Termux native vs. lingkungan emulasi qemu.

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
> Termux **belum** mencapai VIP saat README ini ditulis — lihat bagian
> *Status tested*. Perintah di atas menjalankan apa yang sudah ada.
> Detail: [`termux/README.md`](termux/README.md)

## Troubleshooting

| Gejala | Penyebab / cek |
|---|---|
| `[ Gratis PENGGUNA ]` + `Koneksi Gagal` | fake server hidup? `pgrep -f fakelicstls` |
| `Tanda tangan respons server tidak valid` | `req_nonce` respons ≠ `X-Req-Nonce` request |
| `library "libpython3.14.so" not found` | lib dari release belum terpasang di `/system/lib64` (Linux) |
| `library "libandroid-support.so" not found` | `libandroid-support.so` belum ada di samping libpython |
| Loading bar numpuk newline | bar 92 char > lebar layar → `COLUMNS=80` / perkecil font |
| Termux `Koneksi Gagal` | shim DNS di `sitecustomize` + fake server |

## Struktur
```
├── termux/       patcher non-root (Android)
├── linux/        patcher sudo (systemd/nohup + qemu)
├── shared/       fake TLS server + certs
├── FINDINGS.md   catatan RE
└── WALKTHROUGH.md
```
