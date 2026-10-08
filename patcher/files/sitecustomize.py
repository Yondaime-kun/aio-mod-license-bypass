"""
sitecustomize.py — AIO-MOD engine runtime hooks.

Installed into paths the Nuitka standalone engine scans at interpreter start
(PYTHONPATH / CWD). Provides:

  1. uid spoof            — some engine checks expect uid 0 or 2000
  2. network redirect     — license host -> 127.0.0.1 (non-root, no /etc/hosts)
  3. progress-bar shrink  — bar is ~92 chars, wraps on narrow (phone) screens
  4. optional tracing     — set AIO_DEBUG=1 to log net/proc activity

Design rules:
  - Fail-open: any error must NEVER break the engine. Every hook is wrapped.
  - Import-safe: the module must import cleanly under Nuitka's embedded Python.
    Do NOT assume helpers exist; define everything used.
"""
import os
import re
import sys

# ── 1. uid spoof ─────────────────────────────────────────────────────────────
try:
    os.getuid = lambda: 2000
    os.geteuid = lambda: 2000
except Exception:
    pass

# ── tracing (opt-in) ─────────────────────────────────────────────────────────
_DEBUG = os.environ.get("AIO_DEBUG", "0") == "1"
_LOG_PATHS = []
try:
    _LOG_PATHS.append(os.environ.get("AIO_REDIRECT_LOG", "/tmp/aio_redirect.log"))
except Exception:
    pass
try:
    _LOG_PATHS.append(os.path.join(os.environ.get("HOME", "/tmp"), "aio_redirect.log"))
except Exception:
    pass


def _log(msg):
    if not _DEBUG:
        return
    for p in _LOG_PATHS:
        try:
            with open(p, "a") as f:
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
                    _log("[net] getaddrinfo %s -> %s" % (host, _DNS_REDIRECT[host]))
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
                    _log("[net] connect %s -> 127.0.0.1" % addr[0])
                    return ("127.0.0.1",) + tuple(addr[1:])
            except Exception:
                pass
            return addr

        def _connect(self, addr):
            _log("[net] connect %r" % (addr,))
            return _orig_conn(self, _fix(addr))

        def _connect_ex(self, addr):
            _log("[net] connect_ex %r" % (addr,))
            return _orig_connex(self, _fix(addr))

        _s.socket.connect = _connect
        _s.socket.connect_ex = _connect_ex
    except Exception:
        pass

    if _DEBUG:
        try:
            import subprocess as _sp
            _orig_popen = _sp.Popen

            class _TracingPopen(_orig_popen):
                def __init__(self, *a, **k):
                    _log("[proc] Popen %r" % (a[0] if a else k.get("args"),))
                    super().__init__(*a, **k)

            _sp.Popen = _TracingPopen
        except Exception:
            pass


_install_net_redirect()


# ── 3. progress-bar shrinker ─────────────────────────────────────────────────
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
