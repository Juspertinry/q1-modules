#!/system/bin/sh
# Virtual Desktop lives in /data/app, which Magisk cannot overlay, so its AOT
# image is patched in place. post-fs-data lands before zygote, so the binary is
# never already mapped in.

MODDIR=${0%/*}
. $MODDIR/bytepatch.sh

# Virtual Desktop 1.34.0.0 (versionCode 10600)
VD_STOCK=54535420bd66098d1d2982b08312b839
VD_90=0cb4834b09d39e0fe63fbfcd00998b96
VD_DONE=ca64320fbc8c13c708c7014aa6d80762

LIB=$(find /data/app -maxdepth 5 -name 'libaot-VirtualDesktop.Mobile.dll.so' 2>/dev/null | head -1)
if [ -z "$LIB" ]; then
  log -t vd90hz "Virtual Desktop not installed, nothing to do"
  exit 0
fi

# Anything outside these three is a VD update and must not be touched.
CUR=$(md5_of "$LIB")
case "$CUR" in
  $VD_STOCK|$VD_90|$VD_DONE) ;;
  *) log -t vd90hz "VD build changed ($CUR), refusing to patch $LIB"; exit 0 ;;
esac

# Only ever back up an unpatched image. On a re-run the file is already
# patched, and copying it would quietly defeat uninstall.
BK=$MODDIR/backup/libaot-VirtualDesktop.Mobile.dll.so
if [ ! -f "$BK" ] && [ "$CUR" = "$VD_STOCK" ]; then
  mkdir -p "$MODDIR/backup"
  cp "$LIB" "$BK"
  log -t vd90hz "backed up stock VD image"
fi

# The menu caps rates by HmdType, and Quest 1 (259) sits below the Quest 2
# (320) threshold. Lower the comparisons and drop the checkbox that hides it.
patch_at "$LIB" 665236 bf020571 bf0e0471 "max-rate gate cmp #320 -> #259"
patch_at "$LIB" 356672 1fff0471 1f0b0471 "StreamingTab cmp #319 -> #258"
patch_at "$LIB" 385824 1fff0471 1f0b0471 "SettingsTab cmp #319 -> #258"
patch_at "$LIB" 356704 a8010034 1f2003d5 "StreamingTab nop cbz"
patch_at "$LIB" 385860 a8010034 1f2003d5 "SettingsTab nop cbz"

# The rate behind that gate is a hardcoded immediate, so passing it only
# yields 90. The Framerate enum already carries 120, so raising the cap exposes
# it. Two paths need it: the auto value and the explicit clamp.
patch_at "$LIB" 665272 550b8052 150f8052 "auto max movz w21,#90 -> #120"
patch_at "$LIB" 665212 df6a0171 dfe20171 "clamp cmp w22,#90 -> #120"
patch_at "$LIB" 665216 490b8052 090f8052 "clamp ceiling movz w9,#90 -> #120"

# Each rate is emitted behind its own Supports<N>Hertz call, and the 120 one
# returns false here. Nop both guards, one per tab.
patch_at "$LIB" 375864 e00500b4 1f2003d5 "list A: force 120 entry"
patch_at "$LIB" 416068 400700b4 1f2003d5 "list B: force 120 entry"

if [ "$(md5_of "$LIB")" != "$VD_DONE" ]; then
  log -t vd90hz "VD image hash wrong after patching, restoring backup"
  [ -f "$BK" ] && cat "$BK" > "$LIB"
  exit 1
fi

log -t vd90hz "VD image ok: $PATCH_APPLIED applied, $PATCH_SKIPPED already patched"
