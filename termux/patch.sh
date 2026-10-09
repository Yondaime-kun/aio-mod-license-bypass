#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  AIO-MOD TOOLKIT v3.5.2  —  LICENSE BYPASS PATCHER  (TERMUX NATIVE)
# =============================================================================
#  Versi ini untuk dijalankan LANGSUNG di Termux (aarch64 Android native),
#  bukan di VPS x86_64 via qemu. Perbedaan vs patch.sh (VPS):
#
#    VPS/x86              ->  Termux native
#    ─────────────────────────────────────────────
#    qemu-aarch64-static  ->  LANGSUNG jalankan ./aio-mod (native aarch64)
#    /system/lib64        ->  $PREFIX/lib (libc Termux native)
#    fake Termux FS       ->  SUDAH Termux asli
#    systemd service      ->  nohup / Termux:Boot (Android tak ada systemd)
#    iptables             ->  tak perlu (TIDAK ada jalur keluar ke server asli
#                             kalau hosts + fake server sudah lokal; Android
#                             non-root juga tak punya iptables)
#
#  Yang TETAP sama: fake Crypto.Signature.eddsa + sitecustomize + sentinel +
#  hosts redirect + fake TLS server. Inti bypass identik.
#
#  Usage:  ./patch-termux.sh [install|verify|revert]
# =============================================================================
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
SP="$PREFIX/lib/python3.14/site-packages"
SHARE="$PREFIX/share"
RELEASE_DIR="$HOME_DIR/release"
FAKE_TLS_PORT=8443
# Engine asli (decoded, dynamic) — launcher upstream (13.8MB) tidak dipakai
# karena jalur unduh/decode-nya gagal di Termux non-root (lihat patch_engine).
ENGINE_DIR="$HOME_DIR/.aio-patcher/engine"
ENGINE_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/aio-mod-engine"
ENGINE_MD5="785231328c86e8e3e24f8a2c7f149814"
LIBPY_URL="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/libpython3.14.so"
LIBPY_MD5="778aec5978a4f2b47b2fc6f81ad2262f"
LICENSE_HOST="aio.scwill.store"
RUN_DIR="$HOME_DIR/.aio-patcher"          # pengganti /opt (tak perlu root)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SELF_DIR/files"
CERTS="$SELF_DIR/../shared/certs"
FAKESRV="$SELF_DIR/../shared/fakelicstls.py"

C_R="\033[0m"; C_G="\033[1;32m"; C_Y="\033[1;33m"; C_E="\033[1;31m"; C_C="\033[1;36m"
say()  { echo -e "${C_C}▸${C_R} $*"; }
ok()   { echo -e "${C_G}✓${C_R} $*"; }
warn() { echo -e "${C_Y}!${C_R} $*"; }
err()  { echo -e "${C_E}×${C_R} $*" >&2; }
die()  { err "$*"; exit 1; }

# Deteksi Termux: PREFIX harus berisi pola com.termux DAN python TERMUX asli
# (bukan fake FS di VPS x86 — bedakan via uname arch + keberadaan $PREFIX/lib/libpython)
IS_TERMUX=0
case "$PREFIX" in
  */com.termux/*|*/com.termux) IS_TERMUX=1 ;;
esac
# VPS x86 emulasi: uname x86_64 -> bukan Termux asli
[ "$(uname -m)" = "aarch64" ] && [ "$IS_TERMUX" = 1 ] || {
  if [ "$(uname -m)" != "aarch64" ]; then
    die "Patcher Termux ini butuh arsitektur aarch64 (Termux asli). Di x86 pakai patch.sh."
  fi
}

# =============================================================================
# STEP 1 — Fake Ed25519 verifier (yang menyembuhkan license wall)
# =============================================================================
patch_eddsa() {
  say "Step 1/7  Fake Ed25519 verifier (Crypto + Cryptodome)"
  [ -f "$FILES/eddsa_fake.py" ] || die "  eddsa_fake.py tak ada di $FILES"

  # PENTING: paket Termux 'python-pycryptodomex' HANYA menyediakan 'Cryptodome',
  # sedangkan engine meng-import 'Crypto.Signature.eddsa'. Bikin alias Crypto
  # -> Cryptodome kalau 'Crypto' belum ada (inilah yg sering bikin Gagal/Gratis).
  if [ ! -d "$SP/Crypto" ] && [ -d "$SP/Cryptodome" ]; then
    ln -sfn Cryptodome "$SP/Crypto" 2>/dev/null \
      && ok "  alias Crypto -> Cryptodome dibuat" \
      || warn "  gagal bikin alias Crypto -> Cryptodome"
  fi

  local found=0
  for base in Crypto Cryptodome; do
    local tgt="$SP/$base/Signature/eddsa.py"
    [ -e "$tgt" ] || { warn "  $tgt tak ada — $base belum terpasang"; continue; }
    [ -e "$tgt.asli" ] || cp -a "$tgt" "$tgt.asli"
    cp "$FILES/eddsa_fake.py" "$tgt"
    # Termux punya eddsa.pyi (stub typing) di sebelahnya; hapus supaya tak
    # menutupi/pembingungkan, dan bersihkan pycache (WAJIB: .pyc lama tetap
    # dipakai kalau timestamp-nya lebih baru dari .py hasil copy -> engine
    # tetap pakai verifier ASLI -> gate gagal -> Gratis).
    rm -f "$SP/$base/Signature/eddsa.pyi"
    rm -rf "$SP/$base/Signature/__pycache__"
    # Paksa timestamp .py lebih baru dari segala .pyc yg mungkin tersisa.
    touch "$tgt"
    if grep -q "bypass license verify" "$tgt" 2>/dev/null; then
      ok "  $base/Signature/eddsa.py -> fake (terverifikasi)"
    else
      err "  $base/Signature/eddsa.py GAGAL ditimpa fake"
    fi
    found=1
  done

  # Verifikasi: engine HARUS bisa `import Crypto.Signature.eddsa` DAN modul
  # yg ke-import harus benar-benar fake (kalau tidak, engine pakai verifier asli).
  if python3 -c "
import Crypto.Signature.eddsa as m, inspect, sys
src = inspect.getsource(m)
sys.exit(0 if 'bypass license verify' in src else 3)
" 2>/dev/null; then
    ok "  import Crypto.Signature.eddsa -> FAKE (engine akan bypass)"
  else
    die "  import Crypto.Signature.eddsa BUKAN fake — pyc/versi bentrok. Cek pycryptodome."
  fi

  [ "$found" = 1 ] || die "  pycryptodome belum terpasang: pkg install python-pycryptodomex"
}

# =============================================================================
# STEP 1b — Fake cryptography.Ed25519 (PENENTU saat paket cryptography ada)
# =============================================================================
# TEMUAN PALING PENTING (reproduced A/B/C):
#   Engine memilih backend verifikasi secara adaptif.
#     - TANPA paket 'cryptography'  -> pakai Crypto.Signature.eddsa  -> fake eddsa
#       di Step 1 BERPENGARUH -> VIP.
#     - DENGAN paket 'cryptography' -> pakai cryptography.hazmat...
#       Ed25519PublicKey.verify() (implementasi RUST) -> fake eddsa TIDAK
#       dipakai sama sekali -> engine jatuh ke [ Gratis ] dengan pesan
#       "Tanda tangan respons server tidak valid".
#   Gejala khas di HP: eddsa_hook.log TIDAK PERNAH dibuat, padahal
#   Crypto/Signature/eddsa.py sudah FAKE (karena engine tidak mengimpornya).
#   -> Solusi: timpa juga cryptography...ed25519 dengan verify() no-op.
patch_cryptography() {
  say "Step 1b/7  Fake cryptography Ed25519 (kalau paket cryptography ada)"
  # Modul target: cryptography/hazmat/primitives/asymmetric/ed25519.py
  local targets=()
  local d
  for d in "$SP/cryptography/hazmat/primitives/asymmetric" \
           "$PREFIX/lib/python3.14/site-packages/cryptography/hazmat/primitives/asymmetric"; do
    [ -d "$d" ] && targets+=("$d/ed25519.py")
  done
  if [ "${#targets[@]}" = 0 ]; then
    ok "  paket cryptography tidak ada — engine akan pakai Crypto.Signature.eddsa (Step 1)"
    return 0
  fi
  [ -f "$FILES/ed25519_fake.py" ] || { warn "  ed25519_fake.py tak ada di $FILES"; return 0; }
  local t
  for t in "${targets[@]}"; do
    [ -e "$t" ] || continue
    [ -e "$t.asli" ] || cp -a "$t" "$t.asli"
    cp "$FILES/ed25519_fake.py" "$t"
    rm -rf "$(dirname "$t")/__pycache__"
    touch "$t"
    if grep -q "BYPASS verifikasi" "$t" 2>/dev/null; then
      ok "  cryptography .../ed25519.py -> fake (verify no-op)"
    else
      err "  cryptography .../ed25519.py GAGAL ditimpa"
    fi
  done
  # Verifikasi import: kelas yg ke-load harus fake, dan verify() harus no-op.
  if python3 -c "
import sys
from cryptography.hazmat.primitives.asymmetric import ed25519
k = ed25519.Ed25519PublicKey.from_public_bytes(b'\x00'*32)
try:
    k.verify(b'\x00'*64, b'x')   # fake: tidak melempar
except Exception:
    sys.exit(3)
sys.exit(0 if hasattr(k, 'verify') else 4)
" 2>/dev/null; then
    ok "  cryptography Ed25519PublicKey.verify() -> no-op (bypass)"
  else
    warn "  verifikasi fake cryptography gagal — cek versi paket cryptography"
  fi
}

# =============================================================================
# STEP 2 — sitecustomize (spoof uid; di Termux native getuid biasanya sudah 0/10123,
#          tapi tetap pasang utk konsistensi)
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
# STEP 2b — Shim apt (blokir 'upgrade' yang lambat, matikan progress bar non-TTY)
# =============================================================================
patch_apt_shim() {
  say "Step 2b/7  Shim apt (skip 'upgrade')"
  local binn="$PREFIX/bin"
  local real="$binn/apt"
  # PENTING: JANGAN timpa $PREFIX/bin/apt — dpkg akan gagal "Setting up apt"
  # (file milik paket 'apt' berubah) sehingga `pkg install` mati total.
  # Engine mencari `apt` di PATH; cukup taruh shim sebagai `apt` di bin kita
  # SENDIRI yang lebih depan di PATH daripada $PREFIX/bin.
  local shim_dir="$RUN_DIR/shim-bin"
  mkdir -p "$shim_dir"
  install -m755 "$FILES/apt-shim.sh" "$shim_dir/apt" 2>/dev/null \
    && ok "  shim apt dipasang di $shim_dir/apt (tidak menimpa paket apt)" \
    || warn "  gagal pasang shim apt"
  # apt-get TIDAK di-shim (dpkg & pkg memakainya); biarkan asli.
  if [ -e "$real" ] && [ ! -e "$real.asli" ]; then
    cp -a "$real" "$real.asli" 2>/dev/null || true
  fi
}

# =============================================================================
# STEP 3 — Sentinel .open_ssl_cache + CA palsu ke certifi
# =============================================================================
patch_sentinel() {
  say "Step 3/7  Sentinel .open_ssl_cache"
  mkdir -p "$SHARE"
  [ -e "$SHARE/.open_ssl_cache" ] || touch "$SHARE/.open_ssl_cache"
  chmod 666 "$SHARE/.open_ssl_cache" 2>/dev/null || true
  ok "  $SHARE/.open_ssl_cache siap"
}

# Engine memvalidasi TLS server dgn CA store (certifi / OpenSSL default).
# Tanpa CA kita di store, handshake ditolak: TLSV1_ALERT_UNKNOWN_CA -> Gratis.
patch_ca() {
  say "Step 3b/7  CA palsu -> trust store (certifi / etc tls)"
  local added=0
  # WAJIB: root CA (we1ca.pem). Engine memvalidasi chain TLS thd root CA ini;
  # tanpa root CA di trust store -> TLSV1_ALERT_UNKNOWN_CA -> mode Gratis.
  local ca_files="$CERTS/we1ca.pem $CERTS/lc2.pem"
  for cacert in "$SP/certifi/cacert.pem" \
                "$PREFIX/lib/python3.14/site-packages/certifi/cacert.pem"; do
    [ -e "$cacert" ] || continue
    [ -e "$cacert.asli" ] || cp -a "$cacert" "$cacert.asli" 2>/dev/null || true
    local need=0
    [ -f "$CERTS/we1ca.pem" ] && ! grep -qF "$(head -1 "$CERTS/we1ca.pem")" "$cacert" 2>/dev/null && need=1
    if [ "$need" = 1 ]; then
      { echo ""; echo "# aio-mod patcher: fake root CA"; cat "$CERTS/we1ca.pem"; \
        [ -f "$CERTS/lc2.pem" ] && cat "$CERTS/lc2.pem"; } >> "$cacert" 2>/dev/null \
        && { ok "  root CA (WE1) + leaf -> $cacert"; added=1; }
    else
      ok "  root CA sudah ada di $cacert"; added=1
    fi
  done
  # CA bundle OpenSSL Termux (dipakai _ssl langsung)
  local tls="$PREFIX/etc/tls/cert.pem"
  if [ -f "$tls" ]; then
    [ -e "$tls.asli" ] || cp -a "$tls" "$tls.asli" 2>/dev/null || true
    if ! grep -qF "$(head -1 "$CERTS/we1ca.pem" 2>/dev/null)" "$tls" 2>/dev/null; then
      { cat "$CERTS/we1ca.pem"; [ -f "$CERTS/lc2.pem" ] && cat "$CERTS/lc2.pem"; } >> "$tls" 2>/dev/null \
        && { ok "  root CA + leaf -> $tls"; added=1; }
    fi
  fi
  # PENTING: engine (Nuitka, via _ssl) memakai cacert.pem BAWAAN certifi
  # (bukan env SSL_CERT_FILE). Kalau CA kita hanya ada di ca-bundle.pem,
  # handshake tetap ditolak: TLSV1_ALERT_UNKNOWN_CA -> Gratis. Jadi sisipkan
  # LANGSUNG ke cacert.pem (dan simpan .asli utk revert).
  local cac="$SP/certifi/cacert.pem"
  if [ -f "$cac" ]; then
    [ -e "$cac.asli" ] || cp -a "$cac" "$cac.asli" 2>/dev/null || true
    if ! grep -qF "$(head -1 "$CERTS/we1ca.pem" 2>/dev/null)" "$cac" 2>/dev/null; then
      { cat "$CERTS/we1ca.pem"; [ -f "$CERTS/lc2.pem" ] && cat "$CERTS/lc2.pem"; } >> "$cac" 2>/dev/null \
        && { cacert_n=$(grep -c "BEGIN CERT" "$cac" 2>/dev/null); \
             ok "  root CA + leaf -> cacert.pem ($cacert_n cert)"; added=1; }
    fi
  fi
  [ "$added" = 1 ] || warn "  tidak ada trust store yg ditemukan — set SSL_CERT_FILE manual"
}

# =============================================================================
# STEP 4 — Redirect DNS (Termux non-root: TIDAK bisa tulis /etc/hosts)
# =============================================================================
patch_dns() {
  say "Step 4/7  Redirect DNS $LICENSE_HOST"
  # Termux non-root TIDAK bisa menulis /etc/hosts (system file Android).
  # Solusinya: pasang shim DNS lokal lewat resolv/route engine sendiri.
  if [ -w /etc/hosts ] 2>/dev/null; then
    # Kasus langka: HP rooted & /etc/hosts writable
    grep -q "$LICENSE_HOST" /etc/hosts 2>/dev/null \
      || echo "127.0.0.1 $LICENSE_HOST" >> /etc/hosts
    ok "  /etc/hosts diupdate (root tersedia)"
  else
    # Non-root: pakai shim getaddrinfo/socket di sitecustomize (lihat catatan)
    ok "  non-root: /etc/hosts dilewati (normal di Termux)"
    # cek di SEMUA lokasi yg dipindai engine (SP, release/, .local/)
    local _dns_ok=0
    for _f in "$SP/sitecustomize.py" "$RELEASE_DIR/sitecustomize.py" \
              "$HOME_DIR/.local/lib/python3.14/site-packages/sitecustomize.py"; do
      if [ -f "$_f" ] && grep -qE "_DNS_REDIRECT|_dns_redirect" "$_f" 2>/dev/null; then
        ok "  DNS redirect aktif via sitecustomize: $_f"
        _dns_ok=1
      fi
    done
    if [ "$_dns_ok" = 0 ]; then
      warn "  DNS redirect belum terpasang di sitecustomize manapun"
      warn "  -> jalankan: cp '$FILES/sitecustomize.py' '$RELEASE_DIR/sitecustomize.py'"
    fi
  fi
}

# =============================================================================
# STEP 4b — Engine sebenarnya (27MB, decoded)
# =============================================================================
# 'aio-mod' yg di-download dari upstream (13.8MB) adalah INSTALLER/launcher:
# ia mengunduh & men-decode engine asli ke $HOME/release lalu menjalankannya.
# Di Termux non-root langkah download-nya sering gagal (HTTPError utk banyak
# dependency) sehingga yg jalan adalah launcher sendiri -> license gate beda ->
# mode Gratis. Jadi kita pasang engine ASLI (dynamic, 27MB) langsung, dan
# runner menjalankan itu.
patch_engine() {
  say "Step 4b/7  Engine asli (decoded, 27MB)"
  mkdir -p "$ENGINE_DIR"
  local eng="$ENGINE_DIR/aio-mod-engine"
  if [ -s "$eng" ] && [ "$(md5sum "$eng" 2>/dev/null | cut -d' ' -f1)" = "$ENGINE_MD5" ]; then
    ok "  engine sudah ada & md5 cocok"
  else
    ok "  engine belum ada — mengunduh dari upstream release..."
    if command -v curl >/dev/null 2>&1; then
      curl -sL --retry 2 -o "$eng" "$ENGINE_URL" || true
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$eng" "$ENGINE_URL" || true
    fi
    local got=$(md5sum "$eng" 2>/dev/null | cut -d' ' -f1)
    if [ "$got" != "$ENGINE_MD5" ]; then
      rm -f "$eng"
      die "  gagal unduh engine (md5=$got, harus $ENGINE_MD5)
      unduh manual: $ENGINE_URL
      taruh di: $eng"
    fi
  fi
  chmod 755 "$eng"
  # Engine dynamic butuh libpython3.14.so VERSI KHUSUS (bukan libpython Termux
  # biasa: isinya beda). Ambil dari release asset yg sama, taruh di samping
  # engine, lalu runner mengarahkan LD_LIBRARY_PATH ke folder itu.
  local lib="$ENGINE_DIR/libpython3.14.so"
  if [ ! -s "$lib" ] || [ "$(md5sum "$lib" 2>/dev/null | cut -d' ' -f1)" != "$LIBPY_MD5" ]; then
    if command -v curl >/dev/null 2>&1; then
      curl -sL --retry 2 -o "$lib" "$LIBPY_URL" || true
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$lib" "$LIBPY_URL" || true
    fi
    if [ "$(md5sum "$lib" 2>/dev/null | cut -d' ' -f1)" != "$LIBPY_MD5" ]; then
      warn "  libpython3.14.so gagal diunduh (engine mungkin tetap 'cari lib' error)"
      rm -f "$lib"
    fi
  fi
  [ -s "$lib" ] && ok "  libpython3.14.so siap ($(stat -c%s "$lib" 2>/dev/null || echo ?) bytes)"
  # libandroid-support.so: libpython3.14.so (aarch64 Termux build) LINK ke ini;
  # tanpa dia libpython gagal load -> engine ambil jalur berbeda -> "Tanda
  # tangan respons server tidak valid". WAJIB, walau cuma 20KB.
  local libas="$ENGINE_DIR/libandroid-support.so"
  local libas_url="https://github.com/Yondaime-kun/aio-mod-license-bypass/releases/download/engine-v3.5.2/libandroid-support.so"
  if [ ! -s "$libas" ]; then
    dl "$libas_url" "$libas" 2>/dev/null || true
  fi
  if [ -s "$libas" ]; then
    cp -f "$libas" "$RELEASE_DIR/libandroid-support.so" 2>/dev/null || true
    ok "  libandroid-support.so siap ($(stat -c%s "$libas" 2>/dev/null) bytes)"
  else
    warn "  libandroid-support.so GAGAL diunduh (engine mungkin pakai jalur beda)"
  fi
  # Engine 27MB disebar ke $RELEASE_DIR (yg dipindai Nuitka) + dipakai runner.
  # rm dulu: 'install' bisa gagal menimpa file executable yg sedang dipakai.
  local rdst="$RELEASE_DIR/aio-mod"
  rm -f "$rdst" "$rdst.engine" 2>/dev/null || true
  cp -f "$eng" "$RELEASE_DIR/aio-mod-engine" 2>/dev/null || true
  cp -f "$eng" "$rdst" 2>/dev/null || true
  chmod 755 "$rdst" "$RELEASE_DIR/aio-mod-engine" 2>/dev/null || true
  ok "  engine terpasang: $eng ($(stat -c%s "$eng" 2>/dev/null || echo '?') bytes)"
  # python shared lib utk engine dynamic: VERSI KHUSUS dari release (bukan
  # libpython Termux biasa). Taruh di ENGINE_DIR + RELEASE_DIR.
  local libsrc="$ENGINE_DIR/libpython3.14.so"
  if [ -s "$libsrc" ]; then
    cp -f "$libsrc" "$RELEASE_DIR/libpython3.14.so" 2>/dev/null || true
    ok "  libpython3.14.so -> $RELEASE_DIR"
  fi
}

# =============================================================================
# STEP 4c — Dependency engine (java/zip/7z/aapt/java...)
# =============================================================================
# Temuan lapangan: tanpa paket ini engine berhenti di "Install paket utama
# AIO-MOD..." / "Sync resource toolkit..." lalu tak pernah sampai menu.
# Engine TIDAK bisa menginstalnya sendiri di Termux non-root dengan andal,
# jadi kita pasang lebih dulu (pkg install). Daftar = yg engine cek sendiri.
patch_deps() {
  say "Step 4c/7  Dependency engine (zip/7z/aapt/java/clang)"
  local need=()
  command -v zip      >/dev/null 2>&1 || need+=(zip)
  command -v unzip    >/dev/null 2>&1 || need+=(unzip)
  command -v 7z       >/dev/null 2>&1 || need+=(p7zip)
  command -v aapt     >/dev/null 2>&1 || need+=(aapt)
  command -v java     >/dev/null 2>&1 || need+=(openjdk-17)
  command -v clang    >/dev/null 2>&1 || need+=(clang)
  command -v python3  >/dev/null 2>&1 || need+=(python)
  python3 -c 'import Crypto' 2>/dev/null || need+=(python-pycryptodomex)
  python3 -c 'import nacl'   2>/dev/null || need+=(python-pynacl)
  python3 -c 'import requests' 2>/dev/null || need+=(python-requests)
  python3 -c 'import certifi'  2>/dev/null || need+=(python-certifi)
  if [ "${#need[@]}" = 0 ]; then
    ok "  semua dependency sudah ada"
    return 0
  fi
  say "  memasang: ${need[*]}"
  export DEBIAN_FRONTEND=noninteractive
  # dpkg bisa nyangkut di conffile prompt (sources.list) -> paksa non-interaktif.
  if command -v apt-get >/dev/null 2>&1; then
    apt-get -y -o Dpkg::Options::=--force-confnew \
            -o Dpkg::Options::=--force-confdef install "${need[@]}" >/dev/null 2>&1 \
      || apt-get -y -f install >/dev/null 2>&1 || true
  fi
  # pip utk yg tak ada di repo Termux (certifi/requests/pynacl)
  for pkg in certifi requests; do
    python3 -c "import $pkg" 2>/dev/null || \
      python3 -m pip install --quiet "$pkg" >/dev/null 2>&1 || true
  done
  local missing=()
  for c in zip unzip 7z aapt java clang; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ "${#missing[@]}" = 0 ] \
    && ok "  dependency terpasang" \
    || warn "  masih kurang: ${missing[*]} (install manual: pkg install ${missing[*]})"
}

# =============================================================================
# STEP 4d — Blokir server license ASLI (engine pakai DoH -> hosts tak cukup)
# =============================================================================
# Temuan lapangan: engine me-resolve license host lewat DoH sendiri sehingga
# /etc/hosts DIABAIKAN; ia benar2 connect ke IP Cloudflare asli lalu gagal.
# Wajib REJECT IP asli supaya engine jatuh ke 127.0.0.1 (fake server kita).
# Non-root: coba iptables; kalau tidak bisa, andalkan sitecustomize redirect
# (lihat patch_dns) dan laporkan apa adanya.
patch_block_real() {
  say "Step 4d/7  Blokir IP server license asli (anti-exfil)"
  local blocked=0 ip
  if command -v iptables >/dev/null 2>&1 && iptables -L OUTPUT -n >/dev/null 2>&1; then
    for ip in $LICENSE_IPS; do
      iptables -C OUTPUT -d "$ip" -j REJECT 2>/dev/null \
        || iptables -A OUTPUT -d "$ip" -j REJECT 2>/dev/null \
        && { ok "  iptables REJECT $ip"; blocked=1; }
    done
  fi
  [ "$blocked" = 1 ] \
    && return 0
  warn "  iptables tak tersedia/tak diizinkan (Termux non-root normal)"
  warn "  -> andalan: sitecustomize redirect socket. Kalau engine tetap Gratis,"
  warn "     jalankan blokir di container/host: iptables -A OUTPUT -d <IP> -j REJECT"
}

# =============================================================================
# STEP 5 — Fake TLS server (nohup, BUKAN systemd)
# =============================================================================
patch_server() {
  say "Step 5/7  Fake TLS license server (:$FAKE_TLS_PORT, nohup)"
  mkdir -p "$RUN_DIR"
  install -m644 "$FAKESRV" "$RUN_DIR/fakelicstls.py"
  install -m644 "$CERTS/lc2.pem"   "$RUN_DIR/lc2.pem"
  install -m600 "$CERTS/leaf.key"  "$RUN_DIR/leaf.key"
  install -m644 "$CERTS/we1ca.pem" "$RUN_DIR/we1ca.pem"
  # pilih python dgn pynacl (Termux: pkg install python-pynacl)
  local PY=""
  for cand in "$PREFIX/bin/python3" "$PREFIX/bin/python" python3; do
    command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import nacl' 2>/dev/null \
      && { PY="$cand"; break; }
  done
  [ -n "$PY" ] || die "  pynacl belum ada: pkg install python-pynacl
      (WAJIB: fake server harus tanda-tangan Ed25519 sungguhan pakai PyNaCl)"
  # matikan instans lama (proses apa pun yg pegang port 8443 / nama file)
  pkill -9 -f "$RUN_DIR/fakelicstls.py" 2>/dev/null || true
  pkill -9 -f "fakelicstls" 2>/dev/null || true
  pkill -9 -f "fakelics-debug.py" 2>/dev/null || true
  # tunggu port benar2 bebas (maks ~6s)
  local i=0
  while [ $i -lt 12 ]; do
    "$PY" - <<PYEOF 2>/dev/null && break
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("0.0.0.0", $FAKE_TLS_PORT)); s.close(); raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PYEOF
    # bind gagal / masih dipakai -> tidur, coba lagi
    i=$((i+1)); sleep 0.5
  done
  sleep 0.5
  nohup "$PY" "$RUN_DIR/fakelicstls.py" >> "$RUN_DIR/fakelics.log" 2>&1 &
  sleep 2
  if pgrep -f "$RUN_DIR/fakelicstls.py" >/dev/null; then
    ok "  fake server jalan (pid $(pgrep -f "$RUN_DIR/fakelicstls.py" | head -1))"
    # verifikasi: server beneran bales JSON VIP.
    # PENTING: pakai $PY (python yg punya nacl) utk probe, bukan python3 sembarang.
    local resp
    resp=$("$PY" -c "
import socket, ssl
ctx = ssl._create_unverified_context()
try:
    s = ctx.wrap_socket(socket.create_connection(('127.0.0.1', $FAKE_TLS_PORT), timeout=5))
    s.sendall(b'POST /v1/device/check HTTP/1.1\r\nHost: aio.scwill.store\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
    data = b''
    s.settimeout(5)
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
        if b'is_vip' in data:
            break
    print('is_vip' if b'is_vip' in data else 'NO_VIP:' + repr(data[:80]))
except Exception as e:
    print('ERR:' + str(e))
" 2>&1)
    if [ "$resp" = "is_vip" ]; then
      ok "  server bales JSON VIP (terverifikasi)"
    else
      warn "  server GAGAL bales VIP -> $resp"
      echo "  --- 8 baris terakhir $RUN_DIR/fakelics.log:"
      tail -8 "$RUN_DIR/fakelics.log" 2>/dev/null | sed 's/^/      /'
      echo "  --- cek python '$PY' punya nacl?"
      "$PY" -c "import nacl; print('      nacl OK', nacl.__version__)" 2>&1 | sed 's/^/      /'
    fi
  else
    die "  fake server gagal start — cek $RUN_DIR/fakelics.log"
  fi
  # helper start/stop
  cat > "$RUN_DIR/start-server.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "$RUN_DIR/fakelicstls.py" 2>/dev/null || true
sleep 1
nohup "$PY" "$RUN_DIR/fakelicstls.py" >> "$RUN_DIR/fakelics.log" 2>&1 &
echo "fake server started"
EOF
  chmod +x "$RUN_DIR/start-server.sh"
}

# =============================================================================
# STEP 6 — Runner $PREFIX/bin/aio (native, TANPA qemu)
# =============================================================================
patch_runner() {
  say "Step 6/7  Runner $PREFIX/bin/aio  (native aarch64)"
  cat > "$PREFIX/bin/aio" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Jalankan engine langsung (native — Termux sudah aarch64).
cd "$RELEASE_DIR" || { echo "dir release tak ada: $RELEASE_DIR"; exit 1; }
export PREFIX="$PREFIX"
export HOME="$HOME_DIR"
# PYTHONPATH: SITE-PACKAGES (utk fake eddsa) + RELEASE_DIR (utk sitecustomize)
export PYTHONPATH="$SP:$RELEASE_DIR"
# CA BUNDLE: engine memvalidasi TLS server thd trust store Python.
# Bundle = CA palsu kita (root WE1 + leaf) + certifi bawaan. Tanpa ini engine
# menolak cert: TLSV1_ALERT_UNKNOWN_CA -> jatuh ke mode Gratis.
CA_BUNDLE="$RUN_DIR/ca-bundle.pem"
if [ ! -s "\$CA_BUNDLE" ]; then
  cat "$RUN_DIR/we1ca.pem" "$RUN_DIR/lc2.pem" "$SP/certifi/cacert.pem" > "\$CA_BUNDLE" 2>/dev/null || true
fi
if [ -s "\$CA_BUNDLE" ]; then
  export SSL_CERT_FILE="\$CA_BUNDLE"
  export REQUESTS_CA_BUNDLE="\$CA_BUNDLE"
  export CURL_CA_BUNDLE="\$CA_BUNDLE"
fi
# PENTING: Nuitka standalone kadang tak scan PYTHONPATH utk sitecustomize.
# Salin sitecustomize ke SEMUA lokasi yg mungkin dipindai interpreter:
cp -f "$SP/sitecustomize.py" "$RELEASE_DIR/sitecustomize.py" 2>/dev/null
mkdir -p "$HOME_DIR/.local/lib/python3.14/site-packages" 2>/dev/null
cp -f "$SP/sitecustomize.py" "$HOME_DIR/.local/lib/python3.14/site-packages/sitecustomize.py" 2>/dev/null
# PATH: shim-bin (apt no-op upgrade) HARUS lebih depan dari $PREFIX/bin, kalau
# tidak engine memanggil apt asli & dpkg bisa rusak. Juga pastikan bin engine
# (java/zip/7z/aapt/clang) terlihat.
export PATH="$RUN_DIR/shim-bin:$PREFIX/bin:$PREFIX/bin/applets:\$PATH"
# LD_LIBRARY_PATH: engine dynamic butuh libpython3.14.so VERSI KHUSUS (bukan
# libpython Termux biasa). Engine + lib ada di $ENGINE_DIR.
# PENTING (fix lapangan): JANGAN pakai /system/lib64 di Termux native —
# linker Android namespace 'default' tak memuat lib kita, dan bionic /system
# beda versi -> "CANNOT LINK EXECUTABLE". Pakai $ENGINE_DIR + $PREFIX/lib.
export LD_LIBRARY_PATH="$ENGINE_DIR:$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
# PENTING: engine harus dijalankan PERSIS seperti VPS yang sukses:
#   CWD        = release dir (engine cari sitecustomize/.aio_work relatif CWD)
#   PYTHONPATH = release:site-packages (sitecustomize + modul engine)
#   COLUMNS    = 80 (layout engine)
# Pakai path LITERAL: variabel runner tidak selalu ter-set saat 'aio' dipanggil.
RELEASE_DIR="${RELEASE_DIR:-$HOME_DIR/release}"
SP="${SP:-$PREFIX/lib/python3.14/site-packages}"
cd "$RELEASE_DIR" 2>/dev/null || cd "$HOME" 2>/dev/null || true
export PYTHONPATH="$RELEASE_DIR:$SP${PYTHONPATH:+:$PYTHONPATH}"
export COLUMNS="${COLUMNS:-80}"
# Jalankan engine 27MB dari $ENGINE_DIR (bukan launcher 13.8MB di release/).
ENGINE_BIN="$ENGINE_DIR/aio-mod-engine"
[ -x "\$ENGINE_BIN" ] || ENGINE_BIN="$RELEASE_DIR/aio-mod"
"\$ENGINE_BIN" "\$@"
EOF
  chmod +x "$PREFIX/bin/aio"
  ok "  $PREFIX/bin/aio siap (jalankan: aio)"
}

# =============================================================================
# VERIFY
# =============================================================================
do_verify() {
  say "Verifikasi"
  local fail=0
  for base in Crypto Cryptodome; do
    local f="$SP/$base/Signature/eddsa.py"
    [ -e "$f" ] || continue
    grep -qi "bypass license verify" "$f" 2>/dev/null \
      && ok "  fake: $base" || { err "  BUKAN fake: $base"; fail=1; }
  done
  # cryptography ed25519 WAJIB fake kalau paket cryptography terpasang
  # (kalau tidak: engine pakai verifier RUST -> "Tanda tangan respons server
  # tidak valid" -> Gratis, walau Crypto/Signature/eddsa.py sudah fake).
  local ce="$SP/cryptography/hazmat/primitives/asymmetric/ed25519.py"
  if [ -e "$ce" ]; then
    grep -q "BYPASS verifikasi" "$ce" 2>/dev/null \
      && ok "  fake: cryptography Ed25519 (verify no-op)" \
      || { err "  cryptography Ed25519 BUKAN fake — engine akan Gratis"; fail=1; }
  else
    ok "  cryptography tidak terpasang (engine pakai fake eddsa)"
  fi
  grep -q "getuid" "$SP/sitecustomize.py" 2>/dev/null && ok "  sitecustomize ok" || { err "  sitecustomize kosong"; fail=1; }
  [ -e "$SHARE/.open_ssl_cache" ] && ok "  .open_ssl_cache ok" || { err "  sentinel hilang"; fail=1; }
  # CA palsu WAJIB ada di cacert.pem certifi (kalau tidak: TLSV1_ALERT_UNKNOWN_CA)
  # Cek via PEM utuh CA kita (bukan baris "BEGIN CERTIFICATE" yang juga dimiliki
  # 120 CA bawaan -> false positive/negative).
  local cac="$SP/certifi/cacert.pem"
  local ca_pem="$CERTS/we1ca.pem"
  if [ -f "$cac" ] && [ -f "$ca_pem" ] && \
     python3 - "$cac" "$ca_pem" <<'PY' 2>/dev/null
import sys
try:
    cac = open(sys.argv[1], "rb").read()
    ca  = open(sys.argv[2], "rb").read().strip()
except Exception:
    sys.exit(1)
# Bandingkan isi base64 (abaikan whitespace/header perbedaan minor).
import re
norm = lambda b: re.sub(rb"\s+", b"", b)
sys.exit(0 if norm(ca) in norm(cac) else 1)
PY
  then
    ok "  CA palsu ada di certifi cacert.pem ($(grep -c 'BEGIN CERT' "$cac" 2>/dev/null) cert)"
  else
    err "  CA palsu TIDAK ada di certifi cacert.pem (handshake akan ditolak)"; fail=1
  fi
  # dependency engine
  local dm=0
  for c in zip unzip 7z aapt java; do
    command -v "$c" >/dev/null 2>&1 && dm=$((dm+1))
  done
  [ "$dm" -ge 4 ] && ok "  dependency engine terpasang ($dm/5)" \
                  || warn "  dependency engine kurang ($dm/5) — engine bisa stuck saat setup"
  pgrep -f "$RUN_DIR/fakelicstls.py" >/dev/null && ok "  fake TLS server aktif" || { err "  fake server mati"; fail=1; }
  [ -x "$PREFIX/bin/aio" ] && ok "  runner 'aio' ok" || { err "  runner hilang"; fail=1; }
  [ -d "$RELEASE_DIR" ] && ok "  release dir ok" || warn "  release dir belum ada: $RELEASE_DIR"
  echo
  if [ "$fail" = 0 ]; then
    echo -e "${C_G}══ SEMUA KOMPONEN SIAP (Termux native) ══${C_R}"
    echo -e "  Jalankan:  ${C_Y}aio${C_R}   (atau: cd $RELEASE_DIR && ./aio-mod)"
    echo -e "  Engine akan menampilkan  ${C_Y}★ VIP MEMBER ★${C_R}"
  else
    echo -e "${C_E}══ ADA YANG GAGAL ══${C_R}"; return 1
  fi
}

do_revert() {
  say "Revert"
  for base in Crypto Cryptodome; do
    local f="$SP/$base/Signature/eddsa.py"
    [ -e "$f.asli" ] && { mv "$f.asli" "$f"; ok "  restore $base"; }
  done
  # restore cryptography ed25519 (kalau pernah di-fake)
  local ce="$SP/cryptography/hazmat/primitives/asymmetric/ed25519.py"
  [ -e "$ce.asli" ] && { mv "$ce.asli" "$ce"; rm -rf "$(dirname "$ce")/__pycache__"; ok "  restore cryptography ed25519"; }
  [ -e "$SP/sitecustomize.py.asli" ] && { mv "$SP/sitecustomize.py.asli" "$SP/sitecustomize.py"; ok "  restore sitecustomize"; }
  [ -e "$PREFIX/bin/apt.asli" ] && { mv "$PREFIX/bin/apt.asli" "$PREFIX/bin/apt"; ok "  restore apt"; }
  # restore trust store (certifi + openssl)
  [ -e "$SP/certifi/cacert.pem.asli" ] && { mv "$SP/certifi/cacert.pem.asli" "$SP/certifi/cacert.pem"; ok "  restore certifi"; }
  [ -e "$PREFIX/etc/tls/cert.pem.asli" ] && { mv "$PREFIX/etc/tls/cert.pem.asli" "$PREFIX/etc/tls/cert.pem"; ok "  restore tls cert.pem"; }
  pkill -f "$RUN_DIR/fakelicstls.py" 2>/dev/null || true
  rm -f "$PREFIX/bin/aio" "$RUN_DIR/fakelicstls.py"
  ok "  revert selesai"
}

case "${1:-install}" in
  install|"")
    echo -e "${C_C}╔══════════════════════════════════════════════╗"
    echo -e "║  AIO-MOD PATCHER — Termux Native (aarch64)   ║"
    echo -e "╚══════════════════════════════════════════════╝${C_R}"
    patch_eddsa
    patch_cryptography
    patch_sitecustomize
    patch_apt_shim
    patch_sentinel
    patch_ca
    patch_engine
    patch_deps
    patch_dns
    patch_block_real
    patch_server
    patch_runner
    do_verify
    ;;
  verify) do_verify ;;
  revert) do_revert ;;
  *) echo "usage: $0 [install|verify|revert]"; exit 1 ;;
esac
