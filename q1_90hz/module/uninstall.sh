#!/system/bin/sh
# Restore Virtual Desktop. The /system side was only ever an overlay.
MODDIR=${0%/*}
BK=$MODDIR/backup/libaot-VirtualDesktop.Mobile.dll.so
LIB=$(find /data/app -maxdepth 5 -name 'libaot-VirtualDesktop.Mobile.dll.so' 2>/dev/null | head -1)
if [ -f "$BK" ] && [ -n "$LIB" ]; then
  cat "$BK" > "$LIB"
  log -t vd90hz "restored backed-up VD image"
fi
