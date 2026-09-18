#!/system/bin/sh
# Lines sent to logcat from this context do not reliably survive (not PATH and
# not an SELinux denial, both checked), so mirror everything to a file that is
# always readable: /data/adb/q1_90hz.log
LOGF=/data/adb/q1_90hz.log
say() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOGF
  /system/bin/log -t vd90hz "$*" 2>/dev/null
}
# Reapply the non-persistent refresh-rate props every boot. setprop is safe
# this early. `settings` needs the framework, so it waits for boot_completed.
RATE=90

# vrapi refuses rates it has no timing entry for. allRefreshRates lifts that.
setprop debug.oculus.allRefreshRates 1

setprop debug.oculus.refreshRate $RATE
setprop debug.sf.refresh_rate $RATE

FB=/sys/class/graphics/fb0

# The bootloader brings the panel up on its own timing and MDSS keeps that
# pixel clock while programming the porches from the retimed device tree. The
# two disagree, so the panel scans at RATE * (72 / base) until the panel is
# genuinely power cycled: 72.00Hz on a 90 base, 54.01Hz on a 120 base, both
# measured. A blank/unblank pair reprograms the PLL, and that is all the
# manual "sleep and wake once after boot" was ever doing.
#
# It has to be FB_BLANK_POWERDOWN (4). FB_BLANK_NORMAL (1) leaves the panel
# powered and changes nothing.
panel_clock_ok() {
  # MDSS reports the bit clock it believes it programmed. The pixel clock is
  # that divided by bpp/lanes, 24/4 here, so the two should agree bar rounding.
  _want=$(cat $FB/dynamic_bitclk 2>/dev/null)
  _have=$(cat /sys/kernel/debug/clk/pclk0_clk_src/rate 2>/dev/null)
  [ -n "$_want" ] && [ -n "$_have" ] && [ "$_want" -gt 0 ] || return 1
  _want=$((_want / 6))
  _d=$((_want - _have))
  [ $_d -lt 0 ] && _d=$((0 - _d))
  [ $_d -lt $((_want / 100)) ]
}

resync_panel_clock() {
  [ -w $FB/blank ] || return

  # Only worth doing while the panel is already on. If it is off the headset is
  # not being worn, and forcing it on here would just burn battery. The next
  # real wake does the same reprogram anyway.
  _on=0
  for _ in $(seq 1 60); do
    case "$(cat $FB/show_blank_event 2>/dev/null)" in
      *"panel_power_on = 1"*) _on=1; break ;;
    esac
    sleep 2
  done
  [ "$_on" = 1 ] || { say "panel off, skipping clock resync"; return; }

  panel_clock_ok && { say "panel clock already correct"; return; }

  echo 4 > $FB/blank
  sleep 2
  echo 0 > $FB/blank
  sleep 3

  if panel_clock_ok; then
    say "panel clock resynced for $RATE"
  else
    say "panel clock resync did not take, sleep and wake once"
  fi
}

( for i in $(seq 1 120); do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
  done
  settings put system peak_refresh_rate $RATE
  settings put system min_refresh_rate $RATE
  settings put global peak_refresh_rate $RATE
  settings put global min_refresh_rate $RATE
  say "refresh-rate props/settings applied at $RATE"

  resync_panel_clock
) &
