#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  diagnose.sh — cek kenapa AIO-MOD masih "Gratis PENGGUNA" di Termux
#  Usage:  ./patcher/diagnose.sh
# =============================================================================
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# HOME bisa salah kalau dijalankan via sudo; deteksi lokasi release yg benar
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
[ -d "$HOME_DIR/release" ] || HOME_DIR="/data/data/com.termux/files/home"
SP="$PREFIX/lib/python3.14/site-packages"
# fallback kalau versi python beda
[ -d "$SP" ] || SP=$(ls -d "$PREFIX"/lib/python3.*/site-packages 2>/dev/null | head -1)
RELEASE_DIR="$HOME_DIR/release"

G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; C='\033[1;36m'; N='\033[0m'
ok(){ echo -e "${G}✓${N} $*"; }
no(){ echo -e "${R}✗${N} $*"; }
wr(){ echo -e "${Y}!${N} $*"; }
hd(){ echo -e "\n${C}== $* ==${N}"; }

hd "Lingkungan"
echo "  PREFIX = $PREFIX"
echo "  SP     = $SP"
echo "  arch   = $(uname -m)"
[ -d "$PREFIX" ] && ok "PREFIX ada" || no "PREFIX TIDAK ada — ini bukan Termux?"
[ -d "$SP" ] && ok "site-packages ada" || no "site-packages TIDAK ada: $SP"

hd "1. Fake Ed25519 verifier (INTI BYPASS)"
found_fake=0
for base in Crypto Cryptodome; do
  f="$SP/$base/Signature/eddsa.py"
  if [ -e "$f" ]; then
    if grep -qi "bypass license verify" "$f" 2>/dev/null; then
      ok "$base/Signature/eddsa.py = FAKE"
      found_fake=1
    else
      no "$base/Signature/eddsa.py = ASLI (belum di-patch!)  size=$(stat -c%s "$f")"
    fi
  else
    wr "$base/Signature/eddsa.py TIDAK ADA (paket $base beda struktur?)"
  fi
done
[ "$found_fake" = 1 ] || no ">>> TIDAK ADA fake verifier -> INI penyebab Gratis PENGGUNA"

hd "2. Paket crypto yg terpasang"
pip list 2>/dev/null | grep -iE "crypto|nacl" || echo "  (pip list kosong)"
echo "  --- alias Crypto -> Cryptodome:"
if [ -d "$SP/Crypto" ]; then
  ok "Crypto ada"
elif [ -d "$SP/Cryptodome" ]; then
  no "Crypto TIDAK ada (cuma Cryptodome) -> engine import 'Crypto' GAGAL"
  echo "     fix: ln -sfn Cryptodome $SP/Crypto"
else
  no "Cryptodome/Crypto dua-duanya TIDAK ada -> pkg install python-pycryptodomex"
fi
echo "  --- isi Signature/ yg ada:"
for base in Crypto Cryptodome; do
  [ -d "$SP/$base/Signature" ] && echo "    $base/Signature/: $(ls "$SP/$base/Signature" 2>/dev/null | tr '\n' ' ')"
done
echo "  --- test import (yg dipakai engine):"
python3 -c "import Crypto.Signature.eddsa; print('    OK import Crypto.Signature.eddsa')" 2>&1 | tail -1

hd "3. sitecustomize"
if [ -e "$SP/sitecustomize.py" ]; then
  grep -q "getuid" "$SP/sitecustomize.py" && ok "spoof uid ada" || wr "spoof uid TIDAK ada"
  grep -q "ShrinkStream\|_shrink" "$SP/sitecustomize.py" && ok "bar shrinker ada" || wr "bar shrinker TIDAK ada (opsional)"
  grep -q "_install_net_redirect\|getaddrinfo" "$SP/sitecustomize.py" && ok "network redirect shim ada (WAJIB utk non-root)" || no "network redirect shim TIDAK ada -> engine gak bisa connect ke fake server"
else
  no "sitecustomize.py TIDAK ada"
fi

hd "3c. sitecustomize di lokasi yg dipindai Nuitka"
_ok=0
for loc in "$HOME_DIR/release/sitecustomize.py" "$HOME_DIR/.local/lib/python3.14/site-packages/sitecustomize.py"; do
  if [ -e "$loc" ] && grep -q "aio.scwill.store" "$loc" 2>/dev/null; then
    ok "ada + shim network: $loc"
    _ok=1
  elif [ -e "$loc" ]; then
    wr "ada tapi TANPA shim network: $loc (versi lama?)"
  fi
done
[ "$_ok" = 1 ] || no "sitecustomize TIDAK ada di lokasi yang dipindai engine (release/ atau .local/)"
echo "     (Nuitka standalone scan CWD=release/, bukan site-packages)"

hd "4. Sentinel .open_ssl_cache"
[ -e "$PREFIX/share/.open_ssl_cache" ] && ok "ada" || no "HILANG — buat: touch $PREFIX/share/.open_ssl_cache"

hd "5. Engine"
if [ -s "$RELEASE_DIR/aio-mod" ]; then
  ok "engine ada: $RELEASE_DIR/aio-mod ($(stat -c%s "$RELEASE_DIR/aio-mod") bytes)"
  [ -x "$RELEASE_DIR/aio-mod" ] && ok "executable" || no "TIDAK executable — chmod +x"
else
  no "engine TIDAK ada di $RELEASE_DIR/aio-mod"
fi

hd "6. Fake TLS server (opsional, buat login)"
if pgrep -f fakelicstls >/dev/null 2>&1; then
  ok "fakelicstls proses jalan"
  # cek port beneran listen
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -q ":8443" && ok "port 8443 LISTEN" || no "port 8443 TIDAK listen (server mati?)"
  fi
  # test koneksi nyata ke fake server
  if python3 -c "import socket;s=socket.create_connection(('127.0.0.1',8443),timeout=3);print('connect OK');s.close()" 2>/dev/null; then
    ok "koneksi ke 127.0.0.1:8443 BERHASIL"
  else
    no "koneksi ke 127.0.0.1:8443 GAGAL (fake server tak respons)"
  fi
else
  wr "fakelicstls TIDAK jalan"
fi
echo "  --- redirect engine (jalankan 'aio' lalu cek):"
[ -s /tmp/aio_redirect.log ] && ok "redirect log ada: $(wc -l < /tmp/aio_redirect.log) baris" || echo "  (redirect log kosong — jalankan 'aio' dulu utk test)"
grep -q "aio.scwill.store" /etc/hosts 2>/dev/null && ok "/etc/hosts redirect ada" || echo "  /etc/hosts: (non-root, dilewati — pakai shim Python)"

hd "KESIMPULAN"
if [ "$found_fake" = 1 ]; then
  ok "Fake verifier AKTIF — seharusnya VIP. Kalau masih Gratis, restart Termux (cache pyc) & jalankan ulang."
else
  no "Fake verifier TIDAK aktif -> ini penyebab Gratis PENGGUNA."
  echo
  echo -e "  ${Y}Perbaiki dengan:${N}"
  echo "    1) pastikan pycryptodome terpasang:"
  echo "         pkg install python-pycryptodomex   # atau: pip install pycryptodomex"
  echo "    2) jalankan patcher:"
  echo "         ./patcher/patch-termux.sh install"
  echo "    3) hapus cache:"
  echo "         rm -rf $SP/Crypto/Signature/__pycache__ $SP/__pycache__"
  echo "    4) jalankan: aio"
fi
