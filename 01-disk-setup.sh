#!/bin/bash
set -eux

SCRIPT_ROOT=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_ROOT/config"

DISK_DEVICE=/dev/disk/by-id/$DISK_DEVICE_ID

# see destructful_partition
PART_EFI=-part1
PART_ROOT=-part2
PART_SWAP=-part3

DISK_PART_BOOT=$DISK_DEVICE$PART_EFI
DISK_PART_ROOT=$DISK_DEVICE$PART_ROOT
DISK_PART_SWAP=$DISK_DEVICE$PART_SWAP

CRYPT_ROOTFS=crypt-$POOL
DISK_CRYPT_ROOTFS=/dev/mapper/$CRYPT_ROOTFS

mkdir -p /mnt/gentoo

destructful_partition() {
	sgdisk --zap-all $DISK_DEVICE

	local PART_TYPE=8200
	# ZFS: PART_TYPE=BF01

	sgdisk \
		-n1:1M:+$PART_EFI_SIZE -t1:EF00 $DISK_DEVICE \
		-n2:0:-$PART_SWAP_SIZE -t2:8300 $DISK_DEVICE \
		-n3:0:0                -t2:$PART_TYPE $DISK_DEVICE
}

boot_create() {
	mkfs.vfat -F 32 -n EFI $DISK_PART_BOOT
}

btrfs_create() {
	mkfs.btrfs -L ROOT $DISK_CRYPT_ROOTFS

	mkdir -p /mnt/gentoo
	mount $DISK_CRYPT_ROOTFS /mnt/gentoo
	for sv in rootfs home root var/log var/cache var/tmp
	do
		NAME=$(echo "$sv"|sed -e 's/\//-/g')
		btrfs sub create /mnt/gentoo/@$NAME
	done
	umount /mnt/gentoo
}

btrfs_mount() {
	mkdir -p /mnt/gentoo

	mount -o defaults,noatime,compress=zstd,autodefrag,subvol=@rootfs $DISK_CRYPT_ROOTFS /mnt/gentoo
	for sv in home root var/log var/cache var/tmp
	do
		NAME=$(echo "$sv"|sed -e 's/\//-/g')
		rmdir /mnt/gentoo/$NAME || echo what
		mkdir -p /mnt/gentoo/$sv
		mount -o defaults,noatime,compress=zstd,autodefrag,subvol=@$NAME $DISK_CRYPT_ROOTFS /mnt/gentoo/$sv
	done
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

#DISK_ID=$DISK_DEVICE_ID$PART
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

STAGE_BASEURL="${DISTFILES_MIRROR}/releases/amd64/autobuilds/current-stage3-amd64-${PROFILE}"

_get_latest_stage_url() {
	local METADATA_URL="${STAGE_BASEURL}/latest-stage3-amd64-${PROFILE}.txt"
	local LATEST_STAGE="$(curl "${METADATA_URL}" | awk '/^stage3-/ { print $1 }')"
	STAGE_URL="${STAGE_BASEURL}/${LATEST_STAGE}"
	echo "Lastest stage3 is ${STAGE_URL}"
}

stage_get() {
	_get_latest_stage_url

	cd /mnt/gentoo
	wget -ct0 -T10 "${STAGE_URL}"
	tar xvJpf stage3-*.tar.xz --xattrs --numeric-owner
}

luks_setup() {
	luks_create $DISK_PART_ROOT
	luks_open $DISK_PART_ROOT $CRYPT_ROOTFS
}

fs_zfs_create() {
	zpool_create
	zpool status
	zfs_create
	zfs list
}

zfs_import() {
	zpool import -f -N -R /mnt/gentoo $POOL
	zfs mount $POOL/ROOT/rootfs
	zfs mount -a
}

_ask() {
	# https://stackoverflow.com/a/1885534
	read -p "Are you sure? " -n 1 -r
	echo    # (optional) move to a new line
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
			[[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
	fi
}

btrfs_prepare_disk() {
	_ask
	destructful_partition
	boot_create
	luks_setup
	btrfs_create
}

btrfs_populate() {
	btrfs_mount
	stage_get
}

for i in "$@"
do
	time "$i"
done
