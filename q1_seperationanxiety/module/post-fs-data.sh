#!/system/bin/sh
# Load the TE driver before the sensors HAL starts. Frame sync is established
# once, early. If the HAL comes up with no TE every frame is discarded and
# tracking never initialises.
MODDIR=${0%/*}
LOG=$MODDIR/sa.log
KO=$MODDIR/seperationanxiety.ko

# Built against one exact kernel. MODVERSIONS with no force-load means a
# different build is a different ABI, so check before loading.
EXPECT_RELEASE="4.4.205-perf+"
EXPECT_SHA1="5cd7637e06c507e7ef4b8f45b12b02b5c2df9979"

log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

: > "$LOG"
log "SeperationAnxiety starting"

REL=$(uname -r)
SHA=$(sha1sum /proc/version 2>/dev/null | cut -d' ' -f1)

if [ "$REL" != "$EXPECT_RELEASE" ]; then
  log "REFUSING: kernel release is '$REL', expected '$EXPECT_RELEASE'"
  log "Rebuild the module against this kernel; see README.md"
  exit 0
fi

if [ "$SHA" != "$EXPECT_SHA1" ]; then
  log "REFUSING: /proc/version sha1 is $SHA, expected $EXPECT_SHA1"
  log "Same release string, different build. Symbol CRCs will not match."
  log "  running: $(cat /proc/version)"
  exit 0
fi

log "kernel matches ($REL)"

if lsmod | grep -q '^seperationanxiety'; then
  log "already loaded, nothing to do"
  exit 0
fi

insmod "$KO"
RC=$?
if [ $RC -ne 0 ]; then
  log "insmod failed rc=$RC, see dmesg"
  exit 0
fi

log "module loaded"
# A non-zero IRQ count proves it took over rather than silently no-opping.
sleep 1
log "gpio10 irq: $(grep 'msmgpio  10' /proc/interrupts | tr -s ' ')"
exit 0
