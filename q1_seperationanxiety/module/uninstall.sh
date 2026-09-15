#!/system/bin/sh
# The driver is still live in the running kernel, so drop it now rather than
# leave it driving the pin until reboot. Unload restores the saved pin config.
#
# Safe once tracking is up: TE is only needed to bootstrap, so the pipeline
# keeps running without it.

lsmod | grep -q '^seperationanxiety' && rmmod seperationanxiety 2>/dev/null
exit 0
