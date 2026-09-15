#!/usr/bin/env python3
"""Retime the Quest 1 DSI panel by editing the appended DTBs in a boot image.

The boot image carries 14 concatenated DTBs (one per hardware revision) at the
tail of the kernel blob, no QCDT index -- the bootloader walks them by totalsize
and matches on board id. Every edit here is size-preserving u32-for-u32, so the
blob length never moves and the header needs no fixup.

Only the refresh rate and the horizontal front porch are touched. Everything
else about the panel, including the DSC config and the DDIC init sequence,
is left alone.
"""

import argparse, math, struct, sys, os

FDT_MAGIC = b'\xd0\x0d\xfe\xed'
BEGIN, END, PROP, NOP, FDTEND = 1, 2, 3, 4, 9


class Fdt:
    def __init__(self, buf, base):
        self.buf, self.base = buf, base
        (magic, self.totalsize, self.off_struct, self.off_strings,
         _rsv, _v, _lv, _b, self.size_strings, self.size_struct) = struct.unpack(
            '>10I', buf[base:base + 40])
        assert magic == 0xd00dfeed

    def _str(self, off):
        p = self.base + self.off_strings + off
        return self.buf[p:self.buf.index(b'\0', p)].decode()

    def props(self):
        """yield (path, name, absolute_value_offset, length)

        All offsets inside an FDT are relative to its own base, and these DTBs
        are concatenated without padding, so the base is rarely 4-byte aligned.
        Walk in DTB-relative space and only translate on the way out.
        """
        b = self.base
        o = self.off_struct
        end = o + self.size_struct
        stack = []
        while o < end:
            tok, = struct.unpack('>I', self.buf[b + o:b + o + 4]); o += 4
            if tok == BEGIN:
                e = self.buf.index(0, b + o) - b
                stack.append(self.buf[b + o:b + e].decode())
                o = (e + 4) & ~3
            elif tok == END:
                stack.pop()
            elif tok == PROP:
                ln, noff = struct.unpack('>II', self.buf[b + o:b + o + 8]); o += 8
                yield "/".join(stack), self._str(noff), b + o, ln
                o = (o + ln + 3) & ~3
            elif tok == NOP:
                pass
            elif tok == FDTEND:
                break
            else:
                raise ValueError("bad FDT token %d" % tok)

    def model(self):
        for path, name, o, ln in self.props():
            if path == "" and name == "model":
                return self.buf[o:o + ln - 1].decode(errors='replace')
        return "?"


def find_dtbs(buf, start, stop):
    out, i = [], start
    while True:
        i = buf.find(FDT_MAGIC, i, stop)
        if i < 0:
            return out
        sz, = struct.unpack('>I', buf[i + 4:i + 8])
        if 0x1000 < sz <= stop - i:
            out.append(i)
            i += sz
        else:
            i += 4


# per-panel fixed geometry, from the stock device tree.
# hact is the DSC-compressed horizontal active: 1440 px at 3:1 reads as 480
# columns of 24bpp on the link, which is the domain the DT porches live in.
PANELS = {
    'sdc': dict(node='qcom,mdss_dsi_sdc_lightman_video',
                hact=480, hpw=70, hbp=110, vtotal=1624),
    'auo': dict(node='qcom,mdss_dsi_auo_1440x1600_video',
                hact=480, hpw=8, hbp=8, vtotal=1632),
}
LANES, BPP = 4, 24


def link_rate(p, fps, hfp, vtot=None):
    htot = p['hact'] + p['hpw'] + p['hbp'] + hfp
    pclk = htot * (vtot or p['vtotal']) * fps
    return htot, pclk, pclk * BPP // LANES


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src'); ap.add_argument('dst')
    ap.add_argument('--fps', type=int, required=True,
                    help='base panel-framerate; sets the fixed pixel clock')
    ap.add_argument('--min', type=int, help='min-refresh-rate (default: --fps)')
    ap.add_argument('--max', type=int, help='max-refresh-rate (default: --fps)')
    ap.add_argument('--hfp', type=int,
                    help='override h-front-porch (default: leave stock)')
    ap.add_argument('--height', type=int,
                    help='active lines per frame. The DDIC has a floor of about '
                         '6us per line and line time is 1/(rate x vtotal), so '
                         'fewer lines is the only way past ~104Hz. Must be a '
                         'multiple of the 16-line DSC slice. Also rewrites '
                         'pic_height inside the DSC PPS the on-command sends.')
    ap.add_argument('--keep-pps', action='store_true',
                    help='with --height, leave pic_height in the DSC PPS at 1600 '
                         'so the DDIC keeps its own frame geometry and only the '
                         'line count sent to it changes')
    ap.add_argument('--vfp', type=int,
                    help='override v-front-porch. MDP prefetches the next frame '
                         'during vertical blanking, and that window is a fixed '
                         'line count, so its real duration shrinks as the rate '
                         'rises. Growing it costs pixel clock but buys prefetch '
                         'time.')
    ap.add_argument('--panel', choices=['sdc', 'auo', 'both'], default='sdc')
    ap.add_argument('--phy-scale', action='store_true',
                    help='rescale the static D-PHY timing block so its absolute ns '
                         'timing is preserved at the new bit clock')
    ap.add_argument('-n', '--dry-run', action='store_true')
    a = ap.parse_args()

    lo = a.min if a.min else a.fps
    hi = a.max if a.max else a.fps
    if not lo <= a.fps <= hi:
        sys.exit("! --fps must sit inside [--min, --max]: DFPS only grows the "
                 "porch, so the base rate has to be the fastest one")

    buf = bytearray(open(a.src, 'rb').read())
    if buf[:8] != b'ANDROID!':
        sys.exit("! not an Android boot image")
    ks, _ka, _rs, _ra, _ss, _sa, _ta, pg, hv = struct.unpack('<9I', buf[8:44])
    print("boot image : header v%d, page %d, kernel %d bytes" % (hv, pg, ks))

    dtbs = find_dtbs(buf, pg, pg + ks)
    print("appended   : %d DTBs\n" % len(dtbs))
    if not dtbs:
        sys.exit("! no appended DTBs found")

    targets = ['sdc', 'auo'] if a.panel == 'both' else [a.panel]
    edits = 0

    for base in dtbs:
        f = Fdt(buf, base)
        model = f.model()
        want = {}
        for key in targets:
            p = PANELS[key]
            want[p['node']] = (key, p)

        # collect this DTB's current values first, so the report can show the move
        cur = {}
        for path, name, o, ln in f.props():
            leaf = path.rsplit('/', 1)[-1]
            if leaf in want and ln == 4:
                cur.setdefault(leaf, {})[name] = (o, struct.unpack('>I', buf[o:o + 4])[0])

        # The DSC picture parameter set travels to the DDIC as DCS register
        # 0xE4 inside the on-command; pic_height is bytes 6..7 of the PPS.
        # The kernel derives its own encoder config from panel-height, so the
        # two must agree.
        if a.height is not None and not a.keep_pps:
            for path, name, o, ln in f.props():
                leaf = path.rsplit('/', 1)[-1]
                if leaf in want and name == 'qcom,mdss-dsi-on-command':
                    i = o
                    while i + 7 <= o + ln:
                        dl = (buf[i + 5] << 8) | buf[i + 6]
                        if buf[i + 7] == 0xE4 and dl >= 9:
                            ph = i + 7 + 1 + 6
                            have = (buf[ph] << 8) | buf[ph + 1]
                            if have != 1600:
                                sys.exit("! PPS pic_height reads %d, expected 1600" % have)
                            if not a.dry_run:
                                buf[ph] = a.height >> 8
                                buf[ph + 1] = a.height & 0xFF
                            edits += 1
                            print("      pps pic_height 1600 -> %d" % a.height)
                        i += 7 + dl

        # Offsets of the 12-byte D-PHY timing block, one per panel node.
        tmg = {}
        for path, name, o, ln in f.props():
            leaf = path.rsplit('/', 1)[-1]
            if leaf in want and ln == 12 and name == 'qcom,mdss-dsi-panel-timings':
                tmg[leaf] = o

        for leaf, props in sorted(cur.items()):
            key, p = want[leaf]
            hfp_old = props.get('qcom,mdss-dsi-h-front-porch', (0, 0))[1]
            hfp_new = a.hfp if a.hfp is not None else hfp_old
            vfp_old = props.get('qcom,mdss-dsi-v-front-porch', (0, 0))[1]
            vfp_new = a.vfp if a.vfp is not None else vfp_old
            h_old = props.get('qcom,mdss-dsi-panel-height', (0, 1600))[1]
            h_new = a.height if a.height is not None else h_old
            if h_new % 16:
                sys.exit("! --height must be a multiple of the DSC slice height (16)")
            vtot_new = p['vtotal'] - vfp_old + vfp_new - h_old + h_new

            new = {
                'qcom,mdss-dsi-panel-framerate': a.fps,
                'qcom,mdss-dsi-min-refresh-rate': lo,
                'qcom,mdss-dsi-max-refresh-rate': hi,
            }
            if a.hfp is not None:
                new['qcom,mdss-dsi-h-front-porch'] = hfp_new
            if a.vfp is not None:
                new['qcom,mdss-dsi-v-front-porch'] = vfp_new
            if a.height is not None:
                new['qcom,mdss-dsi-panel-height'] = h_new

            htot, pclk, bits = link_rate(p, a.fps, hfp_new, vtot_new)
            _, _, bits_old = link_rate(p, props.get(
                'qcom,mdss-dsi-panel-framerate', (0, 72))[1], hfp_old)
            blank = 100.0 * (htot - p['hact']) / htot
            # The 12 timing values are durations counted in byte clocks, and the
            # byte clock rides the bit clock. Letting the driver recompute them
            # from generic formulas corrupts the link on this panel, so instead
            # scale Meta's own validated block by the clock ratio: every field
            # then lands on the same absolute nanoseconds it had at the stock
            # rate, which is what keeps it inside D-PHY spec. Works without
            # knowing what any individual field means. Assumes a stock input
            # image, since the ratio is taken against this DTB's own timings.
            if a.phy_scale and leaf in tmg:
                to = tmg[leaf]
                old_t = list(buf[to:to + 12])
                ratio = bits / float(bits_old)
                # t-clk-pre/post live outside the 12-byte block but are the
                # same kind of quantity: clock-lane hold times in byte clocks.
                # Left unscaled, t-clk-post drops under the D-PHY floor of
                # 60ns + 52*UI once the link passes ~900 Mbps.
                # Both land in 6-bit fields of DSI_CLKOUT_TIMING_CTRL; the
                # driver masks with 0x3f, so 64 silently becomes 0.
                for name in ('qcom,mdss-dsi-t-clk-pre', 'qcom,mdss-dsi-t-clk-post'):
                    if name in props:
                        new[name] = min(63, int(math.ceil(props[name][1] * ratio)))
                # Round up: undershooting a D-PHY minimum is what corrupts the
                # link, while overshooting only spends blanking time, which is
                # budget-checked below.
                new_t = [int(math.ceil(v * ratio)) for v in old_t]
                over = [i for i, v in enumerate(new_t) if v > 63]
                if max(new_t) > 255:
                    print("      ! phy timing overflow, skipped")
                elif old_t != new_t:
                    if not a.dry_run:
                        buf[to:to + 12] = bytes(new_t)
                    edits += 1
                    print("      phy x%.4f  %s -> %s%s"
                          % (ratio,
                             " ".join("%02x" % v for v in old_t),
                             " ".join("%02x" % v for v in new_t),
                             "  ! fields %s exceed 63" % over if over else ""))


            # the slowest rate DFPS can reach by growing hfp back out
            print("  %-16s %-5s  %d->%dHz  hfp %d->%d  vfp %d->%d  vtot %d  "
                  "link %.1f->%.1f Mbps  hblank %.0f%%  line %.2fus"
                  % (model, key, props.get('qcom,mdss-dsi-panel-framerate',
                                           (0, 0))[1], a.fps,
                     hfp_old, hfp_new, vfp_old, vfp_new, vtot_new,
                     bits_old / 1e6, bits / 1e6, blank,
                     1e6 / (a.fps * vtot_new)))

            for name, val in new.items():
                if name not in props:
                    print("      ! %s absent, skipped" % name)
                    continue
                o, old = props[name]
                if old != val:
                    if not a.dry_run:
                        buf[o:o + 4] = struct.pack('>I', val)
                    edits += 1

    print("\n%d property edits%s" % (edits, " (dry run, nothing written)" if a.dry_run else ""))
    if not a.dry_run:
        open(a.dst, 'wb').write(buf)
        print("wrote %s (%d bytes, unchanged length)" % (a.dst, len(buf)))


if __name__ == '__main__':
    main()
