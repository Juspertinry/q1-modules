#!/system/bin/sh
# Builds the /system overlay from the headset's own files, so no device
# binaries ship in the zip. Needs a boot image retimed to 144Hz, or the kernel
# still caps at 72 and this only asks for a rate the display stack refuses.

SKIPUNZIP=0

. $MODPATH/bytepatch.sh

HALNAME=vendor.oculus.hardware.graphics.composer@1.1-impl-monterey.so
HAL_SRC=/vendor/lib64/hw/$HALNAME
APK_SRC=/system/priv-app/VrDriver/VrDriver.apk
PROPS_SRC=/system/etc/device_props.json
XRSP_SRC=/system/lib64/libxrspdhelper.so

# The pair the composer HAL advertises. The chosen rate shows up as DR<n> in
# the "VrApi : FPS=.." logcat line. Keep RATE_HI at or below the panel rate.
RATE_HI=90
RATE_LO=72   # verified working pair

# All four are required. Dropping DO_XRSP makes the runtime settle on 72 while
# still reporting success.
DO_PROPS=1
DO_HAL=1
DO_VRDRIVER=1
DO_XRSP=1
RATE=$RATE_HI.0

# Derived against this build. The hashes are the gate, the build number is
# only reported so a mismatch is legible.
OS_TESTED=49845030443200410
HAL_STOCK=1a55f6862ba8fd13560d9663bf2b4b5b
HAL_DONE=cd3dc0885d6be092881d01bdc0fdc354   # {144,120}, informational only
APK_STOCK=fe8b9a03a087bf4d5819e7ffc8c26c7f
XRSP_STOCK=27443232abdee0e4aeb191e576f407c6
XRSP_DONE=fa19bcf91ad637b18a795589175ae73a
APK_DONE=2a5f6f08f355a69fc796eeada0d947f9

ui_print " "
ui_print "  Quest 1 90Hz override (stable)"
ui_print " "

PLAT=$(getprop ro.board.platform)
DEV=$(getprop ro.product.device)
OS=$(getprop ro.build.version.incremental)
ui_print "  device   : $(getprop ro.product.model) ($DEV)"
ui_print "  platform : $PLAT"
ui_print "  build    : $OS"
ui_print " "

# Device specific. Dropping it elsewhere breaks the display stack.
[ "$PLAT" = "msm8998" ] || abort "  ! not msm8998, aborting"
[ "$DEV" = "monterey" ] || abort "  ! not a Quest 1 (monterey), aborting"

if [ "$OS" != "$OS_TESTED" ]; then
  ui_print "  ! built against $OS_TESTED, this is $OS"
  ui_print "    continuing only if the file hashes still match"
  ui_print " "
fi

for f in "$HAL_SRC" "$APK_SRC" "$PROPS_SRC" "$XRSP_SRC"; do
  [ -f "$f" ] || abort "  ! missing $f, aborting"
done

# Not fatal. The module can be installed before the boot image is flashed.
MAXFPS=$(grep -o 'max_fps=[0-9]*' /sys/class/graphics/fb0/msm_fb_panel_info 2>/dev/null | cut -d= -f2)
if [ -n "$MAXFPS" ] && [ "$MAXFPS" -lt "$RATE_HI" ]; then
  ui_print "  ! kernel reports max_fps=$MAXFPS, below $RATE_HI"
  ui_print "    flash a boot image retimed to at least $RATE_HI"
  ui_print " "
fi

# --- 1. device_props.json -------------------------------------------------
# vrapiserver rejects rates that disagree with this. Stock has no
# force_refresh_rate key, so it is added rather than rewritten.
if [ "$DO_PROPS" = "1" ]; then
ui_print "  - device_props.json"
mkdir -p $MODPATH/system/etc
awk -v q='"' -v r="$RATE" '
$0 ~ q "device_default_refresh_rate" q { sub(/:"[0-9.]+"/, ":" q r q) }
$0 ~ q "force_refresh_rate" q          { sub(/:"[0-9.]+"/, ":" q r q); seen = 1 }
{ line[NR] = $0 }
END {
  for (i = 1; i <= NR; i++) {
    print line[i]
    if (!seen && line[i] ~ q "device_default_refresh_rate" q)
      print "  " q "force_refresh_rate" q ":" q r q ","
  }
}' "$PROPS_SRC" > $MODPATH/system/etc/device_props.json

for k in device_default_refresh_rate force_refresh_rate; do
  grep -q "\"$k\":\"$RATE\"" $MODPATH/system/etc/device_props.json \
    || abort "  ! could not set $k"
done
else
ui_print "  - device_props.json  SKIPPED"
fi

# --- 2. composer HAL ------------------------------------------------------
# The real source of the rate list. Both constructors carry a copy as one
# 64-bit immediate {72,60}. Rewrite both.
if [ "$DO_HAL" = "1" ]; then
ui_print "  - composer HAL"
require_hash "$HAL_SRC" $HAL_STOCK $HAL_DONE "composer HAL" \
  || abort "  ! refusing to patch an unknown vendor image"
mkdir -p $MODPATH/system/vendor/lib64/hw
HAL=$MODPATH/system/vendor/lib64/hw/$HALNAME
cp "$HAL_SRC" "$HAL"
# imm16 is bits 5..20, so under 2048 only the low half moves. Encoded here so
# the rates above are the only thing to edit.
enc() { _v=$(( ($1 << 5) | 8 )); printf "%02x%02x" $(( _v & 255 )) $(( (_v >> 8) & 255 )); }
HI=$(enc $RATE_HI)
LO=$(enc $RATE_LO)
patch_at "$HAL" 13620 0809 $HI "C2 mov x8,#72 -> #$RATE_HI"
patch_at "$HAL" 13632 8807 $LO "C2 movk #60 -> #$RATE_LO"
patch_at "$HAL" 13780 0809 $HI "C1 mov x8,#72 -> #$RATE_HI"
patch_at "$HAL" 13792 8807 $LO "C1 movk #60 -> #$RATE_LO"
# No fixed HAL_DONE, the hash depends on the rates. patch_at verifies instead.
else
ui_print "  - composer HAL       SKIPPED"
fi

# --- 3. VrDriver ----------------------------------------------------------
# libvrapiimpl validates against its own global vector, not the list it
# enumerates, so new rates get offered but refused. One branch flip fixes it.
# The .so is stored uncompressed, so it is edited in place and both CRCs fixed.
if [ "$DO_VRDRIVER" = "1" ]; then
ui_print "  - VrDriver"
require_hash "$APK_SRC" $APK_STOCK $APK_DONE "VrDriver.apk" \
  || abort "  ! refusing to patch an unknown VrDriver build"
mkdir -p $MODPATH/system/priv-app/VrDriver
APK=$MODPATH/system/priv-app/VrDriver/VrDriver.apk
cp "$APK_SRC" "$APK"
patch_at "$APK" 12097084 81060054 34000014 "libvrapiimpl b.ne -> b"
patch_at "$APK"  9881590 8806433a 50ce17cb "CRC (local header)"
patch_at "$APK" 21539996 8806433a 50ce17cb "CRC (central dir)"
[ "$(md5_of "$APK")" = "$APK_DONE" ] || abort "  ! patched VrDriver hash is wrong"
else
ui_print "  - VrDriver           SKIPPED"
fi

# --- 3b. xrspd timings gate ---------------------------------------------
# xrspd drops every rate it has no timing entry for. With {120,90} both get
# dropped and the runtime is left with no rate at all, which is the black
# screen. The timings come from a capnp message, not the TIMINGS blob in
# .rodata, so editing that does nothing. Patch the match arm instead: turning
# its b.eq into an unconditional b resolves every rate to the first entry.
if [ "$DO_XRSP" = "1" ]; then
ui_print "  - xrspd timings gate"
if [ "$(md5_of "$XRSP_SRC")" != "$XRSP_STOCK" ]; then
  ui_print "    ! libxrspdhelper.so is an unrecognised build, skipping"
else
  mkdir -p $MODPATH/system/lib64
  XRSP=$MODPATH/system/lib64/libxrspdhelper.so
  cp "$XRSP_SRC" "$XRSP"
  patch_at "$XRSP" 1449264 a0000054 05000014 "timings match b.eq -> b"
  [ "$(md5_of "$XRSP")" = "$XRSP_DONE" ] || abort "  ! patched xrspd helper hash is wrong"
fi
else
ui_print "  - xrspd timings gate SKIPPED"
fi

if [ "$PATCH_FAILED" != "0" ]; then
  abort "  ! $PATCH_FAILED patch(es) failed, aborting"
fi
ui_print "    $PATCH_APPLIED applied, $PATCH_SKIPPED already patched"

# --- 4. permissions -------------------------------------------------------
# Named set_permissions so these win if Magisk reapplies defaults.
set_permissions() {
  set_perm_recursive $MODPATH 0 0 0755 0644
  # Loads into surfaceflinger's process. vendor_file looks right and silently
  # fails to load.
  [ -f "$HAL" ] && set_perm "$HAL" 0 0 0644 u:object_r:same_process_hal_file:s0
  [ -f "$APK" ] && set_perm "$APK" 0 0 0644 u:object_r:system_file:s0
  XRSPLIB=$MODPATH/system/lib64/libxrspdhelper.so
  [ -f "$XRSPLIB" ] && set_perm "$XRSPLIB" 0 0 0644 u:object_r:system_lib_file:s0
  PROPSJSON=$MODPATH/system/etc/device_props.json
  [ -f "$PROPSJSON" ] && set_perm "$PROPSJSON" 0 0 0644 u:object_r:system_file:s0
  set_perm "$MODPATH/service.sh" 0 0 0755
  set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
}
set_permissions

ui_print " "
ui_print "  Installed. Reboot to apply."
ui_print " "
ui_print "  Verify after reboot with:"
ui_print "    logcat -d | grep -oE 'FPS=[0-9]+/[0-9]+'      -> expect n/90"
ui_print "    cat /d/clk/pclk0_clk_src/rate               -> panel pclk"
ui_print "    logcat -d -b all | grep 'timings for'       -> expect 90 found"
ui_print " "
