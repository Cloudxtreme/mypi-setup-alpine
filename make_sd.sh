#!/usr/bin/env bash

set -e

RPI_HOSTNAME=rpi2

ALPINE_VERSION=3.9.2
ALPINE_ARCH=armv7

DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

DEVICE="${1:-mmcblk0}"
BOOT_DEVICE="${DEVICE}p1"
ROOT_DEVICE="${DEVICE}p2"

if [[ "Darwin" == "$(uname -s)" ]]; then
    rm -f ./mnt
    ln -s "/Volumes/NO NAME" ./mnt
    rm -rf ./mnt/*
else
    #DEVICE_SIZE=$(blockdev --getsz "/dev/${DEVICE}")
    PARTITIONS="$(fdisk -l "/dev/${DEVICE}" | grep "^/dev/${DEVICE}")"

    echo "${PARTITIONS}"

    mkdir -p "${DIR_THIS}/mnt"

    (umount "/dev/${BOOT_DEVICE}" || true) &>/dev/null
    (umount "/dev/${ROOT_DEVICE}" || true) &>/dev/null
    (umount "${DIR_THIS}/mnt" || true) &>/dev/null

    mkfs.vfat "/dev/${BOOT_DEVICE}"

    mount "/dev/${BOOT_DEVICE}" "${DIR_THIS}/mnt"
fi

pushd "${DIR_THIS}/mnt"
tar xf "${DIR_THIS}/alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" --no-same-owner  
popd

DIR_APKOVL="${DIR_THIS}/apkovl"

if [[ ! -d "${DIR_APKOVL}" ]]; then
    mkdir -p "${DIR_APKOVL}"
else
    rm -rf "${DIR_APKOVL:?}/"*
fi

cp -a "${DIR_THIS}/src/"* "${DIR_APKOVL}"

cat > "${DIR_APKOVL}/mypi-setup/config" <<-__EOF__
BOOT_DEVICE_NAME=${BOOT_DEVICE}"
ROOT_DEVICE_NAME=${ROOT_DEVICE}"
WLAN_SSID=${WLAN_SSID}"
WLAN_PASSWORD=${WLAN_PASSWORD}"
__EOF__

cat > "${DIR_APKOVL}/mypi-setup/answer.txt" <<-__EOF__
KEYMAPOPTS="us us"
HOSTNAMEOPTS="-n ${RPI_HOSTNAME}"
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname ${RPI_HOSTNAME}
"
TIMEZONEOPTS="-z UTC"
PROXYOPTS=none
APKREPOSOPTS="-f"
SSHDOPTS="-c openssh"
NTPOPTS="-c busybox"
APKCACHEOPTS="none"
LBUOPTS="none"
__EOF__

pushd "${DIR_APKOVL}"
    tar czf ${DIR_THIS}/mnt/${RPI_HOSTNAME}.apkovl.tar.gz .
popd >/dev/null

umount "${DIR_THIS}/mnt"