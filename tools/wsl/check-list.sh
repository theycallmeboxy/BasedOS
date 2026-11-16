R=$HOME/basedos-work/stock-root
grep -vE '^\s*(#|$)' /mnt/e/projects/spruceOS-gkd350hultra/basedos/manifest/harvest.list | sed 's/ *=>.*//' | while read -r p; do [ -e "$R$p" ] || [ -L "$R$p" ] || echo "MISSING $p"; done
ls $R/usr/sbin | grep -iE "fsck|mkfs|e2|exfat|dosfs" | tr '\n' ' '; echo
ls $R/usr/bin | grep -iE "wpa|iw$|rfkill|hcitool|evtest|amixer|aplay|alsa" | tr '\n' ' '
