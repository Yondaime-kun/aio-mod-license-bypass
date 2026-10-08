#!/data/data/com.termux/files/usr/bin/bash
# A/B test: apakah sitecustomize MEMBANTU atau malah MERUSAK?
set +e
SP="$PREFIX/lib/python3.14/site-packages"
RD="$HOME/release"
LIB="$HOME/libaio_redirect.so"

echo "════════ TEST A: sitecustomize AKTIF (sekarang) ════════"
rm -f "$HOME/aio_redirect.log" /tmp/aio_redirect.log
cd "$RD"
AIO_DEBUG=1 PREFIX="$PREFIX" HOME="$HOME" \
  PYTHONPATH="$SP:$RD" \
  timeout 15 ./aio-mod </dev/null 2>&1 | tr '\r' '\n' | grep -aE "VIP MEMBER|Gratis|Koneksi|Menyiapkan|\[net\]|Traceback|Error" | head -8
echo "-- log:"; cat "$HOME/aio_redirect.log" 2>/dev/null | head -3 || echo "   KOSONG"

echo
echo "════════ TEST B: sitecustomize DINONAKTIFKAN ════════"
mv "$SP/sitecustomize.py" "$SP/sitecustomize.py.off" 2>/dev/null
mv "$RD/sitecustomize.py" "$RD/sitecustomize.py.off" 2>/dev/null
rm -rf "$SP/__pycache__" "$RD/__pycache__"
cd "$RD"
PREFIX="$PREFIX" HOME="$HOME" PYTHONPATH="$SP:$RD" \
  timeout 15 ./aio-mod </dev/null 2>&1 | tr '\r' '\n' | grep -aE "VIP MEMBER|Gratis|Koneksi|Menyiapkan" | head -5
# restore
mv "$SP/sitecustomize.py.off" "$SP/sitecustomize.py" 2>/dev/null
mv "$RD/sitecustomize.py.off" "$RD/sitecustomize.py" 2>/dev/null

echo
echo "════════ TEST C: python bisa import sitecustomize? ════════"
PYTHONPATH="$SP:$RD" python3 -c "import sitecustomize as s; print('OK _DNS_REDIRECT=', hasattr(s,'_DNS_REDIRECT'))" 2>&1 | head -3

echo
echo "════════ TEST D: engine linked ke libc? (utk LD_PRELOAD) ════════"
command -v readelf >/dev/null && readelf -d "$RD/aio-mod" 2>/dev/null | grep -iE "NEEDED" | head -5 || echo "  (readelf tak ada)"