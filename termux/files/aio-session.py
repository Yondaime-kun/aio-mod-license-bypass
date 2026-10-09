#!/usr/bin/env python3
"""aio-session — jalankan engine AIO-MOD dengan stdin/stdout PIPE.

Tujuan: `sitecustomize.py` (hook bypass [Job/Claim]) HANYA dimuat kalau stdin
BUKAN tty. Shell interaktif / tmux = tty → hook mati. Wrapper ini memberi
engine pipe sungguhan, lalu me-relay I/O secara manual:

  - stdin  user  -> p.stdin   (relay thread, line-buffered)
  - p.stdout     -> stdout user (raw, apa adanya: menu, progress, animasi)

Dipakai oleh runner `aio` (kalau mode hook aktif). Kalau wrapper gagal
(mis. tidak ada python), runner fallback ke `exec` biasa.

Exit code: sama dgn engine.
"""
import os
import sys
import subprocess
import threading

# ---- konfigurasi dari env (di-set oleh runner `aio`) ----
RUN_BIN = os.environ.get("AIO_RUN_BIN") or ""
CWD = os.environ.get("AIO_CWD") or os.getcwd()
LOG = os.environ.get("AIO_HOOK_LOG") or ""
NO_TTY = os.environ.get("AIO_NO_TTY") == "1"


def _dbg(msg):
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("aio-session: %s\n" % msg)
    except Exception:
        pass


def main():
    if not RUN_BIN or not os.path.isfile(RUN_BIN):
        sys.stderr.write("aio-session: binary tidak ditemukan: %r\n" % RUN_BIN)
        return 127

    env = dict(os.environ)
    # Pastikan tidak ada sisa yang memaksa tty
    env.pop("AIO_RUN_BIN", None)
    env.pop("AIO_CWD", None)
    env.pop("AIO_HOOK_LOG", None)
    env.pop("AIO_NO_TTY", None)

    try:
        proc = subprocess.Popen(
            [RUN_BIN] + sys.argv[1:],
            cwd=CWD,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
    except OSError as e:
        sys.stderr.write("aio-session: gagal spawn engine: %s\n" % e)
        return 127

    stop = threading.Event()

    def pump_out():
        out = sys.stdout
        try:
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                out.write(chunk.decode("utf-8", "replace"))
                out.flush()
        except Exception as e:
            _dbg("pump_out error: %s" % e)
        finally:
            stop.set()

    def pump_in():
        # baca stdin user per baris; kirim apa adanya ke engine
        try:
            while not stop.is_set():
                line = sys.stdin.readline()
                if not line:
                    break
                try:
                    proc.stdin.write(line.encode("utf-8", "replace"))
                    proc.stdin.flush()
                except Exception:
                    break
        except Exception:
            pass
        # setelah EOF user, beri jeda sebelum tutup stdin engine
        try:
            import time
            time.sleep(0.5)
            proc.stdin.close()
        except Exception:
            pass

    t_out = threading.Thread(target=pump_out, daemon=True)
    t_in = threading.Thread(target=pump_in, daemon=True)
    t_out.start()
    t_in.start()

    try:
        rc = proc.wait()
    except KeyboardInterrupt:
        try:
            proc.terminate()
        except Exception:
            pass
        rc = 130
    stop.set()
    return rc


if __name__ == "__main__":
    sys.exit(main())
