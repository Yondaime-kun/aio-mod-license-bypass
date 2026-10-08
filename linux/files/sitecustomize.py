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
_LOG = os.environ.get("AIO_REDIRECT_LOG", "/tmp/aio_redirect.log")
_PATCH_LOG = os.environ.get("AIO_PATCH_LOG", "/tmp/aio_patch.log")


def _log(path, msg):
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
    "_aio_ed25519_payload_ok",
    "_aio_server_free_verify",
    "_aio_license_pin_ok",
    "_verify_pubkey_pin",
    "_verify_free_pass",
    "_verify_decode_block",
    "_vip_server_verified",
    "_aio_server_device_check",
    "_aio_ed25519_verify",
)
_SUBMODULES = ("license", "license_client", "setup_tools", "login_system",
               "core", "utils", "login", "server", "verify")


def _force_true(owner, name, out):
    try:
        if hasattr(owner, name):
            setattr(owner, name, (lambda *a, **k: True))
            out.append(name)
    except Exception:
        pass


def _patch_module(mod, tag):
    out = []
    for name in _GATE_NAMES:
        _force_true(mod, name, out)
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
                has_gate = any(hasattr(mod, g) for g in _GATE_NAMES)
                if has_gate or ("aio" in lname and ("encoded" in lname or "mod" in lname)):
                    seen.add(id(mod))
                    _patch_module(mod, name)
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
