#!/usr/bin/env python3
"""Build the spruce-for-GKD kit from the spruce fork: an overlay zip (unzip over a spruce card),
the same change as git patches, and release notes.

  spruce-kit.py <spruce repo> <out dir> [--branch gkd350h-ultra] [--base origin/Development]

The overlay holds every file the branch adds or changes relative to its merge base with the
upstream branch, at the branch's version; files the branch deletes are listed in REMOVED.txt.
Nothing else from spruce is included, so the kit only works on top of a spruce install.
"""
import argparse
import datetime
import os
import subprocess
import sys
import zipfile


def git(repo, *args, binary=False):
    out = subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True).stdout
    return out if binary else out.decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("out")
    ap.add_argument("--branch", default="gkd350h-ultra")
    ap.add_argument("--base", default="origin/Development")
    a = ap.parse_args()

    base = git(a.repo, "merge-base", a.base, a.branch).strip()
    head = git(a.repo, "rev-parse", a.branch).strip()
    version = git(a.repo, "show", f"{base}:spruce/spruce").strip()
    base_date = git(a.repo, "show", "-s", "--format=%cs", base).strip()
    tag = f"spruce-{version}-gkd350hultra-{head[:8]}"
    os.makedirs(a.out, exist_ok=True)

    changes = git(a.repo, "diff", "--name-status", "--no-renames", base, a.branch).splitlines()
    added_or_changed = [l.split("\t", 1)[1] for l in changes if l[0] in "AM"]
    removed = [l.split("\t", 1)[1] for l in changes if l[0] == "D"]

    zpath = os.path.join(a.out, f"{tag}-overlay.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for path in added_or_changed:
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, git(a.repo, "show", f"{a.branch}:{path}", binary=True))
        if removed:
            z.writestr("GKD-REMOVED.txt", "\n".join(removed) + "\n")

    pdir = os.path.join(a.out, f"{tag}-patches")
    os.makedirs(pdir, exist_ok=True)
    subprocess.run(["git", "-C", a.repo, "format-patch", "-q", "-o", os.path.abspath(pdir), f"{base}..{a.branch}"],
                   check=True)

    log = git(a.repo, "log", "--reverse", "--format=- %s", f"{base}..{a.branch}")
    notes = f"""# spruce for the GKD 350H Ultra (on BasedOS): {tag}

Built {datetime.date.today().isoformat()} from the spruce fork branch `{a.branch}` at `{head[:12]}`.
Based on spruce `{version}`, upstream commit `{base[:12]}` ({base_date}).

## What this is

spruce does not support the GKD 350H Ultra yet. This kit adds it, for a GKD running BasedOS
(github.com/theycallmeboxy/BasedOS). It changes {len(added_or_changed)} files of spruce and touches
nothing else; a card set up this way still works in your other spruce devices.

## Which spruce to put it on

A spruce **nightly built from upstream commit `{base[:12]}` or later**, until these changes are
merged (then the kit is no longer needed). Nightlies list their commit in `commits_nightly.txt`
at the root of the card. An older nightly can mix old and new versions of the same scripts.

## Install

1. Install the spruce nightly on the card as usual (extract it to the root of a FAT32 card).
2. Unzip `{os.path.basename(zpath)}` to the root of the card and let it overwrite.
3. Put the card in the GKD (BasedOS installed) and power on.

After a spruce update, unzip the kit again (or a newer one): an update puts spruce's own files back.

## Changes

{log}
## Known gaps

See the BasedOS repo, docs/spruce-on-gkd.md, for what works and what doesn't yet.
"""
    with open(os.path.join(a.out, f"{tag}-RELEASE-NOTES.md"), "w", encoding="utf-8") as f:
        f.write(notes)
    print(f"{tag}: {len(added_or_changed)} files in the overlay, {len(removed)} removed, "
          f"{len(os.listdir(pdir))} patches -> {a.out}")


if __name__ == "__main__":
    sys.exit(main())
