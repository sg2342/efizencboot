#!/bin/sh -e
#

basedir=$(dirname "$(realpath "$0")")
obj_dir_pfx="$basedir"/_build
export MAKEOBJDIRPREFIX="$obj_dir_pfx"

src_env_conf="$basedir"/src-env.conf
export SRCCONF="$basedir"/src.conf
kern_conf_dir="$basedir"/kernel

etc_rc="$basedir"/kernel_mfs/etc_rc
loader_conf="$basedir"/loader_mfs/loader.conf

loader_patch="$basedir"/patches/efi_loader_md_image.patch

kernel_mfs_image="$obj_dir_pfx"/md0.uzip
kernel_file="$obj_dir_pfx"/kernel
loader_mfs_image="$obj_dir_pfx"/bootfs.img
loader_file="$obj_dir_pfx"/BOOTX64.efi

ncpu=$(sysctl -n hw.ncpu)
kldload filemon || true

##############################################################################
# create mfs that will be embedded in the kernel:
#   populate /rescue/* from FreeBSD-rescue pkg
#   install our /etc/rc
#   empty directories /dev /tmp and /mnt
#
kernel_mfs_image() {
    if [ -f "$kernel_mfs_image" ] ; then
        printf '> kernel mfs image "%s" exists: skip step\n' "$kernel_mfs_image"
        return 0
    fi

    scratch_d="$obj_dir_pfx"/scratch
    mkdir -p "$scratch_d"/d "$scratch_d"/p

    pkg create -o "$scratch_d" -f tar FreeBSD-rescue
    PKG_DBDIR="$scratch_d"/p \
	     pkg -r "$scratch_d"/d add -M "$scratch_d"/FreeBSD-rescue*.tar

    mkdir "$scratch_d"/d/dev \
          "$scratch_d"/d/mnt \
          "$scratch_d"/d/tmp \
          "$scratch_d"/d/etc
    cp "$etc_rc" "$scratch_d"/d/etc/rc

    makefs "$scratch_d"/img "$scratch_d"/d

    mkuzip -A zstd -o "$kernel_mfs_image" "$scratch_d"/img

    rm -rf "$scratch_d"
}

##############################################################################
# build kernel with embedded mfs
#
kernel_build () {
    if [ -f "$kernel_file" ] && [ "$kernel_file" -nt "$kernel_mfs_image" ]
    then
        printf '> kernel file "%s" exists: skip step\n' "$kernel_file"
        return 0
    fi

    env KERNCONFDIR="$kern_conf_dir" KERNCONF=ZENC \
        MFS_IMAGE="$kernel_mfs_image" \
        make -s -j"$ncpu" -C /usr/src  SRC_ENV_CONF="$src_env_conf" \
	buildkernel

    cp "$obj_dir_pfx"/usr/src/amd64.amd64/sys/ZENC/kernel "$kernel_file"

    rm -rf "${obj_dir_pfx:?}"/usr
}

##############################################################################
# create mfs that will be embedded in the loader:
#   use lua code and default config from FreeBSD-bootloader pkg
#   install loader.conf
#   install kernel
#
loader_mfs_image() {
    if [ -f "$loader_mfs_image" ] && [ "$loader_mfs_image" -nt "$kernel_file" ]
    then
        printf '> loader mfs image "%s" exists: skip step\n' "$loader_mfs_image"
        return 0
    fi

    scratch_d="$obj_dir_pfx"/scratch
    mkdir -p "$scratch_d"/d

    pkg create -o "$scratch_d" -f tar FreeBSD-bootloader
    tar -C "$scratch_d"/d -xf "$scratch_d"/FreeBSD-bootloader*.tar \
	/boot/lua /boot/defaults /boot/device.hints

    cp "$loader_conf" "$scratch_d"/d/boot/

    mkdir "$scratch_d"/d/boot/kernel
    cp "$kernel_file" "$scratch_d"/d/boot/kernel

    makefs "$loader_mfs_image" "$scratch_d"/d

    rm -rf "$scratch_d"
}

##############################################################################
# build EFI loader with embedded mfs image:
#   patch /usr/src (https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=235806)
#   build loader_lua.efi
#   unpatch /usr/src
#   embed mfs in built loader_lua.efi
loader_build() {
    if [ -f "$loader_file" ] && [ "$loader_file" -nt "$loader_mfs_image" ]
    then
        printf '> loader file "%s" exists: skip step\n' "$loader_file"
        return 0
    fi
    git -C /usr/src apply "$loader_patch"

    md_size=$(($(stat -f "%z" "$loader_mfs_image") + 512))

    make -s -j"$ncpu" -C /usr/src/stand/ \
	 SRC_ENV_CONF="$src_env_conf"  MD_IMAGE_SIZE="$md_size" \
	MK_FORTH=no MK_LOADER_UBOOT=no MK_LOADER_OFW=no MK_FDT=no

    git -C /usr/src restore stand/efi/loader

    cp "$obj_dir_pfx"/usr/src/amd64.amd64/stand/efi/loader_lua/loader_lua.efi \
       "$loader_file"

    sh /usr/src/sys/tools/embed_mfs.sh "$loader_file" "$loader_mfs_image"

    rm -rf "${obj_dir_pfx:?}"/usr
}

kernel_mfs_image
kernel_build
loader_mfs_image
loader_build
