#!/data/data/com.termux/files/usr/bin/bash
# Bandingkan environment Termux vs VPS (yang VIP).
echo "== ENGINE =="
md5sum ~/release/aio-mod
ls -la ~/release/aio-mod ~/release/aio-mod-shim 2>/dev/null
echo
echo "== SERVER: python mana & nacl =="
ps aux 2>/dev/null | grep -c "[f]akelicstls" || pgrep -af fakelicstls
echo
echo "== apakah server respon PERSIS? =="
python3 - <<'EOF'
import socket, ssl, json
ctx = ssl._create_unverified_context()
s = ctx.wrap_socket(socket.create_connection(('127.0.0.1',8443), timeout=5))
s.sendall(b'POST /v1/device/check HTTP/1.1\r\nHost: a.r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
d=b''; s.settimeout(5)
while True:
    try: c=s.recv(4096)
    except: break
    if not c: break
    d+=c
h,b=d.split(b'\r\n\r\n',1)
print("HEADERS:"); print(h.decode('latin1'))
print("BODY:"); print(b.decode('latin1')[:400])
EOF
echo
echo "== TLS: engine percaya cert kita? (verifikasi CA) =="
python3 - <<'EOF'
import socket, ssl, certifi
# coba VERIFIKASI (bukan unverified) ke 127.0.0.1 dgn hostname aio.scwill.store
ctx = ssl.create_default_context(cafile=certifi.where())
try:
    s = ctx.wrap_socket(socket.create_connection(('127.0.0.1',8443), timeout=5),
                        server_hostname='aio.scwill.store')
    print("VERIFIED OK -> cert kita dipercaya certifi")
except Exception as e:
    print("VERIFY GAGAL:", type(e).__name__, e)
EOF
