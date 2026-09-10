#!/bin/bash
# The launcher consumes the generator output, without another application list.
set -eu
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp with spaces"
export MENU_INPUT="$TEST_ROOT/input" MENU_OUTPUT="$TEST_ROOT/output"
mkdir -p "$TEST_ROOT/bin" "$TMPDIR" "$HOME"
export PATH="$TEST_ROOT/bin:$PATH"
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/killall"
printf '#!/bin/sh\ncat "$MENU_INPUT"\nexit "${GENERATOR_STATUS:-0}"\n' >"$TEST_ROOT/bin/xlunch_genquick"
cat >"$TEST_ROOT/bin/xlunch" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = --input ]; then cp -- "$2" "$MENU_OUTPUT"; exit; fi
    shift
done
exit 1
SH
chmod +x "$TEST_ROOT/bin/"*
fail() { echo "FAIL: $*" >&2; exit 1; }
cat >"$MENU_INPUT" <<'MENU'
Справка MiniOS;/icons/help.svg;/custom path/minios-help-flux.desktop
Personal Help;/icons/help.svg;/custom path/dev.minios.Help.desktop
New Application;/icons/new.svg;/custom path/new.desktop
MENU
bash "$SOURCE_DIR/bin/fbappselect"
cmp "$MENU_INPUT" "$MENU_OUTPUT" || fail 'generator output was filtered again'
[ -z "$(find "$TMPDIR" -type f -print -quit)" ] || fail 'temporary menu leaked'
echo 'PASS: generator entries are passed unchanged and the temporary menu is removed'
rm -- "$MENU_OUTPUT"
if GENERATOR_STATUS=42 bash "$SOURCE_DIR/bin/fbappselect"; then
    fail 'a failed generator opened a partial menu'
fi
[ ! -e "$MENU_OUTPUT" ] || fail 'xlunch ran after a generation failure'
[ -z "$(find "$TMPDIR" -type f -print -quit)" ] || fail 'temporary menu leaked'
echo 'PASS: a generation failure does not launch xlunch or leak its temporary file'
