#!/usr/bin/env python3
"""Replace /init inside a gzip newc cpio initramfs."""
import gzip
import stat
import sys
from pathlib import Path


def parse(data: bytes):
    entries = []
    off = 0
    while off + 110 <= len(data):
        if data[off : off + 6] != b"070701":
            raise SystemExit(f"bad cpio magic at {off}")
        def hx(i):
            return int(data[off + i : off + i + 8], 16)
        fields = {
            "ino": hx(6),
            "mode": hx(14),
            "uid": hx(22),
            "gid": hx(30),
            "nlink": hx(38),
            "mtime": hx(46),
            "filesize": hx(54),
            "devmajor": hx(62),
            "devminor": hx(70),
            "rmajor": hx(78),
            "rminor": hx(86),
            "namesize": hx(94),
            "check": hx(102),
        }
        name_off = off + 110
        name = data[name_off : name_off + fields["namesize"]].split(b"\0", 1)[0].decode()
        data_off = (name_off + fields["namesize"] + 3) & ~3
        blob = data[data_off : data_off + fields["filesize"]]
        next_off = (data_off + fields["filesize"] + 3) & ~3
        entries.append((fields, name, blob))
        off = next_off
        if name.startswith("TRAILER"):
            break
    return entries, off


def emit(fields, name, blob) -> bytes:
    nameb = name.encode() + b"\0"
    filesize = len(blob)
    namesize = len(nameb)
    nums = [
        fields["ino"],
        fields["mode"],
        fields["uid"],
        fields["gid"],
        fields["nlink"],
        fields["mtime"],
        filesize,
        fields["devmajor"],
        fields["devminor"],
        fields["rmajor"],
        fields["rminor"],
        namesize,
        fields["check"],
    ]
    hdr = b"070701" + b"".join(f"{n:08X}".encode() for n in nums)
    out = hdr + nameb
    out += b"\0" * ((4 - (len(out) % 4)) % 4)
    out += blob
    out += b"\0" * ((4 - (len(blob) % 4)) % 4)
    return out


def main():
    src, init_path, dest = sys.argv[1:]
    raw = gzip.decompress(Path(src).read_bytes())
    entries, end = parse(raw)
    init = Path(init_path).read_bytes()
    if not init.endswith(b"\n"):
        init += b"\n"
    found = False
    chunks = []
    for fields, name, blob in entries:
        if name == "init":
            blob = init
            fields["mode"] = stat.S_IFREG | 0o755
            found = True
        chunks.append(emit(fields, name, blob))
    if not found:
        raise SystemExit("init not in cpio")
    Path(dest).write_bytes(gzip.compress(b"".join(chunks), mtime=0))
    print(f"wrote {dest} entries={len(entries)}")


if __name__ == "__main__":
    main()
