#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  AIO-MOD  —  BOOTSTRAP untuk TERMUX (aarch64 native)
# =============================================================================
#  Di Termux, engine aarch64 jalan NATIVE (tanpa qemu) dan runtime Python
#  sudah tersedia via `pkg`. Jadi tidak perlu download .deb manual —
#  cukup install paket, taruh engine, lalu jalankan patch.sh.
#
#  Usage:  ./bootstrap-termux.sh
# =============================================================================
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
RELEASE_DIR="$HOME_DIR/release"
ENGINE_URL="https://github.com/willstore69/toolkit/releases/download/3.5/aio-mod"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_R="\033[0m"; C_G="\033[1;32m"; C_Y="\033[1;33m"; C_E="\033[1;31m"; C_C="\033[1;36m"
say()  { echo -e "${C_C}▸${C_R} $*"; }
ok()   { echo -e "${C_G}✓${C_R} $*"; }
warn() { echo -e "${C_Y}!${C_R} $*"; }
err()  { echo -e "${C_E}×${C_R} $*" >&2; }
die()  { err "$*"; exit 1; }

[ -d "$PREFIX" ] || die "Bukan Termux (PREFIX tak ditemukan). Pakai bootstrap.sh utk Linux."

# =============================================================================
# STEP 1 — Paket Termux (network tools + python deps)
# =============================================================================
step_pkgs() {
  say "Step 1/4  Install paket Termux (tanpa full upgrade)"
  command -v pkg >/dev/null 2>&1 || die "  'pkg' tak ada — ini bukan Termux?"
  # JANGAN 'pkg upgrade' — lambat & berisiko. Cukup refresh index + install yg perlu.
  # DEBIAN_FRONTEND noninteractive supaya apt gak nyangkut prompt "Y/n".
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y 2>&1 | tail -2 || true
  pkg install -y python python-pip python-pycryptodomex python-pynacl \
      python-cryptography openssl-tool curl 2>&1 | tail -3 || true
  ok "  paket terpasang"
}

# =============================================================================
# STEP 2 — Engine aio-mod (download upstream)
# =============================================================================
step_engine() {
  say "Step 2/4  Engine aio-mod"
  mkdir -p "$RELEASE_DIR"
  if [ -s "$RELEASE_DIR/aio-mod" ]; then
    ok "  sudah ada ($(stat -c%s "$RELEASE_DIR/aio-mod" 2>/dev/null || echo '?') bytes)"
    chmod +x "$RELEASE_DIR/aio-mod"
    return
  fi
  say "  download: $ENGINE_URL"
  curl -fL --retry 3 -o "$RELEASE_DIR/aio-mod" "$ENGINE_URL" || die "  download gagal"
  chmod +x "$RELEASE_DIR/aio-mod"
  ok "  engine terpasang ($(stat -c%s "$RELEASE_DIR/aio-mod") bytes)"
}

# =============================================================================
# STEP 3 — Bypass license
# =============================================================================
step_bypass() {
  say "Step 3/4  Terapkan bypass (patch.sh)"
  [ -x "$SELF_DIR/patch.sh" ] || die "  patch.sh tak ada"
  "$SELF_DIR/patch.sh" install
}

# =============================================================================
# STEP 4 — Verifikasi
# =============================================================================
step_verify() {
  say "Step 4/4  Verifikasi"
  local fail=0
  for base in Crypto Cryptodome; do
    local f="$PREFIX/lib/python3.14/site-packages/$base/Signature/eddsa.py"
    [ -e "$f" ] || continue
    grep -qi "bypass license verify" "$f" 2>/dev/null && ok "  fake: $base" || { warn "  $base bukan fake"; fail=1; }
  done
  [ -x "$PREFIX/bin/aio" ] && ok "  runner 'aio' siap" || { warn "  runner belum"; fail=1; }
  [ -s "$RELEASE_DIR/aio-mod" ] && ok "  engine siap" || { warn "  engine belum"; fail=1; }
  echo
  [ "$fail" = 0 ] && echo -e "${C_G}══ SIAP. Jalankan:  aio ══${C_R}" || echo -e "${C_Y}══ Ada catatan di atas ══${C_R}"
}

echo -e "${C_C}╔══════════════════════════════════════════════════╗"
echo -e "║  AIO-MOD  BOOTSTRAP  (Termux aarch64 native)     ║"
echo -e "╚══════════════════════════════════════════════════╝${C_R}"
step_pkgs
step_engine
step_bypass
step_verify
