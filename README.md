# Wi-Fi HaLow on Raspberry Pi

Working notes and scripts for getting 802.11ah (Wi-Fi HaLow) radios running on
Raspberry Pi hardware, including monitor-mode capture into Wireshark.

Two radios are covered. They share nothing — different chipsets, different
drivers, different constraints.

| Radio | Chip | Bus | Status |
|---|---|---|---|
| [ALFA AHPI7292S](nrc7292/) | Newracom NRC7292 | SPI (40-pin HAT) | **Verified working** — associates, monitor mode captures S1G beacons |
| [Morse MM8108-EKH19](mm8108/) | Morse Micro MM8108 | USB | Scripted, **not yet verified end to end** |

A [Wireshark profile](wireshark/) for analysing the captures is included: S1G
coloring rules, filter buttons and S1G-aware columns, verified against six HaLow
captures.

## Read this first

**Use stock Raspberry Pi OS, not WLAN Pi OS.** WLAN Pi's kernel headers packages
ship no `Module.symvers`, and their kernels are built `CONFIG_MODVERSIONS=y` with
`CONFIG_MODULE_FORCE_LOAD` off. Out-of-tree modules build fine and then refuse to
load with `no symbol version for module_layout`, and `modprobe --force` cannot
override it. This affects every WLAN Pi release checked (bullseye has no headers
package at all). See [notes/wlanpi-kernel-headers.md](notes/wlanpi-kernel-headers.md)
for the evidence and a patch.

**Pick the image to match the driver, not the other way round.** Neither of these
drivers tracks current kernels, and picking the wrong image wastes a lot of time:

| Image | Kernel | Notes |
|---|---|---|
| Raspberry Pi OS **bookworm** (`2024-11-19`) | 6.6.51 | What the NRC7292 path below is verified on |
| Raspberry Pi OS **trixie** (`2026-06-19`) | 6.18.39 | NRC7292 fork's `master` targets this |

Bookworm images live under `raspios_lite_arm64/images/` by date. Once trixie
became stable, `raspios_oldstable_lite_arm64` started pointing at bookworm — but
its *older* dated directories contain bullseye, because the "oldstable" label
tracked whatever was oldstable at build time. Check the filename, not the path.

## The Morse driver is going mainline

`drivers/net/wireless/morsemicro/mm81x` was merged for **Linux 7.3** (commit
`b1906cea0`, 2026-07-08, after the v7.2 merge window). It is in no released
kernel yet — not 7.1, not 7.2. Once distributions ship 7.3+, MM8108 support
becomes `CONFIG_MM81X_USB=m` with firmware already in linux-firmware under
`morsemicro/mm81x/`, and the out-of-tree build in [mm8108/](mm8108/) becomes
unnecessary. The Newracom NRC7292 has no mainline driver and no prospect of one.

## Mirrors

The upstream situation for the NRC7292 is fragile — ALFA's download host is gone
and Newracom's link to the working board file is dead — so the package is
mirrored:

- **[shark-fi/nrc7292_sw_pkg](https://github.com/shark-fi/nrc7292_sw_pkg)** —
  full fork with history, of
  [craigpeacock/nrc7292_sw_pkg](https://github.com/craigpeacock/nrc7292_sw_pkg)
- **[nrc7292/vendor/](nrc7292/vendor/)** — the irreplaceable artifacts on their
  own (AHPI7292S board file, firmware, overlays, GPLv2 license)

## Layout

```
nrc7292/   ALFA AHPI7292S - setup, monitor mode, vendored blobs
mm8108/    Morse MM8108 USB dongle - setup, station mode
wireshark/ Wireshark profile for 802.11ah analysis
notes/     Kernel packaging defects, compatibility research
```
