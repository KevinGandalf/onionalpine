#!/usr/bin/env python3
"""Extract an Alpine minirootfs without chown or mknod (sandbox allows only uid 0)."""
import os
import sys
import tarfile

def main():
    archive, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    skipped = 0
    with tarfile.open(archive, "r:gz") as tf:
        for m in tf:
            if m.isdev() or m.ischr() or m.isblk() or m.isfifo():
                skipped += 1
                continue
            target = os.path.join(dest, m.name)
            try:
                tf.extract(m, dest, set_attrs=False)
            except Exception as e:
                print(f"skip {m.name}: {e}", file=sys.stderr)
                skipped += 1
                continue
            # apply mode only (owner stays root)
            try:
                if m.issym():
                    continue
                if m.islnk():
                    continue
                os.chmod(target, m.mode & 0o7777)
            except Exception:
                pass
    print(f"extracted into {dest}, skipped {skipped} special files")

if __name__ == "__main__":
    main()
