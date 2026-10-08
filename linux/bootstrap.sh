#!/usr/bin/env bash
# =============================================================================
#  AIO-MOD TOOLKIT  —  FULL AUTO BOOTSTRAP  (Linux x86_64 host)
# =============================================================================
#  Skrip ini menyiapkan SELURUH lingkungan dari nol secara otomatis:
#    1. Engine aio-mod          (download dari GitHub release upstream)
#    2. Fake Termux filesystem  (PREFIX + HOME)
#    3. Python 3.14 runtime     (download .deb Termux, extract)
#    4. Deps Python             (certifi/requests/pycryptodome/pynacl/...)
#    5. Bionic libs             (linker64 + libc dari AOSP sys-img)
#    6. Bypass license          (panggil patch.sh)
#
#  Hasil: `sudo aio` langsung jalan mode ★ VIP MEMBER ★.
#
#  Target: Ubuntu/Debian x86_64 dengan qemu-user-static.
#  Untuk Termux native, file engine ditaruh di ~/release lalu pakai
#  patch-termux.sh saja (runtime Termux sudah native — tak perlu langkah 2-5).
#
#  Usage:  sudo ./bootstrap.sh
# =============================================================================
set -euo pipefail

# ─── konfigurasi ─────────────────────────────────────────────────────────────
TERMUX_USR="/data/data/com.termux/files/usr"
TERMUX_HOME="/data/data/com.termux/files/home"
RELEASE_DIR="$TERMUX_HOME/release"
SYS64="/system/lib64"
WORKDIR="${AIO_WORKDIR:-$TERMUX_HOME/.aio-bootstrap}"

# Engine 27MB (decoded, dynamic) — BUKAN file 13.8MB upstream (itu launcher).
ENGINE_BYPASS_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/aio-mod-engine"
ENGINE_MD5="785231328c86e8e3e24f8a2c7f149814"
LIBPY_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/libpython3.14.so"
LIBPY_MD5="778aec5978a4f2b47b2fc6f81ad2262f"
LIBAS_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/libandroid-support.so"
LIBAS_MD5="1506571136dcb594e28db729e9c9f4e1"
BIONIC_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/bionic-libs.tar.gz"
# dipertahankan utk referensi (launcher upstream, tidak dipakai)
ENGINE_URL="https://github.com/willstore69/toolkit/releases/download/3.5/aio-mod"

# Termux packages (aarch64) — dari repo resmi Termux
TERMUX_REPO_BASE="https://packages-cf.termux.dev/apt/termux-main"
TERMUX_REPO_INDEX="$TERMUX_REPO_BASE/dists/stable/main/binary-aarch64/Packages"
# Python 3.14 + deps; versi bisa berubah -> resolve dinamis via script
PY_MAJOR=3.14

AOSP_IMG="https://dl.google.com/android/repository/sys-img/android/arm64-v8a-34_r02.zip"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_R="\033[0m"; C_G="\033[1;32m"; C_Y="\033[1;33m"; C_E="\033[1;31m"; C_C="\033[1;36m"
say()  { echo -e "${C_C}▸${C_R} $*"; }
ok()   { echo -e "${C_G}✓${C_R} $*"; }
warn() { echo -e "${C_Y}!${C_R} $*"; }
err()  { echo -e "${C_E}×${C_R} $*" >&2; }
die()  { err "$*"; exit 1; }

[ "$(id -u)" = "0" ] || die "Harus root: sudo $0"
for t in curl ar dpkg-deb qemu-aarch64-static; do
  command -v "$t" >/dev/null 2>&1 || die "tool '$t' tak ada. Install: apt install qemu-user-static binutils curl"
done

mkdir -p "$WORKDIR"

# =============================================================================
# STEP 1 — Engine aio-mod (engine 27MB decoded, bukan launcher 13.8MB upstream)
# =============================================================================
step_engine() {
  say "Step 1/6  Engine aio-mod (engine 27MB dari release bypass)"
  mkdir -p "$RELEASE_DIR"
  # File upstream (13.8MB) = LAUNCHER/installer, bukan engine. Engine 27MB
  # (dynamic, butuh libpython) diambil dari release repo bypass ini.
  if [ -s "$RELEASE_DIR/aio-mod" ] && \
     [ "$(stat -c%s "$RELEASE_DIR/aio-mod" 2>/dev/null || echo 0)" -gt 20000000 ]; then
    ok "  sudah ada: $RELEASE_DIR/aio-mod ($(stat -c%s "$RELEASE_DIR/aio-mod") bytes)"
    return
  fi
  local out="$WORKDIR/aio-mod"
  say "  download: $ENGINE_BYPASS_URL"
  curl -fL --retry 3 --connect-timeout 15 --max-time 180 -o "$out" "$ENGINE_BYPASS_URL" || die "  download engine gagal"
  # verifikasi md5 engine yang diharapkan
  local got; got="$(md5sum "$out" | cut -d' ' -f1)"
  if [ -n "${ENGINE_MD5:-}" ] && [ "$got" != "$ENGINE_MD5" ]; then
    die "  md5 engine tidak cocok (got $got, want $ENGINE_MD5)"
  fi
  install -m755 "$out" "$RELEASE_DIR/aio-mod"
  ok "  engine terpasang: $(stat -c%s "$RELEASE_DIR/aio-mod") bytes"
}

# =============================================================================
# STEP 2 — Fake Termux filesystem
# =============================================================================
step_fs() {
  say "Step 2/6  Fake Termux filesystem"
  mkdir -p "$TERMUX_USR" "$TERMUX_HOME" "$TERMUX_USR/bin" "$TERMUX_USR/lib" \
           "$TERMUX_USR/share" "$TERMUX_USR/lib/python$PY_MAJOR/site-packages" \
           "$SYS64"
  ok "  $TERMUX_USR + $TERMUX_HOME siap"
}

# =============================================================================
# STEP 3 — Python 3.14 runtime (Termux .deb) + stdlib
# =============================================================================
deb_fetch_extract() {
  # $1 = nama paket (tanpa versi), $2 = dest prefix (default Termux usr)
  local pkg="$1" dest="${2:-$TERMUX_USR}"
  local deb="$WORKDIR/$pkg.deb"
  if [ ! -s "$deb" ]; then
    # Resolve dari index resmi Termux (Packages) -> field Filename
    local url
    url=$(curl -fsL --connect-timeout 10 --max-time 30 "$TERMUX_REPO_INDEX" 2>/dev/null \
          | awk -v p="$pkg" '
              /^Package: /{cur=$2}
              /^Filename: /{fn=$2; if(cur==p){print fn; exit}}')
    if [ -z "$url" ]; then
      # fallback: cari partial match (mis. python-pycryptodomex)
      url=$(curl -fsL --connect-timeout 10 --max-time 30 "$TERMUX_REPO_INDEX" 2>/dev/null \
            | awk -v p="$pkg" '
                /^Package: /{cur=$2}
                /^Filename: /{fn=$2; if(index(cur,p)>0){print fn; exit}}')
    fi
    [ -n "$url" ] || { warn "  paket tak ditemukan di index: $pkg"; return 1; }
    say "    fetch $pkg"
    curl -fL --retry 3 --connect-timeout 15 --max-time 180 -o "$deb" "$TERMUX_REPO_BASE/$url" || { warn "  download $pkg gagal"; return 1; }
  fi
  rm -rf "$WORKDIR/x_$pkg"
  dpkg-deb -x "$deb" "$WORKDIR/x_$pkg" 2>/dev/null || { warn "  extract $pkg gagal"; return 1; }
  # copy isi data/data/com.termux/files/usr/* -> dest
  if [ -d "$WORKDIR/x_$pkg/data/data/com.termux/files/usr" ]; then
    cp -a "$WORKDIR/x_$pkg/data/data/com.termux/files/usr/." "$dest/" 2>/dev/null || true
  fi
  return 0
}

step_python() {
  say "Step 3/6  Python 3.14 runtime + stdlib (Termux .deb)"
  # Cek apakah libpython sudah ada
  if [ -s "$SYS64/libpython$PY_MAJOR.so" ] || ls "$TERMUX_USR/lib/libpython"* >/dev/null 2>&1; then
    ok "  libpython$PY_MAJOR sudah ada"
  else
    warn "  libpython belum ada. Diperlukan mirror .deb Termux."
    warn "  Jika auto-download gagal, taruh manual di $WORKDIR lalu ulangi."
    deb_fetch_extract "python" || true
  fi
  # stdlib
  if [ ! -d "$TERMUX_USR/lib/python$PY_MAJOR" ]; then
    warn "  stdlib python$PY_MAJOR belum ada — coba dari paket python"
    deb_fetch_extract "python" || true
  fi
  [ -d "$TERMUX_USR/lib/python$PY_MAJOR" ] \
    && ok "  stdlib python$PY_MAJOR siap" \
    || warn "  stdlib belum lengkap (bisa ditambah manual)"
}

# =============================================================================
# STEP 4 — Deps Python (site-packages)
# =============================================================================
step_deps() {
  say "Step 4/6  Deps Python (deb native + pip wheel)"
  local SPT="$TERMUX_USR/lib/python$PY_MAJOR/site-packages"

  # --- 4a. Paket NATIVE dari .deb Termux (butuh library .so aarch64) ---
  say "  4a. paket native (deb Termux)"
  # CATATAN: cffi tidak punya paket deb di Termux (dikirim sebagai wheel);
  # tapi _cffi_backend sudah dibundel di beberapa paket / bisa dari wheel.
  for p in python python-pycryptodomex python-pynacl python-cryptography openssl libsodium libffi; do
    deb_fetch_extract "$p" || true
  done
  # alias Cryptodome <- Crypto (pycryptodomex tidak menyediakan alias)
  if [ -d "$SPT/Crypto" ] && [ ! -d "$SPT/Cryptodome" ]; then
    ln -sfn Crypto "$SPT/Cryptodome" 2>/dev/null && ok "  alias Cryptodome -> Crypto dibuat"
  fi

  # --- 4b. Paket PURE-PYTHON via pip wheel (enggan pakai deb) ---
  say "  4b. paket pure-python (pip wheel)"
  local wheeldir="$WORKDIR/wheels"
  mkdir -p "$wheeldir"
  local pure="certifi requests urllib3 idna charset-normalizer tqdm colorama packaging"
  local have
  have=$(ls "$SPT" 2>/dev/null | tr 'A-Z' 'a-z')
  local missing=""
  for p in $pure; do
    if echo "$have" | grep -qi "$(echo "$p" | tr -d -- '-_')"; then
      ok "  ada: $p"
    else
      missing="$missing $p"
    fi
  done
  if [ -n "$missing" ]; then
    say "  download wheel:${missing}"
    # pip download bisa HANG kalau pypi lambat/blocked -> batasi waktu keras.
    local PYH
    PYH=$(command -v python3 || true)
    if [ -n "$PYH" ]; then
      timeout 90 "$PYH" -m pip download --no-deps --only-binary=:all: --dest "$wheeldir" $missing >/dev/null 2>&1 \
        || timeout 90 "$PYH" -m pip download --no-deps --dest "$wheeldir" $missing >/dev/null 2>&1 \
        || warn "  pip download timeout/gagal — lanjut (deps opsional)"
      for whl in "$wheeldir"/*.whl; do
        [ -e "$whl" ] || continue
        unzip -oq "$whl" -d "$SPT" 2>/dev/null && ok "  install $(basename "$whl")" || true
      done
    else
      warn "  python3 host tak ada — deps pure-python harus manual"
    fi
  fi
}

# =============================================================================
# STEP 5 — Bionic/Android libs
# =============================================================================
# CATATAN: qemu-aarch64-static memakai HOST loader, jadi `linker64` TIDAK
# diperlukan. Yang dibutuhkan hanya shared lib aarch64 (libc/libm/libz/...)
# yang justru SUDAH dibawa oleh paket .deb Termux (libandroid-support, dll).
# Jadi step ini memastikan lib dari deb dipindah juga ke /system/lib64
# (sebagian engine mencarinya di sana), + verifikasi.
step_bionic() {
  say "Step 5/6  Libs aarch64 (libpython + libandroid dari release -> /system/lib64)"
  mkdir -p "$SYS64"
  # Engine 27MB butuh libpython3.14.so + libandroid-support.so yang SPESIFIK
  # (bukan versi .deb Termux biasa). Ambil dari release bypass + verifikasi md5.
  # delimiter '|' (bukan ':' — URL mengandung ':')
  for pair in "libpython3.14.so|$LIBPY_URL|$LIBPY_MD5" \
              "libandroid-support.so|$LIBAS_URL|$LIBAS_MD5"; do
    local name="${pair%%|*}"
    local rest="${pair#*|}"
    local url="${rest%%|*}"
    local md5="${rest##*|}"
    local dst="$SYS64/$name"
    if [ -s "$dst" ] && [ "$(md5sum "$dst" | cut -d' ' -f1)" = "$md5" ]; then
      ok "  $name sudah ada & md5 cocok"
      continue
    fi
    say "  download $name"
    if curl -fL --retry 3 --connect-timeout 15 --max-time 240 -o "$dst.tmp" "$url"; then
      local got; got="$(md5sum "$dst.tmp" | cut -d' ' -f1)"
      if [ "$got" = "$md5" ]; then
        mv -f "$dst.tmp" "$dst"; chmod 644 "$dst"
        ok "  $name terpasang ($(stat -c%s "$dst") bytes)"
      else
        rm -f "$dst.tmp"; warn "  $name md5 salah ($got) — dilewati"
      fi
    else
      warn "  $name gagal diunduh"
    fi
  done
  # lib lain dari .deb Termux (opsional)
  local src="$TERMUX_USR/lib"
  if [ -d "$src" ]; then
    for lib in libc.so libm.so libz.so libffi.so libsodium.so; do
      [ -e "$src/$lib" ] && [ ! -e "$SYS64/$lib" ] && cp -a "$src/$lib" "$SYS64/" 2>/dev/null || true
    done
  fi

  # BIONIC: engine ELF nya PT_INTERP = /system/bin/linker64 (WAJIB ada, kalau
  # tidak qemu-aarch64-static gagal "Could not open '/system/bin/linker64'").
  # linker64 + libc bionic tidak ada di .deb Termux biasa -> ambil dari release.
  if [ ! -s /system/bin/linker64 ]; then
    local bl="$WORKDIR/bionic-libs.tar.gz"
    say "  download bionic libs (linker64 + libc)"
    if curl -fL --retry 3 --connect-timeout 15 --max-time 240 -o "$bl" "$BIONIC_URL"; then
      mkdir -p /system/bin "$SYS64"
      tar -xzf "$bl" -C / 2>/dev/null && chmod 755 /system/bin/linker64 2>/dev/null || true
      [ -s /system/bin/linker64 ] && ok "  /system/bin/linker64 siap" || warn "  linker64 gagal extract"
    else
      warn "  bionic libs gagal diunduh — engine tak akan jalan"
    fi
  else
    ok "  /system/bin/linker64 sudah ada"
  fi
  [ -s "$SYS64/libpython$PY_MAJOR.so" ] \
    && ok "  libpython$PY_MAJOR tersedia" \
    || warn "  libpython$PY_MAJOR belum ada — engine akan gagal load"
}

# =============================================================================
# STEP 6 — Bypass license (delegasi ke patch.sh)
# =============================================================================
step_bypass() {
  say "Step 6/6  Terapkan bypass license (patch.sh)"
  if [ -x "$SELF_DIR/patch.sh" ]; then
    "$SELF_DIR/patch.sh" install
  else
    warn "  patch.sh tak ada di $SELF_DIR — jalankan manual setelah bootstrap"
  fi
}

# =============================================================================
# MAIN
# =============================================================================
echo -e "${C_C}╔══════════════════════════════════════════════════╗"
echo -e "║  AIO-MOD  FULL AUTO BOOTSTRAP  (x86_64 host)     ║"
echo -e "╚══════════════════════════════════════════════════╝${C_R}"
step_engine
step_fs
step_python
step_deps
step_bionic
step_bypass
echo
ok "Bootstrap selesai. Jalankan:  sudo aio"
