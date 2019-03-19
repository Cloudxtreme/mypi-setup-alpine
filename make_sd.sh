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
    DEVICE_SIZE=$(blockdev --getsz "/dev/${DEVICE}")

    PARTITIONS="$(fdisk -l "/dev/${DEVICE}" | grep "^/dev/${DEVICE}")"

    echo "${PARTITIONS}"


    mkdir -p "${DIR_THIS}/mnt"

    (umount "/dev/${BOOT_DEVICE}" || true) &>/dev/null
    (umount "/dev/${ROOT_DEVICE}" || true) &>/dev/null
    (umount "${DIR_THIS}/mnt" || true) &>/dev/null

    mkfs.vfat "/dev/${BOOT_DEVICE}"

    mount "/dev/${BOOT_DEVICE}" "${DIR_THIS}/mnt"
fi

pushd ${DIR_THIS}/mnt
tar xf "${DIR_THIS}/alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" --no-same-owner  
popd

DIR_APKOVL="${DIR_THIS}/apkovl"

if [[ ! -d "${DIR_APKOVL}" ]]; then
    mkdir -p "${DIR_APKOVL}"
else
    rm -rf "${DIR_APKOVL}/"*
fi

cp -a "${DIR_THIS}/src/"* "${DIR_APKOVL}"

APKREPOSOPTS=-f
#APKREPOSOPTS=-1
#APKREPOSOPTS=mirror1.hs-esslingen.de

echo "BOOT_DEVICE_NAME=${BOOT_DEVICE}" >> "${DIR_APKOVL}/mypi-setup/config"
echo "ROOT_DEVICE_NAME=${ROOT_DEVICE}" >> "${DIR_APKOVL}/mypi-setup/config"
echo "WLAN_SSID=${WLAN_SSID}"          >> "${DIR_APKOVL}/mypi-setup/config"
echo "WLAN_PASSWORD=${WLAN_PASSWORD}"  >> "${DIR_APKOVL}/mypi-setup/config"

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
APKREPOSOPTS="${APKREPOSOPTS}"
SSHDOPTS="-c openssh"
NTPOPTS="-c busybox"
APKCACHEOPTS="none"
LBUOPTS="none"
__EOF__

###############################################################################
#
#                                                      /<BOOT>/setup-phase-2.sh
#
(
cat <<-__EOF__
#!/bin/sh

set -x
set -e

rc-update del hwclock boot &> /dev/null|| true
rc-update add swclock boot

apk add bash htop jq docker perl

rc-update add docker boot
service docker start
__EOF__

if [[ -n "${WLAN_SSID}" && -n "${WLAN_PASSWORD}" ]]; then
cat <<-__EOF__
apk add wireless-tools wpa_supplicant
ip link | grep wlan0
ip link set wlan0 up
iwlist wlan0 scanning
iwconfig wlan0 essid ${WLAN_SSID}

cat > /etc/wpa_supplicant/wpa_supplicant.conf <<-_EOF_
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
_EOF_

wpa_passphrase "${WLAN_SSID}" "${WLAN_PASSWORD}" > /etc/wpa_supplicant/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
udhcpc -i wlan0
ip addr show wlan0

###############################################################################
#
# Update /etc/network/interfaces
#
cat >> /etc/network/interfaces <<-_EOF_

auto wlan0
iface wlan0 inet dhcp
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
_EOF_

###############################################################################
#
# Configure udhcpc to ignore DNS and GATEWAY from wlan0
#
mkdir -p /etc/udhcpc
cat > /etc/udhcpc/udhcpc.conf <<-_EOF_
NO_DNS=wlan0
NO_GATEWAY=wlan0
_EOF_

###############################################################################
#
# Enable WLAN
#
ifconfig wlan0 down
/etc/init.d/wpa_supplicant start
rc-update add wpa_supplicant boot

__EOF__
fi
)  > "${DIR_THIS}/mnt/setup-phase-2.sh"
#
#                                                      /<BOOT>/setup-phase-2.sh
#
###############################################################################

pushd "${DIR_APKOVL}"
    tar czf ${DIR_THIS}/mnt/${RPI_HOSTNAME}.apkovl.tar.gz .
popd >/dev/null

umount "${DIR_THIS}/mnt"