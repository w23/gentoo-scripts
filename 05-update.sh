#!/bin/bash
set -eux
export CCACHE_DIR=/var/cache/ccache

update() {
	eix-sync
}

upgrade() {
	time chrt -i 0 emerge -DuNtav --with-bdeps=y --keep-going @selected --backtrack 10000 --autounmask-keep-masks --verbose-conflicts
}

clean() {
	emerge -ca || echo ca
	eclean-dist -d
	ccache -s
	ccache -z
	time ccache -c
}

all() {
	time update
	time upgrade
	time clean
}

time "$@" || date && date
