#!/usr/bin/env bash
# Morse Micro sniffer capture, following Morse app note APPNOTE-36.
# https://docs.morsemicro.com/application-notes/appnote-36-how-to-do-a-sniffer-capture
#
# NOT VERIFIED against hardware - written from the app note and driver sources.
#
# THE THING THAT CATCHES PEOPLE: you capture from morse0, not from the monitor
# interface, and morse0 only exists if the driver was built with
# CONFIG_MORSE_MONITOR=y. Kconfig defaults that to n.
#
# Usage:  bash monitor.sh [freq_kHz] [op_bw_mhz] [pri_bw_mhz] [pri_chan_idx]
#         bash monitor.sh 908000 8 2 0     # 908 MHz, 8 MHz op, 2 MHz primary
set -euo pipefail

FREQ_KHZ="${1:-908000}"
OP_BW="${2:-8}"
PRI_BW="${3:-2}"
PRI_IDX="${4:-0}"
MON="${MON:-mon0}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Do not run with sudo; it calls sudo where needed."
lsmod | grep -q '^morse' || die "morse driver not loaded. Run setup.sh first."
command -v morse_cli >/dev/null || die "morse_cli not found. Run station.sh first."

say "Locating the Morse radio"
NETDEV=""
for n in /sys/class/net/*; do
    [ -e "$n/device/driver" ] || continue
    if [ "$(basename "$(readlink -f "$n/device/driver")")" = "morse" ]; then
        NETDEV="$(basename "$n")"; break
    fi
done
[ -n "$NETDEV" ] || die "No netdev bound to the morse driver."
PHY="$(basename "$(readlink -f "/sys/class/net/$NETDEV/phy80211")")"
echo "  netdev: $NETDEV    phy: $PHY"

CAPDEV=""
for n in /sys/class/net/*; do
    case "$(basename "$n")" in morse*) CAPDEV="$(basename "$n")" ;; esac
done
if [ -z "$CAPDEV" ]; then
    die "No morse0 interface.

       Captures come from morse0, not from the monitor interface, and morse0
       only exists when the driver is built with CONFIG_MORSE_MONITOR=y.
       Kconfig defaults it to n, so a stock build silently cannot sniff:

           config MORSE_MONITOR
               bool \"Monitor mode support\"
               default n

       setup.sh in this repo sets it. Rebuild, then check:
           ls -d /sys/class/net/morse*"
fi
echo "  capture interface: $CAPDEV"

say "Creating monitor interface $MON on $PHY"
sudo iw dev "$MON" del 2>/dev/null || true
sudo iw dev "$NETDEV" del 2>/dev/null || true
sudo iw phy "$PHY" interface add "$MON" type monitor \
    || die "Could not add monitor interface on $PHY"
sudo ip link set "$MON" up
sudo ip link set "$CAPDEV" up

say "Setting channel via morse_cli"
# Unlike the NRC7292 (iw, with a mapped 2.4 GHz frequency), morse_cli takes the
# real sub-GHz frequency in kHz.
echo "  freq=${FREQ_KHZ}kHz op_bw=${OP_BW}MHz pri_bw=${PRI_BW}MHz pri_idx=${PRI_IDX}"
sudo morse_cli -i "$MON" channel -c "$FREQ_KHZ" -o "$OP_BW" -p "$PRI_BW" -n "$PRI_IDX" \
    || die "morse_cli channel failed - is that frequency legal for your region?"

say "Result"
iw dev "$MON" info 2>/dev/null | grep -E "type|channel" || true
sudo morse_cli -i "$MON" channel 2>/dev/null || true

cat <<EOF

Capture from ${CAPDEV} (NOT ${MON}):

    sudo tcpdump -i ${CAPDEV} -w capture.pcap

Stream to Wireshark on a workstation (run this on the WORKSTATION):

    ssh ${USER}@<this-host> 'sudo tcpdump -i ${CAPDEV} -U -w -' \\
      | /Applications/Wireshark.app/Contents/MacOS/Wireshark -k -i -

Or Wireshark's sshdump extcap (Capture > Options > SSH remote capture) with the
remote interface set to ${CAPDEV} - that is what the app note recommends.

EOF
