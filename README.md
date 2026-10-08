# AIO-MOD Toolkit — License Bypass Research (VIP)

Reverse-engineering write-up + automated patcher untuk **AIO-MOD Toolkit v3.5.2**
(release `willstore69/toolkit`), sebuah engine Python ter-*compile* Nuitka
(CPython 3.14, aarch64/Android-Termux) yang dilindungi license wall Ed25519
*fail-closed*.

Hasil akhir: engine berjalan di mode **`★ VIP MEMBER ★`** dengan 18 menu penuh
terbuka, dan **tidak ada data (HWID) yang dikirim ke server asli**.

> ⚠️ **Hanya untuk riset keamanan & lingkungan milik sendiri.** Tujuannya
> mendokumentasikan teknik RE terhadap binary Python ter-*compile* + proteksi
> license. Jangan pakai pada sistem yang bukan milikmu.

---

## Ringkasan temuan

| Pertanyaan | Jawaban |
|-----------|---------|
| Ada bytecode Python untuk di-patch? | **Tidak** — Nuitka meng-*compile* ke kode C native. |
| `strings` binary mengungkap logic? | **Tidak** — rodata terenkripsi, plaintext hanya di memory runtime. |
| Titik masuk bypass? | **Import module** — engine tetap `import Crypto.Signature.eddsa` dari site-packages (bukan di-embed). |
| Kenapa fail-closed bisa dilewati? | Verifier Ed25519 diganti fake `verify()` → `None` (pycryptodome: None = sukses). |
| Bagaimana dengan cert-pin? | Fake TLS server lokal + CA palsu meniru issuer; pin "rotated" lolos. |
| HWID terkirim ke server asli? | **Tidak** — fake server lokal, hosts redirect, + blokir IP asli. |

Detail lengkap ada di **[WALKTHROUGH.md](WALKTHROUGH.md)**.

---

## Cara pakai — FULL AUTO (engine di-download otomatis)

**Tidak perlu download apa pun manual.** Bootstrap mengunduh engine + runtime
sendiri.

### Di Termux (aarch64 native) — paling gampang
```bash
pkg install git
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass
./patcher/bootstrap-termux.sh    # install paket + download engine + bypass
aio
```

### Di Linux x86_64 (via qemu-aarch64-static)
```bash
sudo apt install qemu-user-static binutils curl unzip
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass
sudo ./patcher/bootstrap.sh      # download engine + Termux .deb + deps + bypass
sudo aio
```

**Apa yang di-download bootstrap:**
- Engine `aio-mod` dari GitHub release upstream (`willstore69/toolkit` @ 3.5)
- Runtime Python 3.14 + deps (`.deb` dari repo resmi Termux)
- Wheel pure-python (certifi/requests/tqdm/...) via pip
- Bypass license diterapkan otomatis (memanggil `patch.sh`)

> Kalau mau pakai engine yang sudah ada (taruh sendiri di `~/release/aio-mod`),
> bootstrap akan mendeteksi & melewati langkah download.

### Perintah umum
```bash
./patcher/patch.sh verify     # cek status semua komponen (VPS)
./patcher/patch.sh revert     # kembalikan ke kondisi asli
./patcher/patch-termux.sh verify   # versi Termux
```

Patcher bersifat **idempotent** — aman dijalankan berulang. Setiap file yang
di-patch di-backup `.asli` sebelum ditimpa.

---

## Isi repo

```
patcher/
├── bootstrap.sh          # ★ FULL AUTO: download engine + runtime + bypass (x86)
├── bootstrap-termux.sh   # ★ FULL AUTO (Termux native)
├── patch.sh              # patcher Linux/x86 (qemu + systemd)
├── patch-termux.sh       # patcher Termux native (aarch64, tanpa qemu)
├── files/
│   ├── eddsa_fake.py     # verifier Ed25519 palsu (inti bypass)
│   ├── fakelicstls.py    # fake license TLS server
│   ├── fakelics.service  # unit systemd (VPS)
│   └── aio-patch.service
└── certs/                # CA + leaf palsu (buatan sendiri, bukan kunci asli)
    ├── lc2.pem
    ├── leaf.key
    └── we1ca.pem
```

**Tidak disertakan** (lihat `.gitignore`): engine `aio-mod` (~27 MB) dan semua
dump memori/artefak RE — tapi **`bootstrap.sh` mengunduhnya otomatis**, jadi
kamu tetap tak perlu ambil manual.

---

## Environment yang dibutuhkan

- Engine asli `aio-mod` (release 3.5) — **tidak** disertakan, ambil dari upstream.
- Termux: `python`, `python-pycryptodomex` (atau paket `Crypto`/`Cryptodome`),
  `python-pynacl`.
- x86_64: `qemu-user-static`, `systemd`, `python3-pynacl`.
- Engine harus dijalankan dari CWD `release/` dengan path relatif `./aio-mod`.

## Keamanan / privasi

- Fake server **tidak** membuka koneksi keluar (tidak ada `socket.connect` /
  `requests`); hanya listen lokal & menulis log lokal.
- Patcher VPS menambah `iptables REJECT` + blackhole route ke IP server asli,
  sehingga HWID tak mungkin sampai ke sana meskipun engine punya DoH resolver
  sendiri yang mengabaikan `/etc/hosts`.
- Di Termux non-root: jaring pengaman = hosts redirect + fake server lokal
  (opsional: mode pesawat / firewall Android).
