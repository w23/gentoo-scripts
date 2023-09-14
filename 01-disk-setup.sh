#!/bin/bash
set -eux

SCRIPT_ROOT=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_ROOT/config"

DISK_ID=$DISK_DEVICE_ID$PART
DISK_DEVICE=/dev/disk/by-id/$DISK_DEVICE_ID
DISK=$DISK_DEVICE$PART
DISK_BOOT=$DISK_DEVICE$BOOT_PART

mkdir -p /mnt/gentoo

destructful_partition() {
	sgdisk --zap-all $DISK_DEVICE
	sgdisk -n1:1M:+$EFI_PART_SIZE -t1:EF00 $DISK_DEVICE
	sgdisk -n2:0:0 -t2:BF01 $DISK_DEVICE
}

boot_create() {
	mkfs.fat -F 32 $DISK_BOOT
}

luks_create() {
	ARG_DISK=$1
	#ARG_KEYFILE=$2
	cryptsetup -v \
		--type luks2 \
		--cipher aes-xts-plain64 \
		--key-size 512 \
		--hash sha512 \
		--iter-time 5000 \
		--use-random \
		--verify-passphrase \
		luksFormat \
		$ARG_DISK # $ARG_KEYFILE
}

# luks_create_key() {
# 	DISK_ID=$1
# 	KEY_FILE=$DISK_ID.key
# 	DISK_DEVICE=/dev/disk/by-id/$DISK_ID
# 	#dd if=/dev/random of=$KEY_FILE bs=1024
# 	chmod a-w $KEY_FILE
# 	create_luks $DISK_DEVICE $KEY_FILE
# }

luks_open() {
	DISK_DEVICE=$1
	DISK_NAME=$2
	#KEY_FILE=$DISK_ID.key
	#DISK_DEVICE=/dev/disk/by-id/$DISK_ID
	# --key-file $KEY_FILE
	cryptsetup luksOpen $DISK_DEVICE $DISK_NAME
}

# create zfs pool
zpool_create() {
	zpool create \
		-o ashift=12 \
		-O acltype=posixacl -O canmount=off -O compression=lz4 \
		-O dnodesize=auto -O normalization=formD \
		-O atime=off \
		-O xattr=sa \
		-O mountpoint=/ -R /mnt/gentoo \
		$POOL /dev/mapper/crypt-$POOL

	#-O encryption=aes-256-gcm -O keylocation=prompt -O keyformat=passphrase \

	#	-O encryption=aes-256-gcm \
	#	-O keyformat=raw \
	#	-O keylocation=file://"$zfskeyloc" \
}

zfs_create() {
	zfs create -o canmount=off -o mountpoint=/ $POOL/ROOT
	zfs create -o canmount=off -o mountpoint=/home -o setuid=off $POOL/HOME
	zfs create -o canmount=off -o mountpoint=none -o setuid=off $POOL/PORTAGE

	zfs create -o canmount=noauto -o mountpoint=/ $POOL/ROOT/rootfs
	zfs mount $POOL/ROOT/rootfs

	zfs create -o mountpoint=/root             $POOL/ROOT/root
	zfs create -o canmount=off                 $POOL/ROOT/var
	zfs create -o canmount=off                 $POOL/ROOT/var/lib
	zfs create                                 $POOL/ROOT/var/log
	zfs create                                 $POOL/ROOT/var/spool

	zfs create -o com.sun:auto-snapshot=false  $POOL/ROOT/var/cache
	zfs create -o com.sun:auto-snapshot=false  $POOL/ROOT/var/tmp
	chmod 1777 /mnt/gentoo/var/tmp

	zfs create                                 $POOL/ROOT/opt

	zfs create -o canmount=off                 $POOL/ROOT/usr
	zfs create                                 $POOL/ROOT/usr/local

	zfs create                                 $POOL/ROOT/var/games

	# zfs create                                 $POOL/var/mail
	# zfs create                                 $POOL/var/snap
	# zfs create                                 $POOL/var/www

	#zfs create -o com.sun:auto-snapshot=false  $POOL/ROOT/var/lib/docker
	zfs create -o com.sun:auto-snapshot=false  $POOL/ROOT/var/lib/docker
	#zfs create -o com.sun:auto-snapshot=false  $POOL/ROOT/var/lib/nfs

	#zfs create -o com.sun:auto-snapshot=false -o mountpoint=/usr/src -o sync=disabled $POOL/ROOT/usr/src
	zfs create -o mountpoint=/usr/src -o sync=disabled $POOL/ROOT/usr/src

	zfs create -o com.sun:auto-snapshot=false -o mountpoint=/var/db/repos/gentoo $POOL/PORTAGE/portage
	zfs create -o com.sun:auto-snapshot=false -o mountpoint=/var/cache/distfiles -o compression=off $POOL/PORTAGE/distfiles
	zfs create -o com.sun:auto-snapshot=false -o mountpoint=/var/cache/binpkgs -o compression=off $POOL/PORTAGE/packages
	zfs create -o com.sun:auto-snapshot=false -o mountpoint=/var/tmp/portage -o sync=disabled -o exec=on $POOL/PORTAGE/var-tmp-portage
	zfs create -o com.sun:auto-snapshot=false -o mountpoint=/var/cache/ccache -o sync=disabled -o exec=on $POOL/PORTAGE/ccache

	zfs snapshot -r $POOL@empty
}

stage_get() {
	cd /mnt/gentoo
	wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/$TAGE_DATE/stage3-amd64-$TAGE_DATE.tar.xz
	tar xvJpf stage3-*.tar.xz --xattrs --numeric-owner
}

luks_setup() {
	luks_create $DISK
	luks_open $DISK crypt-$POOL
}

fs_create() {
	zpool_create
	zpool status
	zfs_create
	zfs list
}

fs_import() {
	zpool import -f -N -R /mnt/gentoo $POOL
	zfs mount $POOL/ROOT/rootfs
	zfs mount -a
}
"$@"
