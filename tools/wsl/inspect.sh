R=$HOME/basedos-work/stock-root
cd $R
echo "== GPU libs"; ls -la usr/lib/libEGL* usr/lib/libGLES* usr/lib/libgbm* usr/lib/libmali* usr/lib/libwayland-egl* usr/lib/libSDL2-2.0* 2>&1 | cut -c1-160
echo "== mali dirs"; find . -path ./proc -prune -o \( -iname "*mali*" -o -iname "*panfrost*" \) -print 2>/dev/null | head -30
echo "== who bind-mounts GPU libs"; grep -rlE "libEGL|libmali|gpudriver|GPU_DRIVER" usr/lib/systemd/system usr/bin/*.sh usr/lib/rocknix usr/lib/autostart 2>/dev/null | head
echo "== sizes"; du -sh usr/lib/python3* usr/lib/firmware usr/lib/modules usr/share/alsa 2>/dev/null
echo "== sshd/sftp"; ls -la usr/sbin/sshd usr/lib/openssh/sftp-server usr/libexec/sftp-server 2>&1 | cut -c1-120
ls usr/lib/modules
find usr/lib/modules -name "*.ko*"
ls usr/lib/firmware | head -40
