#!/bin/bash
# MacBook Air A1466 (MacBookAir7,2) — Fedora Silverblue Installer
# Tested on Fedora Silverblue 42
# https://github.com/maciejmiller/mbp-a1708-ubuntu (styl wzorowany)

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────
LOGFILE="/var/log/mba-a1466-install.log"
RESULTS=()

log()    { printf '%s\n' "$(date '+%H:%M:%S') $*" | tee -a "$LOGFILE" > /dev/null; }
info()   { echo -e "${CYAN} →${NC} $*"; log "INFO: $*"; }
ok()     { echo -e "${GREEN} ✓${NC} $*"; log "OK: $*"; }
warn()   { echo -e "${YELLOW} ⚠${NC} $*"; log "WARN: $*"; }
fail()   { echo -e "${RED} ✗${NC} $*"; log "FAIL: $*"; }
header() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

result_ok()   { RESULTS+=("${GREEN}✓${NC} $*"); }
result_skip() { RESULTS+=("${YELLOW}–${NC} $*"); }
result_fail() { RESULTS+=("${RED}✗${NC} $*"); }

# ─── Helpers ──────────────────────────────────────────────────────────────────
ask() {
    local prompt="$1"
    local answer
    echo -e "\n${BOLD}$prompt${NC} [T/n] \c"
    read -r answer
    [[ "${answer,,}" != "n" ]]
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Uruchom jako root: sudo bash $0${NC}"
        exit 1
    fi
}

check_model() {
    local model
    model=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || \
            cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || \
            system_profiler SPHardwareDataType 2>/dev/null | grep "Model Identifier" | awk '{print $NF}' || \
            echo "")

    if [[ "$model" != "MacBookAir7,2" ]]; then
        echo -e "${RED}Ten skrypt jest przeznaczony dla MacBookAir7,2 (A1466 Early 2015).${NC}"
        echo -e "Wykryty model: ${BOLD}${model:-nieznany}${NC}"
        echo -e "${YELLOW}Kontynuować mimo to?${NC} [t/N] \c"
        read -r answer
        [[ "${answer,,}" == "t" ]] || exit 1
        warn "Kontynuowanie na nieobsługiwanym modelu: $model"
    else
        ok "Wykryto model: MacBookAir7,2 (A1466)"
    fi
}

check_silverblue() {
    if ! command -v rpm-ostree &>/dev/null; then
        echo -e "${RED}Ten skrypt wymaga Fedora Silverblue (rpm-ostree).${NC}"
        exit 1
    fi
    ok "Fedora Silverblue wykryta"
    local deployment
    deployment=$(rpm-ostree status --json 2>/dev/null | python3 -c \
        "import json,sys; d=json.load(sys.stdin)['deployments'][0]; print(d.get('version','?'))" 2>/dev/null || echo "?")
    info "Deployment: $deployment"
}

# ─── Modules ──────────────────────────────────────────────────────────────────

module_kargs() {
    header "Kernel Parameters (rpm-ostree kargs)"

    local current
    current=$(rpm-ostree kargs 2>/dev/null || echo "")
    info "Aktualne kargs: $current"

    # Parametry dla MacBook Air A1466 / Broadwell
    # hid_apple.fnmode=1      → F1-F12 bez Fn
    # hid_apple.iso_layout=0  → poprawny układ polskiej klawiatury
    # acpi_osi=Darwin         → ACPI jak w macOS → backlight + energia działa
    # pcie_ports=compat       → stabilność NVMe Apple PCIe
    # acpi_backlight=native   → jasność przez /sys/class/backlight
    # mem_sleep_default=s2idle → stabilny suspend
    # i915.enable_dc=1        → oszczędzanie energii GPU (Broadwell OK)
    declare -A KARGS=(
        ["hid_apple.fnmode=1"]="Fn keys jako F1-F12 domyślnie"
        ["hid_apple.iso_layout=0"]="Układ klawiatury non-ISO"
        ["acpi_osi=Darwin"]="ACPI tryb macOS (backlight, energia)"
        ["pcie_ports=compat"]="Stabilność PCIe / NVMe Apple"
        ["acpi_backlight=native"]="Jasność ekranu przez sysfs"
        ["mem_sleep_default=s2idle"]="Suspend s2idle"
        ["i915.enable_dc=1"]="Intel GPU power saving (Broadwell)"
        ["quiet"]="Cichy boot"
        ["splash"]="Splash screen"
    )

    local added=0 skipped=0 failed=0
    for karg in "${!KARGS[@]}"; do
        if echo "$current" | grep -q "${karg%%=*}"; then
            info "Już ustawiony: $karg"
            (( skipped++ )) || true
        else
            if rpm-ostree kargs --append="$karg" >> "$LOGFILE" 2>&1; then
                ok "Dodano: $karg — ${KARGS[$karg]}"
                (( added++ )) || true
            else
                fail "Błąd: $karg"
                (( failed++ )) || true
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        ok "Kernel params: $added dodanych, $skipped już było"
        result_ok "Kernel params — wymagany restart"
    else
        warn "Kernel params: $failed błędów"
        result_fail "Kernel params — sprawdź log"
    fi
}

module_overlay() {
    header "RPM Fusion + Overlay (broadcom-wl, multimedia, energia)"

    # Na Silverblue: pakiety systemowe przez rpm-ostree install
    # Minimalna lista — reszta przez Flatpak
    local fedora_ver
    fedora_ver=$(rpm -E %fedora)

    info "Fedora: $fedora_ver"

    # Sprawdź czy RPM Fusion już dodane
    if ! rpm-ostree status | grep -q "rpmfusion"; then
        info "Dodawanie RPM Fusion repos..."
        rpm-ostree install --idempotent \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm" \
            >> "$LOGFILE" 2>&1 || warn "RPM Fusion — sprawdź ręcznie po restarcie"
    else
        ok "RPM Fusion już skonfigurowane"
    fi

    local OVERLAY_PKGS=(
        # Wi-Fi — Broadcom BCM4360 (A1466 używa BCM4360, nie BCM4350!)
        # brcmfmac NIE obsługuje BCM4360 w kernel 6.x — potrzebny broadcom-wl
        "broadcom-wl"

        # Firmware
        "linux-firmware"

        # Intel GPU / VA-API (Broadwell HD 6000)
        "intel-media-driver"
        "libva-intel-driver"
        "libva-utils"

        # Zarządzanie energią
        "powertop"
        "tlp"
        "tlp-rdw"

        # Bluetooth
        "bluez"
        "bluez-tools"

        # Podświetlenie klawiatury / jasność
        "light"

        # Ikony (lepiej jako overlay niż Flatpak)
        "papirus-icon-theme"
    )

    info "Instalowanie overlay packages..."
    if rpm-ostree install --idempotent "${OVERLAY_PKGS[@]}" >> "$LOGFILE" 2>&1; then
        ok "Overlay zaplanowany"
        result_ok "RPM overlay — wymagany restart"
    else
        fail "Błąd podczas instalacji overlay"
        result_fail "RPM overlay — sprawdź log"
    fi
}

module_wifi_check() {
    header "Wi-Fi — Broadcom BCM4360"

    # A1466 (2015) ma BCM4360 — ważna różnica vs A1708 (BCM4350)
    # BCM4360 NIE jest obsługiwany przez brcmfmac w mainline kernel
    # Jedyna opcja: broadcom-wl (wl kernel module) z RPM Fusion nonfree

    local pci_id
    pci_id=$(lspci -nn 2>/dev/null | grep -i broadcom | head -1 || echo "brak PCI")
    info "Broadcom PCI: $pci_id"

    if lsmod | grep -q '^wl'; then
        ok "Moduł wl (broadcom-wl) załadowany — Wi-Fi powinno działać"
        result_ok "Wi-Fi (wl) — aktywny"
    elif lsmod | grep -q '^brcmfmac'; then
        warn "brcmfmac załadowany — BCM4360 NIE jest obsługiwany przez brcmfmac"
        warn "Wi-Fi może nie działać. Zainstaluj broadcom-wl z RPM Fusion (moduł overlay)"
        result_fail "Wi-Fi — brcmfmac nie obsługuje BCM4360, potrzebny broadcom-wl"
    else
        warn "Żaden moduł Wi-Fi nie załadowany"
        info "Po restarcie (po overlay) uruchom: sudo modprobe wl"
        info "Trwałe ładowanie: echo 'wl' | sudo tee /etc/modules-load.d/broadcom-wl.conf"

        # Utwórz plik modules-load już teraz (zadziała po restarcie)
        echo 'wl' > /etc/modules-load.d/broadcom-wl.conf
        ok "Utworzono /etc/modules-load.d/broadcom-wl.conf"
        result_ok "Wi-Fi — broadcom-wl zaplanowany (aktywny po restarcie)"
    fi

    # Blacklist brcmfmac/brcmutil — konflikty z wl
    cat > /etc/modprobe.d/blacklist-broadcom.conf << 'EOF'
# MacBook Air A1466 — BCM4360 wymaga broadcom-wl (wl), nie brcmfmac
blacklist brcmfmac
blacklist brcmutil
blacklist b43
blacklist b43legacy
blacklist ssb
blacklist bcma
EOF
    ok "Blacklist brcmfmac/brcmutil ustawiony"
}

module_suspend() {
    header "Suspend Stack (s2idle)"

    # Sleep hook — unload/reload wl wokół suspend (podobnie jak brcmfmac na A1708)
    info "Instalowanie mba-a1466-sleep.sh..."

    cat > /usr/lib/systemd/system-sleep/mba-a1466-sleep.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/mba-a1466-suspend.log"
WIFI_STORE="/tmp/wifi-connection-backup"

log() { printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE" >/dev/null; }

pre_suspend() {
    log "PRE: suspend start"
    sync

    # Zapisz aktywne połączenie Wi-Fi
    nmcli connection show --active 2>/dev/null | grep wifi > "$WIFI_STORE" || true

    # Wyłącz Wi-Fi przed suspend
    nmcli radio wifi off 2>/dev/null || true
    rfkill block wifi 2>/dev/null || true
    sleep 1

    # Usuń moduł wl
    modprobe -r wl 2>/dev/null || true
    sleep 1

    if lsmod | grep -q '^wl'; then
        log "PRE: ERROR — wl still loaded, aborting unload"
        rfkill unblock wifi 2>/dev/null || true
        nmcli radio wifi on 2>/dev/null || true
    else
        log "PRE: wl unloaded OK"
    fi

    log "PRE: done"
}

post_resume() {
    log "POST: resume start"

    # Załaduj wl z powrotem
    modprobe wl 2>/dev/null || true
    sleep 2

    rfkill unblock wifi 2>/dev/null || true
    nmcli radio wifi on 2>/dev/null || true
    sleep 1

    # Przywróć połączenie
    if [[ -f "$WIFI_STORE" ]]; then
        local conn
        conn=$(cut -d' ' -f1 "$WIFI_STORE")
        nmcli connection up id "$conn" 2>/dev/null || true
        rm -f "$WIFI_STORE"
    fi

    # Odśwież backlight (czasem ginie po wake)
    local bl="/sys/class/backlight/intel_backlight"
    if [[ -d "$bl" ]]; then
        local max
        max=$(cat "$bl/max_brightness" 2>/dev/null || echo 200)
        echo "$((max / 2))" > "$bl/brightness" 2>/dev/null || true
    fi

    log "POST: done"
}

case "$1/$2" in
    pre/suspend)  pre_suspend ;;
    post/suspend) post_resume ;;
    *)            exit 0 ;;
esac
EOF

    chmod 755 /usr/lib/systemd/system-sleep/mba-a1466-sleep.sh
    ok "Sleep hook zainstalowany"

    # Lid switch
    info "Konfigurowanie lid switch..."
    sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
    sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
    ok "Lid switch → suspend"

    # Weryfikacja s2idle w kargs (powinien być ustawiony z module_kargs)
    local kargs
    kargs=$(rpm-ostree kargs 2>/dev/null || cat /proc/cmdline)
    if echo "$kargs" | grep -q "s2idle"; then
        ok "s2idle karg potwierdzony"
        result_ok "Suspend stack — aktywny po restarcie"
    else
        warn "s2idle nie znaleziony w kargs — uruchom module_kargs"
        result_fail "Suspend — brak s2idle karg"
    fi
}

module_gnome() {
    header "GNOME — ustawienia (A1466 optimized)"

    # Touchpad
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    gsettings set org.gnome.desktop.peripherals.touchpad speed 0.2
    ok "Touchpad OK"

    # Klawiatura
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'pl')]"
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:escape']"
    ok "Klawiatura OK"

    # Energia
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 1800
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 600
    gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'suspend'
    gsettings set org.gnome.desktop.session idle-delay 300
    ok "Energia OK"

    # GNOME Shell
    gsettings set org.gnome.mutter dynamic-workspaces true
    gsettings set org.gnome.mutter center-new-windows true
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
    gsettings set org.gnome.shell.overrides workspaces-only-on-primary false
    ok "GNOME Shell OK"

    # Czcionki
    gsettings set org.gnome.desktop.interface font-name 'Inter 11'
    gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11'
    gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
    gsettings set org.gnome.desktop.interface font-hinting 'slight'
    ok "Czcionki OK"

    # Night Light
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700
    ok "Night Light OK"

    result_ok "GNOME — ustawienia zastosowane"
}

module_theme() {
    header "Motyw — Adwaita Dark + Papirus"

    # Color scheme
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
    ok "Motyw ustawiony"

    # adw-gtk3 przez Flatpak
    info "Instalowanie adw-gtk3 theme (Flatpak)..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOGFILE" 2>&1 || true
    flatpak install -y flathub \
        org.gtk.Gtk3theme.adw-gtk3 \
        org.gtk.Gtk3theme.adw-gtk3-dark \
        >> "$LOGFILE" 2>&1 \
        && ok "adw-gtk3 Flatpak zainstalowany" \
        || warn "adw-gtk3 — sprawdź ręcznie"

    # Flatpak override — motyw dla wszystkich aplikacji Flatpak
    flatpak override --gtk-theme=adw-gtk3-dark >> "$LOGFILE" 2>&1 && ok "Flatpak GTK override OK" || true
    flatpak override --icon-theme=Papirus-Dark >> "$LOGFILE" 2>&1 && ok "Flatpak icon override OK" || true

    result_ok "Motyw — Adwaita Dark + Papirus"
}

module_fonts() {
    header "Czcionki — Inter + JetBrains Mono"

    # Inter i JetBrains Mono muszą być zainstalowane PRZED module_gnome,
    # inaczej gsettings ustawi czcionkę której nie ma i GNOME zignoruje
    local font_dir="${HOME}/.local/share/fonts"
    mkdir -p "$font_dir"

    local inter_ok=0 jbmono_ok=0

    # ── Inter ────────────────────────────────────────────────────────────────
    if fc-list | grep -qi "Inter"; then
        ok "Inter już zainstalowany"
        inter_ok=1
    else
        info "Pobieranie Inter (latest release)..."
        local tmpdir
        tmpdir=$(mktemp -d)

        # Pobierz z GitHub releases
        local inter_url
        inter_url=$(curl -s https://api.github.com/repos/rsms/inter/releases/latest \
            | python3 -c "import sys,json; \
              [print(a['browser_download_url']) for a in json.load(sys.stdin)['assets'] \
              if a['name'].endswith('.zip') and 'Inter-' in a['name']]" \
            2>/dev/null | head -1)

        if [[ -n "$inter_url" ]]; then
            curl -sL "$inter_url" -o "$tmpdir/inter.zip" >> "$LOGFILE" 2>&1
            unzip -q "$tmpdir/inter.zip" -d "$tmpdir/inter" >> "$LOGFILE" 2>&1
            # Skopiuj tylko desktop (nie variable) dla lepszej kompatybilności
            find "$tmpdir/inter" -name "Inter-*.otf" ! -name "*Italic*" \
                -exec cp {} "$font_dir/" \; 2>/dev/null \
            || find "$tmpdir/inter" -name "*.otf" \
                -exec cp {} "$font_dir/" \; 2>/dev/null
            ok "Inter skopiowany do $font_dir"
            inter_ok=1
        else
            warn "Nie udało się pobrać Inter — sprawdź połączenie"
            warn "Ręcznie: https://rsms.me/inter/"
        fi
        rm -rf "$tmpdir"
    fi

    # ── JetBrains Mono ───────────────────────────────────────────────────────
    if fc-list | grep -qi "JetBrains Mono"; then
        ok "JetBrains Mono już zainstalowany"
        jbmono_ok=1
    else
        info "Pobieranie JetBrains Mono (latest release)..."
        local tmpdir2
        tmpdir2=$(mktemp -d)

        local jbmono_url
        jbmono_url=$(curl -s https://api.github.com/repos/JetBrains/JetBrainsMono/releases/latest \
            | python3 -c "import sys,json; \
              [print(a['browser_download_url']) for a in json.load(sys.stdin)['assets'] \
              if a['name'] == 'JetBrainsMono.zip']" \
            2>/dev/null | head -1)

        if [[ -n "$jbmono_url" ]]; then
            curl -sL "$jbmono_url" -o "$tmpdir2/jbmono.zip" >> "$LOGFILE" 2>&1
            unzip -q "$tmpdir2/jbmono.zip" -d "$tmpdir2/jbmono" >> "$LOGFILE" 2>&1
            # Tylko TTF desktop, bez variable fonts
            find "$tmpdir2/jbmono/fonts/ttf" -name "*.ttf" \
                -exec cp {} "$font_dir/" \; 2>/dev/null \
            || find "$tmpdir2/jbmono" -name "*.ttf" \
                -exec cp {} "$font_dir/" \; 2>/dev/null
            ok "JetBrains Mono skopiowany do $font_dir"
            jbmono_ok=1
        else
            warn "Nie udało się pobrać JetBrains Mono"
            warn "Ręcznie: https://www.jetbrains.com/lp/mono/"
        fi
        rm -rf "$tmpdir2"
    fi

    # ── Odśwież cache czcionek ────────────────────────────────────────────────
    if [[ $inter_ok -eq 1 || $jbmono_ok -eq 1 ]]; then
        fc-cache -f "$font_dir" >> "$LOGFILE" 2>&1
        ok "Font cache odświeżony"
    fi

    # ── Weryfikacja ───────────────────────────────────────────────────────────
    local ok_count=0
    fc-list | grep -qi "Inter"        && ok "Weryfikacja: Inter OK"        && (( ok_count++ )) || warn "Inter NIE ZNALEZIONY po instalacji"
    fc-list | grep -qi "JetBrains"    && ok "Weryfikacja: JetBrains Mono OK" && (( ok_count++ )) || warn "JetBrains Mono NIE ZNALEZIONY"

    if [[ $ok_count -eq 2 ]]; then
        result_ok "Czcionki — Inter + JetBrains Mono zainstalowane"
    elif [[ $ok_count -eq 1 ]]; then
        result_fail "Czcionki — jedna z czcionek nie działa (sprawdź log)"
    else
        result_fail "Czcionki — błąd instalacji (sprawdź log)"
    fi
}

module_flatpak() {
    header "Flatpak — aplikacje"

    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOGFILE" 2>&1
    ok "Flathub OK"

    local APPS=(
        "org.mozilla.firefox"           # przeglądarka
        "com.raggesilver.BlackBox"      # terminal
        "org.gnome.TextEditor"          # edytor tekstu
        "com.visualstudio.code"         # VS Code
        "org.signal.Signal"             # komunikator
        "com.discordapp.Discord"        # komunikator
        "org.videolan.VLC"              # multimedia
        "com.mattjakeman.ExtensionManager" # rozszerzenia GNOME
        "io.github.flattool.Warehouse"  # zarządzanie Flatpak
        "org.gnome.baobab"             # analiza dysku
        "md.obsidian.Obsidian"          # notatki
        "com.spotify.Client"            # muzyka
    )

    local installed=0 failed=0
    for app in "${APPS[@]}"; do
        # Wytnij komentarz jeśli jest
        local app_id="${app%% *}"
        if flatpak list --app | grep -q "$app_id"; then
            info "Już zainstalowane: $app_id"
            (( installed++ )) || true
        else
            if flatpak install -y flathub "$app_id" >> "$LOGFILE" 2>&1; then
                ok "Zainstalowano: $app_id"
                (( installed++ )) || true
            else
                warn "Błąd: $app_id"
                (( failed++ )) || true
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        result_ok "Flatpak — $installed aplikacji zainstalowanych"
    else
        result_fail "Flatpak — $failed błędów (sprawdź log)"
    fi
}

module_chrome() {
    header "Google Chrome — overlay RPM"

    # Chrome nie jest dostępny jako Flatpak (oficjalnie) ani w Flathub
    # Na Silverblue jedyna droga to rpm-ostree overlay z repo Google
    # Alternatywa: Chromium z Flathub — ale skoro pytasz o Chrome, robimy Chrome

    if rpm -q google-chrome-stable &>/dev/null 2>&1; then
        ok "Google Chrome już zainstalowany"
        result_ok "Chrome — już zainstalowany"
        return
    fi

    info "Dodawanie repozytorium Google Chrome..."

    # Dodaj repo Google
    cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
    ok "Repo Google Chrome dodane"

    info "Instalowanie Chrome przez rpm-ostree overlay (wymagany restart)..."
    if rpm-ostree install --idempotent google-chrome-stable >> "$LOGFILE" 2>&1; then
        ok "Chrome zaplanowany w overlay"

        # Flatpak override żeby Chrome widział motywy GTK
        flatpak override --env=GTK_THEME=adw-gtk3-dark 2>/dev/null || true

        result_ok "Chrome — wymagany restart (overlay)"
    else
        fail "Instalacja Chrome nie powiodła się"
        info "Alternatywa: Chromium z Flathub:"
        info "  flatpak install flathub org.chromium.Chromium"
        result_fail "Chrome — sprawdź log"
    fi
}

module_btop() {
    header "btop — monitor systemu"

    # btop dostępny jako overlay RPM (Fedora repo)
    # Nie ma oficjalnego Flatpak — overlay to właściwa droga
    if command -v btop &>/dev/null; then
        local ver
        ver=$(btop --version 2>/dev/null | head -1 || echo "?")
        ok "btop już zainstalowany: $ver"
        result_ok "btop — już zainstalowany"
        return
    fi

    info "Instalowanie btop przez rpm-ostree overlay..."
    if rpm-ostree install --idempotent btop >> "$LOGFILE" 2>&1; then
        ok "btop zaplanowany w overlay"

        # Konfiguracja btop — dark theme, układ przyjazny dla MacBook 13"
        local btop_conf_dir="${HOME}/.config/btop"
        mkdir -p "$btop_conf_dir"

        # Tylko jeśli nie ma już konfiguracji
        if [[ ! -f "$btop_conf_dir/btop.conf" ]]; then
            cat > "$btop_conf_dir/btop.conf" << 'EOF'
#? Config file for btop v. 1.3+

color_theme = "dracula"
theme_background = True
truecolor = True
force_tty = False
graph_symbol = "braille"
graph_symbol_cpu = "default"
graph_symbol_gpu = "default"
graph_symbol_mem = "default"
graph_symbol_net = "default"
graph_symbol_proc = "default"
shown_boxes = "cpu mem net proc"
update_ms = 2000
proc_sorting = "cpu lazy"
proc_reversed = False
proc_tree = False
proc_colors = True
proc_gradient = True
proc_per_core = True
proc_mem_bytes = True
proc_cpu_graphs = True
proc_info_smaps = False
proc_left = False
proc_filter_kernel = False
cpu_graph_upper = "Auto"
cpu_graph_lower = "Auto"
cpu_invert_lower = True
cpu_single_graph = False
cpu_bottom = False
show_uptime = True
check_temp = True
cpu_sensor = "Auto"
show_coretemp = True
cpu_core_map = ""
temp_scale = "celsius"
base_10_sizes = False
show_cpu_freq = True
clock_format = "%H:%M"
background_update = True
custom_cpu_name = "Intel i5-5250U (Broadwell)"
net_download = 100
net_upload = 20
net_auto = True
net_sync = False
net_iface = ""
show_battery = True
selected_battery = "Auto"
show_gpu_info = 2
mem_graphs = True
mem_below_net = False
zfs_arc_cached = True
EOF
            ok "Konfiguracja btop zapisana (~/.config/btop/btop.conf)"
        else
            info "Istniejąca konfiguracja btop zachowana"
        fi

        result_ok "btop — wymagany restart (overlay)"
    else
        fail "Instalacja btop nie powiodła się"
        result_fail "btop — sprawdź log"
    fi
}

module_tlp() {
    header "TLP — zarządzanie energią"

    local tlp_conf="/etc/tlp.conf"
    if [[ ! -f "$tlp_conf" ]]; then
        warn "TLP nie zainstalowany jeszcze — zadziała po restarcie (overlay)"
        result_skip "TLP — uruchom ponownie po restarcie"
        return
    fi

    # MacBook Air — optymalizacja baterii
    local settings=(
        "CPU_SCALING_GOVERNOR_ON_AC=performance"
        "CPU_SCALING_GOVERNOR_ON_BAT=powersave"
        "CPU_ENERGY_PERF_POLICY_ON_AC=performance"
        "CPU_ENERGY_PERF_POLICY_ON_BAT=power"
        "WIFI_PWR_ON_BAT=on"
        "WIFI_PWR_ON_AC=off"
        "RUNTIME_PM_ON_BAT=auto"
        "RUNTIME_PM_ON_AC=on"
        "PCIE_ASPM_ON_BAT=powersupersave"
    )

    cp "$tlp_conf" "${tlp_conf}.bak"
    info "Backup: ${tlp_conf}.bak"

    for setting in "${settings[@]}"; do
        local key="${setting%%=*}"
        local value="${setting##*=}"
        if grep -q "^#*${key}=" "$tlp_conf"; then
            sed -i "s|^#*${key}=.*|${key}=${value}|" "$tlp_conf"
        else
            echo "${key}=${value}" >> "$tlp_conf"
        fi
        ok "TLP: $key=$value"
    done

    systemctl enable --now tlp.service >> "$LOGFILE" 2>&1 && ok "TLP aktywny" || warn "TLP — błąd uruchomienia"
    result_ok "TLP — skonfigurowany"
}

module_gnome_restore() {
    header "Restore ustawień GNOME z A1708"

    local backup_dir="${HOME}/.config/gnome-backup"

    if [[ ! -d "$backup_dir" ]]; then
        warn "Brak backupu w $backup_dir"
        info "Uruchom najpierw: ./gnome-settings.sh backup na A1708"
        info "Następnie skopiuj $backup_dir na ten komputer"
        result_skip "GNOME restore — brak backupu"
        return
    fi

    local latest
    latest=$(ls -t "$backup_dir"/gnome-settings-*.ini 2>/dev/null | head -1 || echo "")

    if [[ -z "$latest" ]]; then
        warn "Brak pliku gnome-settings-*.ini w $backup_dir"
        result_skip "GNOME restore — brak pliku"
        return
    fi

    ok "Backup znaleziony: $latest"

    # Motyw z backup
    local theme_info="${backup_dir}/theme-info.txt"
    if [[ -f "$theme_info" ]]; then
        info "Przywracam motyw z A1708..."
        while IFS=': ' read -r key value; do
            value=$(echo "$value" | tr -d "'" | xargs)
            case "$key" in
                gtk-theme)      gsettings set org.gnome.desktop.interface gtk-theme "$value" ;;
                icon-theme)     gsettings set org.gnome.desktop.interface icon-theme "$value" ;;
                cursor-theme)   gsettings set org.gnome.desktop.interface cursor-theme "$value" ;;
                color-scheme)   gsettings set org.gnome.desktop.interface color-scheme "$value" ;;
                font-name)      gsettings set org.gnome.desktop.interface font-name "$value" ;;
                monospace-font) gsettings set org.gnome.desktop.interface monospace-font-name "$value" ;;
            esac
        done < "$theme_info"
        ok "Motyw z A1708 przywrócony"
    fi

    # WM preferences
    dconf load /org/gnome/desktop/wm/preferences/ < <(
        sed -n '/^\[wm-preferences\]/,/^\[/{ /^\[wm-preferences\]/d; /^\[/d; p }' "$latest"
    ) && ok "WM preferences OK" || warn "WM preferences — pomiń"

    # Night Light
    dconf load /org/gnome/settings-daemon/plugins/color/ < <(
        sed -n '/^\[night-light\]/,/^\[/{ /^\[night-light\]/d; /^\[/d; p }' "$latest"
    ) && ok "Night Light z A1708 OK" || true

    # Rozszerzenia
    local ext_list="${backup_dir}/extensions-list.txt"
    if [[ -f "$ext_list" ]]; then
        echo ""
        info "Rozszerzenia z A1708 (zainstaluj przez Extension Manager):"
        cat "$ext_list"
    fi

    result_ok "GNOME restore z A1708 — gotowe"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    header "Podsumowanie"

    for r in "${RESULTS[@]}"; do
        echo -e " $r"
    done

    echo ""
    info "Pełny log: $LOGFILE"

    local needs_reboot=0
    for r in "${RESULTS[@]}"; do
        [[ "$r" == *"restart"* ]] && needs_reboot=1
    done

    if [[ $needs_reboot -eq 1 ]]; then
        echo -e "\n${YELLOW} Wymagany restart systemu.${NC}"
        echo -e " ${BOLD}systemctl reboot${NC}\n"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo " ╔═════════════════════════════════════════════╗"
    echo " ║  MacBook Air A1466 — Fedora Silverblue      ║"
    echo " ║  MacBookAir7,2 (Early 2015) / Broadwell     ║"
    echo " ╚═════════════════════════════════════════════╝"
    echo -e "${NC}"

    require_root
    touch "$LOGFILE"
    log "=== Instalacja rozpoczęta ==="

    check_model
    check_silverblue

    echo ""
    echo -e "${BOLD}Wybierz moduły do zainstalowania:${NC}"

    ask "Kernel parameters (rpm-ostree kargs) — Fn keys, ACPI, s2idle, backlight?" \
        && module_kargs || result_skip "Kernel params"

    ask "RPM Fusion overlay — broadcom-wl, intel VA-API, TLP, Papirus?" \
        && module_overlay || result_skip "RPM overlay"

    ask "Wi-Fi — sprawdzenie BCM4360 + blacklist brcmfmac?" \
        && module_wifi_check || result_skip "Wi-Fi check"

    ask "Suspend stack — sleep hook (wl unload/reload) + lid switch?" \
        && module_suspend || result_skip "Suspend stack"

    ask "GNOME — ustawienia touchpad, klawiatura, energia, czcionki?" \
        && module_gnome || result_skip "GNOME ustawienia"

    ask "Czcionki — Inter + JetBrains Mono (pobierz z GitHub)?" \
        && module_fonts || result_skip "Czcionki"

    ask "Motyw — Adwaita Dark + Papirus + Flatpak override?" \
        && module_theme || result_skip "Motyw"

    ask "Flatpak — instalacja aplikacji (Firefox, Code, Signal, VLC, Spotify...)?" \
        && module_flatpak || result_skip "Flatpak apps"

    ask "Google Chrome — overlay RPM (repo Google)?" \
        && module_chrome || result_skip "Chrome"

    ask "btop — monitor systemu (overlay RPM + konfiguracja)?" \
        && module_btop || result_skip "btop"

    ask "TLP — zarządzanie energią (wymaga overlay + restart)?" \
        && module_tlp || result_skip "TLP"

    ask "GNOME restore z A1708 (wymaga backupu w ~/.config/gnome-backup/)?" \
        && module_gnome_restore || result_skip "GNOME restore"

    print_summary

    log "=== Instalacja zakończona ==="
}

main "$@"
