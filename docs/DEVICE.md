# Tested device

- Device: Anbernic RG40xx H
- SoC/GPU: Allwinner H700 / Mali-G31
- Architecture: aarch64
- Firmware: muOS 2508.4 LOOSE GOOSE
- Rendering: fbdev + EGL/GLES through the custom WPE backend
- Current DHCP address during 2026-07-15 validation: `192.168.1.116`

The IP is not a permanent device identifier and may change after reboot. Override
it when invoking `scripts/deploy.sh` or `scripts/import-device-devlibs.sh`.

Device paths:

- Port launcher: `/mnt/union/ROMS/Ports/Moonrider.sh`
- Port data: `/mnt/sdcard/ports/moonrider/`
- Diagnostics: `/mnt/mmc/moonrider-diag.log`
- Controller: `/mnt/mmc/mr-ctl.sh`
- Known-good desktop-export backup: `/mnt/mmc/moonrider-old-backup-20260715/`
