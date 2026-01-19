#!/bin/sh -e
#

basedir=$(dirname "$(realpath "$0")")

usr_src=${usr_src:-"/usr/src"}
base_pkgs=${base_pkgs:-"/usr/obj/usr/src/repo/FreeBSD:15:amd64/latest/"}
_build=${_build:-"$basedir"/_build}

src_env_conf="$basedir"/src-env.conf
kern_conf_dir="$basedir"/kernel

etc_rc="$basedir"/kernel_mfs/etc_rc
loader_conf="$basedir"/loader_mfs/loader.conf
local_lua="$basedir"/loader_mfs/local.lua

vt_fb_rotate_patch="$basedir"/patches/vt_fb_rotate.patch

kernel_mfs_image="$_build"/md0.uzip
kernel_file="$_build"/kernel
loader_mfs_image="$_build"/bootfs.img
loader_file="$_build"/BOOTX64.efi

export SRCCONF="$basedir"/src.conf
export MAKEOBJDIRPREFIX="$_build"/obj_dir_pfx

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

    scratch_d="$_build"/scratch
    mkdir -p "$scratch_d"/d "$scratch_d"/p

    rescue_pkg="$(find "$base_pkgs" -name FreeBSD-rescue\*.pkg -print |
                  sort | tail -1)"
    if [ -z "$rescue_pkg" ]; then
	pkg create -o "$scratch_d" -f tar FreeBSD-rescue
    else
	cp "$rescue_pkg" "$scratch_d"
    fi

    PKG_DBDIR="$scratch_d"/p pkg -r "$scratch_d"/d add \
	     -M "$scratch_d"/FreeBSD-rescue*

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
# build kernel with embedded mfs and patched vt_fb
#
kernel_build () {
    if [ -f "$kernel_file" ] && [ "$kernel_file" -nt "$kernel_mfs_image" ]
    then
        printf '> kernel file "%s" exists: skip step\n' "$kernel_file"
        return 0
    fi

    git -C "$usr_src" apply "$vt_fb_rotate_patch"

    env KERNCONFDIR="$kern_conf_dir" KERNCONF=ZENC \
        MFS_IMAGE="$kernel_mfs_image" \
        make -s -j"$ncpu" -C "$usr_src"  SRC_ENV_CONF="$src_env_conf" \
	buildkernel

    git -C "$usr_src" restore sys/dev/vt/hw/fb

    cp "$MAKEOBJDIRPREFIX"/"$usr_src"/amd64.amd64/sys/ZENC/kernel \
       "$kernel_file"

    rm -rf "$MAKEOBJDIRPREFIX"
}

##############################################################################
# create mfs that will be embedded in the loader:
#   use lua code and default config from FreeBSD-bootloader-15 pkg
#   install loader.conf and local.lua
#   install kernel
#
loader_mfs_image() {
    if [ -f "$loader_mfs_image" ] && [ "$loader_mfs_image" -nt "$kernel_file" ]
    then
        printf '> loader mfs image "%s" exists: skip step\n' "$loader_mfs_image"
        return 0
    fi

    scratch_d="$_build"/scratch
    mkdir -p "$scratch_d"/d

    loader_pkg="$(find "$base_pkgs" -name FreeBSD-bootloader-15\*.pkg -print |
                  sort | tail -1)"
    if [ -z "$loader_pkg" ]; then
	pkg create -o "$scratch_d" -f tar FreeBSD-bootloader
    else
	cp "$loader_pkg" "$scratch_d"
    fi

    tar -C "$scratch_d"/d -xf "$scratch_d"/FreeBSD-bootloader* \
	/boot/lua /boot/defaults /boot/device.hints /boot/loader.conf.d

    cp "$loader_conf" "$scratch_d"/d/boot/
    cp "$local_lua" "$scratch_d"/d/boot/lua/

    mkdir "$scratch_d"/d/boot/kernel
    cp "$kernel_file" "$scratch_d"/d/boot/kernel

    makefs "$loader_mfs_image" "$scratch_d"/d

    rm -rf "$scratch_d"
}

##############################################################################
# build EFI loader with embedded mfs image:
#   build loader_lua.efi
#   embed mfs in built loader_lua.efi
loader_build() {
    if [ -f "$loader_file" ] && [ "$loader_file" -nt "$loader_mfs_image" ]
    then
        printf '> loader file "%s" exists: skip step\n' "$loader_file"
        return 0
    fi

    md_size=$(($(stat -f "%z" "$loader_mfs_image") + 512))

    make -s -j"$ncpu" -C "$usr_src"/stand/ \
	 SRC_ENV_CONF="$src_env_conf" MD_IMAGE_SIZE="$md_size" \
	 MK_FORTH=no MK_LOADER_UBOOT=no MK_LOADER_OFW=no

    cp "$MAKEOBJDIRPREFIX"/"$usr_src"/amd64.amd64/stand/efi/loader_lua/loader_lua.efi \
       "$loader_file"

    sh "$usr_src"/sys/tools/embed_mfs.sh "$loader_file" "$loader_mfs_image"

    rm -rf "$MAKEOBJDIRPREFIX"
}

kernel_mfs_image
kernel_build
echo loader_mfs_image
loader_mfs_image
echo loader_build
loader_build
