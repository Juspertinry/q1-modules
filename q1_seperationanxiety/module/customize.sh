#!/system/bin/sh
# Refuse here rather than install cleanly and do nothing every boot.
EXPECT_RELEASE="4.4.205-perf+"
EXPECT_SHA1="5cd7637e06c507e7ef4b8f45b12b02b5c2df9979"

ui_print "- SeperationAnxiety: synthetic display TE for panel-less Quest 1"
ui_print "- checking kernel build"

REL=$(uname -r)
SHA=$(sha1sum /proc/version 2>/dev/null | cut -d' ' -f1)

ui_print "  release : $REL"
ui_print "  build   : $SHA"

if [ "$REL" != "$EXPECT_RELEASE" ]; then
  ui_print "! kernel release mismatch (built for $EXPECT_RELEASE)"
  ui_print "! this module will NOT load; rebuild it for this kernel"
  abort "! aborting install"
fi

if [ "$SHA" != "$EXPECT_SHA1" ]; then
  ui_print "! same release but a different build"
  ui_print "! expected $EXPECT_SHA1"
  ui_print "! symbol CRCs will not match; rebuild required"
  abort "! aborting install"
fi

ui_print "- kernel matches, installing"
set_perm_recursive "$MODPATH" 0 0 0755 0644
