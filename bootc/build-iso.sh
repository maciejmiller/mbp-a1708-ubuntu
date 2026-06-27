#!/bin/bash
# ============================================================
#  build-iso.sh — buduje ISO z obrazu kontenera bootc
#  Wymaga: podman, bootc-image-builder
#
#  Użycie:
#    ./build-iso.sh          → pełny build (kontener + ISO)
#    ./build-iso.sh image    → tylko zbuduj obraz kontenera
#    ./build-iso.sh iso      → tylko ISO (z istniejącego obrazu)
#    ./build-iso.sh clean    → wyczyść artefakty
# ============================================================

set -euo pipefail

# ── Konfiguracja ─────────────────────────────────────────────
IMAGE_NAME="mba-a1466"
IMAGE_TAG="latest"
IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"
OUTPUT_DIR="./output"
ISO_NAME="fedora-silverblue-mba-a1466.iso"
BUILDER_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

# ── Kolory ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN} ✓${NC} $*"; }
info() { echo -e "${CYAN} →${NC} $*"; }
warn() { echo -e "${YELLOW} ⚠${NC} $*"; }
header() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

# ── Sprawdzenia ───────────────────────────────────────────────
check_deps() {
    header "Sprawdzanie zależności"

    command -v podman &>/dev/null || { echo "Wymagany: podman"; exit 1; }
    ok "podman: $(podman --version)"

    # bootc-image-builder potrzebuje rootful podman lub --privileged
    if [[ $EUID -ne 0 ]]; then
        warn "Zalecane uruchomienie jako root (bootc-image-builder wymaga --privileged)"
        warn "Lub: sudo ./build-iso.sh"
    fi

    # Wolne miejsce — budowanie ISO zajmuje ~15 GB
    local free_gb
    free_gb=$(df -BG . | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ $free_gb -lt 15 ]]; then
        warn "Mało miejsca: ${free_gb}GB wolnych (zalecane 15GB+)"
    else
        ok "Wolne miejsce: ${free_gb}GB"
    fi
}

# ── Buduj obraz kontenera ─────────────────────────────────────
build_image() {
    header "Budowanie obrazu kontenera"

    info "Obraz: $IMAGE_FULL"
    info "Containerfile: bootc/Containerfile"

    local start=$SECONDS
    podman build \
        --tag "$IMAGE_FULL" \
        --file bootc/Containerfile \
        --layers \
        .

    local elapsed=$(( SECONDS - start ))
    ok "Obraz zbudowany: $IMAGE_FULL (${elapsed}s)"
    podman image inspect "$IMAGE_FULL" --format "Rozmiar: {{.Size}}" | \
        awk '{printf " ✓ %s: %.1f GB\n", $1, $2/1024/1024/1024}'
}

# ── Generuj ISO ───────────────────────────────────────────────
build_iso() {
    header "Generowanie ISO (bootc-image-builder)"

    mkdir -p "$OUTPUT_DIR"

    info "Builder: $BUILDER_IMAGE"
    info "Output:  $OUTPUT_DIR/$ISO_NAME"

    # bootc-image-builder — oficjalne narzędzie Red Hat/Fedora do budowania ISO z obrazu OCI
    podman run \
        --rm \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "$BUILDER_IMAGE" \
        --type anaconda-iso \
        --local \
        "localhost/${IMAGE_FULL}"

    # Zmień nazwę outputu
    if [[ -f "$OUTPUT_DIR/bootiso/install.iso" ]]; then
        mv "$OUTPUT_DIR/bootiso/install.iso" "$OUTPUT_DIR/$ISO_NAME"
        ok "ISO gotowe: $OUTPUT_DIR/$ISO_NAME"
        ls -lh "$OUTPUT_DIR/$ISO_NAME"
    elif [[ -f "$OUTPUT_DIR/install.iso" ]]; then
        mv "$OUTPUT_DIR/install.iso" "$OUTPUT_DIR/$ISO_NAME"
        ok "ISO gotowe: $OUTPUT_DIR/$ISO_NAME"
        ls -lh "$OUTPUT_DIR/$ISO_NAME"
    else
        warn "ISO w niestandardowej lokalizacji — sprawdź $OUTPUT_DIR/"
        find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null
    fi
}

# ── Nagraj na pendrive ────────────────────────────────────────
write_usb() {
    header "Nagrywanie na pendrive"

    local iso_path="$OUTPUT_DIR/$ISO_NAME"
    if [[ ! -f "$iso_path" ]]; then
        echo "Brak ISO: $iso_path — uruchom najpierw build"
        exit 1
    fi

    echo "Dostępne dyski:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v loop
    echo ""
    echo -e "${YELLOW}Podaj urządzenie (np. sdb, NIE /dev/sdb):${NC} \c"
    read -r dev

    if [[ ! -b "/dev/$dev" ]]; then
        echo "Nieprawidłowe urządzenie: /dev/$dev"
        exit 1
    fi

    echo -e "${YELLOW}UWAGA: Wszystkie dane na /dev/$dev zostaną SKASOWANE.${NC}"
    echo -e "Kontynuować? [wpisz 'tak']: \c"
    read -r confirm
    [[ "$confirm" == "tak" ]] || { echo "Anulowano."; exit 0; }

    info "Nagrywanie $iso_path → /dev/$dev ..."
    dd if="$iso_path" of="/dev/$dev" bs=4M status=progress conv=fsync
    sync
    ok "Gotowe — pendrive /dev/$dev"
}

# ── Czyszczenie ───────────────────────────────────────────────
do_clean() {
    header "Czyszczenie"
    podman rmi "$IMAGE_FULL" 2>/dev/null && ok "Obraz usunięty" || info "Obraz nie istniał"
    rm -rf "$OUTPUT_DIR" && ok "Output/ usunięty" || true
}

# ── Info o obrazie ────────────────────────────────────────────
do_info() {
    header "Informacje o obrazie"
    podman image inspect "$IMAGE_FULL" 2>/dev/null || echo "Obraz $IMAGE_FULL nie istnieje — uruchom build"
}

# ── Main ─────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo " ╔═════════════════════════════════════════════╗"
echo " ║  MacBook Air A1466 — bootc ISO Builder      ║"
echo " ╚═════════════════════════════════════════════╝"
echo -e "${NC}"

check_deps

case "${1:-all}" in
    all)
        build_image
        build_iso
        echo ""
        ok "Wszystko gotowe!"
        info "ISO: $OUTPUT_DIR/$ISO_NAME"
        info "Nagraj na pendrive: ./build-iso.sh usb"
        ;;
    image)  build_image ;;
    iso)    build_iso ;;
    usb)    write_usb ;;
    clean)  do_clean ;;
    info)   do_info ;;
    *)
        echo "Użycie: $0 {all|image|iso|usb|clean|info}"
        echo ""
        echo "  all    → zbuduj obraz + wygeneruj ISO (domyślne)"
        echo "  image  → tylko obraz kontenera (podman build)"
        echo "  iso    → tylko ISO z istniejącego obrazu"
        echo "  usb    → nagraj ISO na pendrive (dd)"
        echo "  clean  → usuń obraz i output/"
        echo "  info   → info o obrazie"
        ;;
esac
