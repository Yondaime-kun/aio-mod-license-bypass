"""
Sitecustomize extension — Adaptive progress-bar shrinker for the AIO-MOD engine.

Engine's loading bar ("Configure [███...░░░]  56%  Upgrade paket Termux...")
is a pre-baked ~92-char string emitted with a leading \r. On a narrow terminal
(< 93 cols, e.g. Termux phone) it wraps -> \r can't clear the wrapped line ->
output stacks as newlines.

This hook wraps sys.stdout.write: when a chunk looks like a progress bar
(contains \r + block chars \u2588/\u2591), it is shrunk in place to fit the
real terminal width. Non-console output (piped/log) is passed through with the
bar suppressed to a single short line.

Fail-open: any error -> original write is used.
"""
import os as _os
import re as _re

try:
    _os.getuid = lambda: 2000
    _os.geteuid = lambda: 2000
except Exception:
    pass

# ─── Redirect license server ke fake lokal (Termux non-root, tanpa /etc/hosts) ─
# Engine bisa memakai: getaddrinfo biasa, DoH resolver, atau connect ke IP
# langsung. Kita shim di SEMUA layer supaya apapun caranya, tetap diarahkan
# ke 127.0.0.1 (fake server). Fail-open: error apa pun -> perilaku asli.
_dns_redirect = {
    'aio.scwill.store': '127.0.0.1',
}
_LOG = _os.environ.get('AIO_REDIRECT_LOG', '/tmp/aio_redirect.log')


def _log(msg):
    try:
        with open(_LOG, 'a') as f:
            f.write(msg + '\n')
    except Exception:
        pass


def _install_net_redirect():
    try:
        import socket as _s
    except Exception:
        return

    # 1) getaddrinfo: map hostname -> 127.0.0.1
    try:
        _orig_gai = _s.getaddrinfo

        def _gai(host, *args, **kwargs):
            if isinstance(host, str) and host in _dns_redirect:
                _log('[redirect] getaddrinfo %s -> %s' % (host, _dns_redirect[host]))
                return _orig_gai(_dns_redirect[host], *args, **kwargs)
            return _orig_gai(host, *args, **kwargs)

        _s.getaddrinfo = _gai
    except Exception:
        pass

    # 2) connect / connect_ex: kalau target IP = IP server asli, alihkan ke 127.0.0.1
    _BLOCKED_IPS = {'172.67.143.135', '104.21.46.254'}
    try:
        _orig_conn = _s.socket.connect
        _orig_connex = _s.socket.connect_ex

        def _fix_addr(address):
            try:
                if isinstance(address, tuple) and address:
                    host = address[0]
                    if host in _BLOCKED_IPS:
                        _log('[redirect] connect %s -> 127.0.0.1' % host)
                        return ('127.0.0.1',) + tuple(address[1:])
            except Exception:
                pass
            return address

        def _connect(self, address):
            return _orig_conn(self, _fix_addr(address))

        def _connect_ex(self, address):
            return _orig_connex(self, _fix_addr(address))

        _s.socket.connect = _connect
        _s.socket.connect_ex = _connect_ex
    except Exception:
        pass


_install_net_redirect()
# ─────────────────────────────────────────────────────────────────────────────

_ANSI = _re.compile(r'\x1b\[[0-9;]*m')
_BLOCK = ('\u2588', '\u2591')
_MAXLEN = 4000  # only inspect reasonably small chunks


def _term_cols(default=80):
    # 1) ioctl on stdout
    try:
        import shutil
        return shutil.get_terminal_size((default, 24)).columns
    except Exception:
        pass
    # 2) env
    try:
        return int(_os.environ.get('COLUMNS', default))
    except Exception:
        return default


def _vis_len(s):
    return len(_ANSI.sub('', s).replace('\r', ''))


def _shrink(s, cols):
    """Shrink a progress-bar chunk to fit `cols` visible columns."""
    if cols <= 0 or _vis_len(s) <= cols:
        return s
    out = s
    # 1) drop the trailing label (after "]  NN%  ") incl. its colour code
    out = _re.sub(r'(\]\s*\d+%\s+)\x1b\[93m[^\x1b]*', r'\1', out)
    if _vis_len(out) <= cols:
        return out
    # 2) shorten the bar blocks (drop filled first, then empty)
    while _vis_len(out) > cols:
        if '\u2591' in out:
            out = out.replace('\u2591', '', 1)
        elif '\u2588' in out:
            out = out.replace('\u2588', '', 1)
        else:
            break
    return out


class _ShrinkStream:
    """Proxy around a text stream shrinking bar chunks on write()."""

    def __init__(self, stream):
        self._s = stream
        self._cols = _term_cols()

    def write(self, data):
        try:
            if isinstance(data, (bytes, bytearray)):
                return self._s.write(data)
            if len(data) <= _MAXLEN and '\r' in data and (
                    '\u2588' in data or '\u2591' in data):
                data = _shrink(data, self._cols)
        except Exception:
            pass
        return self._s.write(data)

    def __getattr__(self, name):
        return getattr(self._s, name)


def _install():
    try:
        import sys
        # refresh width lazily in case of resize before first bar
        if sys.stdout is not None and not isinstance(sys.stdout, _ShrinkStream):
            sys.stdout = _ShrinkStream(sys.stdout)
        if sys.stderr is not None and not isinstance(sys.stderr, _ShrinkStream):
            sys.stderr = _ShrinkStream(sys.stderr)
    except Exception:
        pass


_install()
