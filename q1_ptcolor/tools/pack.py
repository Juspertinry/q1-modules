#!/usr/bin/env python3
"""Zip module/ into dist/. Entries use forward slashes and the scripts keep LF
endings, which is what Magisk's installer expects. ptcolor and the shell
scripts need the exec bit, so modes are set explicitly rather than inherited
from whatever the checkout happens to have."""
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
mod = root / "module"

TEXT = ('.sh', '.prop', '.conf', 'update-binary', 'updater-script', 'ptcolor')

version = next(
    line.split("=", 1)[1].strip()
    for line in (mod / "module.prop").read_text().splitlines()
    if line.startswith("version=")
)

out = root / "dist" / f"q1_ptcolor-{version}.zip"
out.parent.mkdir(exist_ok=True)

files = sorted(
    (p, p.relative_to(mod).as_posix())
    for p in mod.rglob("*") if p.is_file()
)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for path, arc in files:
        data = path.read_bytes()
        if arc.endswith(TEXT) or path.name in TEXT:
            data = data.replace(b"\r\n", b"\n")
        zi = zipfile.ZipInfo(arc)
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = (0o755 if arc.endswith(('.sh', 'update-binary'))
                            or '/bin/' in arc else 0o644) << 16
        z.writestr(zi, data)

print(out)
for info in zipfile.ZipFile(out).infolist():
    print(f"  {info.file_size:7d}  {info.filename}")
