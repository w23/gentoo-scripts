#!/bin/bash
set -eux
export CCACHE_DIR=/var/cache/ccache
update() {
	eix-sync
	time chrt -i 0 emerge -DuNtav --with-bdeps=y --keep-going @selected --backtrack 10000 --autounmask-keep-masks --autounmask --autounmask-write
	emerge -ca
	eclean-dist -d
	ccache -s
	ccache -z
	time ccache -c
}
time update
