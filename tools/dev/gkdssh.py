#!/usr/bin/env python3
"""Minimal SSH/SFTP helper for the GKD 350H Ultra (stock ROCKNIX).

Password auth only, so nothing (no authorized_keys) is written to the eMMC.
Works anywhere paramiko does (Windows without rsync/sshpass included).

Env:  GKD_HOST (required), GKD_USER (default root),
      GKD_PASS (required; set it empty, GKD_PASS=, for an empty root password)

  gkdssh.py run  '<shell command>'          run a command, stream output, exit with its status
  gkdssh.py script <local.sh> [args...]     pipe a local script into `sh -s`
  gkdssh.py push <local> <remote>           copy a file or directory tree to the device
  gkdssh.py pull <remote> <local>           copy a file from the device
  gkdssh.py dump '<shell command>' <local> [--zstd]
                                            save a command's stdout (e.g. dd of a block
                                            device) to a local file; --zstd decompresses a
                                            zstd stream on the fly. Prints md5/sha256 of
                                            the bytes written. Refuses to overwrite.
"""
import hashlib
import os
import time
import posixpath
import stat
import sys

import paramiko
import paramiko.auth_strategy


def connect():
    host = os.environ.get("GKD_HOST")
    pw = os.environ.get("GKD_PASS")
    if not host or pw is None:
        sys.exit("set GKD_HOST and GKD_PASS")
    user = os.environ.get("GKD_USER", "root")
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    if pw == "":
        # Some stock builds let root in with an empty password ("none" auth),
        # which SSHClient.connect() does not try on its own.
        c.connect(host, username=user, password=None, timeout=8,
                  allow_agent=False, look_for_keys=False, auth_strategy=NoneAuth(user))
    else:
        c.connect(host, username=user, password=pw, timeout=8,
                  allow_agent=False, look_for_keys=False)
    return c


class NoneAuth(paramiko.auth_strategy.AuthStrategy):
    def __init__(self, user):
        super().__init__(ssh_config=paramiko.SSHConfig())
        self.user = user

    def get_sources(self):
        yield _NoneSource(self.user)


class _NoneSource(paramiko.auth_strategy.AuthSource):
    def authenticate(self, transport):
        return transport.auth_none(self.username)


def run(c, cmd, stdin_data=None):
    chan = c.get_transport().open_session()
    chan.set_combine_stderr(True)
    chan.exec_command(cmd)
    if stdin_data is not None:
        chan.sendall(stdin_data)
        chan.shutdown_write()
    out = sys.stdout.buffer
    while True:
        data = chan.recv(65536)
        if not data:
            break
        out.write(data)
        out.flush()
    return chan.recv_exit_status()


def sftp_mkdirs(sftp, path):
    parts = []
    while path not in ("", "/"):
        try:
            sftp.stat(path)
            break
        except IOError:
            parts.append(path)
            path = posixpath.dirname(path)
    for p in reversed(parts):
        sftp.mkdir(p)


# The only places on the device we may write to: RAM, the SD card, and the
# systemd hook directory. Everything else under /storage is the eMMC.
WRITABLE = ("/tmp/", "/run/", "/storage/games-external/", "/storage/.config/system.d/")


def check_remote(remote):
    # Git Bash/MSYS rewrites "/tmp/x" into "C:/Users/.../Temp/x"; a relative
    # path would then land in root's home (/storage, the eMMC). Refuse both.
    if not remote.startswith("/") or ":" in remote or "\\" in remote:
        sys.exit(f"refusing remote path {remote!r}: must be an absolute POSIX path "
                 "(on Git Bash set MSYS_NO_PATHCONV=1)")
    norm = posixpath.normpath(remote) + "/"
    if not norm.startswith(WRITABLE):
        sys.exit(f"refusing to write {remote!r}: outside {', '.join(WRITABLE)}")


def card_mounted(c):
    _i, o, _e = c.exec_command("grep -q ' /storage/games-external ' /proc/mounts && echo yes")
    return o.read().strip() == b"yes"


def push(c, local, remote):
    check_remote(remote)
    # With the card out, /storage/games-external is a plain folder on the eMMC.
    if posixpath.normpath(remote).startswith("/storage/games-external") and not card_mounted(c):
        sys.exit("refusing: the SD card is not mounted at /storage/games-external")
    sftp = c.open_sftp()
    n = 0
    if os.path.isdir(local):
        for root, _dirs, files in os.walk(local):
            rel = os.path.relpath(root, local).replace(os.sep, "/")
            rdir = remote if rel == "." else posixpath.join(remote, rel)
            sftp_mkdirs(sftp, rdir)
            for f in files:
                sftp.put(os.path.join(root, f), posixpath.join(rdir, f))
                n += 1
    else:
        sftp_mkdirs(sftp, posixpath.dirname(remote))
        sftp.put(local, remote)
        n = 1
    print(f"pushed {n} file(s) -> {remote}", file=sys.stderr)


def pull(c, remote, local):
    sftp = c.open_sftp()
    if stat.S_ISDIR(sftp.stat(remote).st_mode):
        sys.exit("pull: directories not supported; tar them on the device first")
    sftp.get(remote, local)


def dump(c, cmd, local, use_zstd):
    if os.path.exists(local):
        sys.exit(f"refusing to overwrite {local}")
    chan = c.get_transport().open_session(window_size=16 << 20, max_packet_size=32768)
    chan.exec_command(cmd)
    got = 0
    t0 = last = time.time()
    part = local + ".part"
    with open(part, "xb") as f:
        out = HashingWriter(f)
        sink = out
        if use_zstd:
            # stream_writer hands output on in bounded chunks. (decompressobj()
            # does not: on long runs of zeros it balloons and stalls.)
            import zstandard
            sink = zstandard.ZstdDecompressor().stream_writer(out, write_size=1 << 20,
                                                              closefd=False)
        while True:
            while chan.recv_stderr_ready():
                sys.stderr.buffer.write(chan.recv_stderr(65536))
            data = chan.recv(1 << 20)
            if not data:
                break
            got += len(data)
            sink.write(data)
            now = time.time()
            if now - last >= 15:
                last = now
                print(f"  {out.n / 2**20:9.0f} MiB written, {got / 2**20:8.0f} MiB received, "
                      f"{got / 2**20 / (now - t0):5.1f} MiB/s on the wire", file=sys.stderr, flush=True)
        if sink is not out:
            sink.flush()
    while chan.recv_stderr_ready():
        sys.stderr.buffer.write(chan.recv_stderr(65536))
    rc = chan.recv_exit_status()
    if rc != 0:
        sys.exit(f"remote command failed (exit {rc}); partial output left in {part}")
    os.replace(part, local)
    print(f"bytes={out.n} md5={out.md5.hexdigest()} sha256={out.sha.hexdigest()} "
          f"seconds={time.time() - t0:.0f}")


class HashingWriter:
    def __init__(self, f):
        self.f, self.n = f, 0
        self.md5, self.sha = hashlib.md5(), hashlib.sha256()

    def write(self, data):
        self.f.write(data)
        self.md5.update(data)
        self.sha.update(data)
        self.n += len(data)
        return len(data)

    def flush(self):
        self.f.flush()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    op = sys.argv[1]
    c = connect()
    try:
        if op == "run":
            sys.exit(run(c, sys.argv[2]))
        elif op == "script":
            with open(sys.argv[2], "rb") as f:
                body = f.read().replace(b"\r\n", b"\n")
            args = " ".join("'" + a.replace("'", "'\\''") + "'" for a in sys.argv[3:])
            sys.exit(run(c, "sh -s " + args, body))
        elif op == "push":
            push(c, sys.argv[2], sys.argv[3])
        elif op == "pull":
            pull(c, sys.argv[2], sys.argv[3])
        elif op == "dump":
            dump(c, sys.argv[2], sys.argv[3], "--zstd" in sys.argv[4:])
        else:
            sys.exit(__doc__)
    finally:
        c.close()


if __name__ == "__main__":
    main()
