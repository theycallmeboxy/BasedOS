# Mainline experiment: ROCKNIX's RK3576 kernel source, patched the way ROCKNIX's build patches it
# (scripts/unpack with PKG_PATCH_DIRS="mainline RK3576 default mainline-rockchip 7.2.6"), plus
# its generic DSI panel driver and device trees. Run in WSL; works in ~/mainline (ext4, fast).
#   sh tools/mainline/fetch.sh [rocknix commit]
# Leaves ~/mainline/linux-<ver>, ready for tools/mainline/build.sh.
set -e
W=~/mainline
REPO=https://github.com/ROCKNIX/distribution
mkdir -p "$W"
cd "$W"

if [ ! -d rocknix ]; then
	git clone -q --depth 1 --filter=blob:none --sparse -b next "$REPO" rocknix
fi
cd rocknix
[ -z "$1" ] || { git fetch -q --depth 1 origin "$1"; git checkout -q "$1"; }
git sparse-checkout set scripts projects/ROCKNIX/packages/linux projects/ROCKNIX/devices/RK3576 \
	projects/ROCKNIX/packages/linux-drivers/generic-dsi projects/ROCKNIX/patches/linux
echo "rocknix $(git log -1 --format='%h %cd' --date=short)"
P=$W/rocknix/projects/ROCKNIX

# The RK3576 case of ROCKNIX's linux package.mk: version and checksum.
mk=$P/packages/linux/package.mk
ver=$(sed -n '/^  RK3566|RK3576)/,/;;/s/^ *PKG_VERSION="\(.*\)"/\1/p' "$mk")
sha=$(sed -n '/^  RK3566|RK3576)/,/;;/s/^ *PKG_SHA256="\(.*\)"/\1/p' "$mk")
[ -n "$ver" ] && [ -n "$sha" ] || { echo "can't find the RK3576 kernel version in $mk"; exit 1; }
echo "linux $ver"

cd "$W"
tar=linux-$ver.tar.xz
[ -f "$tar" ] || curl -fL# -o "$tar" "https://www.kernel.org/pub/linux/kernel/v${ver%%.*}.x/$tar"
echo "$sha  $tar" | sha256sum -c --quiet
rm -rf "linux-$ver"
tar xf "$tar"
cd "linux-$ver"
git init -q && git add -A && git -c user.name=x -c user.email=x@x commit -qm "linux $ver"

# scripts/unpack's order, for PKG_DIR=projects/ROCKNIX/packages/linux and DEVICE=RK3576.
dirs="mainline RK3576 default mainline-rockchip 7.2.6"
K=$P/packages/linux/patches
D=$P/devices/RK3576/patches/linux
J=$P/patches/linux
list="$K/*.patch $K/aarch64/*.patch"
for d in $dirs; do list="$list $K/$d/*.patch"; done
list="$list $K/$ver/*.patch $K/$ver/aarch64/*.patch $J/*.patch $J/aarch64/*.patch"
for d in $dirs; do list="$list $J/$d/*.patch $D/$d/*.patch"; done
list="$list $J/$ver/*.patch $D/*.patch"
n=0
for p in $list; do
	[ -f "$p" ] || continue
	n=$((n + 1))
	if grep -qE '^GIT binary patch$|^rename from|^rename to' "$p"; then
		git apply --whitespace=nowarn "$p"
	else
		sed -e 's#@TARGET_CPU@#cortex-a72.cortex-a53#g' -e 's#@DEVICE@#RK3576#g' "$p" | patch -s -p1 -N
	fi
done
echo "$n patches applied"

# post_patch: the generic DSI panel driver, built in, and the device trees.
cp "$P/packages/linux-drivers/generic-dsi/sources/panel-generic-dsi.c" drivers/gpu/drm/panel/
echo "obj-y += panel-generic-dsi.o" >> drivers/gpu/drm/panel/Makefile
cp -r "$P/devices/RK3576/linux/dts/." arch/arm64/boot/dts/
cp "$P/devices/RK3576/linux/linux.aarch64.conf" .rocknix-config
git add -A && git -c user.name=x -c user.email=x@x commit -qm "rocknix RK3576 patches"

# BasedOS's own changes for the 350H Ultra (tools/mainline/patches), each a script that
# refuses when the source isn't what it expects.
for f in "$(dirname "$0")"/patches/*.py; do
	python3 "$f" .
done
git add -A && git -c user.name=x -c user.email=x@x commit -qm "BasedOS patches"
echo "ready: $W/linux-$ver"
