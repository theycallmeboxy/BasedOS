#!/bin/sh
# Unpack a prepared stock SYSTEM squashfs into WSL's own filesystem (case
# sensitive, keeps symlinks and modes). Usage: unpack-stock.sh <SYSTEM> <dest>
# Unpacked to <dest>.partial and renamed only once whole: an interrupted unpack is never taken for
# a finished one. As a normal user, unsquashfs can't make stock's device nodes and says so (those
# messages are left out); any other message is shown, and a tree without stock's os-release and
# libraries stops here.
set -eu
src=$1 dest=$2
[ -e "$dest" ] && { echo "$dest exists; remove it first" >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
rm -rf "$dest.partial"
unsquashfs -q -no-xattrs -d "$dest.partial" "$src" > "$dest.unpack.log" 2>&1 || true
grep -vE "^(create_inode|Write on output file failed|.*Operation not permitted|$)" "$dest.unpack.log" | tail -20 >&2 || true
[ -f "$dest.partial/etc/os-release" ] && [ -d "$dest.partial/usr/lib" ] ||
	{ echo "unpacking $src failed (see $dest.unpack.log)" >&2; exit 1; }
mv "$dest.partial" "$dest"
echo "unpacked: $(find "$dest" | wc -l) entries, $(du -sh "$dest" | cut -f1)"
