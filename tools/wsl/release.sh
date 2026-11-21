#!/bin/sh
# Assemble a BasedOS release from out/ (tools/wsl/build.sh) for publishing:
#
#   release.sh <tag>     e.g. v0.0.1-pre.1; writes out/release-<tag>/
#
# The release is what basedos-setup.sh downloads on the device: the setup script (with <tag>
# written in, so it fetches the rest from that release), release.info (what setup checks first),
# the system layer, the initrd, BasedOS's
# boot script, the recovery card's initrd and boot script, the maskrom USB loader with rkbin's
# licence (for recovery cards), the update payload (.bosupd: an install updates itself from it,
# from the card root or through spruce's updater), and SHA256SUMS. Nothing of stock's
# (BasedOS uses the device's own stock files in place). Refuses a build from a tree with
# uncommitted changes, so a release is always a commit.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:?usage: release.sh <tag>}
OUT=$REPO/out
BUILD=$(tar -xOf "$OUT"/baseos-*.bosupd manifest 2>/dev/null | sed -n 's/^build=//p')
case "$BUILD" in
''|*-dirty*) echo "out/ is from a build with uncommitted changes ($BUILD): commit, then build again" >&2; exit 1 ;;
esac
# The build carries the release's name (/etc/baseos-release, the maintenance screen,
# basedos-update): tag the commit first (git tag -a <tag>), then build, then release.
[ "$BUILD" = "$TAG" ] || { echo "out/ is build $BUILD, not $TAG: tag the commit $TAG first, then build again" >&2; exit 1; }
BOSUPD=$(cd "$OUT" && ls baseos-gkd350hultra-*.bosupd 2>/dev/null | head -1)
[ -n "$BOSUPD" ] || { echo "out/ has no .bosupd" >&2; exit 1; }
R=$OUT/release-$TAG
rm -rf "$R"; mkdir -p "$R"
sed "s|^RELEASE_TAG=@RELEASE_TAG@\$|RELEASE_TAG=$TAG|" "$REPO/tools/basedos-setup.sh" > "$R/basedos-setup.sh"
grep -qx "RELEASE_TAG=$TAG" "$R/basedos-setup.sh" || { echo "couldn't write the tag into basedos-setup.sh" >&2; exit 1; }
FILES="release.info rootfs.squashfs initrd.uimg boot.scr recovery-initrd.uimg recovery.scr rk3576_usb_loader_ddr1.13_usbplug1.04.bin LICENSE.rkbin.txt $BOSUPD"
for f in $FILES; do
	cp "$OUT/$f" "$R/$f"
done
(cd "$R" && sha256sum basedos-setup.sh $FILES > SHA256SUMS)
echo "release $TAG (build $BUILD) in $R:"
ls -l "$R"
