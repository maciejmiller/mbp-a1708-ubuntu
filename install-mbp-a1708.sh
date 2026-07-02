#!/bin/bash
# MacBook Pro A1708 (MacBookPro14,1) Ubuntu Setup Installer
# Tested on Ubuntu 26.04 / kernel 7.0
# https://github.com/maciejmiller/mbp-a1708-ubuntu

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────
LOGFILE="/var/log/mbp-a1708-install.log"
RESULTS=()

log()    { printf '%s\n' "$(date '+%H:%M:%S') $*" | tee -a "$LOGFILE" > /dev/null; }
info()   { echo -e "${CYAN}  →${NC} $*"; log "INFO: $*"; }
ok()     { echo -e "${GREEN}  ✓${NC} $*"; log "OK: $*"; }
warn()   { echo -e "${YELLOW}  ⚠${NC} $*"; log "WARN: $*"; }
fail()   { echo -e "${RED}  ✗${NC} $*"; log "FAIL: $*"; }
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
    model=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
    if [[ "$model" != "MacBookPro14,1" ]]; then
        echo -e "${RED}Ten skrypt jest przeznaczony dla MacBookPro14,1.${NC}"
        echo -e "Wykryty model: ${BOLD}${model:-nieznany}${NC}"
        echo -e "${YELLOW}Kontynuować mimo to?${NC} [t/N] \c"
        read -r answer
        [[ "${answer,,}" == "t" ]] || exit 1
        warn "Kontynuowanie na nieobsługiwanym modelu: $model"
    else
        ok "Wykryto model: MacBookPro14,1"
    fi
}

check_deps() {
    local missing=()
    for cmd in curl git dkms modprobe systemctl update-grub; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Brakujące narzędzia: ${missing[*]}"
        info "Instalowanie..."
        apt-get install -y "${missing[@]}" >> "$LOGFILE" 2>&1
    fi
}

# ─── Modules ──────────────────────────────────────────────────────────────────

module_grub() {
    header "Kernel Parameters (GRUB)"

    local current
    current=$(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub)
    info "Aktualnie: $current"

    local params="quiet splash nvme_core.default_ps_max_latency_us=0 nvme.noacpi=1 pci=noaer i915.enable_dc=0 mem_sleep_default=s2idle thunderbolt.security=none"

    cp /etc/default/grub /etc/default/grub.bak
    info "Backup zapisany: /etc/default/grub.bak"

    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${params}\"|" /etc/default/grub

    if update-grub >> "$LOGFILE" 2>&1; then
        ok "GRUB zaktualizowany"
        result_ok "Kernel params — wymagany restart"
    else
        fail "update-grub nie powiodło się"
        result_fail "Kernel params"
    fi
}

module_suspend() {
    header "Suspend Stack"

    # Platform init script
    info "Instalowanie macbook-a1708-platform-init.sh..."
    cat > /usr/local/sbin/macbook-a1708-platform-init.sh << 'EOF'
#!/bin/bash
set -euo pipefail

log() {
    printf '%s\n' "$1" | systemd-cat -t macbook-platform 2>/dev/null || true
}

readonly PCI_DEVICES=(
    0000:01:00.0
    0000:02:00.0
    0000:04:00.0
    0000:05:00.0
    0000:05:01.0
    0000:05:02.0
    0000:05:04.0
    0000:07:00.0
)

for dev in "${PCI_DEVICES[@]}"; do
    sys_path="/sys/bus/pci/devices/${dev}"
    [[ -d "${sys_path}" ]] || continue
    [[ -e "${sys_path}/d3cold_allowed" ]]          && printf '%s' 0  > "${sys_path}/d3cold_allowed"          2>/dev/null || true
    [[ -e "${sys_path}/power/control" ]]           && printf '%s' on > "${sys_path}/power/control"           2>/dev/null || true
    [[ -e "${sys_path}/power/autosuspend_delay_ms" ]] && printf '%s' -1 > "${sys_path}/power/autosuspend_delay_ms" 2>/dev/null || true
done
log "PCIe power limits applied"

for wake in XHC1 XHC2; do
    grep -q "${wake}.*enabled" /proc/acpi/wakeup 2>/dev/null && printf '%s' "${wake}" > /proc/acpi/wakeup 2>/dev/null || true
done

grep -q "LID0.*disabled" /proc/acpi/wakeup 2>/dev/null && printf '%s' LID0 > /proc/acpi/wakeup 2>/dev/null || true

for lid_node in \
    /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0D:00/power/wakeup \
    /sys/devices/platform/PNP0C0D:00/power/wakeup; do
    [[ -e "${lid_node}" ]] && printf '%s' enabled > "${lid_node}" 2>/dev/null || true
done

modprobe applespi 2>/dev/null && log "applespi loaded" || log "WARNING: applespi not available"
log "MacBook platform initialization complete"
EOF
    chmod 755 /usr/local/sbin/macbook-a1708-platform-init.sh

    # Systemd service
    cat > /etc/systemd/system/macbook-a1708-platform.service << 'EOF'
[Unit]
Description=MacBook Pro A1708 Platform Hardware Initialization
After=basic.target
Before=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/macbook-a1708-platform-init.sh

[Install]
WantedBy=multi-user.target
EOF

    # Sleep hook
    info "Instalowanie macbook-a1708-sleep.sh..."
    cat > /usr/lib/systemd/system-sleep/macbook-a1708-sleep.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/macbook-suspend.log"
WIFI_STORE="/tmp/wifi-connection-backup"
WIFI_DEVICE_PATH="/sys/bus/pci/devices/0000:02:00.0"
WIRELESS_MODULES=(brcmfmac_wcc brcmfmac brcmutil cfg80211)

log() { printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE" >/dev/null; }
ensure() { [[ -e "$2" ]] && printf '%s' "$1" > "$2" 2>/dev/null || true; }

pre_suspend() {
    log "PRE: suspend start"
    sync
    nmcli connection show --active | grep wifi > "$WIFI_STORE" 2>/dev/null || true

    if [[ -d "$WIFI_DEVICE_PATH" ]]; then
        ensure 0  "$WIFI_DEVICE_PATH/d3cold_allowed"
        ensure on "$WIFI_DEVICE_PATH/power/control"
        ensure -1 "$WIFI_DEVICE_PATH/power/autosuspend_delay_ms"
    fi

    nmcli radio wifi off 2>/dev/null || true
    rfkill block wifi 2>/dev/null || true
    sleep 1

    for mod in "${WIRELESS_MODULES[@]}"; do modprobe -r "$mod" 2>/dev/null || true; done

    for _ in {1..5}; do
        lsmod | grep -q '^brcmfmac' || break
        sleep 1
        modprobe -r brcmfmac 2>/dev/null || true
    done

    if lsmod | grep -q '^brcmfmac'; then
        rfkill unblock wifi 2>/dev/null || true
        nmcli radio wifi on 2>/dev/null || true
        log "PRE: ERROR brcmfmac still loaded"
        exit 1
    fi
    log "PRE: done"
}

post_resume() {
    log "POST: resume start"
    modprobe cfg80211 2>/dev/null || true
    modprobe brcmutil 2>/dev/null || true
    modprobe brcmfmac 2>/dev/null || true
    sleep 1

    if [[ -d "$WIFI_DEVICE_PATH" ]]; then
        ensure 0  "$WIFI_DEVICE_PATH/d3cold_allowed"
        ensure on "$WIFI_DEVICE_PATH/power/control"
        ensure -1 "$WIFI_DEVICE_PATH/power/autosuspend_delay_ms"
    fi

    rfkill unblock wifi 2>/dev/null || true
    nmcli radio wifi on 2>/dev/null || true
    sleep 1

    if [[ -f "$WIFI_STORE" ]]; then
        nmcli connection up id "$(cut -d' ' -f1 "$WIFI_STORE")" 2>/dev/null || true
        rm -f "$WIFI_STORE"
    fi

    modprobe -r applespi 2>/dev/null || true
    sleep 1
    modprobe applespi 2>/dev/null || true

    ensure 0 /sys/class/backlight/intel_backlight/bl_power
    for connector in /sys/class/drm/card*/status; do ensure detect "$connector"; done
    log "POST: done"
}

case "$1/$2" in
    pre/suspend)  pre_suspend ;;
    post/suspend) post_resume ;;
    *) exit 0 ;;
esac
EOF
    chmod 755 /usr/lib/systemd/system-sleep/macbook-a1708-sleep.sh

    # Logind lid switch
    info "Konfigurowanie lid switch..."
    sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=suspend/'               /etc/systemd/logind.conf
    sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf

    # Enable service
    systemctl daemon-reload
    if systemctl enable --now macbook-a1708-platform.service >> "$LOGFILE" 2>&1; then
        ok "Suspend stack zainstalowany i aktywny"
        result_ok "Suspend stack"
    else
        fail "Nie udało się uruchomić macbook-a1708-platform.service"
        result_fail "Suspend stack"
    fi
}

module_wifi() {
    header "Wi-Fi (brcmfmac)"

    # Remove bcmwl/broadcom-sta if present — conflicts with brcmfmac
    if dkms status 2>/dev/null | grep -q '^broadcom-sta'; then
        warn "broadcom-sta (bcmwl) detected — removing, conflicts with brcmfmac"
        dkms remove broadcom-sta/$(dkms status | grep broadcom-sta | head -1 | awk -F'[/,]' '{print $2}' | tr -d ' ') --all >> "$LOGFILE" 2>&1 || true
        apt-get remove -y bcmwl-kernel-source broadcom-sta-dkms 2>/dev/null >> "$LOGFILE" 2>&1 || true
        modprobe -r wl 2>/dev/null || true
        ok "broadcom-sta removed"
    fi

    local driver_ok=0 firmware_ok=0

    if lsmod | grep -q '^brcmfmac'; then
        ok "brcmfmac załadowany (mainline kernel)"
        driver_ok=1
    else
        warn "brcmfmac nie jest załadowany"
        info "Próba załadowania..."
        if modprobe brcmfmac 2>/dev/null; then
            ok "brcmfmac załadowany"
            driver_ok=1
        else
            fail "Nie udało się załadować brcmfmac"
        fi
    fi

    if ls /lib/firmware/brcm/brcmfmac4350* &>/dev/null; then
        ok "Firmware BCM4350 obecny w systemie"
        firmware_ok=1
    else
        warn "Brak firmware BCM4350 w /lib/firmware/brcm/"
        info "Instalowanie linux-firmware..."
        if apt-get install -y linux-firmware >> "$LOGFILE" 2>&1; then
            ok "linux-firmware zainstalowany"
            firmware_ok=1
        else
            fail "Instalacja linux-firmware nie powiodła się"
        fi
    fi

    if [[ $driver_ok -eq 1 && $firmware_ok -eq 1 ]]; then
        result_ok "Wi-Fi — działa out of the box (kernel 7.0+)"
    else
        result_fail "Wi-Fi — sprawdź log"
    fi
}

module_audio() {
    header "Audio (Cirrus CS8409 DKMS)"

    if lsmod | grep -q 'snd_hda_codec_cs8409'; then
        ok "snd_hda_codec_cs8409 już załadowany"
        result_ok "Audio — driver już aktywny"
        return
    fi

    info "Instalowanie zależności..."
    apt-get install -y dkms git linux-headers-"$(uname -r)" linux-source-"$(uname -r | cut -d- -f1)" >> "$LOGFILE" 2>&1

    info "Klonowanie snd_hda_macbookpro..."
    local tmpdir
    tmpdir=$(mktemp -d)
    git clone https://github.com/davidjo/snd_hda_macbookpro "$tmpdir/audio" >> "$LOGFILE" 2>&1

    pushd "$tmpdir/audio" > /dev/null

    local kernel_ver
    kernel_ver=$(uname -r)
    local major minor
    major=$(echo "$kernel_ver" | cut -d. -f1)
    minor=$(echo "$kernel_ver" | cut -d. -f2 | cut -d- -f1)

    # Patch dla kernela 6.17+
    if [[ "$major" -gt 6 ]] || [[ "$major" -eq 6 && "$minor" -ge 17 ]]; then
        info "Wykryto kernel $major.$minor — aplikowanie patchy dla 6.17+..."
        sed -i 's|a/codecs/cirrus/cs8409.c.orig|a/codecs/cirrus/cs8409.c|' patch_cs8409.c.diff 2>/dev/null || true
        sed -i 's|a/codecs/cirrus/cs8409.h.orig|a/codecs/cirrus/cs8409.h|' patch_cs8409.h.diff 2>/dev/null || true
    fi

    if sudo ./install.cirrus.driver.sh -i -k "$kernel_ver" >> "$LOGFILE" 2>&1; then
        ok "Cirrus CS8409 DKMS zainstalowany"
        result_ok "Audio — wymagany restart"
    else
        fail "Instalacja audio nie powiodła się"
        result_fail "Audio"
    fi
    popd > /dev/null
    rm -rf "$tmpdir"
}

module_camera() {
    header "Kamera (facetimehd DKMS)"

    if lsmod | grep -q '^facetimehd'; then
        ok "facetimehd już załadowany"
        result_ok "Kamera — driver już aktywny"
        return
    fi

    info "Instalowanie zależności..."
    apt-get install -y dkms git linux-headers-"$(uname -r)" >> "$LOGFILE" 2>&1

    info "Klonowanie facetimehd..."
    local tmpdir
    tmpdir=$(mktemp -d)
    git clone https://github.com/patjak/facetimehd "$tmpdir/facetimehd" >> "$LOGFILE" 2>&1
    git clone https://github.com/patjak/facetimehd-firmware "$tmpdir/facetimehd-firmware" >> "$LOGFILE" 2>&1

    # Firmware
    pushd "$tmpdir/facetimehd-firmware" > /dev/null
    if make >> "$LOGFILE" 2>&1 && make install >> "$LOGFILE" 2>&1; then
        ok "Firmware zainstalowany"
    else
        fail "Instalacja firmware nie powiodła się"
        result_fail "Kamera (firmware)"
        popd > /dev/null
        rm -rf "$tmpdir"
        return
    fi
    popd > /dev/null

    # DKMS
    pushd "$tmpdir/facetimehd" > /dev/null
    local ft_ver
    ft_ver=$(grep '^PACKAGE_VERSION' dkms.conf | cut -d= -f2 | tr -d '"')
    if dkms add . >> "$LOGFILE" 2>&1 && \
       dkms build facetimehd/"$ft_ver" >> "$LOGFILE" 2>&1 && \
       dkms install facetimehd/"$ft_ver" >> "$LOGFILE" 2>&1; then
        modprobe facetimehd 2>/dev/null || true
        ok "facetimehd DKMS zainstalowany"
        result_ok "Kamera"
    else
        fail "Instalacja facetimehd DKMS nie powiodła się"
        result_fail "Kamera"
    fi
    popd > /dev/null
    rm -rf "$tmpdir"
}

module_keyboard() {
    header "Klawiatura (Apple layout)"

    local current
    current=$(grep '^XKBMODEL' /etc/default/keyboard 2>/dev/null | cut -d= -f2 || echo "nieznany")

    if [[ "$current" == "apple" || "$current" == '"apple"' ]]; then
        ok "Klawiatura już ustawiona na apple"
        result_ok "Klawiatura — już skonfigurowana"
        return
    fi

    info "Aktualny model: $current → ustawianie na apple"
    sed -i 's/^XKBMODEL=.*/XKBMODEL="apple"/' /etc/default/keyboard

    if dpkg-reconfigure -f noninteractive keyboard-configuration >> "$LOGFILE" 2>&1; then
        ok "Model klawiatury ustawiony na apple"
        result_ok "Klawiatura — wymagany restart"
    else
        fail "Konfiguracja klawiatury nie powiodła się"
        result_fail "Klawiatura"
    fi
}

module_dracut() {
    header "Dracut — initramfs module forcing"

    local conf="/etc/dracut.conf.d/macbook.conf"

    if [[ -f "$conf" ]] && grep -q "applespi" "$conf"; then
        ok "macbook.conf already present"
        result_ok "Dracut — already configured"
        return
    fi

    info "Writing $conf..."
    echo 'force_drivers+=" applespi intel_lpss_pci spi_pxa2xx_platform "' > "$conf"

    info "Rebuilding initramfs (this may take a minute)..."
    if dracut --force >> "$LOGFILE" 2>&1; then
        ok "initramfs rebuilt"
        result_ok "Dracut — reboot required"
    else
        fail "dracut --force failed"
        result_fail "Dracut"
    fi
}

module_gnome() {
    header "GNOME — extensions, fonts, theme"

    local REAL_USER="${SUDO_USER:-$USER}"
    local REAL_HOME
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

    # Install Inter font
    info "Installing Inter font..."
    apt-get install -y fonts-inter 2>/dev/null >> "$LOGFILE" 2>&1 || \
    apt-get install -y fonts-inter-variable 2>/dev/null >> "$LOGFILE" 2>&1 || \
    pip3 install --break-system-packages inter-font 2>/dev/null >> "$LOGFILE" 2>&1 || true

    # Install extension manager
    info "Installing GNOME Extension Manager..."
    apt-get install -y gnome-shell-extension-manager 2>/dev/null >> "$LOGFILE" 2>&1 || true

    # Apply dconf settings as real user
    info "Applying GNOME settings..."
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/gtk-theme "'Yaru-sage'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/icon-theme "'Yaru-sage'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/font-name "'Inter 10'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/document-font-name "'Inter 10'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/monospace-font-name "'Ubuntu Mono 10'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/color-scheme "'default'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/interface/accent-color "'slate'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/wm/preferences/button-layout "'icon,menu:minimize,maximize,close'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/wm/keybindings/close "['<Super>q']" 2>/dev/null || true

    # Dash-to-dock settings
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/dock-position "'BOTTOM'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size 48 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/custom-theme-shrink true 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/running-indicator-style "'DOTS'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/transparency-mode "'FIXED'" 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/background-opacity 0.3 2>/dev/null || true

    # Just Perfection
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/just-perfection/clock-menu-position 1 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/just-perfection/clock-menu-position-offset 8 2>/dev/null || true

    # Tiling assistant
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/tiling-assistant/focus-hint-color "'rgb(101,123,105)'" 2>/dev/null || true

    ok "GNOME settings applied"

    # Extensions to install via gdbus
    local extensions=(
        "dash-to-dock@micxgx.gmail.com"
        "just-perfection-desktop@just-perfection"
        "transparent-top-bar@ftpix.com"
        "tiling-assistant@ubuntu.com"
        "ding@rastersoft.com"
    )

    info "Installing GNOME extensions..."
    for ext in "${extensions[@]}"; do
        if [[ -d "$REAL_HOME/.local/share/gnome-shell/extensions/$ext" ]]; then
            ok "Extension already installed: $ext"
        else
            sudo -u "$REAL_USER" gdbus call --session \
                --dest org.gnome.Shell.Extensions \
                --object-path /org/gnome/Shell/Extensions \
                --method org.gnome.Shell.Extensions.InstallRemoteExtension \
                "$ext" >> "$LOGFILE" 2>&1 || warn "Could not auto-install $ext — install manually via Extension Manager"
        fi
    done

    result_ok "GNOME — reboot required to activate extensions"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    header "Podsumowanie"
    for r in "${RESULTS[@]}"; do
        echo -e "  $r"
    done
    echo ""
    info "Pełny log: $LOGFILE"

    local needs_reboot=0
    for r in "${RESULTS[@]}"; do
        [[ "$r" == *"restart"* ]] && needs_reboot=1
    done

    if [[ $needs_reboot -eq 1 ]]; then
        echo -e "\n${YELLOW}  Wymagany restart systemu.${NC}"
        echo -e "  ${BOLD}sudo reboot${NC}\n"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔════════════════════════════════════════╗"
    echo "  ║   MacBook Pro A1708 — Ubuntu Installer ║"
    echo "  ║   Ubuntu 26.04 / kernel 7.0+           ║"
    echo "  ╚════════════════════════════════════════╝"
    echo -e "${NC}"

    require_root
    touch "$LOGFILE"
    log "=== Instalacja rozpoczęta ==="

    check_model
    check_deps

    echo ""
    echo -e "${BOLD}Wybierz moduły do zainstalowania:${NC}"

    ask "Kernel parameters (GRUB) — s2idle, nvme, pci, thunderbolt?" && module_grub     || result_skip "Kernel params"
    ask "Suspend stack (platform-init + sleep hook + lid switch)?" && module_suspend  || result_skip "Suspend stack"
    ask "Wi-Fi — brcmfmac?" && module_wifi     || result_skip "Wi-Fi"
    ask "Audio — Cirrus CS8409 DKMS?" && module_audio    || result_skip "Audio"
    ask "Camera — facetimehd DKMS?" && module_camera   || result_skip "Camera"
    ask "Keyboard — apple model?" && module_keyboard || result_skip "Keyboard"
    ask "Dracut — force essential modules into initramfs?" && module_dracut   || result_skip "Dracut"
    ask "GNOME — theme, fonts, extensions, dock settings?"  && module_gnome    || result_skip "GNOME"

    print_summary
    log "=== Instalacja zakończona ==="
}

main "$@"

# (appended)
