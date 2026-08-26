# Headers package can't build out-of-tree modules: missing Module.symvers, and /usr/include conflicts with linux-libc-dev

## Summary

`wlanpi-kernel-headers-*` cannot be used to build out-of-tree kernel modules.
Two independent defects, both in `build-kernel.sh`:

1. **`Module.symvers` is never copied into the package.** With
   `CONFIG_MODVERSIONS=y` and `CONFIG_MODULE_FORCE_LOAD` unset (how the WLAN Pi
   kernels are configured), modules build but cannot be loaded.
2. **`headers_install` puts UAPI headers in `/usr/include`**, which collides
   with `linux-libc-dev`, so on trixie the package fails to install at all.

Hit while building the Morse Micro HaLow driver for an MM8108 USB adapter, but
this affects any out-of-tree module or DKMS package.

## Root cause

`build-kernel.sh` L310-328:

```bash
310	    # Prepare kernel headers
316	    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
317	        INSTALL_HDR_PATH="$VARIANT_HEADERS_DIR/usr" \
318	        headers_install                                    # <-- defect 2
319
320	    cp -a "include" "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
321	    cp -a "arch/$ARCH/include" "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/arch/"
322	    cp Makefile "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
323	    cp .config "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
324	    cp -a scripts "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
                                                                   # <-- defect 1: no Module.symvers
```

## Defect 1 — missing Module.symvers

Verified in the shipped artefact
(`wlanpi-kernel-headers-bookworm-v8` `6.12.67-v8-wlanpi+-20260201`):

```
$ dpkg-deb -c wlanpi-kernel-headers-bookworm-v8_6.12.67-v8-wlanpi+-20260201_arm64.deb | grep -c symvers
0

$ grep -E "^CONFIG_MODVERSIONS|^# CONFIG_MODULE_FORCE_LOAD" \
    usr/src/linux-headers-6.12.67-v8-wlanpi+/.config
CONFIG_MODVERSIONS=y
# CONFIG_MODULE_FORCE_LOAD is not set
```

Same on `wlanpi-kernel-headers-trixie-v8` `7.1.2-v8-wlanpi+-20260710`
(`CONFIG_MODVERSIONS=y`) and on `-bookworm-v8` `6.12.70-...-20260215`.

Without `Module.symvers`, modpost emits `Symbol version dump "Module.symvers"
is missing`, the resulting `.ko` has no `__versions` section, and a
`CONFIG_MODVERSIONS=y` kernel rejects it with `no symbol version for
module_layout`. Because `CONFIG_MODULE_FORCE_LOAD` is not enabled,
`modprobe --force` cannot work around it either.

Raspberry Pi OS ships it, which is why out-of-tree builds work there:

```
$ dpkg-deb -c linux-headers-6.12.96+rpt-rpi-v8_6.12.96-1+rpt1_arm64.deb | grep symvers
./usr/src/linux-headers-6.12.96+rpt-rpi-v8/Module.symvers
```

## Defect 2 — /usr/include collides with linux-libc-dev

The `headers_install` at L316-318 installs 965 files under `/usr/include`:

```
$ sudo apt install wlanpi-kernel-headers-trixie-v8
Unpacking wlanpi-kernel-headers-trixie-v8 (7.1.2-v8-wlanpi+-20260710) ...
dpkg: error processing archive ... (--unpack):
 trying to overwrite '/usr/include/asm-generic/auxvec.h', which is also in package linux-libc-dev (1:6.18.34-1+rpt1)
```

Those headers belong to `linux-libc-dev`. A kernel headers package should ship
only `/usr/src/linux-headers-<rel>/` plus the `/lib/modules/<rel>/build`
symlink. Working around it with `--force-overwrite` would replace the system's
6.18 UAPI headers with 7.1 ones, affecting unrelated userspace builds.

## Suggested patch

```diff
-    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
-        INSTALL_HDR_PATH="$VARIANT_HEADERS_DIR/usr" \
-        headers_install
-
     cp -a "include" "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
     cp -a "arch/$ARCH/include" "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/arch/"
     cp Makefile "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
     cp .config "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
+    cp Module.symvers "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
     cp -a scripts "$VARIANT_HEADERS_DIR/usr/src/linux-headers-$KERNEL_VERSION/"
```

Everything else in the package looks right: the tree is complete
(`.config`, `include/generated/autoconf.h`, `scripts/`), the prebuilt
`scripts/basic/fixdep` and `scripts/mod/modpost` are correctly aarch64 rather
than host binaries, and the postinst fixes the `build` symlink properly.

## Minor: dangling build symlink

The kernel package installs `/lib/modules/<rel>/build` pointing into the CI
runner's workspace (`/home/runner/work/wlanpi-kernel/wlanpi-kernel/linux` on
trixie, `.../cache/kernel` on the bullseye package). When the headers package
isn't installed this is a dangling symlink, which is worse than absent —
`ls -d` and similar checks report it as present. Consider leaving it to the
headers package's postinst to create.

## Suggestion for later

Once the tree is on 7.3+, enabling `CONFIG_MM81X_USB` / `CONFIG_MM81X_SDIO`
(mainline `drivers/net/wireless/morsemicro/mm81x`, merged for 7.3) would give
Wi-Fi HaLow support in-tree, with firmware already in linux-firmware under
`morsemicro/mm81x/`. That removes the need to build this particular driver
out-of-tree at all.

## Verification

Build any out-of-tree module against the headers package and try to load it.
Alternatively:

```
dpkg-deb -c <headers deb> | grep -E "symvers|/usr/include/" | head
```
