# Linux / VPS (x86_64) — patcher SUDO

Bypass AIO-MOD Toolkit di Linux x86_64 dengan hak root: menjalankan engine
aarch64 lewat `qemu-aarch64-static`, fake server via **systemd**, redirect
license host lewat **`/etc/hosts`**, dan `iptables` untuk mencegah HWID keluar.

## Pakai

```bash
sudo apt install qemu-user-static binutils curl unzip python3-pynacl
git clone https://github.com/Yondaime-kun/aio-mod-license-bypass.git
cd aio-mod-license-bypass/linux
sudo ./bootstrap.sh
sudo aio
```

## Komponen yang dipasang

1. Engine `aio-mod` → `~/release/aio-mod` (diunduh otomatis, dijalankan via qemu)
2. Runtime Python 3.14 Termux (`.deb`) + deps di `/data/data/com.termux/...`
3. Fake `Crypto/Cryptodome.Signature.eddsa` + `sitecustomize.py`
4. **`/etc/hosts`:** `aio.scwill.store` → `127.0.0.1`
5. **`fakelics.service`** (systemd) — fake TLS server di `:8443`
6. **`iptables`** REJECT ke IP server asli + shim `apt` (skip `upgrade`)

## Perintah

```bash
sudo ./patch.sh install   # terapkan semua
sudo ./patch.sh verify    # cek status
sudo ./patch.sh revert    # kembalikan asli
```

Cek service & log:
```bash
systemctl status fakelics
journalctl -u fakelics -n 20
ss -tlnp | grep 8443
```

## Troubleshooting

| Gejala | Cek |
|---|---|
| `Koneksi Gagal` | `systemctl status fakelics` → harus **active** |
| `Tanda tangan respons server tidak valid` | fakelics **harus** jalan di Python bernacl (venv/`python3-pynacl`) |
| Grafik/bar aneh | tidak masalah di VPS (log non-TTY) |

> **Penting:** fake server di VPS berjalan lewat **systemd unit `fakelics`**.
> Jangan matikan dengan `pkill` lalu start manual pakai python sistem —
> pakai Python yang punya `nacl`, kalau tidak signature jadi tidak valid.
