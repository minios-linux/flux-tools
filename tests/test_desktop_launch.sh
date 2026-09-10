#!/bin/bash
# Optional integration gate: real GIO/GTK, with only the menu UI stubbed.
# GTK fallback tests require a DISPLAY (use xvfb-run on a headless builder).
set -eu
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
REAL_GIO=$(command -v gio)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" XDG_DATA_HOME="$TEST_ROOT/data" XDG_DATA_DIRS="$TEST_ROOT/system"
export TEST_ROOT REAL_GIO DISPLAY=${DISPLAY:-:99}
export CHOICE="$XDG_DATA_HOME/applications/test-launch.desktop"
mkdir -p "$TEST_ROOT/bin" "$HOME" "${CHOICE%/*}" "$TEST_ROOT/working directory"
export PATH="$TEST_ROOT/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
cat >"$TEST_ROOT/bin/gio" <<'SH'
#!/bin/sh
if [ "$1" = help ] && [ "${FORCE_GTK:-0}" = 1 ]; then exit 0; fi
exec "$REAL_GIO" "$@"
SH
printf '#!/bin/sh\nprintf "%%s" "$CHOICE"\n' >"$TEST_ROOT/bin/xlunch"
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/xlunch_genquick"
cp "$TEST_ROOT/bin/xlunch_genquick" "$TEST_ROOT/bin/fbstartupnotify"
cp "$TEST_ROOT/bin/xlunch_genquick" "$TEST_ROOT/bin/gtkask"
cat >"$TEST_ROOT/probe command" <<'SH'
#!/bin/sh
pwd >"$TEST_ROOT/cwd"
printf '<%s>\n' "$@" >"$TEST_ROOT/args.tmp"
mv "$TEST_ROOT/args.tmp" "$TEST_ROOT/args"
SH
chmod +x "$TEST_ROOT/bin/"* "$TEST_ROOT/probe command"
cat >"$CHOICE" <<EOF
[Desktop Entry]
Type=Application
Name=Launch test
TryExec=$TEST_ROOT/probe command
Exec="$TEST_ROOT/probe command" --title "two words" --mode=a=b %f --keep-this-option %%
Path=$TEST_ROOT/working directory
Terminal=false
EOF
bash "$SOURCE_DIR/bin/fbappselect"
for ((attempt=0; attempt<200; attempt++)); do
    [ ! -f "$TEST_ROOT/args" ] || break
    sleep 0.01
done
printf '<--title>\n<two words>\n<--mode=a=b>\n<--keep-this-option>\n<%%>\n' >"$TEST_ROOT/expected"
cmp "$TEST_ROOT/args" "$TEST_ROOT/expected" || fail 'arguments were changed by the launcher'
[ "$(cat "$TEST_ROOT/cwd")" = "$TEST_ROOT/working directory" ] || fail 'Path was ignored'
echo "PASS: real desktop launch preserves quoting, equals signs, field codes, TryExec and Path (GTK=${FORCE_GTK:-0})"

rm "$TEST_ROOT/args"
sed -i 's|^TryExec=.*|TryExec=/does/not/exist|' "$CHOICE"
if bash "$SOURCE_DIR/bin/fbappselect"; then fail 'invalid TryExec accepted'; fi
[ ! -e "$TEST_ROOT/args" ] || fail 'invalid desktop launched the application'
echo 'PASS: invalid desktop entries do not start an application'
