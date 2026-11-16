R=$HOME/basedos-work/stock-root
ls -la $R/usr/lib/libSDL2* $R/usr/lib/glesonly/ 2>/dev/null | awk '{print $NF, $(NF-2)}' | head -20
