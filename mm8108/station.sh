#!/usr/bin/env bash
# MM8108 station mode: morse_cli + S1G wpa_supplicant.
# NOT VERIFIED END TO END - see README.md. Run setup.sh first.
set -euo pipefail

HOSTAP_REF="mm8108-2.0"
CLI_REF="mm8108-2.0.0"
WORKDIR="${HOME}/halow-morse"
CONF="/etc/wpa_supplicant/wpa_supplicant-s1g.conf"
WPAS_BIN="/usr/local/sbin/wpa_supplicant_s1g"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Do not run with sudo."
lsmod | grep -q '^morse' || die "morse driver not loaded. Run setup.sh first."

# Find the netdev owned by morse - do not assume wlan0.
HALOW_IF=""
for n in /sys/class/net/*; do
    [ -e "$n/device/driver" ] || continue
    [ "$(basename "$(readlink -f "$n/device/driver")")" = "morse" ] && { HALOW_IF="$(basename "$n")"; break; }
done
[ -n "$HALOW_IF" ] || die "No netdev bound to morse."
say "HaLow interface: $HALOW_IF"

sudo apt-get update -qq
sudo apt-get install -y build-essential git pkg-config libnl-3-dev \
    libnl-genl-3-dev libnl-route-3-dev libssl-dev libusb-1.0-0-dev

mkdir -p "$WORKDIR"; cd "$WORKDIR"

say "Building morse_cli @ $CLI_REF"
[ -d morse_cli/.git ] || git clone --quiet -b "$CLI_REF" https://github.com/MorseMicro/morse_cli.git
make -C morse_cli all && sudo make -C morse_cli install

say "Building S1G wpa_supplicant (hostap @ $HOSTAP_REF)"
[ -d hostap/.git ] || git clone --quiet -b "$HOSTAP_REF" https://github.com/MorseMicro/hostap.git
cd hostap/wpa_supplicant
cp -f defconfig .config
for opt in CONFIG_IEEE80211AH=y CONFIG_DRIVER_NL80211_MORSE=y CONFIG_SAE=y; do
    grep -qx "$opt" .config || die "defconfig missing $opt - wrong branch?"
done
make -j"$(nproc)"

# Distinct name: the distro wpa_supplicant manages this box's other radios.
sudo install -m 0755 ./wpa_supplicant "$WPAS_BIN"
sudo install -m 0755 ./wpa_cli /usr/local/bin/wpa_cli_s1g

if [ ! -f "$CONF" ]; then
    sudo mkdir -p /etc/wpa_supplicant
    sudo tee "$CONF" >/dev/null <<'EOF'
ctrl_interface=/var/run/wpa_supplicant_s1g
update_config=1
country=US

network={
    ssid="CHANGEME"
    # HaLow requires WPA3-SAE (or OWE). Plain WPA2-PSK is not valid on S1G.
    key_mgmt=SAE
    sae_password="CHANGEME"
    ieee80211w=2
    proto=RSN
    pairwise=CCMP
    group=CCMP
}
EOF
    sudo chmod 600 "$CONF"
fi

cat <<EOF

Edit $CONF, then:

    morse_cli -i $HALOW_IF version
    morse_cli -i $HALOW_IF channel
    sudo $WPAS_BIN -i $HALOW_IF -c $CONF -d
    sudo dhclient $HALOW_IF

Scan output reports S1G channels in 5 GHz numbering
(CONFIG_MORSE_5GHZ_MAPPED). 'morse_cli -i $HALOW_IF channel' shows the real one.

EOF
