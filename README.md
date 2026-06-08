# MacBook Pro A1708 — Ubuntu Installer

Modularny skrypt instalacyjny dla Ubuntu na MacBook Pro 13" 2017 (A1708 / MacBookPro14,1).

Przetestowany na **Ubuntu 26.04 / kernel 7.0**.

---

## Obsługiwany sprzęt

| Komponent | Model | Status |
|-----------|-------|--------|
| CPU/GPU | Intel Kaby Lake + Intel Iris Plus 640 | ✅ mainline |
| Wi-Fi | Broadcom BCM4350 (brcmfmac) | ✅ mainline kernel 7.0+ |
| Audio | Cirrus Logic CS8409 | ✅ DKMS ([davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)) |
| Kamera | FaceTime HD | ✅ DKMS ([patjak/facetimehd](https://github.com/patjak/facetimehd)) |
| Klawiatura / Touchpad | Apple SPI | ✅ mainline (applespi) |
| Suspend (s2idle) | — | ✅ wymaga konfiguracji |
| Thunderbolt / USB-C data | — | ⚠️ wymaga huba USB-C |

---

## Szybki start

```bash
git clone https://github.com/your-username/mbp-a1708-ubuntu
cd mbp-a1708-ubuntu
sudo bash install-mbp-a1708.sh
```

Skrypt wykrywa model (`MacBookPro14,1`) i pyta o każdy moduł osobno — instalujesz tylko to czego potrzebujesz.

---

## Moduły

### Kernel parameters
Ustawia w GRUB parametry niezbędne do stabilnego działania:

```
nvme_core.default_ps_max_latency_us=0  # stabilność NVMe
nvme.noacpi=1                           # blokuje ACPI power management dla NVMe
pci=noaer                               # wycisza błędy PCIe AER
i915.enable_dc=0                        # wyłącza Display C-states (stabilność GPU)
mem_sleep_default=s2idle                # wymusza s2idle zamiast deep sleep
```

Backup oryginalnego `/etc/default/grub` jest tworzony automatycznie.

### Suspend stack
Trzy komponenty razem zapewniają stabilny suspend/resume:

- **`macbook-a1708-platform-init.sh`** — blokuje d3cold i przypina power/control na urządzeniach PCIe przy starcie systemu
- **`macbook-a1708-sleep.sh`** — unloaduje `brcmfmac` przed suspendem i reloaduje po resumie; logi w `/var/log/macbook-suspend.log`
- **logind** — `HandleLidSwitch=suspend` i `HandleLidSwitchExternalPower=suspend`

> ⚠️ Przed instalacją suspend stacku usuń parametry `resume=` i `resume_offset=` z GRUB jeśli je masz — hibernate nie jest obsługiwany.

### Wi-Fi
Na kernelu 7.0+ `brcmfmac` i firmware BCM4350 są dostępne w mainline — skrypt tylko weryfikuje poprawność instalacji. Nie wymaga DKMS.

### Audio
Driver Cirrus CS8409 instalowany przez DKMS z repozytorium [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro). Skrypt automatycznie aplikuje patche dla kernela 6.17+.

### Kamera
Driver FaceTime HD instalowany przez DKMS z repozytorium [patjak/facetimehd](https://github.com/patjak/facetimehd) wraz z firmware z [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware).

### Klawiatura
Ustawia `XKBMODEL=apple` w `/etc/default/keyboard` — poprawia działanie klawiszy funkcyjnych i układu.

---

## Znane ograniczenia

- **Thunderbolt / USB-C data**: porty nie enumerują urządzeń USB bezpośrednio pod Linuxem (`security=user`, `boltctl` pusty). Do zewnętrznych dysków wymagany jest zasilany hub USB-C.
- **Lid-open wake**: otwieranie klapki nie budzi systemu — wymagane naciśnięcie przycisku zasilania lub touchpada (ograniczenie hardware A1708 pod Linuxem).
- **acpi_osi=Darwin**: nie używać — powoduje utratę klawiatury i touchpada przy starcie.

---

## Logi

- Instalacja: `/var/log/mbp-a1708-install.log`
- Suspend/resume: `/var/log/macbook-suspend.log`

---

## Źródła i podziękowania

- [buxjr311/macbookpro-a1708-ubuntu-power-guide](https://github.com/buxjr311/macbookpro-a1708-ubuntu-power-guide) — suspend stack
- [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — audio DKMS
- [patjak/facetimehd](https://github.com/patjak/facetimehd) — kamera DKMS
- [t2linux.org](https://t2linux.org) — community knowledge base

---

## Licencja

MIT
