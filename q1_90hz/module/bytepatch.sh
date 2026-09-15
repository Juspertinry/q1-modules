# Byte patching over dd. Sourced by customize.sh and post-fs-data.sh.
#
# Offsets are hardcoded to one known build. Nothing is written until the md5
# identifies that build and the bytes read back as the expected instruction, so
# an update is a no-op rather than corruption.

PATCH_APPLIED=0
PATCH_SKIPPED=0
PATCH_FAILED=0

# ui_print only exists during install.
command -v ui_print >/dev/null 2>&1 || ui_print() { log -t vd90hz "$1"; }

hex2esc() {
  _h=$1; _o=""
  while [ -n "$_h" ]; do
    _o="$_o\x$(echo "$_h" | cut -c1-2)"
    _h=$(echo "$_h" | cut -c3-)
  done
  echo "$_o"
}

read_at() {
  dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -v -tx1 | tr -d ' \n'
}

md5_of() {
  md5sum "$1" 2>/dev/null | cut -d' ' -f1
}

# Accepts either hash, so reinstalling over an active overlay is not an error.
require_hash() {
  _m=$(md5_of "$1")
  [ "$_m" = "$2" ] && return 0
  [ "$_m" = "$3" ] && return 0
  ui_print "    ! $4 is an unrecognised build"
  ui_print "      md5      $_m"
  ui_print "      expected $2 (stock)"
  ui_print "            or $3 (already patched)"
  return 1
}

patch_at() {
  _f=$1; _off=$2; _orig=$3; _new=$4; _lbl=$5
  _n=$(( ${#_new} / 2 ))
  _cur=$(read_at "$_f" "$_off" "$_n")

  if [ "$_cur" = "$_new" ]; then
    PATCH_SKIPPED=$((PATCH_SKIPPED + 1))
    return 0
  fi
  if [ "$_cur" != "$_orig" ]; then
    ui_print "    ! $_lbl @ $_off: got $_cur, wanted $_orig"
    PATCH_FAILED=$((PATCH_FAILED + 1))
    return 1
  fi

  printf "$(hex2esc "$_new")" | dd of="$_f" bs=1 seek="$_off" conv=notrunc 2>/dev/null

  if [ "$(read_at "$_f" "$_off" "$_n")" != "$_new" ]; then
    ui_print "    ! $_lbl @ $_off: write-back verify failed"
    PATCH_FAILED=$((PATCH_FAILED + 1))
    return 1
  fi
  PATCH_APPLIED=$((PATCH_APPLIED + 1))
  return 0
}
