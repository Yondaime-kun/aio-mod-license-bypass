"""import-tracer: log every module the engine imports (diagnostic only)."""
import sys
import os

_LOG = os.environ.get("AIO_IMPORT_LOG", "/tmp/aio_imports.log")
_orig_import = None


def _install():
    global _orig_import
    try:
        import builtins
        _orig_import = builtins.__import__

        def _imp(name, *a, **k):
            mod = _orig_import(name, *a, **k)
            try:
                with open(_LOG, "a") as f:
                    f.write("%s\t%s\n" % (name, getattr(mod, "__file__", "?")))
            except Exception:
                pass
            return mod

        builtins.__import__ = _imp
    except Exception:
        pass


_install()
