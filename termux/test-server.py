#!/usr/bin/env python3
"""Test: apakah fakelicstls.py bales VIP? Uji beberapa cara konek."""
import json, os, socket, ssl, subprocess, sys, tempfile, threading, time

SRC = os.path.expanduser("~/aio-mod-re/shared")
d = tempfile.mkdtemp(prefix="srvtest_")
subprocess.run(["cp", os.path.join(SRC, "fakelicstls.py"), d], check=False)
for f in ("lc2.pem", "leaf.key", "we1ca.pem"):
    subprocess.run(["cp", os.path.join(SRC, "certs", f), d], check=False)

env = dict(os.environ, AIO_FAKE_PORT="18443")
srv = subprocess.Popen([sys.executable, "fakelicstls.py"], cwd=d, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
time.sleep(2)


def probe(label, sni=None, conn_close=True, https_path="/v1/device/check"):
    try:
        ctx = ssl._create_unverified_context()
        raw = socket.create_connection(("127.0.0.1", 18443), timeout=5)
        s = ctx.wrap_socket(raw, server_hostname=sni) if sni else ctx.wrap_socket(raw)
        ch = "close" if conn_close else "keep-alive"
        req = (f"POST {https_path} HTTP/1.1\r\nHost: aio.scwill.store:8443\r\n"
               f"Content-Length: 2\r\nConnection: {ch}\r\n\r\n{{}}")
        s.sendall(req.encode())
        data = b""
        s.settimeout(5)
        try:
            while True:
                c = s.recv(4096)
                if not c:
                    break
                data += c
                if b"is_vip" in data:
                    break
        except socket.timeout:
            pass
        s.close()
        ok = b"is_vip" in data
        head = data.split(b"\r\n", 1)[0][:60]
        print(f"  {label}: {'✅ is_vip' if ok else '❌ NO'}  [{head!r}]  {len(data)}B")
        return ok
    except Exception as e:
        print(f"  {label}: ❌ ERR {e}")
        return False


print("=== TES fake server bales VIP? ===")
r = []
r.append(probe("no-SNI, close"))
r.append(probe("SNI, close", sni="aio.scwill.store"))
r.append(probe("SNI, keep-alive", sni="aio.scwill.store", conn_close=False))
r.append(probe("root path", sni="aio.scwill.store", https_path="/"))

srv.terminate()
try:
    out = srv.communicate(timeout=3)[0]
except Exception:
    out = ""
print("\n=== server output ===")
print(out[:1500] if out else "(kosong)")
print(f"\nHASIL: {sum(r)}/{len(r)} berhasil")
