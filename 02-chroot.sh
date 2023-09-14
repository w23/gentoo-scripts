#!/bin/bash
set -eux

prepare() {
	cp -L /etc/resolv.conf /mnt/gentoo/etc/
	mount -t proc /proc /mnt/gentoo/proc
	mount --rbind /sys /mnt/gentoo/sys
	mount --make-rslave /mnt/gentoo/sys
	mount --rbind /dev /mnt/gentoo/dev
	mount --make-rslave /mnt/gentoo/dev
	mount --bind /run /mnt/gentoo/run
	mount --make-slave /mnt/gentoo/run

	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
	mount -t tmpfs -o nosuid,nodev,noexec shm /dev/shm
	chmod 1777 /dev/shm
}

enter() {
	cp "$0" /mnt/gentoo/root/02-chroot.sh
	chroot /mnt/gentoo /bin/bash -i /root/02-chroot.sh enter_finalize
}

enter_finalize() {
	source /etc/profile
	set -e
	bash --rcfile <([ -f ~/.bashrc ] && cat ~/.bashrc; echo 'PS1="(chroot) $PS1"')
}

"$@"
