#!/bin/sh
set -eux

KERNEL_VER=$(readlink /usr/src/linux | sed -e 's/^linux-//')
GCC_VER=$(gcc --version|grep '^gcc'|sed -e 's/.*(.*) \([[:digit:]]*\).*/\1/')

INITRAMFS="/usr/src/initramfs-current" #$KERNEL_VER"

echo KERNEL_VER=$KERNEL_VER
echo GCC_VER=$GCC_VER
echo INITRAMFS=$INITRAMFS

# https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples
# https://wiki.gentoo.org/wiki/Custom_Initramfs

mount_boot() {
	mount -o rw,relatime,fmask=0022,dmask=0022,iocharset=ascii,shortname=mixed /boot || echo already mounted?
}

fixup_systemd_waiting() {
	# A fix for "A start job is running for /dev/mapper/crypt-btroot"
	# See https://github.com/systemd/systemd/issues/34683
	echo 'SUBSYSTEM=="block", KERNEL=="dm-0", ENV{SYSTEMD_READY}="1"' > /etc/udev/rules.d/99-crypt-root.rules
}

grub_install() {
	mount_boot
	grub-install --compress=xz --no-nvram --target=x86_64-efi --efi-directory=/boot --removable
	fixup_systemd_waiting
}

grub_update() {
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg
}

install_prereq() {
	# TODO single file for initramfs exclusively
	echo 'app-misc/pax-utils python' >> /etc/portage/package.use/10-local
	echo 'sys-apps/busybox mdev' >> /etc/portage/package.use/10-local
	echo 'sys-kernel/installkernel -systemd grub' >> /etc/portage/package.use/10-local
	#echo 'sys-fs/cryptsetup static' >> /etc/portage/package.use/10-local
	emerge -tavn busybox app-misc/pax-utils cryptsetup btrfs-progs installkernel
}

create() {
	rm -r "$INITRAMFS" || echo "no old initramfs?"
	mkdir -p $INITRAMFS/{bin,dev,etc,lib/modules,lib64,proc,root,sbin,sys,newroot,run/cryptsetup}
	cp -a /dev/{null,console,tty} $INITRAMFS/dev/
	cp -a /bin/busybox $INITRAMFS/bin/busybox
	cp -a /dev/{urandom,random} $INITRAMFS/dev
	cp -a /sbin/cryptsetup $INITRAMFS/sbin/cryptsetup
	cp -a /sbin/btrfs $INITRAMFS/sbin/btrfs

	lddtree --copy-to-tree $INITRAMFS /bin/busybox
	ln -s ../bin/busybox $INITRAMFS/sbin/mdev
	chroot $INITRAMFS /bin/busybox --install -s

	lddtree --copy-to-tree $INITRAMFS /sbin/cryptsetup
	lddtree --copy-to-tree $INITRAMFS /sbin/btrfs
	#lddtree --copy-to-tree $INITRAMFS /sbin/zpool
	#lddtree --copy-to-tree $INITRAMFS /sbin/zfs
	#lddtree --copy-to-tree $INITRAMFS /sbin/mount.zfs
	# doesn't really exist anymore lddtree --copy-to-tree $INITRAMFS /sbin/fsck.zfs
	#lddtree --copy-to-tree $INITRAMFS /sbin/zdb
	# Why is this not copied over by cryptsetup?!
	cp "/usr/lib/gcc/x86_64-pc-linux-gnu/$GCC_VER/libgcc_s.so.1" $INITRAMFS/lib64/

	cp -av "/lib/modules/${KERNEL_VER}" $INITRAMFS/lib/modules/
	mkdir -p $INITRAMFS/lib/firmware

	# 2024-02-04: comment out: make amdgpu module
	#cp -av /lib/firmware/amd* $INITRAMFS/lib/firmware/

	#cp -av /lib/firmware $INITRAMFS/lib/

	cp -av /usr/src/initramfs-skel/init $INITRAMFS/init

	#mkdir -p $INITRAMFS/etc/zfs
	#zpool set cachefile=/etc/zfs/zpool.cache zroot
	#cp -av /etc/zfs/zpool.cache $INITRAMFS/etc/zfs/
	#zpool set cachefile=none zroot

	#pushd $INITRAMFS
	#find . -print0 | cpio --null --create --verbose --format=newc | xz -9 > $INITRAMFS.cpio.xz
	#popd
}

kernel() {
	pushd /usr/src/linux
	rm -r "$INITRAMFS" || echo "no old initramfs?"
	#if [[ -d "/lib/modules/${KERNEL_VER}" ]]
	#then
	#	create
	#else
	#	mkdir -p "$INITRAMFS"
	#	touch "$INITRAMFS.cpio.xz"
	#fi
	mkdir -p "$INITRAMFS"
	make -j32
	make -j32 modules
	rm -r "/lib/modules/$KERNEL_VER" || echo "no modules?"
	make modules_install
	emerge -t1v @module-rebuild
	rm -r "$INITRAMFS"
	#rm "$INITRAMFS.cpio.xz"
	create
	mount /boot || echo "already mounted?"
	rm "/usr/src/linux/usr/initramfs_data.cpio"
	make -j32
	#cp -a "/boot/vmlinuz-$KERNEL_VER" "/boot/vmlinuz-$KERNEL_VER.old.$(date +%Y-%m-%d-%H-%M)" || echo "no old ver?"
	# 2024-02-0x add disabling systemd install, as it leads to some weird kernel paths
	SYSTEMD_KERNEL_INSTALL=0 make install
	grub_update
	echo "DONE!"
}

$@

#create_initramfs
