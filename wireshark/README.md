# Wireshark profile for Wi-Fi HaLow

An 802.11ah analysis profile: S1G coloring rules, filter buttons, and S1G-aware
columns. Verified against six HaLow captures with Wireshark **4.6.8**.

Derived from the community **WLAN Pros Master** profile, with HaLow additions.
Credit for the base profile belongs to its original authors; only the S1G parts
here are new.

## Install

    cp -r "WLAN Pros - HaLow" ~/.config/wireshark/profiles/

macOS/Linux path shown. On Windows use `%APPDATA%\Wireshark\profiles\`.
Then pick it from the profile selector in Wireshark's bottom-right corner.

## What is S1G-specific

**Coloring rules**

| Rule | Filter |
|---|---|
| S1G Beacon | `wlan.fc.type_subtype == 0x31` |
| S1G NDP (Control) | `radiotap.0_len_psdu.type == 0x02` |

**Filter buttons**

| Button | Filter |
|---|---|
| `MGMT//-  S1G Beacons` | `wlan.fc.type_subtype == 0x0031` |
| `CTRL//All S1G NDP` | `radiotap.0_len_psdu.type == 0x02` |
| `ADDR//SSID WLPC-HALOW` | `wlan.ssid == "WLPC-HALOW"` |
| `ADDR//SSID halow_demo` | `wlan.ssid == "halow_demo"` |

**Columns** — `wlan.s1g.compressed_ssid`, `wlan_radio.phy`, `radiotap.s1g.rssi`,
`radiotap.s1g.bandwidth`, `radiotap.s1g.mcs`.

## Why there is only one NDP rule

A natural instinct is to color each S1G NDP subtype separately:

    radiotap.s1g.ndp.type == 0x0    # CTS
    radiotap.s1g.ndp.type == 0x1    # PS-Poll
    ...

**Those fields do not exist.** Wireshark 4.6.8 rejects them:

    Error: "radiotap.s1g.ndp.type" is not a valid protocol or protocol field.

Worse, Wireshark silently ignores a coloring rule whose filter will not compile,
so such rules look installed while doing nothing.

The reason is structural. S1G NDP control frames are captured as **zero-length
PSDUs** — a radiotap header with no MAC layer. Across all six captures,
`wlan.fc.type == 1` matches **zero frames**: every ACK, CTS and PS-Poll is an
NDP. What Wireshark exposes is `radiotap.0_len_psdu.type`, and it is a constant
`0x02` ("reserved") on all 3934 NDP frames.

The subtype is not recoverable by byte-slicing either. There are 6 undissected
bytes after the radiotap header; a bit-level analysis across 3934 NDP frames from
four captures shows **bits 0-7 constant at `0x04`**, with variance only from bit
8 upward (the RA/AID payload). Every NDP frame in these captures is a single
type, and nothing distinguishes CTS from ACK from PS-Poll.

If Wireshark gains real S1G NDP dissection, splitting this one rule back into
seven is a straight substitution.

## Verified match counts

| Capture | S1G Beacon | S1G NDP |
|---|---|---|
| Full-HALOW-Capture | 1110 | 738 |
| WPA2_Assoc6171 | 5663 | 2851 |
| rasp-halow-capture | 126 | — |

All 170 filters in the profile compile cleanly.

## Not included

`80211_keys` and `recent` are deliberately absent. The first holds WPA
decryption passphrases and the second holds local paths and session state.
Both are listed in the repo `.gitignore` so they cannot be committed by
accident. Add your own keys in Wireshark under
**Preferences → Protocols → IEEE 802.11 → Decryption keys**.

## A note on validating filters yourself

`dfilter_buttons` is a UAT file, and Wireshark escapes double quotes in it as
`\x22`. Feeding the raw line to `dftest` reports a false failure, because the
parser sees a literal backslash:

    wlan.ssid == \x22WLPC-HALOW\x22      <- as stored on disk
    wlan.ssid == "WLPC-HALOW"            <- what Wireshark actually compiles

Unescape before validating, or test through a `dfilter_macros` entry, which does
go through the real UAT loader.
