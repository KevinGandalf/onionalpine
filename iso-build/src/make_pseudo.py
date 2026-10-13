#!/usr/bin/env python3
"""Build an mksquashfs pseudo file with non-root owners from apk tarballs."""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path("/workspace/iso-build/rootfs")
CACHE = Path("/workspace/iso-build/apk-cache")
OUT = Path("/workspace/iso-build/out/pseudo")

LINE = re.compile(
    r"^[\-dlcbps][\w\-]{9}\s+(\S+)/(\S+)\s+\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+(.*)$"
)


def load_ids(path, key_is_name=True):
    ids = {}
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split(":")
        if len(parts) < 3:
            continue
        name, gid = parts[0], parts[2]
        if gid.isdigit():
            ids[name] = int(gid)
    return ids


def resolve(table, token):
    if token in table:
        return table[token]
    if token.isdigit():
        return int(token)
    return 0


def main():
    users = load_ids(ROOT / "etc/passwd")
    groups = load_ids(ROOT / "etc/group")
    owners = {}  # rel path -> (uid, gid)

    apks = sorted(CACHE.glob("*.apk"))
    if not apks:
        raise SystemExit(f"no apks in {CACHE}")
    print(f"scanning {len(apks)} packages", flush=True)
    for i, apk in enumerate(apks, 1):
        if i % 80 == 0:
            print(f"  {i}/{len(apks)}", flush=True)
        proc = subprocess.run(
            ["tar", "-tvzf", str(apk)],
            capture_output=True,
            text=True,
            errors="replace",
        )
        for line in proc.stdout.splitlines():
            m = LINE.match(line)
            if not m:
                continue
            user, group, name = m.group(1), m.group(2), m.group(3)
            if " -> " in name:
                name = name.split(" -> ", 1)[0]
            name = name.lstrip("./")
            if not name or name.startswith(".") or name.endswith("/"):
                name = name.rstrip("/")
            if not name or name.startswith("."):
                continue
            uid = resolve(users, user)
            gid = resolve(groups, group)
            if uid or gid:
                owners[name] = (uid, gid)

    # Script-created paths recorded by the ownership shim (final paths only).
    log = ROOT / "fakeown.log"
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            parts = line.split("\t")
            if len(parts) >= 4 and parts[0] == "C":
                path = parts[1].lstrip("/")
                if not path or ".apk." in path:
                    continue
                uid, gid = int(parts[2]), int(parts[3])
                if uid or gid:
                    owners[path] = (uid, gid)

    lines = []
    missing = 0
    for rel, (uid, gid) in sorted(owners.items()):
        host = ROOT / rel
        if not host.exists() and not host.is_symlink():
            missing += 1
            continue
        mode = os.lstat(host).st_mode & 0o7777
        lines.append(f"{rel} m {mode:04o} {uid} {gid}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n")
    print(f"pseudo {len(lines)} entries, skipped missing {missing} -> {OUT}")


if __name__ == "__main__":
    main()
