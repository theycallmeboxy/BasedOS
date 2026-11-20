#!/bin/sh
# The sources a BasedOS release must offer (NOTICE.md), as one archive beside it:
#
#   release-sources.sh <tag>     writes out/release-<tag>/basedos-<tag>-sources.tar
#
# Needs: Buildroot's legal-info for both userland trees (make legal-info in $BR_WORK/out and
# out-armhf), Buildroot's own release tarball, bash's tarball (tools/bash/build.sh), and BusyBox's
# source for the Alpine build BasedOS ships, in ~/basedos-src-dl/busybox: busybox.net's tarball
# and Alpine's aports main/busybox (APKBUILD, patches, configs) at the matching release, both
# checked against the APKBUILD's sha512sums here again.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:?usage: release-sources.sh <tag>}
BRW=${BR_WORK:-$HOME/basedos-br}
BRVER=2025.02.20
BB=$HOME/basedos-src-dl/busybox
R=$REPO/out/release-$TAG
[ -d "$R" ] || { echo "no $R: run release.sh $TAG first" >&2; exit 1; }
NAME=basedos-$TAG-sources
S=$HOME/basedos-release-src/$NAME
rm -rf "$S"; mkdir -p "$S/buildroot/sources" "$S/busybox" "$S/bash"

# Buildroot: its own tarball, and each tree's legal-info (manifest, config, licences); the
# package sources once, shared by both trees (the same package versions).
cp "$BRW/buildroot-$BRVER.tar.gz" "$S/buildroot/"
for t in out:aarch64 out-armhf:armhf; do
	L=$BRW/${t%%:*}/legal-info
	[ -f "$L/manifest.csv" ] || { echo "no legal-info in $L (make legal-info)" >&2; exit 1; }
	mkdir -p "$S/buildroot/${t#*:}"
	cp -r "$L/manifest.csv" "$L/buildroot.config" "$L/licenses" "$L/README" "$S/buildroot/${t#*:}/"
	cp -rn "$L/sources/." "$S/buildroot/sources/"
done

# BusyBox: Alpine's busybox-static, as prepared/alpine/SOURCE names it.
PV=$(sed -n 's/^busybox-static \([0-9.]*\)-r\([0-9]*\) .*/\1 \2/p' "$REPO/prepared/alpine/SOURCE")
set -- $PV
A=$(ls -d "$BB"/aports-*/main/busybox)
grep -qx "pkgver=$1" "$A/APKBUILD" && grep -qx "pkgrel=$2" "$A/APKBUILD" ||
	{ echo "$A/APKBUILD isn't busybox $1-r$2" >&2; exit 1; }
(cd "$BB" && grep "  busybox-$1.tar.bz2\$" "$A/APKBUILD" | sed 's/^[[:space:]]*//' | sha512sum -c --quiet)
(cd "$A" && sed -n '/^sha512sums="/,/"$/p' APKBUILD | sed 's/^sha512sums="//; s/"$//' | grep -v "busybox-$1.tar.bz2" |
	grep . | sha512sum -c --quiet)
cp "$BB/busybox-$1.tar.bz2" "$S/busybox/"
cp -r "$A" "$S/busybox/alpine-aports-main-busybox"

# bash: GNU's release tarball, unmodified.
cp "$HOME/basedos-bash/bash-5.2.37.tar.gz" "$S/bash/"

cat > "$S/README.txt" <<EOF
Sources for BasedOS $TAG (GKD 350H Ultra), as its NOTICE.md requires of a release.

BasedOS's own code (MIT) is the repository at tag $TAG:
  https://github.com/theycallmeboxy/BasedOS/tree/$TAG
It holds the build configuration used: buildroot/ (the Buildroot external tree and defconfigs),
tools/ (the build scripts), overlay/ and initrd/.

buildroot/    The userland in rootfs.squashfs, built by Buildroot $BRVER (buildroot-$BRVER.tar.gz,
              unmodified): sources/ holds every target package's source and patches, as
              "make legal-info" collected them; aarch64/ and armhf/ hold each tree's manifest.csv
              (package, version, licence, source), buildroot.config and licence texts.
busybox/      BusyBox $1, Alpine Linux's busybox-static $1-r$2 (in rootfs.squashfs, initrd.uimg and
              recovery-initrd.uimg): busybox.net's tarball, and Alpine's aports main/busybox
              (APKBUILD, patches, configs) it's built with.
bash/         bash 5.2.37, GNU's release tarball, unmodified (built by tools/bash/build.sh).

Also in the release, not copyleft (licences in the image under /usr/share/licenses): SDL2 with
ArkOS's patches (zlib; patches in tools/sdl2/patches/), librga (Apache-2.0), zstd (BSD; its source
is in buildroot/sources/), Terminus Font (OFL-1.1). Nothing of the stock firmware is in the
release: each device builds its own vendor set from its own firmware.
EOF
rm -f "$R/$NAME.tar"
tar -C "$(dirname "$S")" -cf "$R/$NAME.tar" "$NAME"
ls -l "$R/$NAME.tar"
