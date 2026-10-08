#!/usr/bin/env python3
"""
Fake AIO-MOD license server (TLS) — portable, works on Termux non-root.

Serves the license API the engine calls (POST /v1/device/check etc.) with a
VIP JSON body. The real bypass is the patched Crypto.Signature.eddsa verifier;
this server only needs to complete the TLS handshake and return valid JSON.

Key portability fixes vs the naive version:
  * TLS is wrapped PER CONNECTION (get_request), not on the listening socket.
    Wrapping a listening socket is invalid on Android/bionic and hangs the
    handshake -> engine sees "Koneksi Gagal".
  * ThreadingHTTPServer, so multiple engine probes don't block each other.
  * Log path is writable (no /var/log on Termux non-root).
"""
import json, time, secrets, base64, hmac, hashlib, ssl, os, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

try:
    from nacl.signing import SigningKey
    SK = SigningKey.generate()
    HAVE_NACL = True
except Exception:
    SK = None
    HAVE_NACL = False

BASE = os.path.dirname(os.path.abspath(__file__))


def _find(*names):
    for n in names:
        p = os.path.join(BASE, n)
        if os.path.exists(p):
            return p
    return os.path.join(BASE, names[0])


CERT = _find("lc2.pem", "we1ca.pem")
KEY = _find("leaf.key")
PORT = int(os.environ.get("AIO_FAKE_PORT", "8443"))
SIG_KID = "aio-license-2026-01"

# writable log location (Termux non-root has no /var/log)
LOG = os.environ.get("AIO_FAKE_LOG") or os.path.join(
    os.environ.get("HOME", "/tmp"), ".aio-patcher", "fakelics.log")


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))
    except Exception:
        pass


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def build_payload(hwid, req_nonce):
    now = int(time.time())
    payload = {
        "ok": True,
        "hwid": hwid,
        "registered_at": "2026-06-24",
        "is_vip": True,
        "expires_at": "2069-06-09",
        "server_time": now,
        "nonce": secrets.token_hex(8),
        "req_nonce": req_nonce,
        "sig_alg": "Ed25519",
        "sig_kid": SIG_KID,
    }
    msg = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    if SK is not None:
        payload["ed25519_sig"] = b64u(SK.sign(msg).signature)
    payload["sig"] = hmac.new(b"aio-license", msg, hashlib.sha256).hexdigest()
    return payload


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
        raw = self.rfile.read(n) if n else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}
        hwid = body.get("hwid", "AIO3-UNKNOWN")
        req_nonce = self.headers.get("X-Req-Nonce", secrets.token_hex(16))
        log("POST %s hwid=%s -> VIP" % (self.path, hwid))
        self._reply(200, build_payload(hwid, req_nonce))

    def do_GET(self):
        log("GET %s" % self.path)
        self._reply(200, {"ok": True, "status": "ok"})

    def log_message(self, *a):
        pass


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, handler, sslctx):
        self._sslctx = sslctx
        super().__init__(addr, handler)

    # Wrap TLS per accepted connection (correct on Android; wrapping the
    # listening socket is invalid and hangs the handshake).
    def get_request(self):
        sock, addr = self.socket.accept()
        try:
            sock = self._sslctx.wrap_socket(sock, server_side=True)
        except Exception as e:
            log("TLS handshake failed from %s: %s" % (addr, e))
            try:
                sock.close()
            except Exception:
                pass
            raise
        return sock, addr


def main():
    for p in (CERT, KEY):
        if not os.path.exists(p):
            sys.stderr.write("missing cert file: %s\n" % p)
            sys.exit(1)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    srv = Server(("0.0.0.0", PORT), H, ctx)
    sys.stderr.write("fake license server on :%d (nacl=%s) log=%s\n"
                     % (PORT, HAVE_NACL, LOG))
    sys.stderr.flush()
    log("started on :%d nacl=%s" % (PORT, HAVE_NACL))
    srv.serve_forever()


if __name__ == "__main__":
    main()
