#!/data/data/com.termux/files/usr/bin/bash
# Diagnosa: kenapa engine tolak respons server? Bandingkan dgn yg VPS.
P="$PREFIX"; SP="$P/lib/python3.14/site-packages"
echo "== 1. versi python engine vs server =="
python3 -V
echo "== 2. log patch (sitecustomize jalan?) =="
tail -5 ~/.aio-patcher/aio_patch.log 2>/dev/null || echo "  kosong"
echo "== 3. log redirect (engine konek ke mana?) =="
tail -12 ~/.aio-patcher/aio_redirect.log 2>/dev/null || echo "  kosong"
echo "== 4. req_dump (body yg engine kirim) =="
tail -8 ~/.aio-patcher/req_dump.log 2>/dev/null || echo "  kosong"
echo "== 5. sentinel =="
cat "$P/share/.open_ssl_cache" 2>/dev/null || echo "  TIDAK ADA"
echo "== 6. skrg jalankan engine, tangkap log server =="
rm -f ~/.aio-patcher/fakelics.log ~/.aio-patcher/aio_redirect.log
rm -f "$P/share/.open_ssl_cache"
nohup python3 ~/.aio-patcher/fakelicstls.py >/dev/null 2>&1 &
sleep 1
timeout 12 aio >/dev/null 2>&1
echo "--- fakelics.log:"
cat ~/.aio-patcher/fakelics.log 2>/dev/null | tail -15
echo "--- aio_redirect.log (engine konek ke):"
cat ~/.aio-patcher/aio_redirect.log 2>/dev/null | tail -15
echo "--- sentinel SETELAH:"
cat "$P/share/.open_ssl_cache" 2>/dev/null || echo "  TIDAK ADA (verifikasi gagal)"
