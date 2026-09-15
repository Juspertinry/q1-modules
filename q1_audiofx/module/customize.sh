#!/system/bin/sh

SRC_FX=/vendor/etc/audio_effects.xml
SRC_AP=/vendor/etc/audio_policy_configuration.xml
DST=$MODPATH/system/vendor/etc

FAST='flags="AUDIO_OUTPUT_FLAG_FAST|AUDIO_OUTPUT_FLAG_PRIMARY"'
DEEP='flags="AUDIO_OUTPUT_FLAG_PRIMARY|AUDIO_OUTPUT_FLAG_DEEP_BUFFER"'

DEV=$(getprop ro.product.device)
[ "$DEV" = "monterey" ] || abort "! Quest 1 (monterey) only, found '$DEV'"
[ -f "$SRC_FX" ] || abort "! $SRC_FX missing"
[ -f "$SRC_AP" ] || abort "! $SRC_AP missing"

for L in libdynproc.so libldnhncr.so libreverbwrapper.so libbundlewrapper.so; do
  [ -f /vendor/lib64/soundfx/$L ] || abort "! /vendor/lib64/soundfx/$L missing"
done

mkdir -p $DST

grep -q '<libraries>' $SRC_FX || abort "! no <libraries> element in $SRC_FX"
grep -q '<effects>' $SRC_FX || abort "! no <effects> element in $SRC_FX"

grep -v -E 'libdynproc\.so|libldnhncr\.so|libreverbwrapper\.so|name="(dynamics_processing|equalizer|bassboost|virtualizer|loudness_enhancer|reverb_env_aux|reverb_env_ins|reverb_pre_aux|reverb_pre_ins)"' \
  $SRC_FX > $TMPDIR/fx_clean.xml

sed -e "/<libraries>/r $MODPATH/patch/libraries.xml" \
    -e "/<effects>/r $MODPATH/patch/effects.xml" \
    $TMPDIR/fx_clean.xml > $DST/audio_effects.xml

grep -q 'e0e6539b-1781-7261-676f-6d7573696340' $DST/audio_effects.xml \
  || abort "! effects patch did not apply"
grep -q 'music_helper' $DST/audio_effects.xml \
  || abort "! lost the QTI volume listeners, refusing to install"

if grep -q "$FAST" $SRC_AP; then
  sed "s#$FAST#$DEEP#" $SRC_AP > $DST/audio_policy_configuration.xml
elif grep -q "$DEEP" $SRC_AP; then
  cat $SRC_AP > $DST/audio_policy_configuration.xml
else
  abort "! primary output flags are not what this module expects"
fi

grep -q "$DEEP" $DST/audio_policy_configuration.xml || abort "! policy patch did not apply"

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $DST/audio_effects.xml 0 0 0644 u:object_r:vendor_configs_file:s0
set_perm $DST/audio_policy_configuration.xml 0 0 0644 u:object_r:vendor_configs_file:s0

ui_print "- Registered: dynamics_processing, equalizer, bassboost,"
ui_print "              virtualizer, loudness_enhancer, reverb"
ui_print "- Primary output moved to deep buffer, fast path disabled"
ui_print "- Output latency rises to roughly 230ms. Reboot to apply."
