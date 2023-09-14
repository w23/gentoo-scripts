#!/bin/sh

set -eux

KERNEL_VER=$(readlink /usr/src/linux | sed -e 's/^linux-//')

# gcc (Gentoo 11.3.0 p4) 11.3.0
#GCC_VER=$(gcc --version|grep '^gcc'|sed -e 's/.*) //')
# gcc (Gentoo 11.2.1_p20220115 p4) 11.2.1 20220115
#GCC_VER=$(gcc --version|grep '^gcc'|sed -e 's/.*(.*) \(.*\) .*/\1/')
#GCC_VER=$(gcc --version|grep '^gcc'|sed -e 's/.*(.*) \([[:graph:]]*\).*/\1/')
# just the major version
GCC_VER=$(gcc --version|grep '^gcc'|sed -e 's/.*(.*) \([[:digit:]]*\).*/\1/')

INITRAMFS="/usr/src/initramfs-current" #$KERNEL_VER"

echo KERNEL_VER=$KERNEL_VER
echo GCC_VER=$GCC_VER
echo INITRAMFS=$INITRAMFS

# https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples
# https://wiki.gentoo.org/wiki/Custom_Initramfs

grub_install() {
	mount /boot
	grub-install --compress=xz --no-nvram --target=x86_64-efi --efi-directory=/boot --removable
}

grub_update() {
	ZPOOL_VDEV_NAME_PATH=1 grub-mkconfig -o /boot/grub/grub.cfg
}

install_prereq() {
	echo 'app-misc/pax-utils python' >> /etc/portage/package.use/10-local
	echo 'sys-apps/busybox mdev' >> /etc/portage/package.use/10-local
	#echo 'sys-fs/cryptsetup static' >> /etc/portage/package.use/10-local
	emerge -tav busybox app-misc/pax-utils cryptsetup
}

create() {
	mkdir -p $INITRAMFS/{bin,dev,etc,lib/modules,lib64,proc,root,sbin,sys,newroot,run/cryptsetup}
	cp -a /dev/{null,console,tty} $INITRAMFS/dev/
	cp -a /bin/busybox $INITRAMFS/bin/busybox
	cp -a /dev/{urandom,random} $INITRAMFS/dev
	cp -a /sbin/cryptsetup $INITRAMFS/sbin/cryptsetup

	lddtree --copy-to-tree $INITRAMFS /bin/busybox
	ln -s ../bin/busybox $INITRAMFS/sbin/mdev
	chroot $INITRAMFS /bin/busybox --install -s

	lddtree --copy-to-tree $INITRAMFS /sbin/cryptsetup
	lddtree --copy-to-tree $INITRAMFS /sbin/zpool
	lddtree --copy-to-tree $INITRAMFS /sbin/zfs
	lddtree --copy-to-tree $INITRAMFS /sbin/mount.zfs
	# doesn't really exist anymore lddtree --copy-to-tree $INITRAMFS /sbin/fsck.zfs
	lddtree --copy-to-tree $INITRAMFS /sbin/zdb
	# Why is this not copied over by cryptsetup?!
	cp "/usr/lib/gcc/x86_64-pc-linux-gnu/$GCC_VER/libgcc_s.so.1" $INITRAMFS/lib64/

	cp -av "/lib/modules/${KERNEL_VER}" $INITRAMFS/lib/modules/
	mkdir -p $INITRAMFS/lib/firmware
	cp -av /lib/firmware/amd* $INITRAMFS/lib/firmware/
	#cp -av /lib/firmware $INITRAMFS/lib/

	cp -av /usr/src/initramfs-skel/init $INITRAMFS/init

	mkdir -p $INITRAMFS/etc/zfs
	zpool set cachefile=/etc/zfs/zpool.cache zroot
	cp -av /etc/zfs/zpool.cache $INITRAMFS/etc/zfs/
	zpool set cachefile=none zroot

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
	make install
	grub_update
	echo "DONE!"
}

$@

#create_initramfs
