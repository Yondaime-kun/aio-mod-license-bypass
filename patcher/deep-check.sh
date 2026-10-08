#!/data/data/com.termux/files/usr/bin/bash
# Cek diagnosa mendalam: kenapa sitecustomize gak ke-load di engine Termux
RELEASE_DIR="$HOME/release"
echo "=== 1. ISI RUNNER aio (apakah versi baru?) ==="
cat "$PREFIX/bin/aio"
echo
echo "=== 2. TES LANGSUNG: engine load sitecustomize? ==="
cd "$RELEASE_DIR"
PREFIX="$PREFIX" HOME="$HOME" PYTHONPATH="$PREFIX/lib/python3.14/site-packages:$RELEASE_DIR" \
  ./aio-mod --help >/tmp/eng_direct.log 2>&1 &
ENGPID=$!
sleep 6
kill $ENGPID 2>/dev/null
echo "redirect log (kalau shim kena, ada isinya):"
cat /tmp/aio_redirect.log 2>/dev/null || echo "  KOSONG"
echo
echo "=== 3. TES: python bisa import sitecustomize dari mana? ==="
cd "$RELEASE_DIR"
python3 -c "
import sys
sys.path.insert(0, '$RELEASE_DIR')
sys.path.insert(0, '$PREFIX/lib/python3.14/site-packages')
try:
    import sitecustomize
    print('sitecustomize dari:', sitecustomize.__file__)
    print('punya _dns_redirect:', hasattr(sitecustomize, '_dns_redirect'))
except Exception as e:
    print('import gagal:', e)
"
echo
echo "=== 4. Apakah engine punya stdlib sendiri? (cek isi release/) ==="
ls "$RELEASE_DIR" | head -20