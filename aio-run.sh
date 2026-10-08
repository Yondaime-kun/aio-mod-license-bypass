#!/bin/bash
# Jalankan AIO-MOD engine (license VIP sudah tembus) secara interaktif.
# Deploy: /usr/local/bin/aio
cd /data/data/com.termux/files/home/release || exit 1
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PYTHONPATH=/data/data/com.termux/files/usr/lib/python3.14/site-packages
export LD_LIBRARY_PATH=/system/lib64
exec qemu-aarch64-static ./aio-mod "$@"
