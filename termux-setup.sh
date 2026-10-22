#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  CleanYourTV — Interactive Termux Setup
#  Tanpa LLM, jalan di Termux Android.
#  Langkah: cek deps → konek TV → backup → debloat → install launcher → tema
# =============================================================================
set -euo pipefail

# ── Warna ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${CYAN}→${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*"; }
hdr()  { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }
ask()  { echo -en "${BOLD}${YELLOW}?${RESET} $* "; }

# ── Confirm (y/n) ─────────────────────────────────────────────────────────────
confirm() {
  local msg="${1}" default="${2:-y}"
  local prompt; [ "$default" = "y" ] && prompt="[Y/n]" || prompt="[y/N]"
  ask "$msg $prompt: "
  read -r ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

# ── Direktori kerja ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$SCRIPT_DIR/tools"
BACKUP_DIR="$SCRIPT_DIR/backup"
mkdir -p "$BACKUP_DIR"

# ── Python helper ─────────────────────────────────────────────────────────────
PY=""
find_python() {
  for p in "$TOOLS/venv/bin/python" python3 python; do
    if command -v "$p" &>/dev/null 2>&1 || [ -x "$p" ]; then
      PY="$p"; return 0
    fi
  done
  return 1
}

tv() { TV_HOST="$TV_IP" "$PY" -I "$TOOLS/tv.py" "$@"; }
tv_batch() { TV_HOST="$TV_IP" "$PY" -I "$TOOLS/tv.py" --batch "$@"; }

# =============================================================================
#  LANGKAH 0 — Banner
# =============================================================================
clear
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║       CleanYourTV — Termux Setup      ║"
echo "  ║  Debloat + Launcher + Tema otomatis   ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"
echo "Script ini akan:"
echo "  1. Cek & install dependensi (Python, adb-shell)"
echo "  2. Konek ke TV lewat ADB over Wi-Fi"
echo "  3. Backup daftar paket TV"
echo "  4. Disable bloatware"
echo "  5. Install launcher CleanYourTV"
echo "  6. Pasang tema pilihan"
echo ""
confirm "Lanjut?" y || { echo "Dibatalkan."; exit 0; }

# =============================================================================
#  LANGKAH 1 — Cek dependensi
# =============================================================================
hdr "Langkah 1: Cek dependensi"

# pkg Termux
MISSING_PKG=()
for p in python wget curl; do
  command -v "$p" &>/dev/null || MISSING_PKG+=("$p")
done

if [ ${#MISSING_PKG[@]} -gt 0 ]; then
  warn "Paket belum ada: ${MISSING_PKG[*]}"
  info "Install via pkg..."
  pkg install -y "${MISSING_PKG[@]}"
fi
ok "Paket sistem OK"

# Python venv + adb-shell
if [ ! -x "$TOOLS/venv/bin/python" ]; then
  info "Buat Python venv di tools/venv ..."
  python3 -m venv "$TOOLS/venv"
  "$TOOLS/venv/bin/pip" install --quiet -r "$TOOLS/requirements.txt"
  ok "Python venv & adb-shell terinstall"
else
  ok "Python venv sudah ada"
fi
find_python || { err "Python tidak ditemukan"; exit 1; }
ok "Python: $PY"

# ADB key — kalau belum ada, generate
ADBKEY_DIR="$TOOLS/adbkey"
mkdir -p "$ADBKEY_DIR"
if [ ! -f "$ADBKEY_DIR/adbkey" ]; then
  info "Generate ADB key baru..."
  "$PY" -I -c "
import os, sys
sys.path.insert(0, '$TOOLS')
from adb_shell.auth.sign_pythonrsa import PythonRSASigner
from adb_shell.auth.keygen import keygen
keygen('$ADBKEY_DIR/adbkey')
print('ADB key generated')
"
  ok "ADB key dibuat di $ADBKEY_DIR/"
else
  ok "ADB key sudah ada"
fi

# =============================================================================
#  LANGKAH 2 — IP TV
# =============================================================================
hdr "Langkah 2: Koneksi ke TV"
echo ""
echo "Pastikan TV dan HP kamu di Wi-Fi yang sama."
echo "Cek IP TV di: Settings → Network → (lihat IP) atau router kamu."
echo ""

while true; do
  ask "Masukkan IP TV (contoh: 192.168.1.50): "
  read -r TV_IP
  TV_IP="${TV_IP// /}"  # hapus spasi
  if [[ "$TV_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    break
  else
    err "Format IP tidak valid, coba lagi."
  fi
done

# Fungsi: tampilkan panduan aktifkan USB debugging
show_usb_debug_guide() {
  echo ""
  echo -e "  ${BOLD}Cara aktifkan USB Debugging di TV:${RESET}"
  echo ""
  echo -e "  ${CYAN}Android TV / Google TV:${RESET}"
  echo "  1. Settings → Device Preferences → About"
  echo "  2. Arahkan ke 'Build' → tekan OK sebanyak 7x"
  echo "     sampai muncul 'You are now a developer!'"
  echo "  3. Kembali → Developer options"
  echo "  4. Aktifkan 'USB debugging'"
  echo "  5. Aktifkan 'Network debugging' atau 'ADB debugging' (kalau ada)"
  echo ""
  echo -e "  ${CYAN}Xiaomi Mi TV / Redmi TV:${RESET}"
  echo "  1. Settings → Device Preferences → About"
  echo "  2. Tekan OK pada 'Build' 7x"
  echo "  3. Developer options → USB Debugging ON"
  echo "     + ADB Debugging / Network Debugging ON"
  echo ""
  echo -e "  ${YELLOW}Tips:${RESET} Setelah aktif, pastikan TV tidak sleep."
  echo "  Kalau TV sleep, ADB bisa terputus."
  echo ""
}

# Cek port 5555 dengan retry loop + countdown
check_port() {
  (echo >/dev/tcp/"$TV_IP"/5555) 2>/dev/null
}

info "Cek port ADB ($TV_IP:5555)..."
if ! check_port; then
  echo ""
  warn "Port 5555 tertutup — USB Debugging belum aktif atau TV belum siap."
  show_usb_debug_guide

  # Loop: cek otomatis tiap 5 detik, max 12x (1 menit)
  MAX_RETRY=12
  RETRY=0
  PORT_OPEN=0
  echo -e "  ${CYAN}Menunggu USB Debugging aktif... (otomatis cek tiap 5 detik)${RESET}"
  echo -e "  Tekan ${BOLD}Ctrl+C${RESET} untuk batalkan."
  echo ""
  while [ $RETRY -lt $MAX_RETRY ]; do
    RETRY=$((RETRY + 1))
    SISA=$((MAX_RETRY - RETRY))
    echo -ne "  Percobaan $RETRY/$MAX_RETRY — cek port 5555... "
    if check_port; then
      echo -e "${GREEN}TERBUKA!${RESET}"
      PORT_OPEN=1
      break
    else
      echo -e "${RED}tertutup${RESET} (coba lagi dalam 5 detik, sisa $SISA percobaan)"
      sleep 5
    fi
  done

  if [ "$PORT_OPEN" = "0" ]; then
    echo ""
    err "Port 5555 masih tertutup setelah 1 menit."
    echo ""
    echo "  Kemungkinan penyebab:"
    echo "  - USB Debugging belum diaktifkan di TV"
    echo "  - TV dan HP beda Wi-Fi / jaringan"
    echo "  - IP TV salah (cek lagi di Settings → Network)"
    echo "  - TV dalam mode sleep"
    echo ""
    confirm "Mau coba lagi dari awal?" n && exec bash "$0" || exit 1
  fi
fi
ok "Port 5555 terbuka"

# Konek ADB
info "Konek ADB ke $TV_IP..."
echo ""
echo -e "  ${YELLOW}⚠ Di TV akan muncul popup 'Allow USB debugging?'${RESET}"
echo "    → Pilih 'Always allow from this device'"
echo "    → Tekan OK"
echo ""
ask "Tekan Enter setelah popup muncul di TV (atau sudah pernah allow sebelumnya)..."
read -r

# Coba konek, retry 3x (kadang butuh beberapa detik setelah allow)
CONN_OK=0
for i in 1 2 3; do
  echo -ne "  Konek ADB percobaan $i/3... "
  if TV_HOST="$TV_IP" "$PY" -I "$TOOLS/tv.py" "echo connected" 2>/dev/null | grep -q "connected"; then
    echo -e "${GREEN}OK${RESET}"
    CONN_OK=1
    break
  else
    echo -e "${RED}gagal${RESET}"
    [ $i -lt 3 ] && sleep 3
  fi
done

if [ "$CONN_OK" = "0" ]; then
  echo ""
  err "Gagal konek ke ADB."
  echo ""
  echo "  Cek:"
  echo "  - Sudah klik 'Allow' di popup TV?"
  echo "  - USB Debugging masih aktif?"
  echo "  - IP TV benar? ($TV_IP)"
  echo ""
  confirm "Mau coba lagi?" y && {
    ask "Tekan Enter setelah siap..."
    read -r
    if TV_HOST="$TV_IP" "$PY" -I "$TOOLS/tv.py" "echo connected" 2>/dev/null | grep -q "connected"; then
      CONN_OK=1
    fi
  }
  [ "$CONN_OK" = "0" ] && { err "Masih gagal. Keluar."; exit 1; }
fi
ok "ADB tersambung ke $TV_IP"

# =============================================================================
#  LANGKAH 3 — Probe TV
# =============================================================================
hdr "Langkah 3: Deteksi TV"

MODEL=$(tv "getprop ro.product.model" 2>/dev/null | tr -d '\r' || echo "unknown")
BRAND=$(tv "getprop ro.product.brand" 2>/dev/null | tr -d '\r' || echo "unknown")
ANDROID=$(tv "getprop ro.build.version.release" 2>/dev/null | tr -d '\r' || echo "unknown")
SDK=$(tv "getprop ro.build.version.sdk" 2>/dev/null | tr -d '\r' || echo "0")
FIRMWARE=$(tv "getprop ro.build.display.id" 2>/dev/null | tr -d '\r' || echo "unknown")

echo ""
echo "  Brand   : $BRAND"
echo "  Model   : $MODEL"
echo "  Android : $ANDROID (SDK $SDK)"
echo "  Firmware: $FIRMWARE"
echo ""

# Cek SDK minimum (launcher perlu SDK 26 / Android 8.0)
if [ "$SDK" -lt 26 ] 2>/dev/null; then
  err "Android $ANDROID (SDK $SDK) terlalu lama. Launcher butuh minimal Android 8.0 (SDK 26)."
  warn "Debloat masih bisa dilanjut, tapi launcher tidak bisa diinstall."
  SKIP_LAUNCHER=1
else
  SKIP_LAUNCHER=0
fi

# =============================================================================
#  LANGKAH 4 — Backup
# =============================================================================
hdr "Langkah 4: Backup"

TS=$(date +%Y%m%d-%H%M%S)
BFILE="$BACKUP_DIR/${BRAND}-${MODEL}-${TS}.txt"

info "Simpan daftar paket ke $BFILE ..."
{
  echo "# CleanYourTV backup — $BRAND $MODEL — Android $ANDROID — $FIRMWARE"
  echo "# Tanggal: $(date)"
  echo "# TV: $TV_IP"
  echo ""
  echo "## Semua paket:"
  tv "pm list packages" 2>/dev/null
  echo ""
  echo "## Paket disabled:"
  tv "pm list packages -d" 2>/dev/null
} > "$BFILE"
ok "Backup disimpan: $BFILE"

# =============================================================================
#  LANGKAH 5 — Debloat
# =============================================================================
hdr "Langkah 5: Debloat"

# Deteksi paket yang bisa dimatikan
info "Scan paket di TV..."

# Ambil semua paket
ALL_PKGS=$(tv "pm list packages" 2>/dev/null | sed 's/^package://')

# Daftar kandidat berdasarkan brand
declare -A PKG_DESC=(
  # Xiaomi / Patchwall
  ["com.mitv.tvhome.mitvplus"]="Patchwall home screen (sering update, bikin berat)"
  ["com.mitv.tvhome.atv"]="Patchwall ATV launcher"
  ["com.miui.tv.analytics"]="Analytics MIUI TV"
  ["com.xiaomi.statistic"]="Telemetri Xiaomi"
  ["com.xiaomi.mitv.updateservice"]="Update service Patchwall"
  ["com.mitv.milinkservice"]="MiLink service"
  ["com.xiaomi.floatingframe"]="Floating frame / iklan Xiaomi"
  ["com.xm.webcontent"]="Web content / iklan Xiaomi"
  ["com.xiaomi.mitv.handbook"]="Panduan TV Xiaomi"
  ["com.xiaomi.mimusic2"]="Mi Music"
  # Google TV bloat
  ["com.google.android.tvrecommendations"]="Google TV recommendations row"
  ["com.google.android.leanbacklauncher.recommendations"]="Leanback recommendations"
  ["com.google.android.katniss"]="Google voice assistant (TV)"
  ["com.google.android.speech.pumpkin"]="Google speech model"
  # Umum
  ["com.amazon.amazonvideo.livingroom"]="Amazon Prime Video (preinstall)"
  ["com.netflix.ninja"]="Netflix (preinstall, bisa diinstall ulang dari store)"
  ["com.android.gallery3d"]="Gallery bawaan"
  ["com.google.android.videos"]="Google Play Movies"
  ["com.google.android.play.games"]="Google Play Games"
  ["com.google.android.youtube.tvmusic"]="YouTube Music TV"
)

# Filter: hanya yang ada di TV ini
CANDIDATES=()
for pkg in "${!PKG_DESC[@]}"; do
  if echo "$ALL_PKGS" | grep -qx "$pkg"; then
    CANDIDATES+=("$pkg")
  fi
done

# Cek examples/ untuk TV ini (kalau ada)
EXAMPLE_LIST=""
BRAND_LOWER=$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')
MODEL_LOWER=$(echo "$MODEL" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
for d in "$SCRIPT_DIR/examples/"*; do
  dname=$(basename "$d" | tr '[:upper:]' '[:lower:]')
  if [[ "$dname" == *"$BRAND_LOWER"* ]] || [[ "$dname" == *"$MODEL_LOWER"* ]]; then
    if [ -f "$d/debloat.txt" ]; then
      EXAMPLE_LIST="$d/debloat.txt"
      ok "Ketemu list untuk TV ini: $d/debloat.txt"
      break
    fi
  fi
done

if [ -n "$EXAMPLE_LIST" ]; then
  echo ""
  echo "  TV kamu ada di database. Mau pakai list yang sudah teruji?"
  confirm "Pakai list dari examples/ ?" y && USE_EXAMPLE=1 || USE_EXAMPLE=0
else
  USE_EXAMPLE=0
fi

DISABLED_LIST=()

if [ "$USE_EXAMPLE" = "1" ] && [ -n "$EXAMPLE_LIST" ]; then
  # Pakai list dari examples/
  info "Pakai list: $EXAMPLE_LIST"
  TV_HOST="$TV_IP" bash "$TOOLS/disable.sh" "$EXAMPLE_LIST"
  ok "Debloat dari list selesai"
else
  # Interaktif per paket
  if [ ${#CANDIDATES[@]} -eq 0 ]; then
    warn "Tidak ada paket bloatware umum yang ditemukan di TV ini."
  else
    echo ""
    echo "Paket berikut ditemukan di TV kamu."
    echo "Pilih mana yang mau dimatikan (bisa di-restore kapan saja):"
    echo ""

    for pkg in "${CANDIDATES[@]}"; do
      desc="${PKG_DESC[$pkg]:-}"
      echo -e "  ${BOLD}$pkg${RESET}"
      [ -n "$desc" ] && echo "  └─ $desc"
      confirm "  Matikan?" y && DISABLED_LIST+=("$pkg")
      echo ""
    done
  fi

  # Tambah paket manual
  echo ""
  confirm "Mau matikan paket lain secara manual?" n && {
    echo "Masukkan nama paket satu per baris, kosongkan untuk selesai:"
    while true; do
      ask "Paket: "
      read -r extra_pkg
      [ -z "$extra_pkg" ] && break
      if echo "$ALL_PKGS" | grep -qx "$extra_pkg"; then
        DISABLED_LIST+=("$extra_pkg")
        ok "Ditambahkan: $extra_pkg"
      else
        err "Paket tidak ditemukan di TV: $extra_pkg"
      fi
    done
  }

  # Eksekusi disable
  if [ ${#DISABLED_LIST[@]} -gt 0 ]; then
    echo ""
    info "Akan mematikan ${#DISABLED_LIST[@]} paket:"
    for p in "${DISABLED_LIST[@]}"; do echo "    - $p"; done
    echo ""
    confirm "Lanjut?" y && {
      for pkg in "${DISABLED_LIST[@]}"; do
        result=$(tv "pm disable-user --user 0 $pkg" 2>/dev/null || echo "failed")
        if echo "$result" | grep -q "disabled"; then
          ok "$pkg → disabled"
        else
          err "$pkg → gagal ($result)"
        fi
      done
    }
  else
    info "Tidak ada paket yang dipilih untuk dimatikan."
  fi
fi

# =============================================================================
#  LANGKAH 6 — Install launcher
# =============================================================================
hdr "Langkah 6: Install Launcher CleanYourTV"

if [ "$SKIP_LAUNCHER" = "1" ]; then
  warn "Skip: Android terlalu lama untuk launcher ini."
else
  # Cek apakah sudah terinstall
  if tv "pm list packages" 2>/dev/null | grep -q "com.gathin.tvhome"; then
    ok "Launcher sudah terinstall di TV."
    LAUNCHER_INSTALLED=1
  else
    LAUNCHER_INSTALLED=0
  fi

  if [ "$LAUNCHER_INSTALLED" = "0" ]; then
    # Cari APK — build lokal atau download
    APK_PATH="$SCRIPT_DIR/launcher/app/build/outputs/apk/release/app-release.apk"

    # Cek APK di root repo dulu (pre-built yang disertakan)
    REPO_APK="$SCRIPT_DIR/app-release.apk"
    if [ -f "$REPO_APK" ]; then
      APK_PATH="$REPO_APK"
      ok "Pakai APK dari repo: $APK_PATH"
    elif [ ! -f "$APK_PATH" ]; then
      echo ""
      info "APK belum ada. Coba download dari repo..."
      APK_URL="https://raw.githubusercontent.com/azhnan-dev/cleanyourtv/main/app-release.apk"
      APK_PATH="$SCRIPT_DIR/app-release.apk"
      if wget -q --show-progress -O "$APK_PATH" "$APK_URL" 2>/dev/null; then
        ok "APK berhasil didownload: $APK_PATH"
      else
        err "Download gagal. Copy APK ke folder repo:"
        echo "    $SCRIPT_DIR/app-release.apk"
        echo ""
        ask "Path APK (kosongkan untuk skip): "
        read -r custom_apk
        if [ -n "$custom_apk" ] && [ -f "$custom_apk" ]; then
          APK_PATH="$custom_apk"
        else
          warn "Skip install launcher."
          SKIP_LAUNCHER=1
        fi
      fi
    fi

    if [ "$SKIP_LAUNCHER" = "0" ] && [ -f "$APK_PATH" ]; then
      info "Upload & install APK ke TV..."
      TV_HOST="$TV_IP" "$PY" -I "$TOOLS/b64push.py" "$APK_PATH" /data/local/tmp/tvhome.apk

      install_result=$(tv "pm install -r /data/local/tmp/tvhome.apk; rm -f /data/local/tmp/tvhome.apk" 2>/dev/null)
      if echo "$install_result" | grep -q "Success"; then
        ok "APK terinstall"
      else
        err "Install gagal: $install_result"
        SKIP_LAUNCHER=1
      fi
    fi
  fi

  if [ "$SKIP_LAUNCHER" = "0" ]; then
    # Set sebagai Home
    info "Set CleanYourTV sebagai Home..."
    tv "cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity" >/dev/null 2>&1 || true

    # Start launcher
    start_result=$(tv "am start -W -n com.gathin.tvhome/.MainActivity" 2>/dev/null || echo "")
    if echo "$start_result" | grep -q "Status: ok"; then
      ok "Launcher berjalan"
    else
      warn "Launcher mungkin belum jalan. Coba tekan Home di remote."
    fi

    # Disable stock launcher
    HOME_PKG=$(tv "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" 2>/dev/null | tail -n 1 | tr -d '\r' | cut -d'/' -f1 || echo "")
    STOCK_LAUNCHERS=("com.google.android.tvlauncher" "com.google.android.apps.tv.launcherx" "com.google.android.leanbacklauncher" "com.mitv.tvhome")

    for stock in "${STOCK_LAUNCHERS[@]}"; do
      if tv "pm list packages" 2>/dev/null | grep -q "^package:$stock$"; then
        if [ "$HOME_PKG" != "com.gathin.tvhome" ] && confirm "Matikan stock launcher ($stock)?" y; then
          tv "pm disable-user --user 0 $stock" >/dev/null 2>&1 && ok "$stock dimatikan" || warn "Gagal matikan $stock"
        fi
      fi
    done

    ok "Launcher CleanYourTV aktif sebagai Home"
  fi
fi

# =============================================================================
#  LANGKAH 7 — Tema
# =============================================================================
hdr "Langkah 7: Pilih Tema"

if [ "$SKIP_LAUNCHER" = "1" ]; then
  warn "Skip tema: launcher tidak terinstall."
else
  # Daftar tema yang tersedia
  THEMES=()
  THEMES_DESC=(
    ["aurora"]="Wallpaper dinamis + tinted pills (recommended)"
    ["default"]="Tema bawaan launcher"
    ["glass"]="Tampilan kaca/transparan"
    ["six-columns"]="6 kolom + 6-app dock"
    ["dussehra"]="Tema festival"
    ["scenes"]="Wallpaper scenes"
  )

  echo ""
  echo "Tema yang tersedia:"
  i=1
  THEME_NAMES=()
  for d in "$SCRIPT_DIR/themes/"*/; do
    name=$(basename "$d")
    [ -f "$d/config.json" ] || continue
    desc="${THEMES_DESC[$name]:-}"
    echo "  $i) $name${desc:+ — $desc}"
    THEME_NAMES+=("$name")
    ((i++))
  done
  echo "  0) Skip (tidak pakai tema)"
  echo ""

  while true; do
    ask "Pilih nomor tema [0-$((i-1))]: "
    read -r choice
    if [ "$choice" = "0" ]; then
      info "Skip tema."
      break
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
      THEME_NAME="${THEME_NAMES[$((choice-1))]}"
      THEME_DIR="$SCRIPT_DIR/themes/$THEME_NAME"

      info "Pasang tema: $THEME_NAME ..."
      if TV_HOST="$TV_IP" bash "$TOOLS/theme.sh" "$THEME_DIR"; then
        ok "Tema $THEME_NAME berhasil dipasang!"
      else
        err "Gagal pasang tema. Coba lagi nanti dengan:"
        echo "    TV_HOST=$TV_IP tools/theme.sh themes/$THEME_NAME"
      fi
      break
    else
      err "Pilihan tidak valid."
    fi
  done
fi

# =============================================================================
#  SELESAI
# =============================================================================
hdr "Selesai!"
echo ""
echo "  TV   : $BRAND $MODEL"
echo "  IP   : $TV_IP"
echo "  Backup: $BFILE"
echo ""
echo "  Untuk restore ke kondisi semula:"
echo "    TV_HOST=$TV_IP bash tools/restore.sh <list-yang-dipakai>"
echo ""
echo "  Untuk reset tema:"
echo "    TV_HOST=$TV_IP bash tools/theme.sh --reset"
echo ""

# Sarankan tutup ADB
if confirm "Tutup koneksi ADB sekarang? (disarankan)" y; then
  tv "settings put global development_settings_enabled 0" 2>/dev/null || true
  ok "ADB debugging dimatikan di TV."
  info "Reboot TV untuk pastikan port 5555 tertutup."
fi

echo ""
ok "Selesai! Tekan Home di remote untuk lihat launcher baru."
echo ""
