#!/usr/bin/env bash
# ============================================================
#  gnome-settings.sh — backup / restore ustawień GNOME
#  Użycie:
#    ./gnome-settings.sh backup   → na starym A1708 (Ubuntu/Fedora)
#    ./gnome-settings.sh restore  → na nowym A1466 (Silverblue)
# ============================================================

set -euo pipefail

BACKUP_DIR="${HOME}/.config/gnome-backup"
BACKUP_FILE="${BACKUP_DIR}/gnome-settings-$(date +%Y%m%d).ini"
EXTENSIONS_BACKUP="${BACKUP_DIR}/extensions-list.txt"
DCONF_DUMP="${BACKUP_DIR}/dconf-full.ini"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${BLUE}[--]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }

mkdir -p "$BACKUP_DIR"

# ── BACKUP (uruchom na A1708) ────────────────────────────────
do_backup() {
  info "Tworzę backup ustawień GNOME..."

  # Pełny dump dconf
  dconf dump / > "$DCONF_DUMP"
  log "dconf dump → $DCONF_DUMP"

  # Tylko kluczowe sekcje (bezpieczniejsze do transferu między distro)
  {
    echo "[interface]"
    dconf dump /org/gnome/desktop/interface/

    echo "[wm-preferences]"
    dconf dump /org/gnome/desktop/wm/preferences/

    echo "[peripherals-touchpad]"
    dconf dump /org/gnome/desktop/peripherals/touchpad/

    echo "[peripherals-keyboard]"
    dconf dump /org/gnome/desktop/peripherals/keyboard/

    echo "[shell]"
    dconf dump /org/gnome/shell/

    echo "[mutter]"
    dconf dump /org/gnome/mutter/

    echo "[power]"
    dconf dump /org/gnome/settings-daemon/plugins/power/

    echo "[night-light]"
    dconf dump /org/gnome/settings-daemon/plugins/color/

    echo "[terminal]"
    dconf dump /org/gnome/terminal/ 2>/dev/null || true

    echo "[nautilus]"
    dconf dump /org/gnome/nautilus/ 2>/dev/null || true
  } > "$BACKUP_FILE"
  log "Selektywny backup → $BACKUP_FILE"

  # Lista rozszerzeń GNOME
  if command -v gnome-extensions &>/dev/null; then
    gnome-extensions list --enabled > "$EXTENSIONS_BACKUP"
    log "Rozszerzenia → $EXTENSIONS_BACKUP"
    echo ""
    info "Aktywne rozszerzenia:"
    cat "$EXTENSIONS_BACKUP"
  fi

  # Motywy i ikony
  THEME_INFO="${BACKUP_DIR}/theme-info.txt"
  {
    echo "gtk-theme: $(gsettings get org.gnome.desktop.interface gtk-theme)"
    echo "icon-theme: $(gsettings get org.gnome.desktop.interface icon-theme)"
    echo "cursor-theme: $(gsettings get org.gnome.desktop.interface cursor-theme)"
    echo "color-scheme: $(gsettings get org.gnome.desktop.interface color-scheme)"
    echo "font-name: $(gsettings get org.gnome.desktop.interface font-name)"
    echo "monospace-font: $(gsettings get org.gnome.desktop.interface monospace-font-name)"
  } > "$THEME_INFO"
  log "Info o motywie → $THEME_INFO"

  echo ""
  echo "════════════════════════════════════════"
  echo " Backup gotowy w: $BACKUP_DIR"
  echo " Skopiuj cały folder na A1466:"
  echo ""
  echo "   scp -r $BACKUP_DIR user@a1466-ip:~/.config/gnome-backup"
  echo "   # lub przez pendrive / chmurę"
  echo "════════════════════════════════════════"
}

# ── RESTORE (uruchom na A1466 po post-install.sh) ────────────
do_restore() {
  info "Przywracam ustawienia GNOME..."

  # Szukaj pliku backup
  if [[ ! -d "$BACKUP_DIR" ]]; then
    warn "Brak folderu $BACKUP_DIR — skopiuj backup z A1708 najpierw"
    exit 1
  fi

  LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/gnome-settings-*.ini 2>/dev/null | head -1 || echo "")
  if [[ -z "$LATEST_BACKUP" ]]; then
    warn "Brak pliku backup — uruchom najpierw ./gnome-settings.sh backup na A1708"
    exit 1
  fi

  info "Używam: $LATEST_BACKUP"

  # ── Motyw ────────────────────────────────────────────────
  THEME_INFO="${BACKUP_DIR}/theme-info.txt"
  if [[ -f "$THEME_INFO" ]]; then
    info "Przywracam motyw..."
    while IFS=': ' read -r key value; do
      value=$(echo "$value" | tr -d "'" | xargs)
      case "$key" in
        gtk-theme)     gsettings set org.gnome.desktop.interface gtk-theme "$value" ;;
        icon-theme)    gsettings set org.gnome.desktop.interface icon-theme "$value" ;;
        cursor-theme)  gsettings set org.gnome.desktop.interface cursor-theme "$value" ;;
        color-scheme)  gsettings set org.gnome.desktop.interface color-scheme "$value" ;;
        font-name)     gsettings set org.gnome.desktop.interface font-name "$value" ;;
        monospace-font) gsettings set org.gnome.desktop.interface monospace-font-name "$value" ;;
      esac
    done < "$THEME_INFO"
    log "Motyw przywrócony"
  fi

  # ── Ustawienia GNOME (selektywnie, bez hardware-specific) ──
  info "Przywracam ustawienia interfejsu..."
  dconf load /org/gnome/desktop/wm/preferences/ < <(
    sed -n '/^\[wm-preferences\]/,/^\[/{ /^\[wm-preferences\]/d; /^\[/d; p }' "$LATEST_BACKUP"
  ) && log "WM preferences OK" || warn "WM preferences — pomiń"

  dconf load /org/gnome/mutter/ < <(
    sed -n '/^\[mutter\]/,/^\[/{ /^\[mutter\]/d; /^\[/d; p }' "$LATEST_BACKUP"
  ) && log "Mutter OK" || warn "Mutter — pomiń"

  dconf load /org/gnome/settings-daemon/plugins/color/ < <(
    sed -n '/^\[night-light\]/,/^\[/{ /^\[night-light\]/d; /^\[/d; p }' "$LATEST_BACKUP"
  ) && log "Night Light OK" || warn "Night Light — pomiń"

  dconf load /org/gnome/nautilus/ < <(
    sed -n '/^\[nautilus\]/,/^\[/{ /^\[nautilus\]/d; /^\[/d; p }' "$LATEST_BACKUP"
  ) && log "Nautilus OK" || warn "Nautilus — pomiń"

  # ── Rozszerzenia GNOME ────────────────────────────────────
  if [[ -f "$EXTENSIONS_BACKUP" ]]; then
    info "Lista rozszerzeń z A1708 (zainstaluj przez Extension Manager):"
    echo ""
    cat "$EXTENSIONS_BACKUP"
    echo ""
    warn "Rozszerzenia GNOME NIE są przenoszone automatycznie."
    warn "Zainstaluj je ręcznie przez: flatpak run com.mattjakeman.ExtensionManager"
    warn "Lub przez: https://extensions.gnome.org"
  fi

  echo ""
  log "Restore zakończony — przeloguj się lub uruchom: gnome-shell --replace &"
}

# ── Pokaż co jest w backupie ────────────────────────────────
do_info() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    warn "Brak backupu w $BACKUP_DIR"
    exit 1
  fi
  echo "Pliki backup:"
  ls -lh "$BACKUP_DIR/"
  echo ""
  if [[ -f "$BACKUP_DIR/theme-info.txt" ]]; then
    echo "Motyw:"
    cat "$BACKUP_DIR/theme-info.txt"
  fi
  if [[ -f "$EXTENSIONS_BACKUP" ]]; then
    echo ""
    echo "Rozszerzenia:"
    cat "$EXTENSIONS_BACKUP"
  fi
}

# ── Main ─────────────────────────────────────────────────────
case "${1:-help}" in
  backup)  do_backup ;;
  restore) do_restore ;;
  info)    do_info ;;
  *)
    echo "Użycie: $0 {backup|restore|info}"
    echo ""
    echo "  backup  → uruchom na A1708 żeby zapisać ustawienia"
    echo "  restore → uruchom na A1466 po post-install.sh"
    echo "  info    → pokaż zawartość backupu"
    ;;
esac
