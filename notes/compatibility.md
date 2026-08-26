# Compatibility research

Everything here was verified against package indexes, downloaded `.deb`
contents, and driver source — not from documentation.

## Driver kernel ceilings

Highest `KERNEL_VERSION(...)` reference anywhere in each tree:

| Driver | Ceiling | Notes |
|---|---|---|
| `MorseMicro/morse_driver` @ `mm8108-2.0.0` | **6.18** | no `KERNEL_VERSION(7,...)` anywhere |
| `newracom/nrc7292_sw_pkg` @ `v1.5.2` | **6.1** | last release Dec 2024 |
| `craigpeacock/nrc7292_sw_pkg` @ `cce7d1589` | ~6.6 | "Tested on v6.6.51" |
| `craigpeacock/nrc7292_sw_pkg` @ `master` | ~6.18 | "Tested on 6.18.34+rpt-rpi-v8" |

## Raspberry Pi OS

| Release | Kernel (Aug 2026) | 6.1 fallback available? |
|---|---|---|
| bookworm | 6.12.96 | yes — `linux-headers-6.1.0-rpi1..rpi8` |
| trixie | 6.18.39 | no |

The bookworm archive also still carries `linux-headers-6.6.20` through
`6.6.74`, so an older bookworm image can get matching headers.

Image directories are dated. `raspios_lite_arm64/images/` holds the current
release; `raspios_oldstable_lite_arm64/images/` holds the previous one — but
its older dated directories contain **bullseye**, because the label tracked
whatever was oldstable at build time. Check the filename.

Bookworm images with useful kernels:

- `2024-11-19-raspios-bookworm-arm64-lite.img.xz` → 6.6 (used here)
- `2023-12-05-raspios-bookworm-arm64-lite.img.xz` → 6.1

## WLAN Pi OS

Out-of-tree modules cannot be built on any WLAN Pi kernel checked:

| Release | Headers package | `Module.symvers` | Installs? |
|---|---|---|---|
| bullseye | none exists | — | — |
| bookworm 6.12.67 / 6.12.70 | yes | **absent** | yes |
| trixie 7.1.2 | yes | **absent** | **no** — conflicts with `linux-libc-dev` |

All those kernels are `CONFIG_MODVERSIONS=y` with `CONFIG_MODULE_FORCE_LOAD`
unset, so a module built without `Module.symvers` cannot be loaded and cannot be
forced. Raspberry Pi OS ships `Module.symvers`, which is why builds work there.

Also note the WLAN Pi kernel package installs `/lib/modules/<rel>/build` as a
symlink into the CI runner's workspace
(`/home/runner/work/wlanpi-kernel/wlanpi-kernel/linux`). It dangles unless the
headers package is installed, and `ls -d` reports a broken symlink as present —
use `[ -d ]` or check `Module.symvers` directly.

See [wlanpi-kernel-headers.md](wlanpi-kernel-headers.md).

## Morse driver in mainline

| Tag | Date | Contains `drivers/net/wireless/morsemicro`? |
|---|---|---|
| v7.1 | 2026-06-14 | no |
| v7.2-rc1 | 2026-06-28 | no |
| v7.2 | 2026-08-16 | no |
| master | — | yes |

Commit `b1906cea0` ("wifi: mm81x: add mm81x Wi-Fi HaLow driver") is dated
2026-07-08, after the v7.2 merge window closed. First release will be **7.3**.

There is no `newracom` directory under `drivers/net/wireless` — the NRC7292 has
no mainline driver.

## The AHM26108D dead end

The ALFA AHM26108D M.2 module is **SDIO + UART only** — no PCIe, no USB. On
M.2 E-key, SDIO lives on pins 9 (CLK), 11 (CMD), 13/15/17/19 (DAT0-3), 21
(WAKE#) and 23 (RESET#). Plugged into any M.2 slot fed by PCIe — which is what
CM4 carriers provide, directly or through a switch — it cannot enumerate at all.
`lspci` shows an empty downstream port and `/sys/bus/sdio/devices/` stays empty.

Driving it from a Pi needs SDIO broken out to the 40-pin header (GPIO 22-27),
which is what ALFA's APIM2 adapter is for.

## Mainline mm81x has no monitor mode

Confirmed against `drivers/net/wireless/morsemicro/mm81x` on master:

- no `monitor.c` in the tree
- `mac.c:2288` declares `interface_modes = BIT(NL80211_IFTYPE_AP) | BIT(NL80211_IFTYPE_STATION)`
- the iface combination at `mac.c:127` lists the same two types

So the in-tree driver landing in 7.3 covers station and AP but cannot sniff. The
out-of-tree driver's monitor support lives in `monitor.c`, gated on
`CONFIG_MORSE_MONITOR` (Kconfig default `n`), which is what creates the `morse0`
capture interface via `alloc_netdev(0, "morse%d", ...)`.

Practical consequence: even after 7.3, keep the out-of-tree driver for capture.
This may change in a later kernel cycle - verify against the tree you are
running by checking whether `mm81x` declares `NL80211_IFTYPE_MONITOR`:

    grep -rn 'interface_modes' drivers/net/wireless/morsemicro/mm81x/mac.c
    ls drivers/net/wireless/morsemicro/mm81x/monitor.c
