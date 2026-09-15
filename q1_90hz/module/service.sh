#!/system/bin/sh
# Reapply the non-persistent refresh-rate props every boot. setprop is safe
# this early. `settings` needs the framework, so it waits for boot_completed.
RATE=90

# vrapi refuses rates it has no timing entry for. allRefreshRates lifts that.
setprop debug.oculus.allRefreshRates 1

setprop debug.oculus.refreshRate $RATE
setprop debug.sf.refresh_rate $RATE

( for i in $(seq 1 120); do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
  done
  settings put system peak_refresh_rate $RATE
  settings put system min_refresh_rate $RATE
  settings put global peak_refresh_rate $RATE
  settings put global min_refresh_rate $RATE
  log -t vd90hz "refresh-rate props/settings applied at $RATE"
) &
