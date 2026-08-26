# Morse Micro MM8108 (EKH19 USB dongle)

> **Status: scripted but not verified end to end.** The scripts below were
> written against the sources and package contents but never run to a working
> link — the WLAN Pi hardware they were aimed at was blocked by the kernel
> headers defect, and effort moved to the NRC7292. Treat them as a starting
> point, not a known-good recipe.

USB ID `325b:8100`. Unlike the NRC7292, this chip has a mainline future.

## Prefer mainline if you can wait

`drivers/net/wireless/morsemicro/mm81x` was merged for **Linux 7.3** (commit
`b1906cea0`, 2026-07-08). It is in no released kernel yet — checked against v7.1,
v7.2-rc1 and v7.2, none contain it. Once 7.3 ships:

- `CONFIG_MM81X_USB=m` gives you `mm81x_core` / `mm81x_usb`
- the USB table binds exactly `{0x325b, 0x8100}`
- firmware comes from linux-firmware at `morsemicro/mm81x/v56/`
- the board config is auto-selected from the chip's own board ID as
  `bcf_boardtype_%04x.bin`

At that point nothing below is needed.

## Out-of-tree build (pre-7.3)

Version pairing is the main trap. For MM8108:

| Component | Repo | Ref |
|---|---|---|
| Driver | `MorseMicro/morse_driver` | tag `mm8108-2.0.0` |
| Firmware + BCF | `MorseMicro/morse-firmware` | branch `2.0` |
| wpa_supplicant | `MorseMicro/hostap` | branch `mm8108-2.0` |
| `morse_cli` | `MorseMicro/morse_cli` | tag `mm8108-2.0.0` |

Use **`morse-firmware`**, not `firmware_binaries` — the latter only ships
`mm6108.bin` and stops at v1.15.3. `morse-firmware` carries `mm8108b2-rl.bin`
and per-vendor BCFs; the EKH19 is MF15457-based, so `bcf_mf15457.bin`.

    bash setup.sh      # driver + firmware
    bash station.sh    # morse_cli + S1G wpa_supplicant

### Notes

- `--recursive` is mandatory when cloning `morse_driver` — there is an
  `mmrc-submodule` rate-control dependency and the build fails cryptically
  without it.
- Load order is `dot11ah.ko` **before** `morse.ko`. Wrong order fails silently.
- The Makefile hardcodes `-Wall -Werror`, which trips on newer GCC. `setup.sh`
  retries with `KCFLAGS=-Wno-error`.
- `compat.h` has shims through kernel **6.18** and no 7.x awareness at all.
- USB support is MM8108-only: `usb.c` defines `MORSE_MM610X_PRODUCT_ID 0x6100`
  but registers only `0x8100`, so an MM6108 USB device will not bind unpatched.
- Unlike SDIO and SPI, the USB path needs **no device tree work**.

## Station mode

`station.sh` installs wpa_supplicant as `/usr/local/sbin/wpa_supplicant_s1g`
rather than overwriting the system one — on a box with other radios, clobbering
it breaks normal Wi-Fi.

Wi-Fi HaLow requires **WPA3-SAE** (or OWE for open networks); plain WPA2-PSK is
not valid on S1G. The generated config uses `key_mgmt=SAE`.

Morse's `wpa_supplicant/defconfig` already enables everything needed —
`CONFIG_IEEE80211AH`, `CONFIG_S1G_TWT`, `CONFIG_DRIVER_NL80211_MORSE`,
`CONFIG_SAE` — so the build is `cp defconfig .config && make`.

The defconfig also sets `CONFIG_MORSE_5GHZ_MAPPED`, so scan output reports S1G
channels in **5 GHz** numbering (the NRC7292 driver uses a 2.4 GHz mapping for
the same reason). Use `morse_cli -i <iface> channel` for the real S1G channel.

## Monitor mode / sniffer capture

Follows Morse [APPNOTE-36](https://docs.morsemicro.com/application-notes/appnote-36-how-to-do-a-sniffer-capture).
Run [`monitor.sh`](monitor.sh).

Two things are easy to get wrong.

**You capture from `morse0`, not from the monitor interface.** The monitor
interface (`mon0`) is created and used to set the channel, but the packets come
off `morse0`. That is unintuitive and is the single most common way this fails.

**`morse0` only exists if the driver was built with `CONFIG_MORSE_MONITOR=y`,
and Kconfig defaults it to `n`:**

```
config MORSE_MONITOR
	bool "Monitor mode support"
	default n
```

With the flag unset, `monitor.o` is never compiled (`morse-$(CONFIG_MORSE_MONITOR) += monitor.o`)
and `alloc_netdev(0, "morse%d", ...)` in `monitor.c` never runs — so the driver
loads, associates, and simply has no capture interface. `setup.sh` in this repo
sets the flag; a stock build will not.

### Channel selection

`morse_cli` takes the **real sub-GHz frequency in kHz**, unlike the NRC7292
where you set a mapped 2.4 GHz frequency through `iw`:

    morse_cli -i mon0 channel -c 908000 -o 8 -p 2 -n 0

`-c` frequency (kHz), `-o` operating bandwidth (MHz), `-p` primary bandwidth
(MHz), `-n` primary channel index.

### Capture

    sudo tcpdump -i morse0 -w capture.pcap

The app note recommends Wireshark's **sshdump** extcap for remote capture, with
the remote interface set to `morse0`. The Wireshark profile in
[../wireshark/](../wireshark/) already has sshdump settings; point
`extcap.sshdump.remotecapturecommand` at `morse0` when using the Morse radio
rather than the NRC7292's `wlan0`.
