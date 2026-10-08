#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  Shim apt  —  dipakai AIO-MOD engine (engine memanggil `apt`, path hardcoded).
#
#  Masalah: engine menjalankan `apt upgrade` yang lambat + tidak perlu, dan
#  progress bar-nya pakai \r sehingga di non-TTY menumpuk newline.
#
#  Shim ini:
#    - MEMBLOKIR 'upgrade' / 'dist-upgrade' / 'full-upgrade'  (instan, no-op)
#    - MENERUSKAN 'update' / 'install' / 'remove' ke apt asli
#    - Jika non-TTY: matikan progress bar sama sekali
#
#  PENTING (fix lapangan): apt asli Termux ada di $PREFIX/bin/apt, BUKAN
#  /usr/bin/apt. Shim versi lama menunjuk /usr/bin/apt.asli -> tak ketemu ->
#  `pkg install` mati ("cannot execute: required file not found"). Di sini
#  REAL_APT di-resolve relatif ke lokasi shim ini sendiri, jadi benar di
#  Termux ($PREFIX/bin) maupun di Linux (fake Termux FS /usr/bin).
# =============================================================================
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_APT=""
for c in "$SELF_DIR/apt.asli" "$SELF_DIR/apt.real" \
         "/usr/bin/apt.asli" "/usr/bin/apt.real"; do
  [ -x "$c" ] && { REAL_APT="$c"; break; }
done
[ -n "$REAL_APT" ] || REAL_APT="$(command -v apt-get 2>/dev/null || echo "$SELF_DIR/apt-get")"

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

# Non-TTY: matikan progress bar supaya tidak menumpuk \r saat di-log.
if [ ! -t 1 ]; then
  exec "$REAL_APT" -o quiet::no-progress=1 "$@"
fi
exec "$REAL_APT" "$@"
