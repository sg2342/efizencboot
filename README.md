# efizencboot

boot (a number of) FreeBSD systems that have encrypted ZFS pools from the
same USB stick while using UEFI Secure Boot.

https://freebsdfoundation.org/freebsd-uefi-secure-boot describes how to
create a FreeBSD loader with embedded memory disk and sign it for UEFI
Secure Boot.

In addition, we embedded a memory disk with a minimal user-land (only rescue)
within the kernel. The `/etc/rc` script will identify the system based on
its `smbios.uuid`, import the ZFS pool, load the ZFS keys and then change
the root file system to the encrypted pool (using `reboot -r`).

# Prerequisites

- FreeBSD 13.0-CURRENT
- git repo with FreeBSD source tree
- PkgBase (see https://wiki.freebsd.org/PkgBase)

# Step By Step Instructions

## create efi loader binary
```sh
doas ./build.sh
```

## sign it
```sh
uefisign -k mycert.key -c mycert.pem -o BOOTX64.efi -v _build/BOOTX64.efi
```
