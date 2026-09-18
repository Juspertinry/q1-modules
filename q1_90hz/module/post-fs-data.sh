#!/system/bin/sh
# Virtual Desktop lives in /data/app, which Magisk cannot overlay, so its AOT
# image is patched in place. post-fs-data lands before zygote, so the binary is
# never already mapped in.

MODDIR=${0%/*}
. $MODDIR/bytepatch.sh

# Virtual Desktop 1.34.0.0 (versionCode 10600)
VD_STOCK=54535420bd66098d1d2982b08312b839
VD_120=ca64320fbc8c13c708c7014aa6d80762
VD_DONE=0cb4834b09d39e0fe63fbfcd00998b96

LIB=$(find /data/app -maxdepth 5 -name 'libaot-VirtualDesktop.Mobile.dll.so' 2>/dev/null | head -1)
if [ -z "$LIB" ]; then
  log -t vd90hz "Virtual Desktop not installed, nothing to do"
  exit 0
fi

# Anything outside these three is a VD update and must not be touched.
CUR=$(md5_of "$LIB")
case "$CUR" in
  $VD_STOCK|$VD_120|$VD_DONE) ;;
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

# Earlier versions also raised VD's own clamp to 120 and forced a 120 entry
# into the menu, which only made sense against a 120 panel base. The composer
# HAL advertises {90,72}, so VD can never select 120 and those five edits did
# nothing. Put them back to stock before the real patches run.
if [ "$CUR" = "$VD_120" ]; then
  patch_at "$LIB" 665272 150f8052 550b8052 "restore stock auto max #90"
  patch_at "$LIB" 665212 dfe20171 df6a0171 "restore stock clamp cmp #90"
  patch_at "$LIB" 665216 090f8052 490b8052 "restore stock clamp ceiling #90"
  patch_at "$LIB" 375864 1f2003d5 e00500b4 "restore list A guard"
  patch_at "$LIB" 416068 1f2003d5 400700b4 "restore list B guard"
fi

# The menu caps rates by HmdType, and Quest 1 (259) sits below the Quest 2
# (320) threshold. Lower the comparisons and drop the checkbox that hides it.
# This is the whole job: stock VD already clamps to 90, so passing the gate is
# all that is needed to get 90 instead of 72.
patch_at "$LIB" 665236 bf020571 bf0e0471 "max-rate gate cmp #320 -> #259"
patch_at "$LIB" 356672 1fff0471 1f0b0471 "StreamingTab cmp #319 -> #258"
patch_at "$LIB" 385824 1fff0471 1f0b0471 "SettingsTab cmp #319 -> #258"
patch_at "$LIB" 356704 a8010034 1f2003d5 "StreamingTab nop cbz"
patch_at "$LIB" 385860 a8010034 1f2003d5 "SettingsTab nop cbz"

if [ "$(md5_of "$LIB")" != "$VD_DONE" ]; then
  log -t vd90hz "VD image hash wrong after patching, restoring backup"
  [ -f "$BK" ] && cat "$BK" > "$LIB"
  exit 1
fi

log -t vd90hz "VD image ok: $PATCH_APPLIED applied, $PATCH_SKIPPED already patched"
