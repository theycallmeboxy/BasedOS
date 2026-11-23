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
# uncommitted changes, so a release is always a commit. Beside them, the setup card's zip (below).
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:?usage: release.sh <tag>}
OUT=$REPO/out
# out/ must be one whole build, of the tag: build.sh's manifest (out/build.sha256, written last)
# names the build, and every file published must match it (a later build that stopped part-way
# leaves no manifest, and files of its own in out/).
[ -f "$OUT/build.sha256" ] || { echo "out/ holds no finished build (no build.sha256): build again" >&2; exit 1; }
BUILD=$(sed -n 's/^# build //p' "$OUT/build.sha256")
case "$BUILD" in
''|*-dirty*) echo "out/ is from a build with uncommitted or untracked changes ($BUILD): commit, then build again" >&2; exit 1 ;;
esac
# The build carries the release's name (/etc/baseos-release, the maintenance screen,
# basedos-update): tag the commit first (git tag -a <tag>), then build, then release.
[ "$BUILD" = "$TAG" ] || { echo "out/ is build $BUILD, not $TAG: tag the commit $TAG first, then build again" >&2; exit 1; }
(cd "$OUT" && grep -v '^#' build.sha256 | sha256sum -c --quiet) ||
	{ echo "out/'s files aren't the ones build $BUILD made: build again" >&2; exit 1; }
[ "$(tar -xOf "$OUT"/baseos-*.bosupd manifest 2>/dev/null | sed -n 's/^build=//p')" = "$TAG" ] &&
	grep -qx "BUILD=$TAG" "$OUT/release.info" ||
	{ echo "out/'s .bosupd or release.info isn't build $TAG" >&2; exit 1; }
BOSUPD=$(cd "$OUT" && ls baseos-gkd350hultra-*.bosupd 2>/dev/null | head -1)
[ -n "$BOSUPD" ] || { echo "out/ has no .bosupd" >&2; exit 1; }
# The setup script is the build's copy, and the tag's.
git -C "$REPO" show "$TAG:tools/basedos-setup.sh" | cmp -s - "$OUT/basedos-setup.sh" ||
	{ echo "out/basedos-setup.sh isn't $TAG's tools/basedos-setup.sh" >&2; exit 1; }
R=$OUT/release-$TAG
rm -rf "$R"; mkdir -p "$R"
sed "s|^RELEASE_TAG=@RELEASE_TAG@\$|RELEASE_TAG=$TAG|" "$OUT/basedos-setup.sh" > "$R/basedos-setup.sh"
grep -qx "RELEASE_TAG=$TAG" "$R/basedos-setup.sh" || { echo "couldn't write the tag into basedos-setup.sh" >&2; exit 1; }
FILES="release.info rootfs.squashfs initrd.uimg boot.scr recovery-initrd.uimg recovery.scr rk3576_usb_loader_ddr1.13_usbplug1.04.bin LICENSE.rkbin.txt $BOSUPD"
for f in $FILES; do
	cp "$OUT/$f" "$R/$f"
done
(cd "$R" && sha256sum basedos-setup.sh $FILES > SHA256SUMS)
# The setup card, for setup with no PC and no network: unpacked onto an SD card, BasedOS's menu in
# stock's Ports (the same file setup puts on the built-in storage) and the release beside it (all
# but the update payload, which setup doesn't use). Not in SHA256SUMS: it holds that file itself.
CARD_ZIP=basedos-setup-card-$TAG.zip
S=$OUT/setup-card-$TAG
rm -rf "$S"; mkdir -p "$S/roms/ports" "$S/basedos-setup"
git -C "$REPO" show "$TAG:overlay/usr/share/basedos/stock/BasedOS.sh" > "$S/roms/ports/BasedOS.sh"
for f in basedos-setup.sh SHA256SUMS $FILES; do
	case "$f" in *.bosupd) continue ;; esac
	cp "$R/$f" "$S/basedos-setup/$f"
done
(cd "$S" && python3 -m zipfile -c "$R/$CARD_ZIP" roms basedos-setup) || { echo "couldn't make $CARD_ZIP" >&2; exit 1; }
rm -rf "$S"
echo "release $TAG (build $BUILD) in $R:"
ls -l "$R"
