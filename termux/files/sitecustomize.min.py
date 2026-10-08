"""sitecustomize.py — MINIMAL: hanya DNS redirect (uji isolasi).

Untuk membuktikan apakah hook lain (watcher/uid/bar) mengganggu verifikasi.
Hanya mengarahkan host license ke 127.0.0.1.
"""
import os
import sys

_REDIR = {"aio.scwill.store": "127.0.0.1"}

try:
    _log = open(os.path.join(os.path.expanduser("~"), ".aio-patcher", "sc_min.log"), "a")
    _log.write("[sc-min] loaded pid=%d\n" % os.getpid())
    _log.flush()
except Exception:
    _log = None


def _install():
    try:
        import socket as _s
    except Exception:
        return
    _orig_gai = _s.getaddrinfo

    def _gai(host, *a, **k):
        try:
            if isinstance(host, str) and host in _REDIR:
                if _log:
                    _log.write("[sc-min] %s -> %s\n" % (host, _REDIR[host]))
                    _log.flush()
                return _orig_gai(_REDIR[host], *a, **k)
        except Exception:
            pass
        return _orig_gai(host, *a, **k)

    _s.getaddrinfo = _gai


_install()
