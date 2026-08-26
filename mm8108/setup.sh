#!/usr/bin/env bash
# Morse Micro MM8108 (EKH19 USB dongle) driver + firmware.
# NOT VERIFIED END TO END - see README.md.
set -euo pipefail

DRIVER_REF="mm8108-2.0.0"
FW_REF="2.0"
WORKDIR="${HOME}/halow-morse"
KSRC="${KSRC:-/lib/modules/$(uname -r)/build}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m    %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

say "Preflight"
[ "$(id -u)" -ne 0 ] || die "Do not run with sudo."
KREL="$(uname -r)"; KMAJ="${KREL%%.*}"; KMIN="$(echo "$KREL" | cut -d. -f2)"
echo "kernel: $KREL"

[ -d "$KSRC" ] || die "No kernel headers at $KSRC."
[ -f "$KSRC/Module.symvers" ] || die "$KSRC/Module.symvers is missing.
       The module will build but not load. Use stock Raspberry Pi OS.
       See notes/wlanpi-kernel-headers.md"
echo "hdrs  : OK"

lsusb -d 325b: || die "No Morse device on USB (expecting 325b:8100)."

if [ "$KMAJ" -gt 6 ] 2>/dev/null || { [ "$KMAJ" -eq 6 ] && [ "$KMIN" -gt 18 ]; } 2>/dev/null; then
    warn "Kernel $KREL is past this driver's ceiling: compat.h stops at 6.18"
    warn "and there is no KERNEL_VERSION(7,...) anywhere in the tree."
    sleep 4
fi

say "Installing dependencies"
sudo apt-get update -qq
sudo apt-get install -y build-essential git bc libnl-3-dev libnl-genl-3-dev \
    libssl-dev pkg-config

mkdir -p "$WORKDIR"; cd "$WORKDIR"

say "Cloning morse_driver @ $DRIVER_REF (--recursive required)"
if [ -d morse_driver/.git ]; then
    git -C morse_driver fetch --tags --quiet
    git -C morse_driver checkout --quiet "$DRIVER_REF"
    git -C morse_driver submodule update --init --recursive --quiet
else
    rm -rf morse_driver
    git clone --recursive --quiet -b "$DRIVER_REF" \
        https://github.com/MorseMicro/morse_driver.git
fi
cd morse_driver
[ -n "$(ls -A mmrc-submodule 2>/dev/null)" ] \
    || die "mmrc-submodule is empty. git submodule update --init --recursive"

MAKE_ARGS=(
    MORSE_TRACE_PATH="$(pwd)" KERNEL_SRC="$KSRC"
    CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_USB=y
    CONFIG_MORSE_USER_ACCESS=y CONFIG_MORSE_VENDOR_COMMAND=y
    CONFIG_MORSE_DEBUGFS=y
)

say "Building driver"
make clean >/dev/null 2>&1 || true
if ! make "${MAKE_ARGS[@]}" 2>&1 | tee /tmp/morse-build.log; then
    warn "Retrying with -Werror demoted (the Makefile hardcodes -Wall -Werror)"
    make clean >/dev/null 2>&1 || true
    make "${MAKE_ARGS[@]}" KCFLAGS=-Wno-error 2>&1 | tee /tmp/morse-build.log \
        || die "Build failed - see /tmp/morse-build.log"
fi

DOT11AH_KO="$(find . -name 'dot11ah.ko' -print -quit)"
MORSE_KO="$(find . -maxdepth 1 -name 'morse.ko' -print -quit)"
[ -n "$DOT11AH_KO" ] && [ -n "$MORSE_KO" ] || die "modules not produced"

say "Installing firmware + BCFs (morse-firmware @ $FW_REF)"
cd "$WORKDIR"
if [ -d morse-firmware/.git ]; then
    git -C morse-firmware fetch --quiet
    git -C morse-firmware checkout --quiet "$FW_REF"
    git -C morse-firmware pull --quiet
else
    rm -rf morse-firmware
    git clone --quiet -b "$FW_REF" https://github.com/MorseMicro/morse-firmware.git
fi
sudo make -C morse-firmware install
ls -1 /lib/firmware/morse/ | grep -E 'mm8108|mf15457' || die "MM8108 firmware missing"

say "Loading modules (dot11ah before morse)"
sudo modprobe mac80211
sudo rmmod morse 2>/dev/null || true
sudo rmmod dot11ah 2>/dev/null || true
cd "$WORKDIR/morse_driver"
sudo insmod "$DOT11AH_KO"
sudo insmod "$MORSE_KO"

sudo dmesg | tail -30
iw dev || true

cat <<'EOF'

If the wrong board config was selected:

    sudo rmmod morse && sudo insmod morse.ko bcf=bcf_mf15457.bin

Next: bash station.sh

EOF
