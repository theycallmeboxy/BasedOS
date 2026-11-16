#!/bin/sh
# Unpack a prepared stock SYSTEM squashfs into WSL's own filesystem (case
# sensitive, keeps symlinks and modes). Usage: unpack-stock.sh <SYSTEM> <dest>
set -eu
src=$1 dest=$2
[ -e "$dest" ] && { echo "$dest exists; remove it first" >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
unsquashfs -q -no-xattrs -d "$dest" "$src" 2>&1 | grep -vE "^(create_inode|Write on output file failed|.*Operation not permitted)" | head -20 || true
echo "unpacked: $(find "$dest" | wc -l) entries, $(du -sh "$dest" | cut -f1)"
