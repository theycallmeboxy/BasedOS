#!/bin/bash
# wpa_cli for BasedOS: the frontend's Wi-Fi menu (spruce's wifi.sh) scans, joins and reads the
# link through it, and the stock image ships wpa_supplicant without it. Built from the same
# release as stock's wpa_supplicant (2.11; the control interface's text protocol), the client
# alone, static, from hostap's official tarball (BSD-3-Clause; the licence goes in the image).
#   build.sh <out dir>          (WSL; needs gcc-aarch64-linux-gnu, curl)
set -euo pipefail
OUT=$1
W=${WPACLI_WORK:-$HOME/basedos-wpacli}
VER=2.11
SHA256=912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a
TAR=wpa_supplicant-$VER.tar.gz

mkdir -p "$W" "$OUT"
cd "$W"
[ -f "$TAR" ] || curl -fsSLO "https://w1.fi/releases/$TAR"
echo "$SHA256  $TAR" | sha256sum -c --quiet
rm -rf "wpa_supplicant-$VER"
tar xzf "$TAR"
cd "wpa_supplicant-$VER/wpa_supplicant"
# Only the control interface; no readline (edit_simple is built in).
printf 'CONFIG_CTRL_IFACE=y\n' > .config
make -s CC=aarch64-linux-gnu-gcc LDFLAGS=-static wpa_cli
aarch64-linux-gnu-strip wpa_cli
install -m 755 wpa_cli "$OUT/wpa_cli"
install -m 644 ../COPYING "$OUT/COPYING"
{
	echo "wpa_cli $VER, hostap (https://w1.fi), $TAR sha256 $SHA256"
	echo "built static for aarch64 by tools/wpa_cli/build.sh: CONFIG_CTRL_IFACE=y only"
	sha256sum "$OUT/wpa_cli" | sed "s#$OUT/##"
} > "$OUT/build-info"
cat "$OUT/build-info"
