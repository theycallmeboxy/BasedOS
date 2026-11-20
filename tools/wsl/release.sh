#!/bin/sh
# Assemble a BasedOS release from out/ (tools/wsl/build.sh) for publishing:
#
#   release.sh <tag>     e.g. v0.0.1-pre.1; writes out/release-<tag>/
#
# The release is what basedos-setup.sh downloads on the device: the setup script (with <tag>
# written in, so it fetches the rest from that release), release.info (what setup checks first),
# the system layer, the initrd, BasedOS's
# boot script, the recovery card's initrd and boot script, and SHA256SUMS. Nothing of stock's: no
# vendor set, no boot.env (setup makes both on the device). Refuses a build from a tree with
# uncommitted changes, so a release is always a commit.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:?usage: release.sh <tag>}
OUT=$REPO/out
BUILD=$(tar -xOf "$OUT"/baseos-*.bosupd manifest 2>/dev/null | sed -n 's/^build=//p')
case "$BUILD" in
''|*-dirty*) echo "out/ is from a build with uncommitted changes ($BUILD): commit, then build again" >&2; exit 1 ;;
esac
R=$OUT/release-$TAG
rm -rf "$R"; mkdir -p "$R"
sed "s|^RELEASE_TAG=@RELEASE_TAG@\$|RELEASE_TAG=$TAG|" "$REPO/tools/basedos-setup.sh" > "$R/basedos-setup.sh"
grep -qx "RELEASE_TAG=$TAG" "$R/basedos-setup.sh" || { echo "couldn't write the tag into basedos-setup.sh" >&2; exit 1; }
for f in release.info rootfs.squashfs initrd.uimg boot.scr recovery-initrd.uimg recovery.scr; do
	cp "$OUT/$f" "$R/$f"
done
(cd "$R" && sha256sum basedos-setup.sh release.info rootfs.squashfs initrd.uimg boot.scr recovery-initrd.uimg recovery.scr > SHA256SUMS)
echo "release $TAG (build $BUILD) in $R:"
ls -l "$R"
