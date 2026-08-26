# Vendored artifacts

Copies of files that are hard or impossible to obtain from their original
sources. Kept here so this repo stays usable if the upstreams disappear — which
is not hypothetical: ALFA's `downloads.alfa.com.tw` no longer resolves, and the
SharePoint link Newracom posted for the corrected board file now returns 403.

Full mirror of the package, with history: **https://github.com/shark-fi/nrc7292_sw_pkg**
(fork of [craigpeacock/nrc7292_sw_pkg](https://github.com/craigpeacock/nrc7292_sw_pkg),
itself a fork of [newracom/nrc7292_sw_pkg](https://github.com/newracom/nrc7292_sw_pkg)).

## Files

| File | Size | What it is |
|---|---|---|
| `nrc7292_bd.dat` | 2128 | **Board data file for the ALFA AHPI7292S.** The hard one. |
| `nrc7292_cspi.bin` | 342732 | NRC7292 CSPI firmware |
| `newracom_for_5.16_or_later.dts` | — | Device tree overlay for kernel 5.16+ |
| `newracom.dts` | — | Device tree overlay for older kernels |
| `LICENSE` | — | GPLv2, from the upstream package |

Checksums in `SHA256SUMS`. The board file is also `md5 bbe184e9b5212cddcc520cd0ef7e0cd2`.

## Why the board file matters

It carries the RF calibration and per-region regulatory limits for the specific
board, and the driver validates a target-version field in it. There are three
versions in circulation and only one works on an AHPI7292S:

| Source | Size | Result |
|---|---|---|
| ALFA's old Pi image | 562 | Rejected — `BD file is invalid! Stop loading FW`; HW version field missing and subsequent bytes offset |
| `newracom/nrc7292_sw_pkg` (EVK) | 2104 | Rejected — target-version field is the EVK's, not the AHPI7292S's |
| **This file** | **2128** | Works |

Newracom's position, from
[issue #60](https://github.com/newracom/nrc7292_sw_pkg/issues/60#issuecomment-1416150132):
the board file is the module manufacturer's responsibility and they supplied a
corrected one only as a one-off courtesy. ALFA has not published a working
replacement, and their download host is gone.

## Licensing

The upstream package is GPLv2 (`LICENSE`); the driver declares
`MODULE_LICENSE("Dual BSD/GPL")`. Redistribution is permitted with the license
preserved, which is why `LICENSE` sits alongside these files.

`nrc7292_bd.dat` and `nrc7292_cspi.bin` are binary blobs from Newracom whose
terms are not separately stated in the package. They are redistributed here on
the same basis they are distributed in the upstream repository. If you are
Newracom or ALFA and want them removed, open an issue.

## Use

`setup.sh` installs these via the package's own `update.sh`. Use these copies
only to repair a bad install:

    cp nrc7292_bd.dat nrc7292_cspi.bin ~/nrc_pkg/sw/firmware/
    md5sum ~/nrc_pkg/sw/firmware/nrc7292_bd.dat   # bbe184e9b5212cddcc520cd0ef7e0cd2
