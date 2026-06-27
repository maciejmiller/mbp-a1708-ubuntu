# Fedora Silverblue — MacBook Air A1466 (2015)
## Kompletny przewodnik instalacji i konfiguracji

---

## Sprzęt

| Komponent | Spec | Status |
|-----------|------|--------|
| CPU | Intel Core i5/i7 5250U (Broadwell) | ✅ pełne wsparcie |
| GPU | Intel HD Graphics 6000 | ✅ VA-API działa |
| Wi-Fi | Broadcom BCM4360 | ⚠️ wymaga broadcom-wl (overlay) |
| Bluetooth | Broadcom BCM20702 | ✅ bluez |
| Touchpad | Apple Magic Trackpad | ✅ libinput |
| Kamera | FaceTime HD | ✅ od kernel 5.x |
| SSD | Apple NVMe (AHCI) | ✅ działa natywnie |
| Audio | Cirrus Logic CS4208 | ✅ PulseAudio/Pipewire |
| Thunderbolt | Intel DSL5520 | ⚠️ podstawowa funkcja OK |

---

## Etap 0 — Przygotowanie (na A1708, przed zakupem A1466)

### Backup ustawień GNOME z A1708
```bash
chmod +x scripts/gnome-settings.sh
./scripts/gnome-settings.sh backup
```
Backup trafia do `~/.config/gnome-backup/` — skopiuj na pendrive lub do chmury.

---

## Etap 1 — Nośnik instalacyjny

### Pobierz Fedora Silverblue
```
https://fedoraproject.org/silverblue/download/
```
Pobierz najnowszy `.iso` (Fedora Silverblue 40+).

### Nagraj na pendrive
```bash
# Na macOS (A1708):
diskutil list                          # znajdź pendrive, np. /dev/disk2
diskutil unmountDisk /dev/disk2
sudo dd if=Fedora-Silverblue-*.iso of=/dev/rdisk2 bs=1m status=progress
```

---

## Etap 2 — Boot z pendrive na A1466

1. Wyłącz MacBook
2. Włącz trzymając **Option (⌥)** — pojawi się boot picker
3. Wybierz "EFI Boot" (żółty pendrive)
4. W GRUB wybierz **"Start Fedora Silverblue"**

---

## Etap 3 — Instalacja Anaconda (Fedora Installer)

### Partycjonowanie (czysta instalacja — macOS won)
```
Urządzenie: cały dysk Apple SSD
Schemat:    Automatic (Btrfs — domyślny dla Silverblue)
```

Anaconda domyślnie tworzy:
- `/boot/efi` — EFI partition (zachowaj jeśli istnieje Apple EFI)
- `/boot` — 1 GB ext4
- `/` — reszta Btrfs (subwolumin `root`)
- `home` — Btrfs subwolumin `home` (automatycznie)

> **Ważne:** Silverblue używa Btrfs — NIE zmieniaj na ext4 ani XFS.
> Immutable rootfs tego wymaga.

### Ustawienia regionalne
- Język: Polski (lub English — Twój wybór)
- Układ klawiatury: Polish
- Strefa czasowa: Europe/Warsaw

### Konto użytkownika
Utwórz konto z uprawnieniami administratora.

**Nie używaj hasła roota** — sudo wystarczy na Silverblue.

---

## Etap 4 — Pierwsze uruchomienie

### Problem z Wi-Fi po instalacji
Po restarcie Wi-Fi **nie będzie działać** (Broadcom). Opcje:
- **USB-C → Ethernet adapter** (polecane)
- **USB Wi-Fi dongle** (np. TP-Link TL-WN725N — działa od razu)
- **iPhone USB tethering** (działa natywnie na Linuxie)

### Aktualizacja systemu (pierwsza rzecz)
```bash
rpm-ostree update
# poczekaj, uruchom ponownie
systemctl reboot
```

---

## Etap 5 — Post-install skrypt

```bash
# Sklonuj lub skopiuj ten folder na A1466
cd fedora-a1466/
chmod +x scripts/post-install.sh
./scripts/post-install.sh
```

Skrypt wykonuje:
1. Kernel params (Fn keys, ACPI, PCIe)
2. RPM Fusion + broadcom-wl (overlay)
3. Aplikacje Flatpak
4. Ustawienia GNOME
5. Motyw (Adwaita Dark + Papirus)
6. TLP (zarządzanie energią)

**Wymagany restart po skrypcie** (rpm-ostree overlay).

---

## Etap 6 — Restore ustawień z A1708

```bash
# Skopiuj backup z pendrive/chmury
cp -r /run/media/user/PENDRIVE/gnome-backup ~/.config/

# Przywróć
./scripts/gnome-settings.sh restore
```

---

## Etap 7 — rEFInd (opcjonalnie, ale polecane)

rEFInd daje ładniejszy boot picker i lepiej radzi sobie z Apple EFI.

```bash
# Po instalacji broadcom-wl i restarcie
# Pobierz rEFInd binary zip z https://www.rodsbooks.com/refind/
# Lub przez overlay:
rpm-ostree install efibootmgr
```

Alternatywnie — GRUB działa, tylko jest brzydszy.

---

## Rozwiązywanie problemów

### Wi-Fi nie działa po restarcie
```bash
# Sprawdź czy moduł załadowany
lsmod | grep wl
# Jeśli nie:
sudo modprobe wl
# Trwale (po każdym restarcie Silverblue):
echo 'wl' | sudo tee /etc/modules-load.d/broadcom-wl.conf
```

### Jasność ekranu nie działa
```bash
# Sprawdź kernel param
cat /proc/cmdline | grep acpi_osi
# Jeśli brak — dodaj przez rpm-ostree kargs
rpm-ostree kargs --append="acpi_backlight=native"
```

### Kamera nie działa
```bash
# Sprawdź czy widoczna
ls /dev/video*
# Lub
v4l2-ctl --list-devices
```

### Suspend/wake — ekran nie wraca
Dodaj kernel param:
```bash
rpm-ostree kargs --append="acpi_sleep=nonvs"
```

### Bluetooth — urządzenia się nie parują
```bash
sudo systemctl enable --now bluetooth
bluetoothctl
# W bluetoothctl:
power on
scan on
```

---

## Silverblue — ważne różnice vs zwykła Fedora

| Akcja | Fedora Workstation | Fedora Silverblue |
|-------|-------------------|-------------------|
| Instalacja pakietu | `dnf install` | `rpm-ostree install` + restart |
| Aplikacje użytkownika | dnf | **Flatpak** (główna droga) |
| Aktualizacja systemu | `dnf update` | `rpm-ostree update` + restart |
| Rollback | brak | `rpm-ostree rollback` ✅ |
| `/usr` | modyfikowalny | **read-only** (immutable) |
| Języki runtime | dnf | `toolbox` lub `distrobox` |

### Toolbox — środowisko deweloperskie
```bash
# Utwórz kontener (mutable Fedora w środku)
toolbox create --image fedora:40
toolbox enter

# Wewnątrz kontenera masz pełne dnf
dnf install nodejs python3 git gcc ...
```

---

## Użyteczne komendy Silverblue

```bash
# Status systemu
rpm-ostree status

# Co jest zainstalowane jako overlay
rpm-ostree status -v

# Rollback do poprzedniej wersji
rpm-ostree rollback

# Historia deploymentów
rpm-ostree db list

# Sprawdź Flatpak
flatpak list --app

# Update Flatpak
flatpak update
```

---

## Po wszystkim — checklist

- [ ] Wi-Fi działa (`nmcli dev status`)
- [ ] Bluetooth działa
- [ ] Dźwięk działa (głośniki + mikrofon)
- [ ] Kamera działa
- [ ] Jasność ekranu (klawisze Fn)
- [ ] Touchpad — tap-to-click, gesty
- [ ] Suspend/wake działa
- [ ] Motyw przeniesiony z A1708
- [ ] Rozszerzenia GNOME zainstalowane
- [ ] Flatpak apps działają
- [ ] `rpm-ostree status` — zielony, bez pending

---

*Wygenerowano dla: MacBook Air A1466 (Early 2015) + Fedora Silverblue 40+*
