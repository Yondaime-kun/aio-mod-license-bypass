#!/data/data/com.termux/files/usr/bin/bash
# UJI ISOLASI: ganti sitecustomize bergantian, lihat mana yg bikin gagal.
set -u
HOME_DIR="$HOME"; RELEASE_DIR="$HOME_DIR/release"
DEFLOG="$HOME_DIR/.aio-patcher"
SP="$(python3 -c 'import site;print(site.getsitepackages()[0])' 2>/dev/null || echo "$PREFIX/lib/python3.14/site-packages")"
CAND=("$RELEASE_DIR/sitecustomize.py" "$SP/sitecustomize.py" "$HOME_DIR/.local/lib/python3.14/site-packages/sitecustomize.py")

show() { echo "  -> $1"; }

echo "════════ UJI ISOLASI sitecustomize ════════"
# simpan yg asli
for f in "${CAND[@]}"; do [ -f "$f" ] && cp -f "$f" "$f.iso-bak" 2>/dev/null; done

run_case() {
  local label="$1" src="$2"
  echo ""; echo "── KASUS: $label ──"
  # pasang sitecustomize sumber ke semua lokasi
  for f in "${CAND[@]}"; do
    mkdir -p "$(dirname "$f")" 2>/dev/null
    if [ -n "$src" ]; then cp -f "$src" "$f" 2>/dev/null; else rm -f "$f" 2>/dev/null; fi
  done
  rm -rf "$RELEASE_DIR/__pycache__" 2>/dev/null
  find "$PREFIX/lib/python3.14/site-packages" -name "__pycache__" -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  rm -f "$PREFIX/share/.open_ssl_cache"
  pkill -9 -f fakelicstls 2>/dev/null; sleep 1
  nohup python3 "$DEFLOG/fakelicstls.py" > "$DEFLOG/iso-srv.log" 2>&1 &
  sleep 2
  ( cd "$RELEASE_DIR" && timeout 25 ./aio-mod ) > "$DEFLOG/iso-run.log" 2>&1
  echo "  hasil:"
  tr '\r' '\n' < "$DEFLOG/iso-run.log" | grep -aE "VIP MEMBER|Gratis|tidak valid|Koneksi" | sort -u | head -4 | sed 's/^/    /'
  echo "  redirect: $(grep -c 'getaddrinfo' "$DEFLOG/sc_min.log" 2>/dev/null || echo 0) getaddrinfo"
}
