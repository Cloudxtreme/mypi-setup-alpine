#!/usr/bin/env bash

set -e

ALPINE_VERSION=3.8.2
ALPINE_ARCH=aarch64

DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

DEVICE="${1:-/dev/mmcblk0}"
BOOT_DEVICE="${DEVICE}p1"

DEVICE_SIZE=$(blockdev --getsz "${DEVICE}")

PARTITIONS="$(fdisk -l "${DEVICE}" | grep "^${DEVICE}")"

echo "${PARTITIONS}"


mkdir -p "${DIR_THIS}/mnt"

(umount "${DIR_THIS}/mnt" || true) &>/dev/null

mkfs.vfat "${BOOT_DEVICE}"

mount "${BOOT_DEVICE}" "${DIR_THIS}/mnt"

pushd ${DIR_THIS}/mnt
tar xf "${DIR_THIS}/alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" --no-same-owner  
popd

cat > ${DIR_THIS}/mnt/answer.txt <<-__EOF__
KEYMAPOPTS="us us"
HOSTNAMEOPTS="-n rpi2"
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname rpi2
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

BOOT_DEVICE=mmcblk0p1
ROOT_DEVICE=mmcblk0p2

###############################################################################
#
#                                                              /<BOOT>/setup.sh
#
(
cat <<-__EOF__
#!/bin/sh

set -x
set -e

# ensure that the time is not to far in the past
date -s "@$(date +'%s')"

cd /media/${BOOT_DEVICE}

NOCOMMIT=1 setup-alpine -f ./answer.txt

apk update
apk add e2fsprogs

yes | mkfs.ext4 /dev/${ROOT_DEVICE}

mount /dev/${ROOT_DEVICE} /mnt
__EOF__

if echo "${ALPINE_VERSION}" | grep ^3.8* > /dev/null ; then
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
mkdir media/mmcblk0p1   # It's the mount point for the first partition on the next reboot

ln -s media/${BOOT_DEVICE}/boot boot

echo "/dev/${BOOT_DEVICE} /media/${BOOT_DEVICE} vfat defaults 0 0" >> etc/fstab
sed -i '/cdrom/d' etc/fstab   # Of course, you don't have any cdrom or floppy on the Raspberry Pi
sed -i '/floppy/d' etc/fstab

sed -i '/v.\\..\\/community/s/^#//' /mnt/etc/apk/repositories   # But enable the repository for community if you want vim, mc, php, apache, nginx, etc.

sed -i 's/^/root=\\/dev\\/${ROOT_DEVICE} /' /media/${BOOT_DEVICE}/cmdline.txt  
reboot 

__EOF__
) > ${DIR_THIS}/mnt/setup.sh 
#
#                                                              /<BOOT>/setup.sh
#
###############################################################################

###############################################################################
#
#                                                      /<BOOT>/setup-phase-2.sh
#
cat > ${DIR_THIS}/mnt/setup-phase-2.sh <<-__EOF__
#!/bin/sh

set -x
set -e

rc-update del hwclock boot
rc-update add swclock boot

apk add bash htop jq docker perl

rc-update add docker boot
service docker start
__EOF__
#
#                                                      /<BOOT>/setup-phase-2.sh
#
###############################################################################

#umount "${DIR_THIS}/mnt"