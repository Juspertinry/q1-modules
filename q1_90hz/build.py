#!/usr/bin/env python3
"""Pack module/ into a flashable Magisk zip."""

import hashlib
import os
import sys
import zipfile

# Fixed order so the zip is reproducible across machines; os.walk is not.
FILES = [
    "bytepatch.sh",
    "customize.sh",
    "module.prop",
    "post-fs-data.sh",
    "service.sh",
    "uninstall.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "module")


def version():
    for line in open(os.path.join(SRC, "module.prop"), encoding="utf-8"):
        if line.startswith("version="):
            return line.split("=", 1)[1].strip()
    sys.exit("! module.prop has no version")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "vd90hz-%s.zip" % version()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in FILES:
            path = os.path.join(SRC, name)
            if not os.path.exists(path):
                sys.exit("! missing %s" % name)
            data = open(path, "rb").read()
            # busybox ash dies on CRLF with a bare "syntax error: unexpected
            # 'do'" and nothing else, and a failed post-fs-data.sh is silent
            # for a whole boot. Catch it here instead.
            if b"\r" in data:
                sys.exit("! %s has CRLF line endings" % name)
            z.writestr(name, data)

    print("%s  %d bytes  md5 %s"
          % (out, os.path.getsize(out),
             hashlib.md5(open(out, "rb").read()).hexdigest()))


main()
