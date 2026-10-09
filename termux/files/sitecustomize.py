"""
sitecustomize.py — AIO-MOD engine runtime hooks (works for Nuitka standalone).

Key finding: the engine is built from `aio_mod_encoded_ready.py` (Nuitka
standalone). It verifies the server Ed25519 signature with an INLINE pure-python
implementation compiled into the binary — it does NOT import Crypto /
cryptography / nacl (confirmed by import tracing). So patching site-packages
crypto modules has no effect on the license gate.

The gate is the Python function `aio_mod_encoded_ready._aio_ed25519_payload_ok`
(and the VIP gate `_vip_server_verified`). That module lives in sys.modules
inside this very interpreter, so it CAN be monkeypatched — but only AFTER the
engine imports it. sitecustomize runs before that, so we start a daemon watcher
thread that patches the module as soon as it appears.

Also provides:
  1. uid spoof            — some engine checks expect uid 0/2000
  2. network redirect     — license host -> 127.0.0.1 (non-root, no /etc/hosts)
  3. progress-bar shrink  — bar is ~92 chars, wraps on narrow (phone) screens
  4. optional net tracing — set AIO_DEBUG=1

Design rules:
  - Fail-open: any error must NEVER break the engine. Every hook is wrapped.
  - Import-safe: must import cleanly under Nuitka's embedded Python.
"""
import os
import re
import sys
import threading
import time

# ── 1. uid spoof ─────────────────────────────────────────────────────────────
try:
    os.getuid = lambda: 2000
    os.geteuid = lambda: 2000
except Exception:
    pass

_DEBUG = os.environ.get("AIO_DEBUG", "0") == "1"
# Log ke lokasi yang PASTI writable (Termux: /tmp tidak ada; pakai ~/.aio-patcher).
_DEFLOG = os.path.join(os.path.expanduser("~"), ".aio-patcher")
_LOG = os.environ.get("AIO_REDIRECT_LOG", os.path.join(_DEFLOG, "aio_redirect.log"))
_PATCH_LOG = os.environ.get("AIO_PATCH_LOG", os.path.join(_DEFLOG, "aio_patch.log"))


def _log(path, msg):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    except Exception:
        pass
    try:
        with open(path, "a") as f:
            f.write(str(msg) + "\n")
    except Exception:
        pass


# ── 2. network redirect ──────────────────────────────────────────────────────
_DNS_REDIRECT = {"aio.scwill.store": "127.0.0.1"}
_BLOCKED_IPS = {"172.67.143.135", "104.21.46.254"}


def _install_net_redirect():
    try:
        import socket as _s
    except Exception:
        return

    try:
        _orig_gai = _s.getaddrinfo

        def _gai(host, *a, **k):
            try:
                if isinstance(host, str) and host in _DNS_REDIRECT:
                    _log(_LOG, "[net] getaddrinfo %s -> %s" % (host, _DNS_REDIRECT[host]))
                    return _orig_gai(_DNS_REDIRECT[host], *a, **k)
            except Exception:
                pass
            return _orig_gai(host, *a, **k)

        _s.getaddrinfo = _gai
    except Exception:
        pass

    try:
        _orig_conn = _s.socket.connect
        _orig_connex = _s.socket.connect_ex

        def _fix(addr):
            try:
                if isinstance(addr, tuple) and addr and addr[0] in _BLOCKED_IPS:
                    _log(_LOG, "[net] connect %s -> 127.0.0.1" % addr[0])
                    return ("127.0.0.1",) + tuple(addr[1:])
            except Exception:
                pass
            return addr

        def _connect(self, addr):
            if _DEBUG:
                _log(_LOG, "[net] connect %r" % (addr,))
            return _orig_conn(self, _fix(addr))

        def _connect_ex(self, addr):
            if _DEBUG:
                _log(_LOG, "[net] connect_ex %r" % (addr,))
            return _orig_connex(self, _fix(addr))

        _s.socket.connect = _connect
        _s.socket.connect_ex = _connect_ex
    except Exception:
        pass


_install_net_redirect()


# ── 3. license-gate monkeypatch watcher ──────────────────────────────────────
_GATE_NAMES = (
    # nama sebenarnya (dari ekstraksi dump memori runtime engine)
    "_aio_ed25519_payload_ok",     # verifikasi signature payload (gate utama)
    "_aio_license_pin_ok",         # verifikasi cert pin
    "_aio_api_signed_payload_ok",  # verifikasi HMAC 'sig' respons
    "_aio_server_free_verify",     # path gratis (jadikan lolos juga)
    "_aio_server_device_check",    # panggilan /v1/device/check
    "_aio_server_usage_check",
    # nama lama (jaga-jaga kalau versi engine beda)
    "_vip_server_verified",
    "_aio_ed25519_verify",
    "_verify_pubkey_pin",
    "_verify_free_pass",
    "_verify_decode_block",
)
_SUBMODULES = ("license", "license_client", "setup_tools", "login_system",
               "core", "utils", "login", "server", "verify")

# ── 3b. hook gate [Job/Claim] (lapis-2) ──────────────────────────────────────
# Fungsi ini mengembalikan DICT (token/entitlement), bukan bool. Kalau di-set
# True, engine gagal parse -> jalan keluarnya: kembalikan dict "sukses" palsu.
# Referensi: dump memori engine + docstring source (lihat FINDINGS.md repo).
_CLAIM_NAMES = (
    "_aio_job_claim",          # claim per-tool (feature + job_hash)
    "_aio_stamp_job_claim",    # tempel claim-id ke APK (best-effort, no-op OK)
    "_aio_special_claim_apk",  # claim special/VIP+ APK
    "_aio_smart_build_token",  # token build Smart/Special
)
_USAGE_NAMES = (
    "_aio_server_usage_check",  # kuota -> izinkan
    "_aio_server_usage_mark",   # tandai pakai -> no-op
)

# JWT dummy (format 3 segmen b64url). Engine hanya cek keberadaan field token.
_FAKE_JWT = (
    "eyJhbGciOiJFZERTQSIsImtpZCI6ImFpby1saWNlbnNlLTIwMjYtMDEifQ"
    ".eyJqdGkiOiJhaW9tb2QtaG9vay0wMDEiLCJleHAiOjIxNDc0ODM2NDd9"
    ".QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE"
)


def _fake_claim(*a, **k):
    try:
        feat = k.get("feature")
        if feat is None and a:
            feat = a[0]
    except Exception:
        feat = None
    return {"ok": True, "grant": True, "granted": True, "feature": feat,
            "token": _FAKE_JWT, "jti": "aiomod-hook-001", "exp": 2147483647,
            "token_ts": 2147483647, "job_id": "hook-job-0001",
            "job_hash": (k.get("job_hash") or (a[1] if len(a) > 1 else "0" * 64))}


def _fake_token(*a, **k):
    return {"ok": True, "granted": True, "token": _FAKE_JWT,
            "jti": "aiomod-hook-001", "exp": 2147483647}


def _fake_usage_check(*a, **k):
    return {"ok": True, "allowed": True, "count": 0, "limit": 999999, "is_vip": True}


def _fake_usage_mark(*a, **k):
    return {"ok": True, "count": 0}


def _fake_stamp(*a, **k):
    return True


_CLAIM_PATCH = {}
for _n in _CLAIM_NAMES:
    _CLAIM_PATCH[_n] = _fake_token if _n == "_aio_smart_build_token" else _fake_claim
_CLAIM_PATCH["_aio_stamp_job_claim"] = _fake_stamp
for _n in _USAGE_NAMES:
    _CLAIM_PATCH[_n] = _fake_usage_check if _n.endswith("check") else _fake_usage_mark


def _force_true(owner, name, out):
    try:
        if hasattr(owner, name):
            setattr(owner, name, (lambda *a, **k: True))
            out.append(name)
    except Exception:
        pass


def _force_claim(owner, name, out):
    try:
        fn = _CLAIM_PATCH.get(name)
        if fn is not None and hasattr(owner, name):
            setattr(owner, name, fn)
            out.append("%s->hook" % name)
    except Exception:
        pass


def _patch_module(mod, tag):
    out = []
    t = (tag or "").lower()
    # Modul crypto/sitecustomize TIDAK boleh di-patch claim: itu modul kita
    # sendiri / modul palsu, bukan engine. Patch di situ bikin engine asli
    # tak pernah di-patch (modul masuk 'seen' lebih dulu).
    _is_engine = ("aio_mod" in t) or ("encoded_ready" in t)
    _is_crypto = ("cryptography" in t) or ("nacl" in t) or ("sitecustomize" in t)
    for name in _GATE_NAMES:
        _force_true(mod, name, out)
    if _is_engine and not _is_crypto:
        for name in _CLAIM_NAMES:
            before = len(out)
            _force_claim(mod, name, out)
            if len(out) > before:
                out[-1] = "%s->claim" % out[-1].replace("->hook", "")
        for name in _USAGE_NAMES:
            before = len(out)
            _force_claim(mod, name, out)
            if len(out) > before:
                out[-1] = "%s->usage" % out[-1].replace("->hook", "")
    for sub in _SUBMODULES:
        submod = getattr(mod, sub, None)
        if submod is not None:
            for name in _GATE_NAMES:
                before = len(out)
                _force_true(submod, name, out)
                if len(out) > before:
                    out[-1] = "%s.%s" % (sub, out[-1])
    if out:
        _log(_PATCH_LOG, "[patch] %s -> %s" % (tag, ", ".join(out)))
    return out


_CLAIM_OWNERS = set()


def _apply_claim_only(mod, tag):
    key = (tag, id(mod))
    if key in _CLAIM_OWNERS:
        return
    out = []
    for name in list(_CLAIM_NAMES) + list(_USAGE_NAMES):
        before = len(out)
        _force_claim(mod, name, out)
        if len(out) > before:
            out[-1] = name
    if out:
        _CLAIM_OWNERS.add(key)
        _log(_PATCH_LOG, "[claim] %s -> %s" % (tag, ", ".join(out)))


def _find_claim_owner():
    """Cari modul MANAPUN yang punya _aio_job_claim (persis hook VPS yg terbukti)."""
    found = []
    try:
        for name, mod in list(sys.modules.items()):
            if mod is None:
                continue
            try:
                if hasattr(mod, "_aio_job_claim"):
                    found.append((name, mod))
            except Exception:
                continue
    except Exception:
        pass
    return found


def _watcher():
    seen = set()
    deadline = time.time() + 300
    dumped = False
    while time.time() < deadline:
        try:
            for name, mod in list(sys.modules.items()):
                if mod is None or id(mod) in seen:
                    continue
                lname = (name or "").lower()
                is_engine = ("aio_mod" in lname) or ("encoded_ready" in lname)
                is_crypto = ("cryptography" in lname) or ("nacl" in lname) or \
                    ("sitecustomize" in lname)
                has_gate = any(hasattr(mod, g) for g in _GATE_NAMES)
                has_claim = any(hasattr(mod, g) for g in _CLAIM_NAMES) or \
                    any(hasattr(mod, g) for g in _USAGE_NAMES)
                # Gate VIP boleh di-patch di modul mana pun; gate CLAIM hanya
                # di modul engine asli (bukan crypto/sitecustomize).
                if has_gate or (has_claim and is_engine) or is_engine:
                    seen.add(id(mod))
                    _patch_module(mod, name)
            # RETRY KHUSUS: cari owner _aio_job_claim di modul mana pun,
            # walau namanya bukan 'aio_mod_encoded_ready'.
            for _cn, _cm in _find_claim_owner():
                if ("cryptography" in (_cn or "").lower()) or \
                   ("nacl" in (_cn or "").lower()) or \
                   ("sitecustomize" in (_cn or "").lower()):
                    continue
                _apply_claim_only(_cm, _cn)
            # dump every aio-ish module once, to see what IS registered
            if not dumped:
                aio_like = [n for n in list(sys.modules) if "aio" in (n or "").lower()]
                if aio_like:
                    dumped = True
                    _log(_PATCH_LOG, "[dump] aio modules: %s" % aio_like)
                    for n in aio_like:
                        m = sys.modules.get(n)
                        if m is not None:
                            gates = [g for g in _GATE_NAMES if hasattr(m, g)]
                            _log(_PATCH_LOG, "[dump] %s gates=%s" % (n, gates))
        except Exception as e:
            _log(_PATCH_LOG, "[patch] watcher error: %s" % e)
        time.sleep(0.01)


try:
    threading.Thread(target=_watcher, name="aio-patch-watcher", daemon=True).start()
    _log(_PATCH_LOG, "[init] watcher started pid=%d" % os.getpid())
except Exception:
    pass


# ── 4. progress-bar shrinker ─────────────────────────────────────────────────
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_BAR_SET = ("\u2588", "\u2591")
_MAXLEN = 4000


def _term_cols(default=80):
    try:
        import shutil
        return shutil.get_terminal_size((default, 24)).columns
    except Exception:
        pass
    try:
        return int(os.environ.get("COLUMNS", default))
    except Exception:
        return default


def _vis_len(s):
    return len(_ANSI.sub("", s).replace("\r", ""))


def _shrink(s, cols):
    if cols <= 0 or _vis_len(s) <= cols:
        return s
    out = re.sub(r"(\]\s*\d+%\s+)\x1b\[93m[^\x1b]*", r"\1", s)
    if _vis_len(out) <= cols:
        return out
    while _vis_len(out) > cols:
        if "\u2591" in out:
            out = out.replace("\u2591", "", 1)
        elif "\u2588" in out:
            out = out.replace("\u2588", "", 1)
        else:
            break
    return out


class _ShrinkStream:
    def __init__(self, stream):
        self._s = stream
        self._cols = _term_cols()

    def write(self, data):
        try:
            if isinstance(data, (bytes, bytearray)):
                return self._s.write(data)
            if len(data) <= _MAXLEN and "\r" in data and any(b in data for b in _BAR_SET):
                data = _shrink(data, self._cols)
        except Exception:
            pass
        return self._s.write(data)

    def __getattr__(self, name):
        return getattr(self._s, name)


def _install_bar_shrinker():
    try:
        if sys.stdout is not None and not isinstance(sys.stdout, _ShrinkStream):
            sys.stdout = _ShrinkStream(sys.stdout)
        if sys.stderr is not None and not isinstance(sys.stderr, _ShrinkStream):
            sys.stderr = _ShrinkStream(sys.stderr)
    except Exception:
        pass


_install_bar_shrinker()
