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
    curl -fL --retry 3 --connect-timeout 15 --max-time 600 -o "$deb" "$TERMUX_REPO_BASE/$url" || { warn "  download $pkg gagal"; return 1; }
  fi
  rm -rf "$WORKDIR/x_$pkg"
  dpkg-deb -x "$deb" "$WORKDIR/x_$pkg" 2>/dev/null || { warn "  extract $pkg gagal"; return 1; }
  # copy isi data/data/com.termux/files/usr/* -> dest
  if [ -d "$WORKDIR/x_$pkg/data/data/com.termux/files/usr" ]; then
    # pastikan dest writable (bootstrap buat sbg root, bisa 700 root-only) —
    # tanpa ini cp gagal diam-diam & paket "terpasang" padahal kosong.
    chmod 755 "$dest" 2>/dev/null || true
    [ -d "$dest/bin" ] && chmod 755 "$dest/bin" 2>/dev/null || true
    [ -d "$dest/lib" ] && chmod 755 "$dest/lib" 2>/dev/null || true
    cp -a "$WORKDIR/x_$pkg/data/data/com.termux/files/usr/." "$dest/" \
      || warn "  copy $pkg -> $dest gagal (izin?)"
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
  for p in python python-pycryptodomex python-pynacl python-cryptography openssl libsodium libffi zlib libbz2 liblzma libexpat libsqlite; do
    deb_fetch_extract "$p" || true
  done
  # toolkit runtime: dependency yang engine sendiri minta saat "Configure"
  # (java, zip, 7z, aapt, zipalign, clang, ndk-multilib, smali/baksmali via
  # resource zip). Tanpa ini, VIP tetap jalan tapi menu modding APK gagal.
  say "  4a2. dependency toolkit (java/zip/7z/aapt/apktool/clang/ndk)"
  for p in openjdk-21 openjdk-17 zip 7zip aapt android-tools clang lld llvm \
           libcompiler-rt make cmake libc++ ndk-multilib \
           ndk-multilib-native-static ndk-multilib-native-stubs ndk-sysroot \
           aapt2 apksigner apktool d8 dx ecj \
           libandroid-shmem libiconv libandroid-execinfo libandroid-spawn \
           radare2 nodejs; do
    deb_fetch_extract "$p" || true
  done
  mkdir -p "$TERMUX_USR/bin"
  # openjdk Termux menaruh binernya di usr/lib/jvm/.../bin (bukan usr/bin);
  # engine mencari 'java' via PATH -> sambungkan ke usr/bin.
  for jb in "$TERMUX_USR"/lib/jvm/*/bin/java "$TERMUX_USR"/lib/jvm/*/bin/*; do
    [ -x "$jb" ] || continue
    local jn; jn="$(basename "$jb")"
    [ -e "$TERMUX_USR/bin/$jn" ] || ln -sf "$jb" "$TERMUX_USR/bin/$jn" 2>/dev/null
  done
  [ -e "$TERMUX_USR/bin/java" ] && ok "  java -> $(readlink -f "$TERMUX_USR/bin/java" 2>/dev/null)" \
    || warn "  java tak ditemukan di paket openjdk"
  # alias Cryptodome <- Crypto (pycryptodomex tidak menyediakan alias)
  if [ -d "$SPT/Crypto" ] && [ ! -d "$SPT/Cryptodome" ]; then
    ln -sfn Crypto "$SPT/Cryptodome" 2>/dev/null && ok "  alias Cryptodome -> Crypto dibuat"
  fi

  # --- 4b. Paket PURE-PYTHON via pip wheel (enggan pakai deb) ---
  say "  4b. paket pure-python (pip wheel)"
  local wheeldir="$WORKDIR/wheels"
  mkdir -p "$wheeldir"
  local pure="certifi requests urllib3 idna charset-normalizer tqdm colorama packaging \
    r2pipe 'protobuf<4' gpapi hermes_dec hbctool pycryptodome pynacl frida frida-tools"
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
      # coba wheel dulu (cepat); kalau tak ada wheel, jatuh ke sdist.
      timeout 120 "$PYH" -m pip download --no-deps --only-binary=:all: --dest "$wheeldir" $missing >/dev/null 2>&1 \
        || timeout 120 "$PYH" -m pip download --no-deps --dest "$wheeldir" $missing >/dev/null 2>&1 \
        || warn "  pip download timeout/gagal — lanjut (deps opsional)"
      # install: wheel -> unzip; sdist (.tar.gz) -> tar + setup.py tidak jalan
      # (pure-python saja), jadi ekstrak module top-level langsung.
      for whl in "$wheeldir"/*.whl; do
        [ -e "$whl" ] || continue
        unzip -oq "$whl" -d "$SPT" 2>/dev/null && ok "  install $(basename "$whl")" || true
      done
      for tgz in "$wheeldir"/*.tar.gz; do
        [ -e "$tgz" ] || continue
        local b; b="$(basename "$tgz" .tar.gz)"
        rm -rf "$WORKDIR/sd_$b"; mkdir -p "$WORKDIR/sd_$b"
        tar -xzf "$tgz" -C "$WORKDIR/sd_$b" 2>/dev/null || continue
        # cari direktori package di dalam sdist
        local pdir
        pdir="$(find "$WORKDIR/sd_$b" -maxdepth 2 -type d -name "$b" 2>/dev/null | head -1)"
        [ -z "$pdir" ] && pdir="$(find "$WORKDIR/sd_$b" -maxdepth 2 -type d -name "${b%%-*}" 2>/dev/null | head -1)"
        if [ -n "$pdir" ]; then
          cp -a "$pdir" "$SPT/" 2>/dev/null && ok "  install sdist $b" || true
        else
          warn "  sdist $b: package dir tak ditemukan"
        fi
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
  say "Step 5/6  Libs aarch64 (bionic lengkap + libpython -> /system/lib64)"
  mkdir -p "$SYS64" /system/bin
  # Satu tar berisi SELURUH closure yang engine butuh: linker64 (PT_INTERP),
  # libc/libc++/liblog/libz/libbz2/libffi/libsodium/libcrypto/libssl/libsqlite...
  # Termasuk libpython3.14.so versi spesifik. Sumber: environment yang terbukti
  # jalan. Diambil dari release bypass + verifikasi md5.
  local bl="$WORKDIR/bionic-libs.tar.gz"
  local need=1
  # sudah lengkap kalau linker64 + libpython3.14 + libz.so.1 + libc++.so ada
  [ -s /system/bin/linker64 ] && [ -s "$SYS64/libpython3.14.so" ] \
    && [ -e "$SYS64/libz.so.1" ] && [ -e "$SYS64/libc++.so" ] && need=0
  if [ "$need" = 1 ]; then
    say "  download bionic libs lengkap"
    if curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$bl" "$BIONIC_URL"; then
      tar -xzf "$bl" -C / 2>/dev/null || warn "  extract bionic gagal"
      chmod 755 /system/bin/linker64 2>/dev/null || true
      ok "  bionic libs -> /system (+$SYS64)"
    else
      warn "  bionic libs gagal diunduh — engine tak akan jalan"
    fi
  else
    ok "  bionic libs sudah lengkap"
  fi
  # linkerconfig: tanpa ini linker64 (bionic) tak menemukan /system/lib64 ->
  # engine keluar diam-diam tepat setelah start (exit 1, nol output).
  if [ ! -e /linkerconfig/ld.config.txt ]; then
    mkdir -p /linkerconfig
    printf 'dir.system = /system/${LIB}\ndir.system.cfi = /system/${LIB}/cfi\n' \
      > /linkerconfig/ld.config.txt 2>/dev/null \
      && ok "  /linkerconfig/ld.config.txt dibuat" \
      || warn "  linkerconfig gagal dibuat"
  else
    ok "  /linkerconfig/ld.config.txt sudah ada"
  fi
  [ -s "$SYS64/libpython3.14.so" ] \
    && ok "  libpython$PY_MAJOR tersedia" \
    || warn "  libpython$PY_MAJOR belum ada — engine akan gagal load"
}

# =============================================================================
# STEP 5c — QEMU wrapper utk binary aarch64 di fake Termux bin
# =============================================================================
# Host x86_64 tidak bisa menjalankan binary aarch64 (java/clang/aapt/...).
# Engine memanggil mereka lewat PATH -> bungkus tiap ELF aarch64 dengan qemu
# supaya toolkit (modding APK) benar-benar berfungsi, bukan cuma VIP.
step_emu_shims() {
  say "Step 5c/6  Bungkus binary aarch64 (Termux bin) dengan qemu"
  local bindir="$TERMUX_USR/bin"
  [ -d "$bindir" ] || { warn "  $bindir tak ada — skip"; return 0; }
  local qemu; qemu="$(command -v qemu-aarch64-static || echo /usr/bin/qemu-aarch64-static)"
  # lib aarch64 (libjvm butuh libandroid-shmem/libiconv/...) harus terlihat
  # oleh linker bionic -> taruh di /system/lib64 (LD_LIBRARY_PATH shim).
  local libdir="$TERMUX_USR/lib"
  if [ -d "$libdir" ]; then
    local n=0
    for l in "$libdir"/*.so "$libdir"/*.so.*; do
      [ -e "$l" ] || continue
      local lb; lb="$(basename "$l")"
      [ -e "$SYS64/$lb" ] || { cp -a "$l" "$SYS64/" 2>/dev/null && n=$((n+1)); }
    done
    ok "  $n lib aarch64 -> $SYS64"
  fi
  local made=0 skip=0
  for f in "$bindir"/*; do
    [ -f "$f" ] || continue
    local b; b="$(basename "$f")"
    case "$b" in *.asli|*.jar|*.zip|*.bin|apt) continue ;; esac
    # identifikasi ELF aarch64 (machine 0xb7) lewat magic header
    local hdr; hdr="$(od -An -tx1 -N20 "$f" 2>/dev/null | tr -d ' \n')"
    case "$hdr" in 7f454c46*) : ;; *) continue ;; esac
    local mach="${hdr:36:2}"; [ "$mach" = "b7" ] || { skip=$((skip+1)); continue; }
    # sudah shim? (cek shebang)
    head -c2 "$f" 2>/dev/null | grep -q '#!' && continue
    mv -f "$f" "$f.aarch64.bin" 2>/dev/null || continue
    cat > "$f" <<EOF
#!/usr/bin/env bash
export TERMUX_PREFIX="$TERMUX_USR"
export PREFIX="$TERMUX_USR"
export HOME="$TERMUX_HOME"
export JAVA_HOME="\$(dirname "\$(dirname "\$(readlink -f "\$0")")")"
export LD_LIBRARY_PATH="$SYS64:$TERMUX_USR/lib"
exec "$qemu" "$f.aarch64.bin" "\$@"
EOF
    chmod 755 "$f"
    made=$((made+1))
  done
  ok "  $made binary dibungkus qemu ($skip non-aarch64 dilewati)"
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
step_emu_shims
step_bypass
echo
ok "Bootstrap selesai. Jalankan:  sudo aio"
