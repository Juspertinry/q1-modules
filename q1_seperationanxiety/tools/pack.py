#!/usr/bin/env python3
"""Zip module/ into dist/. Entries keep forward slashes and LF endings,
otherwise Magisk's shell chokes on them. The .ko is a prebuilt: see README for
why rebuilding needs the recovered symbol CRCs."""
import pathlib
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
mod = root / "module"

version = next(
    line.split("=", 1)[1].strip()
    for line in (mod / "module.prop").read_text().splitlines()
    if line.startswith("version=")
)

out = root / "dist" / f"q1_seperationanxiety-{version}.zip"
out.parent.mkdir(exist_ok=True)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for path in sorted(mod.rglob("*")):
        if not path.is_file():
            continue
        arc = path.relative_to(mod).as_posix()
        data = path.read_bytes()
        if path.suffix != ".ko" and b"\r\n" in data:
            sys.exit(f"CRLF in {arc}, refusing to pack")
        z.writestr(arc, data)

print(out)
for info in zipfile.ZipFile(out).infolist():
    print(f"  {info.file_size:7d}  {info.filename}")
