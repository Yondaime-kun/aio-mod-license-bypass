#!/usr/bin/env bash
# =============================================================================
#  AIO-MOD TOOLKIT v3.5.2  —  AUTOMATED LICENSE BYPASS PATCHER
# =============================================================================
#  Menembus license wall (Ed25519 fail-closed) -> mode ★ VIP MEMBER ★
#
#  Strategi:  engine Nuitka TETAP meng-import Crypto.Signature.eddsa dari
#  site-packages Termux (bukan embedded). Kita ganti module itu dgn fake
#  verifier (verify() -> None). Plus fake TLS license server utk lewati
#  cert-pin + koneksi.
#
#  Caveat: hanya utk environment lab/uji milik sendiri.
#
#  Usage:
#     sudo ./patch.sh            # install semua
#     sudo ./patch.sh verify     # cek status
#     sudo ./patch.sh revert     # kembalikan ke asli
# =============================================================================
set -euo pipefail

# --- konfigurasi ---
TERMUX_USR="/data/data/com.termux/files/usr"
TERMUX_HOME="/data/data/com.termux/files/home"
RELEASE_DIR="$TERMUX_HOME/release"
SP="$TERMUX_USR/lib/python3.14/site-packages"
SHARE="$TERMUX_USR/share"
FAKE_TLS_PORT=8443
LICENSE_HOST="aio.scwill.store"
# IP asli server license (Cloudflare) — diblokir sbg jaring pengaman kalau
# engine pakai DoH resolver sendiri & mengabaikan /etc/hosts.
LICENSE_IPS="172.67.143.135 104.21.46.254"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SELF_DIR/files"
CERTS="$SELF_DIR/certs"

C_R="\033[0m"; C_G="\033[1;32m"; C_Y="\033[1;33m"; C_E="\033[1;31m"; C_C="\033[1;36m"
say()  { echo -e "${C_C}▸${C_R} $*"; }
ok()   { echo -e "${C_G}✓${C_R} $*"; }
warn() { echo -e "${C_Y}!${C_R} $*"; }
err()  { echo -e "${C_E}×${C_R} $*" >&2; }
die()  { err "$*"; exit 1; }

[ "$(id -u)" = "0" ] || die "Harus root: sudo $0"

# =============================================================================
# STEP 1 — Fake crypto verifier  (Crypto.Signature.eddsa + Cryptodome)
# =============================================================================
patch_eddsa() {
  say "Step 1/7  Fake Ed25519 verifier (Crypto + Cryptodome)"
  # Alias Crypto -> Cryptodome kalau perlu (paket pycryptodomex cuma punya Cryptodome)
  if [ ! -d "$SP/Crypto" ] && [ -d "$SP/Cryptodome" ]; then
    ln -sfn Cryptodome "$SP/Crypto" 2>/dev/null && ok "  alias Crypto -> Cryptodome"
  fi
  for base in Crypto Cryptodome; do
    local tgt="$SP/$base/Signature/eddsa.py"
    [ -e "$tgt" ] || { warn "  $tgt tidak ada — skip (paket $base belum terpasang?)"; continue; }
    # backup sekali saja
    [ -e "$tgt.asli" ] || cp -a "$tgt" "$tgt.asli"
    cp "$FILES/eddsa_fake.py" "$tgt"
    rm -rf "$SP/$base/Signature/__pycache__"
    ok "  $base/Signature/eddsa.py -> fake (backup .asli)"
  done
}

# =============================================================================
# STEP 2 — sitecustomize: spoof uid + adaptive progress-bar shrinker
# =============================================================================
patch_sitecustomize() {
  say "Step 2/7  sitecustomize (spoof uid + bar shrinker)"
  local tgt="$SP/sitecustomize.py"
  [ -e "$tgt" ] && [ ! -e "$tgt.asli" ] && cp -a "$tgt" "$tgt.asli"
  install -m644 "$FILES/sitecustomize.py" "$tgt"
  rm -rf "$SP/__pycache__"
  ok "  sitecustomize.py terpasang (uid spoof + bar adapter)"
}

# =============================================================================
# STEP 2b — Shim apt (blokir 'upgrade', matikan progress bar non-TTY)
# =============================================================================
patch_apt_shim() {
  say "Step 2b/7  Shim apt (skip 'upgrade', no progress di non-TTY)"
  local real="/usr/bin/apt"
  local binn="$TERMUX_USR/bin"
  mkdir -p "$binn"
  # Backup apt asli (kalau ada)
  if [ -e "$real" ] && [ ! -e "$real.asli" ]; then
    cp -a "$real" "$real.asli" 2>/dev/null || true
  fi
  if [ -e "$real.asli" ] || [ -e "$real.real" ]; then
    install -m755 "$FILES/apt-shim.sh" "$real"
    ok "  shim /usr/bin/apt dipasang (apt asli -> $real.asli)"
  else
    warn "  /usr/bin/apt tak ada — shim dilewati"
  fi
  # juga pasang di Termux bin (kalau engine resolve via PATH)
  if [ -e "$binn/apt" ] && [ ! -e "$binn/apt.asli" ]; then
    cp -a "$binn/apt" "$binn/apt.asli" 2>/dev/null || true
  fi
  install -m755 "$FILES/apt-shim.sh" "$binn/apt" 2>/dev/null && \
    ok "  shim $binn/apt dipasang" || true
}

# =============================================================================
# STEP 3 — Sentinel file .open_ssl_cache (dibutuhkan accept_vip_login)
# =============================================================================
patch_sentinel() {
  say "Step 3/7  Sentinel .open_ssl_cache"
  mkdir -p "$SHARE"
  [ -e "$SHARE/.open_ssl_cache" ] || touch "$SHARE/.open_ssl_cache"
  chmod 666 "$SHARE/.open_ssl_cache"
  ok "  $SHARE/.open_ssl_cache siap"
}

# =============================================================================
# STEP 4 — Redirect DNS + CA palsu
# =============================================================================
patch_dns_ca() {
  say "Step 4/7  Redirect DNS + CA palsu"
  if ! grep -q "$LICENSE_HOST" /etc/hosts; then
    echo "127.0.0.1 $LICENSE_HOST" >> /etc/hosts
    ok "  /etc/hosts: $LICENSE_HOST -> 127.0.0.1"
  else
    ok "  /etc/hosts sudah ada"
  fi
  # CA palsu ke cacert certifi Termux (jika ada)
  local cacert="$SP/certifi/cacert.pem"
  if [ -e "$cacert" ]; then
    if ! grep -q "BEGIN CERTIFICATE" "$cacert" 2>/dev/null || ! strings "$cacert" >/dev/null 2>&1; then :; fi
    [ -e "$cacert.asli" ] || cp -a "$cacert" "$cacert.asli"
    cat "$CERTS/lc2.pem" >> "$cacert"
    ok "  CA palsu ditambahkan ke certifi cacert.pem"
  else
    warn "  certifi cacert.pem tidak ditemukan — CA di-skip"
  fi
}

# =============================================================================
# STEP 5 — Fake TLS license server (systemd)
# =============================================================================
patch_server() {
  say "Step 5/7  Fake TLS license server (:$FAKE_TLS_PORT)"
  install -Dm644 "$FILES/fakelicstls.py" /opt/aio-patcher/fakelicstls.py
  install -Dm644 "$CERTS/lc2.pem"       /opt/aio-patcher/lc2.pem
  install -Dm600 "$CERTS/leaf.key"      /opt/aio-patcher/leaf.key
  # Pilih python yg punya pynacl
  local PY=""
  for cand in /home/agentuser/.hermes/hermes-agent/venv/bin/python3 /usr/bin/python3; do
    [ -x "$cand" ] && "$cand" -c 'import nacl' 2>/dev/null && { PY="$cand"; break; }
  done
  [ -n "$PY" ] || die "  Tidak ada python dgn pynacl (pip install pynacl)"
  # tulis service dgn path absolut yg benar
  sed -e "s|/tmp/fakelicstls.py|/opt/aio-patcher/fakelicstls.py|" \
      -e "s|/tmp/lc2.pem|/opt/aio-patcher/lc2.pem|" \
      -e "s|/tmp/leaf.key|/opt/aio-patcher/leaf.key|" \
      -e "s|^ExecStart=.*|ExecStart=$PY /opt/aio-patcher/fakelicstls.py|" \
      -e "s|/tmp/fakelics.log|/var/log/aio-fakelics.log|" \
      "$FILES/fakelics.service" > /etc/systemd/system/fakelics.service
  systemctl daemon-reload
  systemctl enable fakelics.service >/dev/null 2>&1 || true
  systemctl restart fakelics.service
  sleep 2
  systemctl is-active --quiet fakelics.service \
    && ok "  fakelics.service aktif (pid $(systemctl show -p MainPID --value fakelics.service))" \
    || die "  fakelics.service gagal start — cek: journalctl -u fakelics"
}

# =============================================================================
# STEP 5b — Blokir IP asli server (anti-exfil jaring pengaman)
# =============================================================================
patch_block_exfil() {
  say "Step 5b/7  Blokir IP server asli (anti-exfil)"
  # engine punya DoH resolver sendiri yg bisa mengabaikan /etc/hosts;
  # blokir IP asli supaya HWID TIDAK BISA sampai ke server walau DoH dipakai.
  for ip in $LICENSE_IPS; do
    # iptables: tolak keluar
    if command -v iptables >/dev/null 2>&1; then
      iptables -C OUTPUT -d "$ip" -j REJECT 2>/dev/null \
        || iptables -A OUTPUT -d "$ip" -j REJECT 2>/dev/null \
        && ok "  iptables REJECT -> $ip" || warn "  iptables gagal utk $ip"
    fi
    # null-route (blackhole) sebagai lapis kedua
    if command -v ip >/dev/null 2>&1; then
      ip route replace blackhole "$ip" 2>/dev/null \
        && ok "  blackhole route -> $ip" || warn "  route gagal utk $ip"
    fi
  done
}

# =============================================================================
# STEP 6 — Wrapper runner
# =============================================================================
patch_runner() {
  say "Step 6/7  Wrapper runner /usr/local/bin/aio"
  cat > /usr/local/bin/aio <<EOF
#!/usr/bin/env bash
cd "$RELEASE_DIR" || exit 1
export PREFIX="$TERMUX_USR"
export HOME="$TERMUX_HOME"
export PYTHONPATH="$SP"
export LD_LIBRARY_PATH="/system/lib64"
exec qemu-aarch64-static ./aio-mod "\$@"
EOF
  chmod +x /usr/local/bin/aio
  ok "  /usr/local/bin/aio siap (jalankan: sudo aio)"
}

# =============================================================================
# STEP 7 — Verifikasi
# =============================================================================
do_verify() {
  say "Step 7/7  Verifikasi"
  local fail=0
  for f in "$SP/Crypto/Signature/eddsa.py" "$SP/Cryptodome/Signature/eddsa.py"; do
    grep -qi "bypass license verify" "$f" 2>/dev/null && ok "  fake: $f" || { err "  BUKAN fake: $f"; fail=1; }
  done
  grep -q "getuid" "$SP/sitecustomize.py" 2>/dev/null && ok "  sitecustomize ok" || { err "  sitecustomize kosong"; fail=1; }
  grep -q "upgrade dilewati" /usr/bin/apt 2>/dev/null && ok "  shim apt aktif" || warn "  shim apt belum (opsional)"
  [ -e "$SHARE/.open_ssl_cache" ] && ok "  .open_ssl_cache ok" || { err "  .open_ssl_cache hilang"; fail=1; }
  grep -q "$LICENSE_HOST" /etc/hosts && ok "  hosts redirect ok" || { err "  hosts belum redirect"; fail=1; }
  systemctl is-active --quiet fakelics.service && ok "  fake TLS server aktif" || { err "  fake TLS server mati"; fail=1; }
  # cek anti-exfil (soft check: warn, bukan fail keras)
  local blk=0
  for ip in $LICENSE_IPS; do
    iptables -C OUTPUT -d "$ip" -j REJECT 2>/dev/null && blk=$((blk+1))
  done
  [ "$blk" -gt 0 ] && ok "  anti-exfil: $blk IP diblokir" || warn "  anti-exfil: belum ada IP diblokir (opsional)"
  [ -x /usr/local/bin/aio ] && ok "  runner /usr/local/bin/aio ok" || { err "  runner hilang"; fail=1; }
  echo
  if [ "$fail" = 0 ]; then
    echo -e "${C_G}══ SEMUA KOMPONEN SIAP ══${C_R}"
    echo -e "  Jalankan toolkit:  ${C_Y}sudo aio${C_R}"
    echo -e "  Engine akan menampilkan  ${C_Y}★ VIP MEMBER ★${C_R}  + 18 menu."
  else
    echo -e "${C_E}══ ADA YANG GAGAL — lihat pesan di atas ══${C_R}"; return 1
  fi
}

# =============================================================================
# REVERT
# =============================================================================
do_revert() {
  say "Revert ke kondisi asli"
  for base in Crypto Cryptodome; do
    local f="$SP/$base/Signature/eddsa.py"
    [ -e "$f.asli" ] && { mv "$f.asli" "$f"; ok "  restore $f"; }
  done
  [ -e "$SP/sitecustomize.py.asli" ] && { mv "$SP/sitecustomize.py.asli" "$SP/sitecustomize.py"; ok "  restore sitecustomize"; }
  [ -e /usr/bin/apt.asli ] && { mv /usr/bin/apt.asli /usr/bin/apt; ok "  restore /usr/bin/apt"; }
  [ -e "$TERMUX_USR/bin/apt.asli" ] && { mv "$TERMUX_USR/bin/apt.asli" "$TERMUX_USR/bin/apt"; ok "  restore Termux apt"; }
  [ -e "$SP/certifi/cacert.pem.asli" ] && { mv "$SP/certifi/cacert.pem.asli" "$SP/certifi/cacert.pem"; ok "  restore cacert"; }
  sed -i "/$LICENSE_HOST/d" /etc/hosts 2>/dev/null && ok "  hosts dibersihkan"
  for ip in $LICENSE_IPS; do
    iptables -D OUTPUT -d "$ip" -j REJECT 2>/dev/null && ok "  iptables rule -$ip dihapus"
    ip route del blackhole "$ip" 2>/dev/null && ok "  blackhole -$ip dihapus"
  done
  systemctl disable --now fakelics.service >/dev/null 2>&1 || true
  rm -f /usr/local/bin/aio /etc/systemd/system/fakelics.service
  systemctl daemon-reload 2>/dev/null || true
  ok "  revert selesai"
}

# =============================================================================
# MAIN
# =============================================================================
case "${1:-install}" in
  install|"") 
    echo -e "${C_C}╔══════════════════════════════════════════════╗"
    echo -e "║  AIO-MOD v3.5.2  LICENSE BYPASS PATCHER      ║"
    echo -e "╚══════════════════════════════════════════════╝${C_R}"
    patch_eddsa
    patch_sitecustomize
    patch_apt_shim
    patch_sentinel
    patch_dns_ca
    patch_server
    patch_block_exfil
    patch_runner
    do_verify
    ;;
  verify) do_verify ;;
  revert) do_revert ;;
  *) echo "usage: $0 [install|verify|revert]"; exit 1 ;;
esac
