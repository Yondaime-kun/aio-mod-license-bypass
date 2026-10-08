#!/usr/bin/env python3
"""Server debug: log SETIAP request+respons lengkap, biar kelihatan request
mana yg engine terima dan field apa yg beda. Port default 8443."""
import json, os, secrets, ssl, sys, time, base64, hmac, hashlib
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

BASE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(BASE, "lc2.pem")
KEY = os.path.join(BASE, "leaf.key")
PORT = int(os.environ.get("AIO_FAKE_PORT", "8443"))
SIG_KID = "aio-license-2026-01"
LOG = os.environ.get("AIO_FAKE_LOG") or os.path.join(
    os.path.expanduser("~"), ".aio-patcher", "fakelics-debug.log")

try:
    from nacl.signing import SigningKey
    SK = SigningKey.generate()
    HAVE = True
except Exception:
    SK = None
    HAVE = False


def _find(*names):
    for n in names:
        p = os.path.join(BASE, n)
        if os.path.exists(p):
            return p
    return os.path.join(BASE, names[0])


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def log(m):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), m))
    except Exception:
        pass


def build(hwid, req_nonce):
    p = {"ok": True, "hwid": hwid, "registered_at": "2026-06-24", "is_vip": True,
         "expires_at": "2069-06-09", "server_time": int(time.time()),
         "nonce": secrets.token_hex(8), "req_nonce": req_nonce,
         "sig_alg": "Ed25519", "sig_kid": SIG_KID}
    msg = json.dumps(p, sort_keys=True, separators=(",", ":")).encode()
    if SK is not None:
        p["ed25519_sig"] = b64u(SK.sign(msg).signature)
    else:
        p["ed25519_sig"] = b64u(b"\x00" * 64)
    p["sig"] = hmac.new(b"aio-license", msg, hashlib.sha256).hexdigest()
    return p


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, code, obj):
        out = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}
        hwid = body.get("hwid", "AIO3-UNKNOWN")
        # ambil mentah, jangan default: kalau header ada tapi kosong, tetap kosong
        rn = self.headers.get("X-Req-Nonce")
        log("=== POST %s ===" % self.path)
        log("  hwid=%s" % hwid)
        log("  X-Req-Nonce raw=%r" % (rn,))
        log("  X-Req-Time=%r" % (self.headers.get("X-Req-Time"),))
        log("  X-Req-Sig=%r" % (self.headers.get("X-Req-Sig"),))
        log("  X-Client-Key=%r" % (self.headers.get("X-Client-Key"),))
        log("  ALL HEADERS: %s" % dict(self.headers))
        log("  BODY: %r" % raw)
        resp = build(hwid, rn if rn is not None else secrets.token_hex(16))
        log("  -> RESP: %s" % json.dumps(resp))
        self._reply(200, resp)

    def do_GET(self):
        out = b'{"detail":"Not found"}'
        self.send_response(404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


class S(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, a, h, c):
        self._c = c
        super().__init__(a, h)

    def get_request(self):
        while True:
            s, a = self.socket.accept()
            try:
                s = self._c.wrap_socket(s, server_side=True)
            except Exception as e:
                log("TLS fail %s: %s" % (a, e))
                try:
                    s.close()
                except Exception:
                    pass
                continue
            return s, a


def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    srv = S(("0.0.0.0", PORT), H, ctx)
    log("started :%d nacl=%s" % (PORT, HAVE))
    srv.serve_forever()


if __name__ == "__main__":
    main()
