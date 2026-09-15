#!/usr/bin/env python3
"""Generate the module's patch from a stock MrServiceMonterey.apk.

Emits two same-length in-place rewrites instead of shipping Meta's shader blob:
a comment line becomes the #define, and the greyscale return becomes the tinted
one. Writes ../module/mr_patch and ../module/mr_colour_ks.bin.

Usage: python gen_payload.py [stock.apk]
"""
import hashlib, re, struct, sys, zipfile

SO_ENTRY = 'lib/arm64-v8a/libmrservice.so'
BASE   = 0xdec0dab1efeed332
TBL_VA = 0x5bdb8 + 0x11
LENGTH = 9032
DEFINE = b'#define PTT vec3(1.000,1.000,1.000)'
RETURN = b'return vec4(luminance*PTT,luminance);\n\n#endif'


def so_bounds(path):
    z = zipfile.ZipFile(path)
    zi = z.getinfo(SO_ENTRY)
    if zi.compress_type != 0:
        raise SystemExit('libmrservice.so is not STORED')
    raw = open(path, 'rb').read()
    nlen, elen = struct.unpack_from('<HH', raw, zi.header_offset + 26)
    return raw, zi.header_offset + 30 + nlen + elen, zi.file_size


def so_va2off(so):
    ph = struct.unpack_from('<Q', so, 0x20)[0]
    pe, pn = struct.unpack_from('<HH', so, 0x36)
    loads = []
    for i in range(pn):
        p = ph + i * pe
        if struct.unpack_from('<I', so, p)[0] == 1:
            off, va = struct.unpack_from('<QQ', so, p + 8)
            loads.append((off, va, struct.unpack_from('<Q', so, p + 32)[0]))
    def f(v):
        for off, va, sz in loads:
            if va <= v < va + sz:
                return off + (v - va)
    return f


def keystream(n0, count):
    return bytes(((((BASE >> (n % 56)) & 0xFFFFFFFF) + n) & 0xFF) for n in range(n0, n0 + count))


def decode(so, tb):
    out = bytearray(LENGTH); out[0] = 0x0a
    ks = keystream(1, LENGTH - 1)
    for i in range(LENGTH - 1):
        out[i + 1] = ks[i] ^ so[tb + i]
    return bytes(out)


def cipher(plain_off, text):
    ks = keystream(plain_off, len(text))
    return bytes(ks[i] ^ text[i] for i in range(len(text)))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'MrService.apk'
    raw, so_start, so_size = so_bounds(src)
    so = raw[so_start:so_start + so_size]
    tb = so_va2off(so)(TBL_VA)
    txt = decode(so, tb)
    if b'samplePassthroughTextures' not in txt:
        raise SystemExit('unexpected blob contents; not a supported build')
    if b'PTT' in txt:
        raise SystemExit('macro name PTT already present in the shader')

    windows = []

    # A comment line long enough to host the define. Must start at a line
    # boundary or the preprocessor directive is illegal.
    ret_at = txt.find(b'      return vec4(luminance);',
                      txt.find(b'#else // HAS_COLOR_TEXTURE',
                               txt.find(b'samplePassthroughTextures')))
    host = None
    for m in re.finditer(rb'(?<=\n)[^\n]*///[^\n]*(?=\n)', txt[:ret_at]):
        if len(m.group()) >= len(DEFINE) and (host is None or len(m.group()) < len(host.group())):
            host = m
    if host is None:
        raise SystemExit('no comment line big enough to host the define')
    a_new = DEFINE + b' ' * (len(host.group()) - len(DEFINE))
    windows.append((host.start(), bytes(host.group()), a_new))

    # The greyscale return, extended through the #endif comment to borrow its
    # bytes. Quest 1 has no colour camera, so this is the live path.
    end = txt.find(b'#endif // HAS_COLOR_TEXTURE', ret_at) + len(b'#endif // HAS_COLOR_TEXTURE')
    b_old = txt[ret_at:end]
    b_new = RETURN + b' ' * (len(b_old) - len(RETURN))
    if len(b_new) != len(b_old):
        raise SystemExit(f'window B does not fit: need {len(RETURN)}, have {len(b_old)}')
    windows.append((ret_at, b_old, b_new))

    # Table-relative offsets. Expected bytes are stored only as a hash, so no
    # original shader text ships, just the replacement and a fingerprint.
    lines = []
    for p_off, old, new in windows:
        t_off = p_off - 1
        exp_md5 = hashlib.md5(cipher(p_off, old)).hexdigest()
        lines.append('%d %s %s' % (t_off, exp_md5, cipher(p_off, new).hex()))
    open('../module/mr_patch', 'w', newline='\n').write('\n'.join(lines) + '\n')

    c_at = windows[0][0] + DEFINE.find(b'vec3(') + len(b'vec3(')
    open('../module/mr_colour_ks.bin', 'wb').write(keystream(c_at, 17))

    print('TABLE_OFF     =', so_start + tb, '(apk byte offset of the blob)')
    print('COLOUR_OFF    =', c_at - 1, '(table index of the 17 colour bytes)')
    print('stock apk md5 =', hashlib.md5(raw).hexdigest())
    print()
    for (p_off, old, new), ln in zip(windows, lines):
        print(f'window @plain {p_off} ({len(old)} bytes)')
        print('  was :', old.decode('utf-8', 'replace').strip()[:78])
        print('  now :', new.decode('utf-8', 'replace').strip()[:78])
    print()
    print('patch file size:', len('\n'.join(lines)) + 1, 'bytes')


main()
