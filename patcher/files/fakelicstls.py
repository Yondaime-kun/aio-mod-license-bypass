#!/usr/bin/env python3
"""
Fake AIO-MOD license server (TLS) — portable version for the bypass patcher.

Serves the license API the engine calls (POST /v1/device/check etc.) with a
JSON body that mimics a VIP response. TLS uses the local fake CA leaf so the
engine's cert-pin rotation path accepts it.

NOTE: the real bypass is the patched Crypto.Signature.eddsa verifier — this
server only needs to complete the TLS handshake and return valid JSON.

Paths are absolute (/opt/aio-patcher) so it runs unchanged as a systemd unit.
"""
import json, time, secrets, base64, hmac, hashlib, ssl, os, sys
from http.server import HTTPServer, BaseHTTPRequestHandler

try:
    from nacl.signing import SigningKey
    SK = SigningKey.generate()
    HAVE_NACL = True
except Exception:
    SK = None
    HAVE_NACL = False

BASE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(BASE, "lc2.pem")
KEY  = os.path.join(BASE, "leaf.key")
PORT = int(os.environ.get("AIO_FAKE_PORT", "8443"))
SIG_KID = "aio-license-2026-01"


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def build_payload(hwid, req_nonce):
    now = int(time.time())
    nonce = secrets.token_hex(8)
    payload = {
        "ok": True,
        "hwid": hwid,
        "registered_at": "2026-06-24",
        "is_vip": True,
        "expires_at": "2069-06-09",
        "server_time": now,
        "nonce": nonce,
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

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}
        hwid = body.get("hwid", "AIO3-UNKNOWN")
        req_nonce = self.headers.get("X-Req-Nonce", secrets.token_hex(16))
        payload = build_payload(hwid, req_nonce)
        out = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
        try:
            with open("/var/log/aio-fakelics.log", "a") as f:
                f.write(f"[{time.strftime('%H:%M:%S')}] {self.path} hwid={hwid} -> VIP\n")
        except Exception:
            pass

    def do_GET(self):
        out = b'{"detail":"Not found"}'
        self.send_response(404)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


def main():
    for p in (CERT, KEY):
        if not os.path.exists(p):
            sys.stderr.write(f"missing cert file: {p}\n")
            sys.exit(1)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    srv = HTTPServer(("0.0.0.0", PORT), H)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write(f"fake license server on :{PORT} (nacl={HAVE_NACL})\n")
    sys.stderr.flush()
    srv.serve_forever()


if __name__ == "__main__":
    main()
