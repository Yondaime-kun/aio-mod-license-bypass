#!/bin/bash
# =============================================================================
#  Shim /usr/bin/apt  —  dipakai AIO-MOD engine (path hardcoded).
#
#  Masalah: engine menjalankan `apt upgrade` yang lambat + tidak perlu, dan
#  progress bar-nya pakai \r sehingga di non-TTY menumpuk newline.
#
#  Shim ini:
#    - MEMBLOKIR 'upgrade' / 'dist-upgrade' / 'full-upgrade'  (instan, no-op)
#    - MENERUSKAN 'update' / 'install' / 'remove' ke apt asli
#    - Jika non-TTY: matikan progress bar sama sekali (--quiet)
#
#  Dipasang oleh patch.sh / patch-termux.sh ke $PREFIX/bin/apt (menimpa).
#  Backup asli: $PREFIX/bin/apt.asli
# =============================================================================
REAL_APT="/usr/bin/apt.asli"
# fallback: apt sistem asli
[ -x "$REAL_APT" ] || REAL_APT="/usr/bin/apt.real"
[ -x "$REAL_APT" ] || REAL_APT="$(command -v apt-get 2>/dev/null || echo /usr/bin/apt-get)"

# deteksi subcommand (lewati flag global spt -y/-qq)
SUB=""
for a in "$@"; do
  case "$a" in
    -*) continue ;;
    *) SUB="$a"; break ;;
  esac
done

# Blokir operasi upgrade (lambat & tak perlu)
case "$SUB" in
  upgrade|dist-upgrade|full-upgrade)
    echo "apt: upgrade dilewati (shim aio-patcher)"
    exit 0
    ;;
esac

# Non-TTY: paksa non-progress supaya tidak menumpuk \r
if [ ! -t 1 ]; then
  exec "$REAL_APT" -o quiet::no-progress=1 -o quiet::no-progress=1 "$@" 2>/dev/null \
    || exec "$REAL_APT" "$@"
fi
exec "$REAL_APT" "$@"
