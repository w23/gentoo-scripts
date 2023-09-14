#!/bin/bash
set -eux

download() {
	emerge-webrsync
	emerge --sync
	#zfs snapshot -r zroot@portage
}

prepare() {
	echo "ACCEPT_LICENSE=\"*\"
PORTAGE_NICENESS=19
USE=\"-bindist -doc -fonts -themes -sendmail mmx sse sse2\"" >> /etc/portage/make.conf
#MAKEOPTS=\"-j32 -l4\"
}

march() {
	emerge -tv app-portage/cpuid2cpuflags

	echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
	gcc -v -E -x c -march=native -mtune=native - < /dev/null 2>&1 | grep cc1 | perl -pe 's/^.* - //g;' >> /etc/portage/make.conf
	# BEWARE, THIS BREAKS STUFF: -mtune=generic -fno-strict-overflow -fPIE -fstack-protector-all -fstack-check=specific"

	# FIXME
	nano /etc/portage/make.conf
}

ccache() {
	emerge -tv ccache
	chown root:portage /var/cache/ccache
	chmod 2775 /var/cache/ccache
	echo "FEATURES=\"\${FEATURES} ccache cgroup splitdebug\"
GRUB_PLATFORMS=\"efi-64\"
CCACHE_SIZE=\"32G\"
CCACHE_DIR=/var/cache/ccache" >> /etc/portage/make.conf
}

# In my experience distcc overhead is not worth it
#distcc() {
#	emerge -tv distcc
#	#distcc-config --set-hosts 'baton,cpp,lzo'
#	#FEATURES+="ccache cgroup splitdebug distcc distcc-pump"
#}

update_world() {
	emerge --ask --update --deep --newuse @world
}

essentials() {
	emerge -tav \
		vim tmux app-misc/mc gentoolkit wpa_supplicant pciutils usbutils mlocate dhcpcd eix logrotate sudo htop lsof \
		openssh
	eix-update
	eselect kernel set 1
}

install_genkernel() {
	emerge -tav grub genkernel gentoo-sources linux-firmware
	genkernel --makeopts=-j32 kernel
}

install_zfs() {
	emerge -tav \
		sys-fs/zfs '>=sys-fs/zfs-kmod-2.0.4' zfs-auto-snapshot \
		--autounmask --autounmask-write  --backtrack=1000
}

init() {
	download
	prepare
	march
	ccache
	essentials
}

"$@"
