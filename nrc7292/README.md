# ALFA AHPI7292S (Newracom NRC7292)

Verified working on a Raspberry Pi CM4, Raspberry Pi OS bookworm 64-bit Lite,
kernel `6.6.51+rpt-rpi-v8`.

## Why you can't follow ALFA's documentation

ALFA's getting-started guide tells you to run:

    curl -sL https://downloads.alfa.com.tw/raspbian/nrc7292_setup.sh.txt | bash -

`downloads.alfa.com.tw` **no longer resolves**. Beyond that:

- ALFA's own `nrc7292_bd.dat` is defective — 562 bytes, rejected by the driver
  with `BD file is invalid! Stop loading FW` (the HW version field is missing and
  subsequent bytes are offset).
- Newracom posted a corrected file in
  [issue #60](https://github.com/newracom/nrc7292_sw_pkg/issues/60#issuecomment-1412633051),
  but that SharePoint link now returns 403. Newracom's position is that the board
  file is the module vendor's responsibility.
- The Newracom package's own `nrc7292_bd.dat` is the **EVK** file (2104 bytes).
  Its target-version field does not match the AHPI7292S, so the driver rejects it.
- Upstream `newracom/nrc7292_sw_pkg` stopped at v1.5.2 (Dec 2024) and does not
  build on any current kernel.

**Use [craigpeacock/nrc7292_sw_pkg](https://github.com/craigpeacock/nrc7292_sw_pkg)
instead** (mirrored at
[shark-fi/nrc7292_sw_pkg](https://github.com/shark-fi/nrc7292_sw_pkg), with the
critical files also kept in [vendor/](vendor/)). That fork ships a working 2128-byte AHPI7292S board file
(`md5 bbe184e9b5212cddcc520cd0ef7e0cd2`), a 64-bit `cli_app`, and kernel fixes.

## Which commit to build

The fork's `master` targets kernel **6.18** and will not compile on 6.6 — you get
errors about `timer_delete_sync_try`, `timer_container_of`,
`ieee80211_emulate_add_chanctx`, and a `.config` callback that gained a
`radio_idx` argument. All of those are newer-kernel APIs.

| Your kernel | Build the driver from |
|---|---|
| 6.6.x | `cce7d1589` — "Add support for v6.2. Tested on v6.6.51" |
| 6.18.x | `master` |

Take **everything else** from `master` regardless — the board file and 64-bit
`cli_app` only exist there. `setup.sh` handles this split: it runs `update.sh`
from `master`, then checks out the older commit only to build the driver.

Never re-run `update.sh` while on the old commit; it overwrites `~/nrc_pkg` with
the 2104-byte EVK board file.

## Install

    bash setup.sh          # as your normal user, NOT with sudo
    sudo reboot
    ~/nrc_pkg/script/start.py 0 0 US

## Things that will bite you

**`Unknown symbol in module`** — `start.py` uses `insmod`, which does not resolve
dependencies. The NRC driver is softmac and needs `mac80211`; the Pi's onboard
Broadcom radio is fullmac and only pulls in `cfg80211`, so `mac80211` is absent on
a fresh install. `setup.sh` loads it and adds it to `/etc/modules`.

**`start.py` crashes with `NameError: name 'script' is not defined`** — lines
780-788 reference `script+path` where the variable defined at line 7 is
`script_path`. A find-and-replace in the fork's "Remove reference to /home/pi"
commits mangled it. `setup.sh` patches it.

**`CTRL-EVENT-SCAN-FAILED ret=-16`** (EBUSY), preceded by many
`nl80211: kernel reports: Match already configured` lines — two wpa_supplicant
instances on the same interface. Raspberry Pi OS bookworm runs NetworkManager,
which claims every wireless interface and starts its own supplicant; `start.py`
launches a second. `setup.sh` marks `wlan0` unmanaged and disables the system
supplicant.

**`start.py` hardcodes `wlan0`**, which on a Pi with onboard Wi-Fi is the Broadcom
radio, not the HaLow one. `setup.sh` adds `dtoverlay=disable-wifi` — but only
after checking you are not connected over that interface.

**The default SSID is `halow_demo`.** Edit
`~/nrc_pkg/script/conf/US/sta_halow_open.conf` to match your AP.

**`iptables` is not installed** on Lite images; `start.py` calls it.

**dhcpcd and dnsmasq are absent** on bookworm (NetworkManager replaced them).
Those `start.py` failures are harmless for station mode — run `sudo dhclient wlan0`
once associated. Do not install dhcpcd; it fights NetworkManager.

## Monitor mode

`start.py 2 0 US <ch> 0` sets monitor mode correctly but then launches the
Wireshark **GUI**, which is useless on a Lite install. Use [`monitor.sh`](monitor.sh):

    bash monitor.sh 2447

Then capture remotely from a machine with Wireshark:

    ssh <user>@<pi> 'sudo tcpdump -i wlan0 -U -w -' | /Applications/Wireshark.app/Contents/MacOS/Wireshark -k -i -

Run that on the **workstation**, not on the Pi.

### Channel numbering

The driver registers S1G channels into a fake 2.4 GHz band so the kernel's
regulatory machinery accepts them. `iw` therefore takes 2.4 GHz frequencies,
while radiotap reports the true sub-GHz frequency. Setting `freq 2447`
(fake channel 8) lands on **905.5 MHz, US S1G channel 7**:

    21:13:11.184010 31810777us tsft 9055 MHz [bit 28] unknown 802.11 frame type (3)

The US table in `package/src/nrc/nrc-s1g.c` runs S1G channels 1-43 across
902.5-922.5 MHz at 1 MHz bandwidth. Confirm where you actually landed by reading
the radiotap frequency, not the number you asked for.

`unknown 802.11 frame type (3)` is tcpdump's inability to decode the 802.11
Extension frame type that S1G Beacons use. Wireshark 4.6 decodes them fine.

The vendor's `~/nrc_pkg/script/sniffer/change_channel.py` is Python 2
(`import commands`) and will not run on bookworm. Use `iw dev wlan0 set freq`.

## Raspberry Pi 5 / CM5

Not supported without patching:

1. `dts/newracom*.dts` declares compatible only through `brcm,bcm2711`; Pi 5 is
   `brcm,bcm2712`, so the overlay never applies.
2. The reset line uses the legacy integer GPIO API with a hardcoded BCM number
   (`RPI_GPIO_FOR_RST = 4` in `nrc-vendor.h`). Behind RP1 that integer does not
   map to BCM4 and needs converting to a `gpiod`/DT lookup.

The DT-declared interrupt is fine on RP1 — only the reset line and the overlay's
compatible list need work.
