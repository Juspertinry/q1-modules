#!/system/bin/sh
# Everything this module does is overlay: two configs generated under
# system/vendor/etc at install time, and two props from system.prop that
# already match stock. Nothing is written outside the module directory, so
# dropping it is the whole revert.
#
# audioserver only reads the audio config at start, so the deep-buffer primary
# output and its added latency stay in effect until the next boot.

log -t q1_audiofx "removed, reboot to restore the stock audio config"
exit 0
