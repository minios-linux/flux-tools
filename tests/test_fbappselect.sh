#!/bin/bash
# The launcher consumes the generator output, without another application list.
set -eu
export DISPLAY=${DISPLAY:-:99}
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
    if [ "$1" = --input ]; then cp -- "$2" "$MENU_OUTPUT"; printf "%s" "${MENU_CHOICE:-}"; exit "${MENU_STATUS:-0}"; fi
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


export CALL_LOG="$TEST_ROOT/calls" LAUNCH_ARGS="$TEST_ROOT/launch-args"
printf '#!/bin/sh\nprintf "notify %%s\\n" "$*" >>"$CALL_LOG"\n' >"$TEST_ROOT/bin/fbstartupnotify"
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/gtkask"
cat >"$TEST_ROOT/bin/gio" <<'SH'
#!/bin/sh
if [ "$1" = help ]; then
    [ "${OLD_GIO:-0}" = 1 ] || echo '  launch   Launch a desktop file'
    exit 0
fi
printf 'gio\n' >>"$CALL_LOG"
printf '%s\n' "$@" >"$LAUNCH_ARGS"
exit "${LAUNCH_STATUS:-0}"
SH
for tool in gtk-launch xterm; do
    cat >"$TEST_ROOT/bin/$tool" <<'SH'
#!/bin/sh
printf '%s\n' "${0##*/}" >>"$CALL_LOG"
printf '%s\n' "$@" >"$LAUNCH_ARGS"
exit "${LAUNCH_STATUS:-0}"
SH
done
chmod +x "$TEST_ROOT/bin/"*
export MENU_CHOICE="$TEST_ROOT/selected app.desktop"
printf '[Desktop Entry]\nType=Application\nExec=probe\n' >"$MENU_CHOICE"
bash "$SOURCE_DIR/bin/fbappselect"
printf 'launch\n%s\n' "$MENU_CHOICE" >"$TEST_ROOT/expected"
cmp "$LAUNCH_ARGS" "$TEST_ROOT/expected" || fail 'desktop path changed'
! grep -qx xterm "$CALL_LOG" || fail 'desktop parsed as a shell command'
echo 'PASS: the exact desktop path is passed to GIO without shell parsing'

OLD_GIO=1 bash "$SOURCE_DIR/bin/fbappselect"
[ "$(cat "$LAUNCH_ARGS")" = 'selected app.desktop' ] || fail 'GTK fallback got the wrong desktop ID'
grep -qx gtk-launch "$CALL_LOG" || fail 'old GLib fallback not used'
if LAUNCH_STATUS=42 bash "$SOURCE_DIR/bin/fbappselect"; then fail 'launch failure ignored'; else status=$?; fi
[ "$status" -eq 42 ] || fail 'wrong launch failure status'
[ "$(tail -n1 "$CALL_LOG")" = 'notify false' ] || fail 'cursor not reset after launch failure'
echo 'PASS: GTK fallback and desktop launch errors are handled'

export MENU_CHOICE='printf "%s\n" "two words"; echo raw-command'
bash "$SOURCE_DIR/bin/fbappselect"
[ "$(tail -n1 "$LAUNCH_ARGS")" = "$MENU_CHOICE" ] || fail 'free-form command was interpolated into the wrapper'
[ "$(tail -n1 "$CALL_LOG")" = xterm ] || fail 'free-form command bypassed the terminal'
echo 'PASS: free-form shell input is passed separately to the terminal wrapper'

rm "$MENU_OUTPUT"
exec 9>"$HOME/.fluxbox/fbappselect-${DISPLAY//[^a-zA-Z0-9_.-]/_}.lock"
flock 9
bash "$SOURCE_DIR/bin/fbappselect"
[ ! -e "$MENU_OUTPUT" ] || fail 'concurrent menu instance was opened'
exec 9>&-
echo 'PASS: a concurrent invocation does not kill or duplicate the current menu'
