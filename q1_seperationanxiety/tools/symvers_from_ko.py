#!/usr/bin/env python3
"""Rebuild Module.symvers from a .ko's __versions section.

Meta ships no Module.symvers and the CRCs are not readable from the running
kernel: /proc/kallsyms has no __crc_* entries and kptr_restrict is 2. They are
in any module already built against that kernel, so recover them from the
prebuilt .ko rather than from the kernel image.
"""
import pathlib
import struct
import sys

# hrtimer exports are GPL-only upstream; the rest are plain EXPORT_SYMBOL.
GPL_ONLY = {
    "hrtimer_init", "hrtimer_cancel",
    "hrtimer_start_range_ns", "hrtimer_forward",
}

ko = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "module/seperationanxiety.ko")
out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "Module.symvers")
d = ko.read_bytes()

shoff, = struct.unpack_from("<Q", d, 0x28)
shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)


def section(i):
    return struct.unpack_from("<IIQQQQ", d, shoff + i * shentsize)


names = section(shstrndx)[4]
rows = []
for i in range(shnum):
    name, _, _, _, off, size = section(i)
    if d[names + name:d.index(b"\0", names + name)] != b"__versions":
        continue
    for j in range(0, size, 64):
        crc, = struct.unpack_from("<I", d, off + j)
        sym = d[off + j + 8:off + j + 64].split(b"\0")[0].decode()
        kind = "EXPORT_SYMBOL_GPL" if sym in GPL_ONLY else "EXPORT_SYMBOL"
        rows.append(f"0x{crc:08x}\t{sym}\tvmlinux\t{kind}")

if not rows:
    sys.exit(f"no __versions section in {ko}")

out.write_text("\n".join(rows) + "\n", newline="\n")
print(f"{out}  ({len(rows)} symbols)")
