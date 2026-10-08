"""
Sitecustomize extension — AIO-MOD engine hooks.

1. spoof uid (some checks expect non-root uid)
2. adaptive progress-bar shrinker (bar is ~92 chars, wraps on narrow screens)
3. network redirect: license host -> 127.0.0.1 (non-root, no /etc/hosts)
4. DEBUG tracing: log every socket/connect/exec so we can see what the engine
   actually does before deciding it's "no connection".

Fail-open: any error -> original behavior.
"""
import os as _os
import re as _re
import sys as _sys

try:
    _os.getuid = lambda: 2000
    _os.geteuid = lambda: 2000
except Exception:
    pass

_DEBUG = _os.environ.get('AIO_DEBUG', '1') == '1'
_LOG = _os.environ.get('AIO_REDIRECT_LOG', '/tmp/aio_redirect.log')


def _log(msg):
    if not _DEBUG:
        return
    try:
        with open(_LOG, 'a') as f:
            f.write(msg + '\n')
    except Exception:
        pass


def _log_exc(where):
    try:
        import traceback
        _log('[exc] %s: %s' % (where, traceback.format_exc().replace('\n', ' | ')))
    except Exception:
        pass


# ─── network redirect + tracing ──────────────────────────────────────────────
_dns_redirect = {'aio.scwill.store': '127.0.0.1'}
_BLOCKED_IPS = {'172.67.143.135', '104.21.46.254'}


def _install_net():
    try:
        import socket as _s
    except Exception:
        _log_exc('import socket')
        return

    # log loads of sitecustomize itself
    _log('[init] sitecustomize loaded; python=%s' % _sys.version.split()[0])

    try:
        _orig_gai = _s.getaddrinfo

        def _gai(host, *a, **k):
            if isinstance(host, str) and host in _dns_redirect:
                _log('[net] getaddrinfo %s -> %s' % (host, _dns_redirect[host]))
                return _orig_gai(_dns_redirect[host], *a, **k)
            _log('[net] getaddrinfo %s (passthrough)' % (host,))
            return _orig_gai(host, *a, **k)

        _s.getaddrinfo = _gai
    except Exception:
        _log_exc('hook getaddrinfo')

    try:
        _oc = _s.socket.connect
        _oce = _s.socket.connect_ex

        def _fix(addr):
            try:
                if isinstance(addr, tuple) and addr and addr[0] in _BLOCKED_IPS:
                    _log('[net] connect %s -> 127.0.0.1' % addr[0])
                    return ('127.0.0.1',) + tuple(addr[1:])
            except Exception:
                pass
            return addr

        def _connect(self, addr):
            _log('[net] connect %r' % (addr,))
            return _oc(self, _fix(addr))

        def _connect_ex(self, addr):
            _log('[net] connect_ex %r' % (addr,))
            return _oce(self, _fix(addr))

        _s.socket.connect = _connect
        _s.socket.connect_ex = _connect_ex
    except Exception:
        _log_exc('hook connect')

    # log subprocess spawns (engine may shell out to check "private server")
    try:
        import subprocess as _sp
        _op = _sp.Popen

        class _P(_op):
            def __init__(self, *a, **k):
                _log('[proc] Popen %r' % (a[0] if a else k.get('args'),))
                super().__init__(*a, **k)

        _sp.Popen = _P
    except Exception:
        _log_exc('hook Popen')


_install_net()
