#!/usr/bin/env bash

set -e

RPI_HOSTNAME=rpi2

ALPINE_VERSION=3.8.2
ALPINE_ARCH=aarch64

DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

DEVICE="${1:-mmcblk0}"
BOOT_DEVICE="${DEVICE}p1"
ROOT_DEVICE="${DEVICE}p2"

DIR_APKOVL="${DIR_THIS}/apkovl"

mkdir -p "${DIR_APKOVL}"
rm -rf "${DIR_APKOVL:?}/*"

if [[ "Darwin" == "$(uname -s)" ]]; then
    rm -f ./mnt
    ln -s "/Volumes/NO NAME" ./mnt
    rm -rf ./mnt/*
else
    DEVICE_SIZE=$(blockdev --getsz "/dev/${DEVICE}")

    PARTITIONS="$(fdisk -l "/dev/${DEVICE}" | grep "^/dev/${DEVICE}")"

    echo "${PARTITIONS}"


    mkdir -p "${DIR_THIS}/mnt"

    (umount "${DIR_THIS}/mnt" || true) &>/dev/null

    mkfs.vfat "${BOOT_DEVICE}"

    mount "/dev/${BOOT_DEVICE}" "${DIR_THIS}/mnt"
fi

pushd ${DIR_THIS}/mnt
tar xf "${DIR_THIS}/alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" --no-same-owner  
popd

cat > "${DIR_APKOVL}/answer.txt" <<-__EOF__
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
#APKREPOSOPTS="-f"
APKREPOSOPTS="-1"
SSHDOPTS="-c openssh"
NTPOPTS="-c busybox"
APKCACHEOPTS="none"
LBUOPTS="none"
__EOF__

###############################################################################
#
#                                                            /<APKOVL>/setup.sh
#
(
cat <<-__EOF__
#!/bin/sh

set -x
set -e

# ensure that the time is not to far in the past
date -s "@$(date +'%s')"

cd /media/${BOOT_DEVICE}

NOCOMMIT=1 setup-alpine -f /answer.txt

apk update
apk add e2fsprogs

yes | mkfs.ext4 /dev/${ROOT_DEVICE}

mount /dev/${ROOT_DEVICE} /mnt
__EOF__

if echo "${ALPINE_VERSION}" | grep ^3\.8.* > /dev/null ; then
##-------------------------------------------------------------- alpine 3.8 ---
cat << __EOF__
mount -o remount,rw /media/${BOOT_DEVICE}
cd /mnt
cp -a /bin /etc /home /lib /root /run /sbin /srv /usr /var .
mkdir .modloop
mkdir dev
mkdir media
mkdir proc
mkdir sys
mkdir tmp

mkdir boot
cp /media/${BOOT_DEVICE}/boot/* boot/

<etc/init.d/modloop awk '
    /if.*KOPT_modloop/ { 
        print "\\t\\t\\t\\tif [ \"\${dir}\" == \"/\" ]; then"
        print "\\t\\t\\t\\t\\tdir=\"\""
        print "\\t\\t\\t\\tfi"
    }
    1' | sed 's,&& \$2 != "/" ,,' > etc/init.d/modloop.new
mv etc/init.d/modloop.new etc/init.d/modloop
chmod 755 etc/init.d/modloop

sed -i 's/^/modloop=\\/boot\\/modloop-rpi /' /media/${BOOT_DEVICE}/cmdline.txt  

__EOF__
else
##-------------------------------------------------------------- alpine 3.9 ---
cat << __EOF__
setup-disk -m sys /mnt

mount -o remount,rw /media/${BOOT_DEVICE}

rm -f /media/${BOOT_DEVICE}/boot/*  
cd /mnt       # We are in the second partition 
rm boot/boot  # Drop the unused symbolink link

mv boot/* /media/${BOOT_DEVICE}/boot/
rm -Rf boot
__EOF__
fi

cat << __EOF__
mkdir media/${BOOT_DEVICE} # It's the mount point for the first partition on the next reboot

ln -s media/${BOOT_DEVICE}/boot boot

echo "/dev/${BOOT_DEVICE} /media/${BOOT_DEVICE} vfat defaults 0 0" >> etc/fstab
sed -i '/cdrom/d' etc/fstab   # Of course, you don't have any cdrom or floppy on the Raspberry Pi
sed -i '/floppy/d' etc/fstab

sed -i '/v.\\..\\/community/s/^#//' /mnt/etc/apk/repositories   # But enable the repository for community if you want vim, mc, php, apache, nginx, etc.

sed -i 's/^/root=\\/dev\\/${ROOT_DEVICE} /' /media/${BOOT_DEVICE}/cmdline.txt  
reboot 

__EOF__
) > "${DIR_APKOVL}/setup.sh" 
chmod 755 "${DIR_APKOVL}/setup.sh"
#
#                                                            /<APKOVL>/setup.sh
#
###############################################################################

###############################################################################
#
#                                               /<APKOVL>/etc/init.d/mypi-setup
#
mkdir -p "${DIR_APKOVL}/etc/init.d"
(
cat << __EOF__
#!/sbin/openrc-run
start()
{
    /setup.sh
}
__EOF__
) > "${DIR_APKOVL}/etc/init.d/mypi-setup"
chmod 755 "${DIR_APKOVL}/etc/init.d/mypi-setup"
#
#                                               /<APKOVL>/etc/init.d/mypi-setup
#
###############################################################################


###############################################################################
#
#                                                      /<BOOT>/setup-phase-2.sh
#
(
cat <<-__EOF__
#!/bin/sh

set -x
set -e

rc-update del hwclock boot
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

touch "${DIR_APKOVL}/etc/.default_boot_services"

mkdir -p "${DIR_APKOVL}/etc/runlevels/default"
pushd "${DIR_APKOVL}/etc/runlevels/default"
ln -s \
    /etc/init.d/mypi-setup \
    .
popd >/dev/null

pushd "${DIR_APKOVL}"
    tar czf ${DIR_THIS}/mnt/${RPI_HOSTNAME}.apkovl.tar.gz .
popd >/dev/null

#umount "${DIR_THIS}/mnt"