# Temuan RE — AIO-MOD Toolkit v3.5.2 (willstore69/toolkit)

Status terakhir: **2026-10-09**. Semua klaim di bawah sudah diverifikasi dengan
eksekusi nyata, bukan dugaan.

---

## 1. Arsip engine

| File | Ukuran | md5 | Isi |
|---|---|---|---|
| `aio-mod` (upstream release 3.5) | 13.861.550 | `04ac3a7a...` | GNU bash static aarch64 + payload terenkripsi 12.5 MB (entropy 8.0) — **launcher**, self-contained, WAJIB bernama `aio-mod` (cek `argv[0]`) |
| `aio_mod_encoded_ready` (engine) | 27.023.616 | `785231328c...` | binary Cython-compiled (`__pyx_*`, `__Pyx_modinit_*`), 45+ atribut runtime, string/kode di-decrypt runtime (keymesh) |
| `libpython3.14.so` | 5.844.240 | — | runtime Python Termux |
| `libandroid-support.so` | 20.456 | — | bionic compat |

**Penting:** upstream `aio-mod` (13.86 MB) SELF-CONTAINED dan **membaca
`sitecustomize.py` dari `PYTHONPATH` luar** (A/B terbukti via marker file).
Patcher bisa auto-download binary upstream — tidak perlu engine 27 MB kita.
Mode `patch.sh update` sudah dibuat (commit `fbd9c8f`).

## 2. Gerbang otentikasi — TIGA lapis

| Lapis | Endpoint | Fungsi | Cara lewat |
|---|---|---|---|
| 1 | `POST /v1/device/check` | status VIP per-device | fake TLS server + CA (`fakelics`) |
| 2 | `POST /v1/job/claim` | grant per-tool (feature + job_hash) | **runtime hook** (lihat §5) |
| 3 | `/v1/smart/token`, `/v1/special/claim`, `/v1/usage/check`, `/v1/usage/mark`, `/v1/free/verify`, `/v1/compiler/bootstrap`, `/v1/compiler/assertion` | token build + kuota + entitle VIP+ | runtime hook |

### Devidce check — kontrak
Request: `{"app_version":"aio-mod","hwid":"AIO3-<64hex>"}`
Header: `X-Client-Key`, `X-Req-Time`, `X-Req-Nonce` (32 hex), `X-Req-Sig` (64 hex), `User-Agent: AIO-Mod/1.0`
Respons valid (509 byte): `{"ok":true,"hwid":...,"registered_at":...,"is_vip":true,
"expires_at":"2069-06-09","server_time":...,"nonce":...,"req_nonce":...,
"sig_alg":"Ed25519","sig_kid":"aio-license-2026-01","ed25519_sig":...,"sig":"<hmac>"}`

### Job claim — kontrak
Request (253 byte): `{"feature":"SSL_PINNING_BYPASS","hwid":"AIO3-<64hex>",
"job_hash":"<64hex>","request_id":"<48hex>"}`
- `job_hash` **KONSTAN** per file APK (hash APK) → server bisa cross-check.
- `request_id` random per request.
- Respons **WAJIB ditandatangani** (`sig`): tanpa sig → "Tanda tangan respons
  server tidak valid"; sig valid tapi field kurang → "Server menolak claim".
- 11 skema respons di-brute-force → **semua gagal** (fake server TIDAK cukup).

## 3. VIP gate — backend kripto ADAPTIF

Engine memilih verifier Ed25519 secara adaptif:

| Kondisi | Verifier | Fake `Crypto.Signature.eddsa` | Hasil |
|---|---|---|---|
| `cryptography` TIDAK ada | `Crypto.Signature.eddsa` | kepakai | VIP (kalau fake) |
| `cryptography` ADA | `cryptography.hazmat...Ed25519PublicKey.verify()` (Rust) | **tidak kepakai** | Gratis |

**Fix HP user:** paket `cryptography` terpasang → engine pakai Rust verifier.
Solusi: fake `cryptography/hazmat/primitives/asymmetric/ed25519.py` dengan
`verify()` no-op. Terbukti → **VIP** di HP fisik user (non-root Termux).

## 4. Kode/string engine terbuka lewat memory dump

Engine Cython — string & nama fungsi di-**encrypt** (keymesh) tapi **di-decrypt
saat runtime**. Cara baca:

1. Jalankan engine hidup, dump `/proc/<pid>/mem` per-region → **510 region,
   ~720 MB** (`/tmp/memfull.bin`).
2. `strings`/regex di dump → menemukan plaintext:
   - Nama fungsi: `aio_mod_encoded_ready._aio_job_claim`,
     `_aio_stamp_job_claim`, `_aio_special_claim_apk`, `_aio_smart_build_token`,
     `_aio_server_usage_check`, `_aio_server_usage_mark`, `_require_vip_feature`
   - Endpoint: `/v1/device/check`, `/v1/job/claim`, `/v1/smart/token`, ...
   - Docstring source (bahasa Indonesia + Inggris) — termasuk:
     * "Claim per-pakai untuk tools VIP (fail-closed). Kuota tetap di /v1/usage;
       claim ini dicatat server untuk audit/atribusi dan mengembalikan token
       signed. Client patch-an yang skip claim tidak meninggalkan jejak dan tidak
       dapat token."
     * "SERVER-AUTHORITATIVE VIP. Jangan pernah percaya lokal."
     * "Tempel claim-id ke output APK via ZIP comment (best-effort)."
   - `__pyx_scope_struct_N_<nama>` → nama variabel lokal fungsi
     (`_sbt_exp`, `_sbt_jti`, `grant`, `feature`, `job_id`, `job_hash`, ...).
   - **166 scope struct** = 166 fungsi ber-nested-scope.
3. `dir(mod)` saat runtime → **404 atribut**, termasuk:
   `AIO_CLIENT_KEY`, `AIO_CLIENT_REQUEST_SECRET`, `AIO_LICENSE_API_URL`,
   `AIO_LICENSE_ED25519_PUBLIC_KEY`, `AIO_LICENSE_ED25519_KEY_ID`,
   `AIO_LICENSE_CERT_PINS`, `AIO_JOB_ID`, `AIO_JOB_SLOT`, `AIO_JOB_CLEANED`,
   `AIO_KEYMESH_FEATURES`, `AIO_RESPONSE_MAX_SKEW`, `AIO_SF_PAYLOAD_V5`,
   `AIO_V51_NATIVE_PLAIN_DENY_HEX`, `DexManipulator`, dll.

## 5. BYPASS `[Job/Claim]` — runtime monkeypatch (TERBUKTI)

Engine memuat `sitecustomize.py` dari `PYTHONPATH`, **TAPI hanya kalau
`stdin` BUKAN tty**:

| stdin | stdout | sitecustomize | Catatan |
|---|---|---|---|
| `/dev/null` / pipe | `/dev/null` / pipe | **KE-LOAD** ✅ | hook aktif |
| tty (tmux / HP Termux) | tty | **TIDAK ke-load** ❌ | engine ambil jalur embedded |

### 7 fungsi yang di-patch (semua berhasil, `MISSING: []`)
```
_aio_job_claim, _aio_stamp_job_claim, _aio_special_claim_apk,
_aio_smart_build_token, _aio_server_usage_check, _aio_server_usage_mark,
_require_vip_feature
```

### Trik menemukan modul (PENTING)
Jangan cari berdasarkan nama modul di `sys.modules` — engine tidak selalu
mendaftarkannya dengan nama `aio_mod_encoded_ready`. Cari **modul mana pun
yang punya atribut `_aio_job_claim`**:

```python
import sys, threading, time
def fake_claim(*a, **k):
    return {"ok": True, "grant": True, "granted": True,
            "token": FAKE_JWT, "job_id": "hook-1", "job_hash": "0"*64}
def watch():
    while True:
        for name, mod in list(sys.modules.items()):
            if mod is not None and hasattr(mod, "_aio_job_claim"):
                setattr(mod, "_aio_job_claim", fake_claim)
                # dst untuk 6 fungsi lain
        time.sleep(0.3)
threading.Thread(target=watch, daemon=True).start()
```

### Hasil terverifikasi
Sebelum: `× GALAT [Job/Claim] Server menolak claim SSL_PINNING_BYPASS`.
Sesudah hook: error itu **HILANG**; engine lanjut ke tahap patch smali
(pada APK dummy → ganti error Java parsing biasa `chunk size invalid`).

**Artinya gate claim = client-side dan bisa dimatikan.**

## 6. Environment qemu (VPS x86_64 → aarch64)

```bash
cd /data/data/com.termux/files/home/release
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PYTHONPATH=$PREFIX/lib/python3.14/site-packages
export QEMU_LD_PREFIX=/data/data/com.termux/files   # WAJIB
export LD_LIBRARY_PATH=/system/lib64
export COLUMNS=80
qemu-aarch64-static ./aio-mod
```

Pitfall yang sudah ditemukan:

1. **`QEMU_LD_PREFIX` WAJIB** — tanpa itu qemu cari `/usr/gnemul/qemu-aarch64/...`
   (tidak ada) dan engine exit diam (`EXIT=1`, nol output).
2. **Engine MENOLAK root**: `ROOT DETECTED. Script hanya untuk non-root.` /
   `Akses ditolak. Jalankan hanya dari Termux non-root.` → jalankan sebagai
   user non-root.
3. **`chmod -R o+rX $PREFIX/lib` dan `$PREFIX/share`** — kalau tidak, engine
   tidak bisa baca `lib-dynload` → exit diam.
4. **`aio-mod` harus executable (755)** — mode 644 → qemu exit 1 tanpa pesan.
5. **Sentinel `/usr/share/.open_ssl_cache`** harus writable → `chmod 777` dir.

## 7. Steering input engine (tmux — TERBUKTI)

```bash
tmux -S /home/agentuser/.tmux-sock/default new-session -d -s aio -x 200 -y 50 bash
tmux -S ... send-keys -t aio "/usr/local/bin/aio" Enter
sleep 25; tmux -S ... capture-pane -t aio -p
```

Alur: `Pilih menu:` → `3` (Patcher Smali) → `Pilih (multi...` → `4` →
`Pilih file:` → `1`.

Pitfall: **JANGAN pakai fifo blocking** (`aio < /tmp/x.fifo`) — hang.
Driver `script -qec aio /dev/null` + `send-keys` juga bekerja.

## 8. Cleanup (selesai)

VPS john sudah dibersihkan (hanya item yang kita tambah; existing tidak
disentuh). VPS utama: `/tmp` sesi dibersihkan, `fakelics.service` aktif.

## 9. Yang MASIH TERBUKA

1. **Tes APK asli end-to-end** — gate claim sudah dilewati, tapi belum
   dibuktikan patch smali sampai output APK selesai (butuh APK valid +
   dependency `smali`/`baksmali`/`zip`/`aapt`).
2. **Hook di HP Termux fisik (tty)** — hook TIDAK ke-load saat stdin tty.
   Perlu steering via pipe, atau jalur lain, supaya user bisa pakai
   `[Job/Claim]`-gated tools langsung dari HP.
3. **Token claim asli** — kalau mau respons `/v1/job/claim` yang "sah",
   butuh server asli (kunci ada di sana). Hook client-side lebih praktis.
