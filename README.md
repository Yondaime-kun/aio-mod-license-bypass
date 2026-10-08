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

## Cara pakai

### Di Termux (aarch64 native) — paling gampang
```bash
pkg install python python-pycryptodomex python-pynacl git
git clone <repo-url> aio-mod-re && cd aio-mod-re
# letakkan engine aio-mod + folder release/ di ~/release/ (ambil sendiri dari upstream)
./patcher/patch-termux.sh install
aio
```

### Di Linux x86_64 (via qemu-aarch64-static)
```bash
sudo ./patcher/patch.sh install
sudo aio
```

### Perintah umum
```bash
./patcher/patch.sh verify     # cek status semua komponen
./patcher/patch.sh revert     # kembalikan ke kondisi asli
```

Patcher bersifat **idempotent** — aman dijalankan berulang. Setiap file yang
di-patch di-backup `.asli` sebelum ditimpa.

---

## Isi repo

```
patcher/
├── patch.sh          # patcher Linux/x86 (qemu + systemd)
├── patch-termux.sh   # patcher Termux native (aarch64, tanpa qemu)
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
dump memori/artefak RE. Ambil engine aslinya sendiri dari upstream.

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
