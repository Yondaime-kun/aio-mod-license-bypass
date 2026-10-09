# Termux (Android): patcher NATIVE (aarch64)

Bypass AIO-MOD Toolkit langsung di **Termux asli** (Android ARM64), tanpa emulasi.
Engine 27MB (Nuitka, ARM aarch64) dijalankan native pakai bionic Android -
jauh lebih cepat daripada qemu di Linux.

## Status tested (jujur)

| Platform | Versi | Hasil |
|---|---|---|
| **Termux di Android 12 ARM64** (container redroid, fingerprint realme RMX3615) | Python 3.14.6, aarch64, SDK 31 | ✅ **★ VIP MEMBER ★** + Smali Patcher |
| **Termux di HP fisik** (non-root, Android 12/13) | Python 3.14.x | ✅ **★ VIP MEMBER ★** |

Yang **sudah terbukti**: `patch.sh install` selesai tanpa gagal, `aio` masuk
menu, banner `★ VIP MEMBER ★`.

**Perbedaan yang diharapkan di HP fisik (non-root)**, ditangani otomatis oleh patcher:
- `iptables` tidak tersedia/tidak diizinkan → dialihkan ke redirect socket
  `sitecustomize`; kalau engine tetap Gratis, blokir IP license dari luar Termux.
- `/etc/hosts` tidak bisa ditulis → sama, dialihkan ke `sitecustomize`.

## Pakai

```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/termux
./bootstrap.sh       # install paket + unduh engine + terapkan bypass
aio                  # jalankan → ★ VIP MEMBER ★
```

Kalau `pkg` melaporkan `apt ... required file not found` (shim apt lama sempat
menimpa paket `apt`), restore:

```bash
cp -f $PREFIX/bin/apt.asli $PREFIX/bin/apt 2>/dev/null
dpkg --configure -a --force-confnew 2>&1 | tail -2
pkg install -y apt
```

## Kalau masih `[ Gratis PENGGUNA ]`

```bash
./diagnose.sh
```

Urutan cek berikut **urutan penyebab yang terbukti di lapangan**, dari yang paling sering:

0. **Paket `cryptography` terpasang.** **INI PENYEBAB #1 di HP fisik.** Engine memilih
   backend verifikasi secara adaptif: kalau `cryptography` ada, ia memakai
   `cryptography.hazmat...Ed25519PublicKey.verify()` (implementasi RUST) dan
   **mengabaikan `Crypto.Signature.eddsa`**, jadi fake eddsa tak berpengaruh →
   `× GALAT Tanda tangan respons server tidak valid` → `[ Gratis PENGGUNA ]`.
   Gejala khas: `~/.aio-patcher/eddsa_hook.log` **tidak pernah dibuat** walau
   `Crypto/Signature/eddsa.py` sudah fake. Cek & perbaiki:
   ```bash
   python3 -c "import cryptography; print(cryptography.__version__)"   # kalau ada -> ini penyebabnya
   ls -la ~/.aio-patcher/cryptography_hook.log                          # harus ada + berisi 'BYPASS'
   ./patch.sh install        # Step 1b menimpa cryptography/.../ed25519.py
   ```
   Patcher menimpa `cryptography/hazmat/primitives/asymmetric/ed25519.py`
   dengan `verify()` no-op. Tidak perlu uninstall `cryptography`.

1. **Fake `Crypto.Signature.eddsa` TIDAK terpasang.** Berlaku saat `cryptography`
   **tidak** ada (engine jatuh ke pycryptodome). `.pyc` lama / `eddsa.pyi` bisa
   menang atas file hasil copy, sehingga engine tetap memakai verifier ASLI → Gratis. Cek:
   ```bash
   grep -c "bypass license verify" $PREFIX/lib/python3.14/site-packages/Crypto/Signature/eddsa.py
   ```
   Harus `1`. Kalau `0`:
   ```bash
   pkg install -y python-pycryptodomex
   rm -f $PREFIX/lib/python3.14/site-packages/Crypto/Signature/eddsa.pyi
   ./patch.sh install
   ```
2. **CA palsu tidak ada di `certifi/cacert.pem`** → handshake ditolak
   (`TLSV1_ALERT_UNKNOWN_CA`) → engine jatuh ke Gratis. Patcher menyisipkan
   root CA + leaf ke `cacert.pem` **dan** `etc/tls/cert.pem`. Cek jumlah cert:
   ```bash
   grep -c "BEGIN CERT" $PREFIX/lib/python3.14/site-packages/certifi/cacert.pem
   ```
   Bawaan certifi 121; setelah patch 124–130.
3. **Dependency engine kurang** → engine berhenti di
   `Install paket utama AIO-MOD...` / `Sync resource toolkit...`, tak sampai menu.
   ```bash
   pkg install -y zip unzip p7zip aapt openjdk-17 clang python
   ```
4. **Server license asli masih bisa dihubungi.** Engine me-resolve host lewat
   DoH sendiri → `/etc/hosts` **diabaikan**. Kalau `iptables` tersedia patcher
   mem-REJECT IP asli; kalau tidak (Termux non-root normal), `sitecustomize`
   mengalihkan socket ke `127.0.0.1`. Kalau tetap Gratis & kamu punya akses root:
   ```bash
   iptables -A OUTPUT -d 172.67.143.135 -j REJECT
   iptables -A OUTPUT -d 104.21.46.254  -j REJECT
   ```
5. **Fake server tanpa PyNaCl** → signature respons invalid
   (`Tanda tangan respons server tidak valid`). Install:
   ```bash
   pkg install python-pynacl
   pkg install python-certifi python-requests   # atau: python3 -m pip install certifi requests
   ./patch.sh install
   ```

## JANGAN lakukan ini (jebakan yang sudah terbukti)

- **Jangan set `LD_LIBRARY_PATH=/system/lib64` di Termux native.** Linker
  Android namespace `default` tidak memuat lib kita, dan `/system` bionic beda
  versi → `CANNOT LINK EXECUTABLE: library "libpython3.14.so" not found`.
  Pakai `$ENGINE_DIR:$PREFIX/lib` (runner sudah begitu).
- **Jangan timpa `$PREFIX/bin/apt`.** dpkg gagal `Setting up apt`
  (`dpkg returned an error code (1)`) dan `pkg install` mati total. Shim apt
  ada di `~/.aio-patcher/shim-bin/apt` (lebih depan di PATH).
- **Menimpa `eddsa.py` harus disertai `touch` + bersihkan `__pycache__`**,
  kalau tidak `.pyc` lama tetap dipakai.

## File

| File | Fungsi |
|---|---|
| `bootstrap.sh` | install paket + unduh engine + panggil `patch.sh` |
| `patch.sh` | patcher utama (install/verify/revert), non-root |
| `diagnose.sh` | cek semua komponen + tunjukkan apa yang kurang |
| `deep-check.sh` | diagnosa mendalam (isi runner, load sitecustomize) |
| `files/sitecustomize.py` | spoof uid + redirect server + shrink bar |
| `files/eddsa_fake.py` | fake verifier pycryptodome |
| `files/apt-shim.sh` | shim `apt` (blokir `upgrade`, tanpa menyentuh paket apt) |

## Perintah

```bash
./patch.sh install   # terapkan bypass (unduh binary upstream otomatis)
./patch.sh update    # ambil binary upstream versi terbaru saja
./patch.sh verify    # cek status
./patch.sh revert    # kembalikan seperti semula
./diagnose.sh
```

Patcher **idempotent**, aman diulang. File yang di-patch di-backup `.asli`.

## Update ke versi baru (auto)

Jalur utama `aio` sekarang adalah **binary resmi dari `willstore69/toolkit`**
yang diunduh otomatis, bukan engine dari repo ini.

```bash
./patch.sh update     # ambil binary upstream versi terbaru
aio
```

Cara kerja:

1. Cek GitHub API `willstore69/toolkit/releases/latest` → ambil URL aset
   `aio-mod`. Kalau API gagal (rate limit/offline), fallback ke tag tetap `3.5`.
2. Binary disimpan sebagai `~/.aio-patcher/upstream/aio-mod`. **Nama file WAJIB
   `aio-mod`**; binary memeriksa `argv[0]`, nama lain membuatnya keluar
   diam-diam tanpa output (gejala: `EXIT=0` tanpa teks apa pun).
3. Runner `aio` memprioritaskan binary upstream; engine 27MB hanya fallback.

**Kenapa bisa:** binary `aio-mod` upstream *self-contained*, membawa engine-nya
sendiri (payload terenkripsi ±12 MB di dalam file 13.8 MB) **dan tetap membaca
`sitecustomize.py` + `site-packages` dari `PYTHONPATH` luar**. Terbukti: dengan
`PYTHONPATH` → sitecustomize kita ke-load; tanpa → tidak. Jadi patch kita
(fake `eddsa`/`cryptography`, redirect, fake TLS server) berlaku langsung
terhadap binary upstream apa adanya.

Ketika upstream merilis versi baru, cukup `./patch.sh update`.

## Catatan
- Binary upstream **hanya jalan kalau namanya `aio-mod`** (cek `argv[0]`).
- Loading bar engine lebarnya ~92 kolom; di layar HP bar-wrap jadi newline.
  Perkecil font / landscape, atau biarkan (murni kosmetik).
- Redirect server via Python berarti engine tidak perlu `/etc/hosts`.
