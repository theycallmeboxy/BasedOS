#!/bin/bash
# BasedOS's userland from Buildroot (docs/vendor-minimal.md): the pinned LTS release and this
# repo's external tree (buildroot/, defconfig basedos_gkd350hultra_defconfig), built in WSL or in the build container
# (tools/container/run.sh, any Linux host).
#
#   build.sh config     fetch and check Buildroot, apply the defconfig, check every option took
#   build.sh sources    config, then list each package source Buildroot would download
#   build.sh build      config, then build (the root lands in $BR_OUT/target)
#   build.sh --armhf ...  the same for the 32-bit root (basedos_gkd350hultra_armhf_defconfig,
#                       in $BR32_OUT, default $BR_WORK/out-armhf): the libraries 32-bit ports need
#                       ($BR_OUT, default $BR_WORK/out, is the 64-bit root's alone)
#
# Needs (Ubuntu 24.04, in WSL or the build container): build-essential file wget cpio unzip rsync bc python3 perl
# Downloads go to ~/basedos-br-dl (BR2_DL_DIR) and are checked against Buildroot's own hashes.
set -euo pipefail
# WSL appends Windows' PATH (folders with spaces), which Buildroot refuses.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
REPO=$(cd "$(dirname "$0")/../.." && pwd)
W=${BR_WORK:-$HOME/basedos-br}
DEFCONFIG=basedos_gkd350hultra_defconfig
BR_OUT=${BR_OUT:-$W/out}
if [ "${1:-}" = --armhf ]; then
	DEFCONFIG=basedos_gkd350hultra_armhf_defconfig
	BR_OUT=${BR32_OUT:-$W/out-armhf}
	shift
fi
VER=2025.02.20
# From the release's signed buildroot-$VER.tar.gz.sign (https://buildroot.org/downloads/).
SHA256=44904ee44ac6750e06135454ed5cbcb8ea9354e6d5b7e2b2668581bd8b6ba1b6
TAR=buildroot-$VER.tar.gz
SRC=$W/buildroot-$VER

config() {
	mkdir -p "$W"
	cd "$W"
	[ -f "$TAR" ] || curl -fsSLO "https://buildroot.org/downloads/$TAR"
	echo "$SHA256  $TAR" | sha256sum -c --quiet
	[ -d "$SRC" ] || tar xzf "$TAR"
	make -s -C "$SRC" O="$BR_OUT" BR2_EXTERNAL="$REPO/buildroot" "$DEFCONFIG" >/dev/null
	# Kconfig drops options it doesn't know (a typo, or a package this release lacks) without a
	# word: every "=y" in the defconfig must be set in the result.
	missing=""
	for opt in $(sed -n 's/^\(BR2_[A-Z0-9_]*\)=y$/\1/p' "$REPO/buildroot/configs/$DEFCONFIG"); do
		grep -q "^$opt=y$" "$BR_OUT/.config" || missing="$missing $opt"
	done
	[ -z "$missing" ] || { echo "not set by Buildroot $VER:$missing" >&2; exit 1; }
	echo "Buildroot $VER configured in $BR_OUT"
}

case "${1:-}" in
config) config ;;
sources)
	config
	# One line per download: package, file and where it comes from.
	make -s -C "$SRC" O="$BR_OUT" show-info | python3 -c '
import json, sys
info = json.load(sys.stdin)
n = 0
for name, p in sorted(info.items()):
    for d in p.get("downloads", []):
        uris = d.get("uris", [])
        src = d.get("source", "")
        url = uris[0].split("|")[-1] if uris else ""
        print("%-28s %-50s %s" % (name, src, url))
        n += 1
print("%d downloads" % n, file=sys.stderr)
' ;;
build)
	config
	make -C "$SRC" O="$BR_OUT" -j"$(nproc)" ;;
*) echo "usage: $0 [--armhf] config|sources|build" >&2; exit 2 ;;
esac
