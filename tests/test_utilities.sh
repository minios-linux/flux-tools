#!/bin/bash
# Exercise the helpers with private files and harmless command stubs.
set -eu
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export TEST_ROOT HOME="$TEST_ROOT/home with spaces" TEST_LOG="$TEST_ROOT/log"
export DISPLAY=:flux-test REAL_SLEEP
REAL_SLEEP=$(command -v sleep)
mkdir -p "$TEST_ROOT/bin" "$HOME/.fluxbox" "$TEST_ROOT/proc"
export PATH="$TEST_ROOT/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
stub() { printf '#!/bin/bash\n%s\n' "$2" >"$TEST_ROOT/bin/$1"; chmod +x "$TEST_ROOT/bin/$1"; }
stub gettext 'printf "%s" "$1"'
stub gtkask 'exit 0'
stub setxkbmap 'exit "${KEYBOARD_STATUS:-0}"'
printf 'us\n' >"$HOME/.fluxbox/kblayout"
if KEYBOARD_STATUS=42 bash "$SOURCE_DIR/bin/fbsetkb" invalid; then fail 'keyboard failure ignored'; else status=$?; fi
[ "$status" -eq 42 ] || fail 'keyboard failure status changed'
[ "$(cat "$HOME/.fluxbox/kblayout")" = us ] || fail 'invalid keyboard saved'
bash "$SOURCE_DIR/bin/fbsetkb" us,ru
[ "$(cat "$HOME/.fluxbox/kblayout")" = us,ru ] || fail 'keyboard not saved'
echo 'PASS: keyboard settings are saved only after successful application'

LC_ALL= LC_MESSAGES= LANG=ru_RU.UTF-8 LANGUAGE=ru_RU:ru bash "$SOURCE_DIR/bin/fbmenu" >"$TEST_ROOT/menu"
grep -q 'fbsetkb ru' "$TEST_ROOT/menu" || fail 'LANGUAGE hid the Russian layout'
LC_ALL= LC_MESSAGES= LANG=nl_NL.UTF-8 bash "$SOURCE_DIR/bin/fbmenu" >"$TEST_ROOT/menu"
grep -q 'fbsetkb nl }$' "$TEST_ROOT/menu" || fail 'missing flag became a broken icon path'
LC_ALL=C bash "$SOURCE_DIR/bin/fbmenu" >"$TEST_ROOT/menu"
[ "$(grep -c 'fbsetkb us' "$TEST_ROOT/menu")" -eq 1 ] || fail 'English keyboard duplicated'
echo 'PASS: layout menus handle LANGUAGE, fallback locales and missing flags'

stub xrandr 'if [ "$1" = --query ]; then
    printf "DP-1 connected\nHDMI-1 connected primary\n"
    exit "${QUERY_STATUS:-0}"
fi
printf "xrandr %s\n" "$*" >>"$TEST_LOG"
exit "${MODE_STATUS:-0}"'
stub pgrep 'printf "%s\n" "${TEST_PIDS:-}"'
# Only synthetic PIDs reach this function; never signal a host process.
kill() { printf 'signal %s\n' "$*" >>"$TEST_LOG"; return "${SIGNAL_STATUS:-0}"; }
export -f kill
sed "s|/proc/|$TEST_ROOT/proc/|g" "$SOURCE_DIR/bin/fbscreensize" >"$TEST_ROOT/fbscreensize"
: >"$TEST_LOG"
if MODE_STATUS=42 bash "$TEST_ROOT/fbscreensize" 1280x800; then fail 'xrandr failure ignored'; else status=$?; fi
[ "$status" -eq 42 ] || fail 'xrandr status changed'
! grep -q '^signal ' "$TEST_LOG" || fail 'failed mode change signalled a compositor'
mkdir -p "$TEST_ROOT/proc/4242" "$TEST_ROOT/proc/4243"
printf 'DISPLAY=%s\0' "$DISPLAY" >"$TEST_ROOT/proc/4242/environ"
printf 'DISPLAY=:another-session\0' >"$TEST_ROOT/proc/4243/environ"
export TEST_PIDS=$'4242\n4243'
bash "$TEST_ROOT/fbscreensize" 1280x800
grep -qx 'xrandr --output HDMI-1 --mode 1280x800' "$TEST_LOG" || fail 'primary output not selected'
grep -qx 'signal -USR1 4242' "$TEST_LOG" || fail 'current compositor not reinitialized'
! grep -q '^signal .*4243' "$TEST_LOG" || fail 'another display was signalled'
: >"$TEST_LOG"
bash "$TEST_ROOT/fbscreensize" 1280x800 -n
! grep -q '^signal ' "$TEST_LOG" || fail '-n signalled the compositor'
echo 'PASS: mode errors propagate and only the current display compositor is notified'

# Power/logout commands are stubs and the sound/overlay path is disabled here.
stub xlunch 'printf "%s" "${ACTION:-}"'
stub reboot 'exit "${ACTION_STATUS:-0}"'
stub poweroff 'exit "${ACTION_STATUS:-0}"'
stub pkexec 'printf "authorize\n" >>"$TEST_LOG"; exec "$@"'
sed -e "s|/proc/|$TEST_ROOT/proc/|g" \
    -e "s|/sbin/|$TEST_ROOT/bin/|g" \
    -e "s|SND=/usr/share/sounds/shutdown.wav|SND=$TEST_ROOT/no-sound|" \
    "$SOURCE_DIR/bin/fblogout" >"$TEST_ROOT/fblogout"
for action in restart shutdown; do
    if ACTION=$action ACTION_STATUS=42 bash "$TEST_ROOT/fblogout"; then fail "$action failure ignored"; else status=$?; fi
    [ "$status" -eq 42 ] || fail "$action status changed"
done
: >"$TEST_LOG"
ACTION=logout bash "$TEST_ROOT/fblogout"
[ "$(cat "$TEST_LOG")" = 'signal -TERM 4242' ] || fail 'logout targeted the wrong process'
if TEST_PIDS= ACTION=logout bash "$TEST_ROOT/fblogout"; then fail 'missing session accepted'; fi
unset -f kill
unset TEST_PIDS
echo 'PASS: logout targets the current Fluxbox and power action errors are preserved'

stub xdg-user-dir 'printf "%s/Pictures in XDG\n" "$HOME"'
stub scrot 'printf "image\n" >"$1"; exit "${SCREENSHOT_STATUS:-0}"'
stub gpicview 'printf "%s\n" "$1" >"$TEST_ROOT/viewed"'
bash "$SOURCE_DIR/bin/fbprintscreen"
image=$(cat "$TEST_ROOT/viewed")
[[ "$image" == "$HOME/Pictures in XDG/"*.png ]] || fail 'screenshot saved in wrong directory'
[ -s "$image" ] || fail 'screenshot missing'
rm "$TEST_ROOT/viewed"
if SCREENSHOT_STATUS=42 bash "$SOURCE_DIR/bin/fbprintscreen"; then fail 'screenshot error ignored'; else status=$?; fi
[ "$status" -eq 42 ] || fail 'screenshot error status changed'
[ ! -e "$TEST_ROOT/viewed" ] || fail 'failed screenshot opened a viewer'
[ "$(find "$HOME/Pictures in XDG" -type f | wc -l)" -eq 1 ] || fail 'failed screenshot left an empty file'
echo 'PASS: screenshots honor XDG paths and clean up failed captures'

stub id 'echo 0'
mkdir -p "$TEST_ROOT/root" "$TEST_ROOT/media/My drive#100%" "$TEST_ROOT/media/Русский"
sed -e "s|^BOOKMARKS=.*|BOOKMARKS=$TEST_ROOT/root/bookmarks|" \
    -e "s|^LOCKDIR=.*|LOCKDIR=$TEST_ROOT/root/locks|" \
    -e "s|^MEDIA_ROOT=.*|MEDIA_ROOT=$TEST_ROOT/media|" \
    "$SOURCE_DIR/bin/gtk-bookmarks-update" >"$TEST_ROOT/bookmarks-update"
printf 'file:///home/user/Documents Personal\nfile://%s/media/old Old\n' "$TEST_ROOT" >"$TEST_ROOT/root/bookmarks"
bash "$TEST_ROOT/bookmarks-update"
grep -q 'My%20drive%23100%25 My drive#100%' "$TEST_ROOT/root/bookmarks" || fail 'volume URI not encoded'
grep -q '%D0%A0%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9 Русский' "$TEST_ROOT/root/bookmarks" || fail 'UTF-8 URI not encoded'
grep -qx 'file:///home/user/Documents Personal' "$TEST_ROOT/root/bookmarks" || fail 'personal bookmark lost'
! grep -q '/media/old' "$TEST_ROOT/root/bookmarks" || fail 'old mount bookmark retained'
cp "$TEST_ROOT/root/bookmarks" "$TEST_ROOT/bookmarks-once"
bash "$TEST_ROOT/bookmarks-update"
cmp "$TEST_ROOT/root/bookmarks" "$TEST_ROOT/bookmarks-once" || fail 'bookmark refresh is not idempotent'
exec 9>"$TEST_ROOT/root/locks/gtk-bookmarks-update.lock"
flock 9
if timeout 4 bash "$TEST_ROOT/bookmarks-update"; then fail 'busy bookmark lock accepted'; else status=$?; fi
[ "$status" -eq 1 ] || fail 'bookmark lock did not return within its own timeout'
exec 9>&-
bash "$TEST_ROOT/bookmarks-update"
echo 'PASS: bookmarks preserve personal entries, encode paths and use bounded crash-safe locking'

stub sleep 'printf "sleep %s\n" "$*" >>"$TEST_LOG"'
stub wmctrl 'echo "unchanged windows"'
stub xsetroot 'printf "cursor %s\n" "$*" >>"$TEST_LOG"'
: >"$TEST_LOG"
bash "$SOURCE_DIR/bin/fbstartupnotify"
for ((attempt=0; attempt<100; attempt++)); do
    if grep -q '/left_ptr 16$' "$TEST_LOG"; then break; fi
    "$REAL_SLEEP" 0.02
done
grep -q '/left_ptr 16$' "$TEST_LOG" || fail 'cursor not reset on timeout'
[ "$(grep -c '^sleep ' "$TEST_LOG")" -eq 20 ] || fail 'startup watcher is not bounded'
echo 'PASS: startup notification restores the cursor even without a new window'
