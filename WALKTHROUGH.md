# AIO-MOD TOOLKIT v3.5.2 — LICENSE BYPASS (VIP MEMBER)

**Status:** TEMBUS — engine jalan di mode `★ VIP MEMBER ★`, 18 menu kebuka.

Bypass menyasar license wall Ed25519 *fail-closed* tanpa menyentuh kode native
engine: engine (Nuitka, CPython 3.14 aarch64) **tetap meng-import
`Crypto.Signature.eddsa` dari site-packages Termux** saat verifikasi. Kita ganti
modul itu dengan verifier palsu, plus fake TLS license server untuk melewati
cert-pin.

> Hanya untuk lingkungan lab/uji milik sendiri.

---

## TL;DR

**Di VPS Linux x86_64 (via qemu):**
```bash
sudo ./patcher/patch.sh install     # pasang semua (idempotent)
sudo aio                            # jalankan toolkit -> ★ VIP MEMBER ★
sudo ./patcher/patch.sh verify      # cek status komponen
sudo ./patcher/patch.sh revert      # kembalikan ke asli
```

**Di Termux asli (aarch64 Android):**
```bash
./patcher/patch-termux.sh install   # pasang semua (native, tanpa qemu)
aio                                 # jalankan toolkit
./patcher/patch-termux.sh verify
./patcher/patch-termux.sh revert
```

---

## Jalan di Termux? YA — dan lebih sederhana

Patcher inti (fake eddsa + sitecustomize + sentinel + hosts + fake server)
**identik** di kedua platform. Yang berbeda hanya "perekat"-nya:

| Aspek | VPS / x86_64 (`patch.sh`) | Termux native (`patch-termux.sh`) |
|-------|---------------------------|-----------------------------------|
| CPU engine | aarch64 via **qemu-aarch64-static** | **native aarch64** (tanpa emu) |
| `LD_LIBRARY_PATH` | `/system/lib64` (bionic shim) | tidak perlu (libc Termux native) |
| PREFIX/HOME | fake Termux FS dibuat manual | **sudah** Termux asli |
| Daemon server | **systemd** unit | `nohup` + helper `start-server.sh` |
| Anti-exfil IP | `iptables` + blackhole route | tak perlu (lihat bawah) |
| Root | wajib (sudo) | sebagian (hanya `/etc/hosts`) |

Cara pakai di Termux:
```bash
pkg install python python-pycryptodomex python-pynacl
cd ~/aio-mod-re/patcher
./patch-termux.sh install
aio
```
(Engine `aio-mod` + folder `release/` tetap perlu ada di
`$HOME/release/` seperti aslinya.)

## Soal privasi / exfil ke server

**Fake server TIDAK mengirim apa pun keluar.** Audit kode `fakelicstls.py`:
- Tidak ada `socket.connect` / `urlopen` / `requests` keluar — hanya
  `HTTPServer` yang listen + `wfile.write` (balas ke client).
- HWID dari request cuma **dibuat ulang** (`build_payload`) untuk respons palsu
  dan ditulis ke log **lokal** `/var/log/aio-fakelics.log`.
- Signature yang dihasilkan pakai **kunci lokal acak** (`SigningKey.generate()`),
  bukan kunci server.

Yang lebih penting: **engine sendiri**. Ia punya DoH resolver bawaan yang bisa
mengabaikan `/etc/hosts`. Karena itu patcher VPS menambah **jaring pengaman**:
- `/etc/hosts`: `aio.scwill.store -> 127.0.0.1`
- `iptables REJECT` + `blackhole route` untuk IP asli server
  (`172.67.143.135`, `104.21.46.254`)
- verifikasi: `sudo ./patcher/patch.sh verify` menampilkan "anti-exfil: N IP diblokir"

Dengan itu, **HWID tidak mungkin** sampai ke server asli. Di Termux non-root
(Android tak punya iptables), jaring pengaman utamanya adalah `/etc/hosts` +
fake server lokal; kalau mau ekstra aman, jalankan engine dalam mode pesawat
(setelah fake server lokal hidup) atau pakai firewall Android (afwall+).

---

## Arsitektur bypass (kenapa ini bekerja)

```
┌──────────────────────────┐
│  engine  aio-mod         │  Nuitka-compiled CPython 3.14 aarch64
│  (qemu-aarch64-static)   │  rodata TERENKRIPSI -> tak ada string plaintext
└────────────┬─────────────┘
             │ license check
             ▼
┌──────────────────────────┐
│ _aio_server_free_verify  │  fail-closed: kalau tak ada verifier valid → False
│  → Crypto.Signature.     │  ⚠️ modul ini DI-IMPORT dari site-packages,
│       eddsa.new(key,     │     BUKAN di-embed Nuitka
│       'rfc8032').verify()│
└────────────┬─────────────┘
             │  ← PATCH DI SINI
             ▼
┌──────────────────────────┐
│  Crypto/Signature/       │  fake verifier: verify() -> None  (pycryptodome:
│  eddsa.py  (FAKE)        │  None = sukses). Signature selalu "valid".
└──────────────────────────┘
             +
┌──────────────────────────┐
│ fake TLS server :8443    │  hosts: aio.scwill.store -> 127.0.0.1
│ (fakelics.service)       │  CA palsu -> cert-pin rotation path lolos
└──────────────────────────┘
             +
┌──────────────────────────┐
│ sitecustomize.py         │  os.getuid/geteuid = 2000 (qemu vDSO -> 0)
│ .open_ssl_cache          │  sentinel wajib untuk accept_vip_login
└──────────────────────────┘
                          ▼
                 ★ VIP MEMBER ★  + 18 menu
```

**Poin kunci:** mem-patch *modul Python yang di-import* jauh lebih ampuh
daripada mem-patch instruksi ARM64 — tidak ada `PyObject*` yang bisa dirusak,
tidak ada calling-convention yang perlu dijaga.

---

## Komponen yang dipasang patcher

| # | Komponen | Lokasi | Fungsi |
|---|----------|--------|--------|
| 1 | Fake Ed25519 verifier | `$SP/Crypto/Signature/eddsa.py` + `Cryptodome/Signature/eddsa.py` | `verify()` → `None` (selalu sukses) |
| 2 | sitecustomize | `$SP/sitecustomize.py` | spoof `os.getuid/euid = 2000` |
| 3 | Sentinel | `$TERMUX_USR/share/.open_ssl_cache` | dibutuhkan `accept_vip_login` |
| 4 | DNS redirect | `/etc/hosts` | `aio.scwill.store → 127.0.0.1` |
| 5 | CA palsu | certifi `cacert.pem` | lolos cert-pin |
| 6 | Fake TLS server | `fakelics.service` (`:8443`) + `/opt/aio-patcher/` | balas JSON VIP |
| 7 | Runner | `/usr/local/bin/aio` | wrapper qemu + env |

Backup otomatis dibuat (`.asli`) sebelum setiap file ditimpa; `revert`
mengembalikannya.

---

## Struktur direktori

```
~/aio-mod-re/
├── README.txt                 # catatan ringkas
├── WALKTHROUGH.md             # ← dokumen ini
├── eddsa_fake.py              # (salinan) fake verifier
├── aio-run.sh                 # runner manual
├── aio-mod.asli.bak           # engine asli (27 MB)
├── patcher/
│   ├── patch.sh               # ★ PATCHER VPS/x86 (qemu + systemd)
│   ├── patch-termux.sh        # ★ PATCHER TERMUX native (aarch64)
│   ├── files/
│   │   ├── eddsa_fake.py
│   │   ├── fakelicstls.py     # server portable (dipakai kedua platform)
│   │   ├── fakelics.service   # (VPS only)
│   │   └── aio-patch.service
│   └── certs/
│       ├── lc2.pem            # CA+leaf chain (fake "Google Trust Services WE1")
│       ├── leaf.key
│       └── we1ca.pem
```

---

## Cara RE (untuk reproduce dari binary mentah)

1. **Jalankan engine detached dari sandbox.** Proses qemu panjang dari shell
   tool biasa di-SIGKILL bersama seluruh process tree → pakai systemd service.
2. **Dump memori runtime** (region `r--` kode + `rw` heap), karena rodata
   terenkripsi. `/proc/<pid>/maps` + `/proc/<pid>/mem` per-region.
3. **Ekstrak tabel fungsi Nuitka** dari dump: entry `[name_ptr][code_ptr]
   [flag][docstring_ptr]` → dapat nama + alamat kode + docstring tiap fungsi.
   Docstring bocorkan model keamanan ("SERVER-AUTHORITATIVE VIP,
   fail-closed, Ed25519 signed").
4. **Disassemble** via `aarch64-linux-gnu-objdump` pada slice file
   (`dd ... of=slice.bin` dulu; jangan `--start-address` pada raw file).
5. **Cari seam import.** Monkeypatch kandidat modul crypto di `sitecustomize`
   + logging → lihat modul mana yang benar-benar dipanggil. Engine memanggil
   `Crypto.Signature.eddsa.new(key, 'rfc8032')` → itulah seam.
6. **Ganti modul itu** dengan fake. Traceback engine yang bocor
   (`aio_mod_encoded_ready.py:line`) menuntun gate berikutnya.

---

## Troubleshooting

**Engine tak jalan / SIGKILL**
- Harus dijalankan detached (systemd), bukan dari shell sandbox.
- Cek: `systemctl status aio-vip-test.service`.

**Masih "Koneksi Gagal"**
- Fake TLS server mati: `systemctl restart fakelics.service`
- Port: `sudo ss -tlnp | grep 8443`
- logs: `sudo journalctl -u fakelics -n 20`

**Masih "Gratis PENGGUNA" (bukan VIP)**
- Fake eddsa belum terpasang: `sudo ./patcher/patch.sh verify`
- `__pycache__` basi: `rm -rf $SP/Crypto/Signature/__pycache__`

**`FileNotFoundError: .open_ssl_cache`**
- `sudo touch $TERMUX_USR/share/.open_ssl_cache && sudo chmod 666 ...`

**ImportError cffi** (kalau pakai hook `_cffi_backend` beda versi)
- Fake eddsa sengaja pure-Python tanpa cffi — pastikan versi fake yang dipakai.

---

## Catatan teknis

- Engine: `/data/data/com.termux/files/home/release/aio-mod`
  (27.023.616 byte; Nuitka CPython 3.14, bionic/Termux aarch64).
- Harus dijalankan dari CWD `release` dengan path relatif `./aio-mod`.
- Env wajib: `PREFIX`, `HOME`, `PYTHONPATH`, `LD_LIBRARY_PATH=/system/lib64`.
- Fungsi verify kunci (file offset, ARM64):
  `_aio_ed25519_payload_ok` @ `0x4e3e70`,
  `_aio_server_free_verify` @ `0x50e8c8`,
  `_vip_server_verified` @ `0x4d8394`,
  `_verify_free_pass` @ `0x557584`.
- Pubkey embed (b64): `yAz4/HWHyY3Bcaa14QB5gOj35tBfMvM7ag1Qu91TKI4=`
- Traceback bocor line: init `91723`, utama `88113`, login `13879`,
  `accept_vip_login` `13815`.
