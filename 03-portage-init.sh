#!/bin/bash
set -eux

download() {
	emerge-webrsync
	emerge --sync
	#zfs snapshot -r zroot@portage
}

prepare() {
	echo 'ACCEPT_LICENSE="*"
# Compiler flags to set for all languages
COMMON_FLAGS="-march=native -O2 -pipe"
# Use the same settings for both variables
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="${RUSTFLAGS} -C target-cpu=native"
PORTAGE_NICENESS=19
MAKEOPTS="-j24 -l22"
GRUB_PLATFORMS="efi-64"
USE="-bindist -doc -sendmail mmx sse sse2"' \
	>> /etc/portage/make.conf

	echo '*/* VIDEO_CARDS: amdgpu radeonsi' > /etc/portage/package.use/00video_cards

	ln -sf ../usr/share/zoneinfo/America/New_York /etc/localtime

	echo "en_GB.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
C.UTF8 UTF-8" > /etc/locale.gen
	locale-gen

#USE=\"-bindist -doc -fonts -themes -sendmail mmx sse sse2\"" >> /etc/portage/make.conf
#MAKEOPTS=\"-j32 -l4\"
}

march() {
	emerge -tv app-portage/cpuid2cpuflags

	echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

	# This is for cross-compilation only:
	#gcc -v -E -x c -march=native -mtune=native - < /dev/null 2>&1 | grep cc1 | perl -pe 's/^.* - //g;' >> /etc/portage/make.conf
	# BEWARE, THIS BREAKS STUFF: -mtune=generic -fno-strict-overflow -fPIE -fstack-protector-all -fstack-check=specific"

	# FIXME
	nano /etc/portage/make.conf
}

ccache() {
	emerge -tv ccache
	mkdir -p /var/cache/ccache
	chown root:portage /var/cache/ccache
	chmod 2775 /var/cache/ccache
	echo "FEATURES=\"\${FEATURES} ccache splitdebug\"
CCACHE_SIZE=\"64G\"
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
		openssh tmux neovim
	eix-update
}


setup_kernel() {
	emerge -tav grub gentoo-sources linux-firmware
	eselect kernel set 1
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

time "$@"
