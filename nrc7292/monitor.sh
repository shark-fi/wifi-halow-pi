#!/usr/bin/env bash
# Put the NRC7292 into monitor mode on a given frequency.
#
# start.py's sniffer mode (sta_type 2) does this correctly but then launches the
# Wireshark GUI, which is no use on a headless Lite install. This does the setup
# and stops.
#
# Usage:  bash monitor.sh [freq_mhz]     default 2447
#
# NOTE: the driver registers S1G channels into a fake 2.4 GHz band so the
# kernel's regulatory code accepts them, so iw takes 2.4 GHz frequencies while
# radiotap reports the real sub-GHz one. 2447 (fake ch 8) = 905.5 MHz, US S1G
# channel 7. Always confirm from the radiotap frequency in the capture.
set -euo pipefail

FREQ="${1:-2447}"
IFACE="${IFACE:-wlan0}"
DRV=~/nrc_pkg/sw/driver/nrc.ko

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$DRV" ] || die "No driver at $DRV - run setup.sh first"

say "Clearing any supplicant holding $IFACE"
sudo killall wpa_supplicant 2>/dev/null || true
sudo rmmod nrc 2>/dev/null || true

say "Loading driver"
sudo modprobe mac80211
sudo insmod "$DRV" fw_name=uni_s1g.bin bd_name=nrc7292_bd.dat
sleep 2
[ -d "/sys/class/net/$IFACE" ] || die "$IFACE did not appear - check dmesg | grep -i nrc"

say "Monitor mode on $IFACE"
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up
sudo iw reg set "${COUNTRY:-US}"
sudo iw dev "$IFACE" set freq "$FREQ"

say "Result"
iw dev "$IFACE" info | grep -E "type|channel|txpower"

cat <<EOF

Capture locally:

    sudo tcpdump -i $IFACE -e -c 20

Stream to Wireshark on a workstation (run THIS on the workstation, not the Pi):

    ssh $USER@\$(hostname -I | awk '{print \$1}') 'sudo tcpdump -i $IFACE -U -w -' \\
      | /Applications/Wireshark.app/Contents/MacOS/Wireshark -k -i -

For an unattended pipe, allow passwordless tcpdump and use an SSH key:

    echo "$USER ALL=(root) NOPASSWD: \$(command -v tcpdump)" | sudo tee /etc/sudoers.d/010_tcpdump
    # then, from the workstation:  ssh-copy-id $USER@<pi>

tcpdump prints S1G Beacons as "unknown 802.11 frame type (3)" - that is the
802.11 Extension type and tcpdump cannot decode it. Wireshark 4.6 can.

EOF
