# MacBook Pro A1708 — Ubuntu Installer

A modular setup script for Ubuntu on the MacBook Pro 13" 2017 (A1708 / MacBookPro14,1).

Tested on **Ubuntu 26.04 / kernel 7.0**.

---

## Hardware Support

| Component | Model | Status |
|-----------|-------|--------|
| CPU/GPU | Intel Kaby Lake + Intel Iris Plus 640 | works out of the box |
| Wi-Fi | Broadcom BCM4350 (brcmfmac) | works out of the box (kernel 7.0+) |
| Audio | Cirrus Logic CS8409 | DKMS (davidjo/snd_hda_macbookpro) |
| Camera | FaceTime HD | DKMS (patjak/facetimehd) |
| Keyboard / Touchpad | Apple SPI | works out of the box (applespi) |
| Suspend (s2idle) | | requires configuration |
| Thunderbolt / USB-C data | Intel Alpine Ridge | works with thunderbolt.security=none |

---

## Quick Start

    git clone https://github.com/a1708ubuntu/mbp-a1708-ubuntu
    cd mbp-a1708-ubuntu
    sudo bash install-mbp-a1708.sh

The script detects the model (MacBookPro14,1) and asks about each module individually.

---

## Modules

### Kernel parameters

Sets GRUB parameters required for stable operation:

    nvme_core.default_ps_max_latency_us=0  # NVMe stability
    nvme.noacpi=1                           # disable ACPI power management for NVMe
    pci=noaer                               # suppress PCIe AER errors
    i915.enable_dc=0                        # disable Display C-states
    mem_sleep_default=s2idle                # force s2idle instead of deep sleep
    thunderbolt.security=none               # enable direct USB-C device enumeration

A backup of the original /etc/default/grub is created automatically.

NOTE: Remove any resume= and resume_offset= parameters from GRUB before running
the installer — hibernate is not supported.

### Suspend stack

Three components together provide stable suspend/resume:

- macbook-a1708-platform-init.sh — disables d3cold and pins power/control on PCIe
  devices at boot; runs as a systemd oneshot service
- macbook-a1708-sleep.sh — unloads brcmfmac before suspend and reloads after
  resume; logs to /var/log/macbook-suspend.log
- logind — HandleLidSwitch=suspend and HandleLidSwitchExternalPower=suspend

### Wi-Fi

On kernel 7.0+, brcmfmac and BCM4350 firmware are available in mainline.
No DKMS required. The script verifies correct installation and removes
broadcom-sta (bcmwl) if present, as it conflicts with brcmfmac.

### Audio

Cirrus CS8409 driver installed via DKMS from davidjo/snd_hda_macbookpro.
Patches for kernel 6.17+ are applied automatically.

### Camera

FaceTime HD driver installed via DKMS from patjak/facetimehd with firmware
from patjak/facetimehd-firmware.

### Keyboard

Sets XKBMODEL=apple in /etc/default/keyboard — fixes function keys and layout.

### Dracut

Forces applespi, intel_lpss_pci, and spi_pxa2xx_platform into the initramfs
via /etc/dracut.conf.d/macbook.conf. Prevents unbootable system after kernel
updates on Ubuntu 26.04 (dracut-based).

---

## Known Limitations

- Lid-open wake: opening the lid does not wake the system — use the power
  button or touchpad (hardware limitation on A1708 under Linux).
- acpi_osi=Darwin: do not use — causes keyboard and touchpad loss at boot.
- thunderbolt.security=none disables Thunderbolt device authorization entirely.
  This is acceptable for a personal machine but be aware of the security implications.

---

## Logs

- Installation: /var/log/mbp-a1708-install.log
- Suspend/resume: /var/log/macbook-suspend.log

---

## Credits

- buxjr311/macbookpro-a1708-ubuntu-power-guide — suspend stack
- davidjo/snd_hda_macbookpro — audio DKMS
- patjak/facetimehd — camera DKMS
- t2linux.org — community knowledge base

---

## License

MIT
