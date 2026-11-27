#!/bin/bash
# bash for BasedOS: PortMaster and nearly every port are bash scripts (#!/bin/bash; arrays,
# BASH_SOURCE, process substitution), and spruce's H700 BaseOS has bash in its base. Stock has
# none (only readline and ncurses), so it is built here from GNU's release tarball (GPL-3.0-or-later;
# the licence goes in the image), with bash's own readline and termcap. Linked against glibc only
# (the vendor layer's 2.40; this cross toolchain's is older, which glibc allows), not static: a
# static glibc loads the NSS modules for user lookups (~user, getpwuid) at run time, and those must
# be from the glibc it was linked with.
#   build.sh <out dir>          (WSL or the build container; needs gcc-aarch64-linux-gnu, make, curl)
set -euo pipefail
OUT=$1
W=${BASH_WORK:-$HOME/basedos-bash}
VER=5.2.37
SHA256=9599b22ecd1d5787ad7d3b7bf0c59f312b3396d1e281175dd1f8a4014da621ff
TAR=bash-$VER.tar.gz
CROSS=aarch64-linux-gnu

mkdir -p "$W" "$OUT"
cd "$W"
[ -f "$TAR" ] || curl -fsSLO "https://ftp.gnu.org/gnu/bash/$TAR"
echo "$SHA256  $TAR" | sha256sum -c --quiet
rm -rf "bash-$VER"
tar xzf "$TAR"
cd "bash-$VER"
# Without bash's own malloc (glibc's is fine and smaller), no translations; readline and termcap
# are the copies in bash's tree (--with-installed-readline and --with-curses are not given).
./configure -q --host=$CROSS --prefix=/usr --without-bash-malloc --disable-nls >/dev/null
make -s -j"$(nproc)" >/dev/null
$CROSS-strip bash
# glibc and nothing else: the vendor layer has it, and the rootfs build's closure check confirms it.
needed=$($CROSS-readelf -d bash | awk '/\(NEEDED\)/ { gsub(/[][]/, "", $NF); printf "%s ", $NF }')
case "$needed" in
"libc.so.6 "|"libc.so.6 ld-linux-aarch64.so.1 ") ;;
*) echo "bash needs more than glibc: $needed" >&2; exit 1 ;;
esac
install -m 755 bash "$OUT/bash"
install -m 644 COPYING "$OUT/COPYING"
{
	echo "bash $VER, GNU (https://www.gnu.org/software/bash/), $TAR sha256 $SHA256"
	echo "built for aarch64 (glibc only) by tools/bash/build.sh: --without-bash-malloc --disable-nls"
	sha256sum "$OUT/bash" | sed "s#$OUT/##"
} > "$OUT/build-info"
cat "$OUT/build-info"
