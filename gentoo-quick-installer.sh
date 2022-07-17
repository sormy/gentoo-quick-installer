#!/bin/sh

##
# GENTOO QUICK INSTALLER
#
# Read more: http://www.artembutusov.com/gentoo-linux-quick-installer-script/
#
# Usage:
#
# export OPTION1=VALUE1
# export OPTION2=VALUE2
# ./gentoo-quick-installer.sh
#
# Options:
#
# USE_LIVECD_KERNEL - 1 to use livecd kernel (saves time) or 0 to build kernel (takes time)
# SSH_PUBLIC_KEY - ssh public key, pass contents of `cat ~/.ssh/id_rsa.pub` for example
# ROOT_PASSWORD - root password, only SSH key-based authentication will work if not set
#
# livecd kernel with root password
# USE_LIVECD_KERNEL=1 ROOT_PASSWORD=Gentoo123 ./gentoo-quick-installer.sh
#
# Gentoo's binary kernel with ssh public key
# USE_LIVECD_KERNEL=0 SSH_PUBLIC_KEY=$(cat id_rsa.pub) ./gentoo-quick-installer.sh
##

set -e

GENTOO_MIRROR="http://distfiles.gentoo.org"

GENTOO_ARCH="amd64"
# Default is hardened server build with OpenRC.
# Other options are amd64-openrc, amd64-nomultilib-openrc, amd64-hardened-openrc,
# and64-hardened-selinux-openrc, and amd-desktop-openrc
GENTOO_STAGE3="	amd64-hardened-nomultilib-openrc"

# Default is set for virtual machines.
# /dev/sda is standard for most IDE/SATA drives.
# /dev/nvme0n1 is standard for most NVME and eMMC drives.
TARGET_DISK=/dev/vda

TARGET_BOOT_SIZE=256M
TARGET_SWAP_SIZE=1G

GRUB_PLATFORMS=pc

USE_LIVECD_KERNEL=${USE_LIVECD_KERNEL:-1}

SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}
ROOT_PASSWORD=${ROOT_PASSWORD:-}

echo "### Checking configuration..."

if [ -z "$SSH_PUBLIC_KEY" ] && [ -z "$ROOT_PASSWORD" ]; then
    echo "SSH_PUBLIC_KEY or ROOT_PASSWORD must be set to continue"
    exit 1
fi

echo "### Setting time..."

ntpd -gq

echo "### Creating partitions..."

sfdisk ${TARGET_DISK} << END
size=$TARGET_BOOT_SIZE,bootable
size=$TARGET_SWAP_SIZE
;
END

echo "### Formatting partitions..."

yes | mkfs.ext4 ${TARGET_DISK}1
yes | mkswap ${TARGET_DISK}2
yes | mkfs.ext4 ${TARGET_DISK}3

echo "### Labeling partitions..."

e2label ${TARGET_DISK}1 boot
swaplabel ${TARGET_DISK}2 -L swap
e2label ${TARGET_DISK}3 root

echo "### Mounting partitions..."

swapon ${TARGET_DISK}2

mkdir -p /mnt/gentoo
mount ${TARGET_DISK}3 /mnt/gentoo

mkdir -p /mnt/gentoo/boot
mount ${TARGET_DISK}1 /mnt/gentoo/boot

echo "### Setting work directory..."

cd /mnt/gentoo

echo "### Installing stage3..."

STAGE3_PATH_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/latest-stage3-$GENTOO_STAGE3.txt"
STAGE3_PATH=$(curl -s "$STAGE3_PATH_URL" | grep -v "^#" | cut -d" " -f1)
STAGE3_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/$STAGE3_PATH"

wget "$STAGE3_URL"

tar xvpf "$(basename "$STAGE3_URL")" --xattrs-include='*.*' --numeric-owner

rm -fv "$(basename "$STAGE3_URL")"

if [ "$USE_LIVECD_KERNEL" != 0 ]; then
    echo "### Installing LiveCD kernel..."

    LIVECD_KERNEL_VERSION=$(cut -d " " -f 3 < /proc/version)

    cp -v "/mnt/cdrom/boot/gentoo" "/mnt/gentoo/boot/vmlinuz-$LIVECD_KERNEL_VERSION"
    cp -v "/mnt/cdrom/boot/gentoo.igz" "/mnt/gentoo/boot/initramfs-$LIVECD_KERNEL_VERSION.img"
    cp -vR "/lib/modules/$LIVECD_KERNEL_VERSION" "/mnt/gentoo/lib/modules/"
fi

echo "### Copying network options..."

cp -v /etc/resolv.conf /mnt/gentoo/etc/

echo "### Configuring fstab..."

cat >> /mnt/gentoo/etc/fstab << END

# added by gentoo installer
LABEL=boot /boot ext4 noauto,noatime 1 2
LABEL=swap none  swap sw             0 0
LABEL=root /     ext4 noatime        0 1
END

echo "### Mounting proc/sys/dev..."

mount -t proc none /mnt/gentoo/proc
mount -t sysfs none /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount -o bind /dev/pts /mnt/gentoo/dev/pts
mount -o bind /dev/shm /mnt/gentoo/dev/shm
mount --bind /run /mnt/gentoo/run
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm /run/shm

echo "### Changing root..."

chroot /mnt/gentoo /bin/bash -s << END
#!/bin/bash

set -e

echo "### Upading configuration..."

env-update
source /etc/profile

echo "### Installing portage..."

mkdir -p /etc/portage/repos.conf
cp -f /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
emerge-webrsync
mv /etc/portage/make.conf /etc/portage/default
mkdir /etc/portage/make.conf
mv /etc/portage/default /etc/portage/make.conf

####################################################################################
# This can be commented out, if you have issues with russian exports, 
# or don't want binary packages.
echo "PORTAGE_BINHOST=\"https://mirror.yandex.ru/calculate/grp/x86_64\"" >> /etc/portage/make.conf/binhost
# required to allow for linux-firmware (required for binary kernel).
echo "ACCEPT_LICENSE=\"*\"" >> /etc/portage/make.conf/default
# entirely optional, but extremely nice to have. Comment out next two lines if you disagree.
emerge -G eix
eix-sync

if [ "$USE_LIVECD_KERNEL" = 0 ]; then
    echo "### Installing kernel..."
    
    echo "sys-kernel/gentoo-kernel-bin ~amd64" >> /etc/portage/package.accept_keywords/kernel
    echo "virtual/dist-kernel ~amd64" >> /etc/portage/package.accept_keywords/kernel
    emerge -g sys-kernel/linux-firmware installkernel-gentoo
    emerge -g virtual/dist-kernel sys-kernel/gentoo-kernel-bin
    emerge -g sys-kernel/genkernel
fi

echo "### Installing bootloader..."

emerge -g grub

cat >> /etc/portage/make.conf/default << IEND

# added by gentoo installer
GRUB_PLATFORMS="$GRUB_PLATFORMS"
IEND

cat >> /etc/default/grub << IEND

# added by gentoo installer
GRUB_CMDLINE_LINUX="net.ifnames=0"
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
IEND

grub-install ${TARGET_DISK}
grub-mkconfig -o /boot/grub/grub.cfg

echo "### Configuring network..."

ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default
emerge -g net-misc/dhcpcd

if [ -z "$ROOT_PASSWORD" ]; then
    echo "### Removing root password..."
    passwd -d -l root
else
    echo "### Configuring root password..."
    echo "root:$ROOT_PASSWORD" | chpasswd
fi

if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "### Configuring SSH..."

    rc-update add sshd default

    mkdir /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 750 /root/.ssh
    chmod 640 /root/.ssh/authorized_keys
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
fi
END

echo "### Rebooting..."

reboot
