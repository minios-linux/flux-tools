#!/bin/bash
# Run the installation path in a private tree: APT, UI and privilege calls are stubs.
set -eu
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export TEST_ROOT HOME="$TEST_ROOT/home" TEST_LOG="$TEST_ROOT/log"
export TMPDIR="$TEST_ROOT/temporary state"
mkdir -p "$TMPDIR"
export TEST_UID=$(id -u) TEST_GID=$(id -g)
export REAL_DESKTOP_UPDATE=$(command -v update-desktop-database)
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/installed" "$TEST_ROOT/apps" "$HOME"
export PATH="$TEST_ROOT/bin:$PATH" LANG=C
# Redirect only target paths and simulated identity; exercise the actual control flow.
sed -e "s|/usr/share/applications|$TEST_ROOT/apps|g" \
    -e "s|EXECUTABLE=\"/usr/bin/|EXECUTABLE=\"$TEST_ROOT/installed/|g" \
    -e 's/\$EUID/\$TEST_EUID/g' "$SOURCE_DIR/bin/fbliveapp" >"$TEST_ROOT/fbliveapp"
cat >"$TEST_ROOT/bin/xterm" <<'SH'
#!/bin/bash
[ "${TERMINAL_CLOSED:-0}" = 0 ] || exit 0
for arg; do command=$arg; done
# Real xterm returns success even when its child exits with an error.
bash -c "$command"
exit 0
SH
cat >"$TEST_ROOT/bin/pkexec" <<'SH'
#!/bin/sh
printf 'pkexec\n' >>"$TEST_LOG"
[ "${AUTH_DENIED:-0}" = 0 ] || exit 126
exec "$@"
SH
printf '#!/bin/sh\nexit "${DECLINE:-0}"\n' >"$TEST_ROOT/bin/gtkask"
printf '#!/bin/sh\nprintf "%%s" "$1"\n' >"$TEST_ROOT/bin/gettext"
cat >"$TEST_ROOT/bin/apt" <<'SH'
#!/bin/sh
printf 'apt %s\n' "$*" >>"$TEST_LOG"
if [ "$1" = install ]; then
    for file in $TEST_DESKTOPS; do
        printf '[Desktop Entry]\nType=Application\nName=Native\nExec=true\nMimeType=application/x-test-flux;\n' >"$TEST_ROOT/apps/$file"
    done
    printf '#!/bin/sh\nprintf "launch\\n" >>"$TEST_LOG"\nprintf "%%s\\n" "$@" >"$TEST_ROOT/args"\n' >"$TEST_EXECUTABLE"
    chmod +x "$TEST_EXECUTABLE"
fi
[ "$1" != "${FAIL_AT:-}" ] || exit 100
SH
cat >"$TEST_ROOT/bin/update-desktop-database" <<'SH'
#!/bin/sh
[ "$2" = "$TEST_ROOT/apps" ] || exit 98
printf 'cache\n' >>"$TEST_LOG"
[ "${CACHE_STATUS:-0}" = 0 ] || exit "$CACHE_STATUS"
exec "$REAL_DESKTOP_UPDATE" "$@"
SH
cat >"$TEST_ROOT/bin/runuser" <<'SH'
#!/bin/sh
printf 'guest\n' >>"$TEST_LOG"
shift 3
exec "$@"
SH
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/fbstartupnotify"
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/xhost"
cat >"$TEST_ROOT/bin/id" <<'SH'
#!/bin/sh
case "$1" in -un) echo testuser;; -u) echo "$TEST_UID";; -g) echo "$TEST_GID";; *) exit 1;; esac
SH
cat >"$TEST_ROOT/bin/getent" <<'SH'
#!/bin/sh
printf 'testuser:x:%s:%s::%s:/bin/bash\n' "$TEST_UID" "$TEST_GID" "$HOME"
SH
chmod +x "$TEST_ROOT/bin/"*
fail() { echo "FAIL: $*" >&2; cat "$TEST_LOG" >&2; exit 1; }
# Privileged install helpers can inherit a private umask from pkexec.
run_app() { (umask 077; bash "$TEST_ROOT/fbliveapp" "$APP" 'file with spaces.sb'); }
check_install_state_cleanup() {
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ] || fail 'temporary install state leaked'
}
prepare() {
    check_install_state_cleanup
    export APP=$1 TEST_DESKTOPS=$2 TEST_EXECUTABLE="$TEST_ROOT/installed/$3"
    rm -f -- "$TEST_EXECUTABLE" "$TEST_ROOT/args"
    # Also repair a cache left private by an earlier privileged install.
    if [ -e "$TEST_ROOT/apps/mimeinfo.cache" ]; then
        chmod 600 "$TEST_ROOT/apps/mimeinfo.cache"
    fi
    : >"$TEST_LOG"
    for file in $TEST_DESKTOPS; do : >"$TEST_ROOT/apps/$file"; done
}
mkdir -p "$HOME/.local/share/applications"
printf 'my customized launcher\n' >"$HOME/.local/share/applications/minios-help-flux.desktop"
printf '[Desktop Entry]\nType=Application\nName=Store URI\nExec=true\nNoDisplay=true\nMimeType=x-scheme-handler/minios-store;\n' >"$TEST_ROOT/apps/minios-store-uri-handler.desktop"
sha256sum "$HOME/.local/share/applications/minios-help-flux.desktop" \
    "$TEST_ROOT/apps/minios-store-uri-handler.desktop" >"$TEST_ROOT/unchanged"
for TEST_EUID in 0 1000; do
    export TEST_EUID
    while IFS='|' read -r app desktops executable; do
        prepare "$app" "$desktops" "$executable"
        run_app || fail "installation failed: $APP, uid=$TEST_EUID"
        for file in $TEST_DESKTOPS; do [ ! -e "$TEST_ROOT/apps/$file" ] || fail "duplicate remains: $file"; done
        grep -qx cache "$TEST_LOG" || fail 'MIME cache was not refreshed'
        [ "$(stat -c %a "$TEST_ROOT/apps/mimeinfo.cache")" = 644 ] ||
            fail 'system MIME application cache is not readable by other users'
        [ "$(tail -n1 "$TEST_LOG")" = launch ] || fail 'application was not launched last'
        [ "$(cat "$TEST_ROOT/args")" = 'file with spaces.sb' ] || fail 'arguments changed'
        sha256sum -c "$TEST_ROOT/unchanged" >/dev/null || fail 'user launcher or URI handler changed'
        grep -q 'minios-store-uri-handler.desktop' "$TEST_ROOT/apps/mimeinfo.cache" || fail 'URI association lost'
        if [ "$TEST_EUID" -ne 0 ]; then
            grep -qx pkexec "$TEST_LOG" || fail 'installation did not request elevation'
            ! grep -qx guest "$TEST_LOG" || fail 'non-root launch switched to guest'
        fi
    done <<'APPS'
vlc|vlc.desktop|vlc
chromium|chromium.desktop|chromium
firefox-esr|firefox-esr.desktop|firefox-esr
minios-installer|minios-installer.desktop|minios-installer
minios-configurator|minios-configurator.desktop|minios-configurator
minios-session-manager|minios-session-manager.desktop|minios-session-manager
minios-kernel-manager|minios-kernel-manager.desktop|minios-kernel-manager
minios-module-manager|minios-module-manager.desktop|minios-module-manager
minios-image-builder|minios-image-builder.desktop|minios-image-builder
minios-store|minios-store.desktop|minios-store-launcher
minios-help|minios-help.desktop dev.minios.Help.desktop|minios-help
driveutility|driveutility.desktop driveutility-kde.desktop|driveutility
APPS
    echo "PASS: 12 install paths remove only duplicate launchers (simulated uid=$TEST_EUID)"
done
export TEST_EUID=1000
for step in update install; do
    prepare minios-help minios-help.desktop minios-help
    if FAIL_AT=$step run_app; then fail "$step failure was ignored"; else status=$?; fi
    [ "$status" -eq 100 ] || fail "wrong failure status: $status"
    [ -f "$TEST_ROOT/apps/minios-help.desktop" ] || fail 'cleanup ran on failure'
    ! grep -Eq '^(cache|launch)$' "$TEST_LOG" || fail 'failure continued to cache or launch'
done
echo 'PASS: update/install failures preserve launchers and do not launch partial installations'
prepare minios-help minios-help.desktop minios-help
DECLINE=1 run_app
[ ! -s "$TEST_LOG" ] || fail 'declining installation executed commands'
[ -f "$TEST_ROOT/apps/minios-help.desktop" ] || fail 'declining removed a launcher'
if AUTH_DENIED=1 run_app; then fail 'authorization failure was ignored'; else status=$?; fi
[ "$status" -eq 126 ] || fail 'authorization failure status changed'
[ "$(cat "$TEST_LOG")" = pkexec ] || fail 'authorization failure ran commands'
echo 'PASS: cancellation and authorization failure do not install or remove launchers'
prepare minios-help minios-help.desktop minios-help
if CACHE_STATUS=42 run_app; then fail 'cache failure was ignored'; else status=$?; fi
[ "$status" -eq 42 ] || fail 'cache failure status changed'
! grep -qx launch "$TEST_LOG" || fail 'application launched after cache failure'
echo 'PASS: cache update failures propagate'
: >"$TEST_LOG"
printf 'installed outside fbliveapp\n' >"$TEST_ROOT/apps/minios-help.desktop"
run_app
[ "$(cat "$TEST_LOG")" = launch ] || fail 'ordinary launch attempted another installation'
[ -f "$TEST_ROOT/apps/minios-help.desktop" ] || fail 'ordinary launch unexpectedly removed files'
echo 'PASS: an already installed application starts without installation or cleanup'

prepare minios-help dev.minios.Help.desktop minios-help
if TERMINAL_CLOSED=1 run_app; then fail 'closed terminal was treated as a successful install'; else status=$?; fi
[ "$status" -eq 1 ] || fail 'missing installation result did not fail closed'
[ ! -s "$TEST_LOG" ] || fail 'closed terminal executed installation commands'
[ -f "$TEST_ROOT/apps/dev.minios.Help.desktop" ] || fail 'closed terminal removed a launcher'
check_install_state_cleanup
echo 'PASS: a terminal closed before reporting its result does not launch the application'
echo 'PASS: temporary installation state is removed after success, failure and cancellation'


# Reinstallation must preserve the caller's settings, including symlinks.
export TEST_EUID=1000
unset XDG_CONFIG_HOME
mkdir -p "$HOME/.config/vlc"
printf 'my volume and playback settings\n' >"$HOME/.config/vlc/vlcrc"
cp "$HOME/.config/vlc/vlcrc" "$TEST_ROOT/saved-vlcrc"
prepare vlc vlc.desktop vlc
run_app
cmp "$HOME/.config/vlc/vlcrc" "$TEST_ROOT/saved-vlcrc" || fail 'VLC config was overwritten'
rm "$HOME/.config/vlc/vlcrc"
ln -s "$TEST_ROOT/saved-vlcrc" "$HOME/.config/vlc/vlcrc"
prepare vlc vlc.desktop vlc
run_app
[ -L "$HOME/.config/vlc/vlcrc" ] || fail 'VLC config symlink was replaced'
grep -qx 'my volume and playback settings' "$TEST_ROOT/saved-vlcrc" || fail 'VLC followed a config symlink'
echo 'PASS: VLC reinstallation preserves both existing settings and symlink targets'

export HOME="$TEST_ROOT/home with an apostrophe's name"
mkdir -p "$HOME"
prepare vlc vlc.desktop vlc
run_app
printf '[qt4]\nqt-privacy-ask=0\n' >"$TEST_ROOT/initial-vlcrc"
cmp "$HOME/.config/vlc/vlcrc" "$TEST_ROOT/initial-vlcrc" || fail 'VLC config initialization failed'
[ "$(stat -c %a "$HOME/.config/vlc/vlcrc")" = 600 ] || fail 'initial VLC settings are not private'
export XDG_CONFIG_HOME="$TEST_ROOT/other config"
prepare vlc vlc.desktop vlc
run_app
cmp "$XDG_CONFIG_HOME/vlc/vlcrc" "$TEST_ROOT/initial-vlcrc" || fail 'VLC ignored XDG_CONFIG_HOME'
unset XDG_CONFIG_HOME
echo 'PASS: new VLC settings honor XDG paths, apostrophes and private permissions'

cat >"$TEST_ROOT/bin/apt-cache" <<'SH'
#!/bin/sh
printf 'lookup %s\n' "$*" >>"$TEST_LOG"
exit "${L10N_MISSING:-0}"
SH
chmod +x "$TEST_ROOT/bin/apt-cache"
while IFS='|' read -r locale package; do
    prepare firefox-esr firefox-esr.desktop firefox-esr
    LC_ALL= LC_MESSAGES= LANG="$locale" run_app
    grep -q "apt install .*firefox-esr-l10n-$package" "$TEST_LOG" || fail "wrong locale package: $locale"
done <<'LOCALES'
en_GB.UTF-8|en-gb
pt_PT.UTF-8|pt-pt
pt_BR.UTF-8|pt-br
es_ES.UTF-8|es-es
zh_CN.UTF-8|zh-cn
zh_TW.UTF-8|zh-tw
ru_RU.UTF-8|ru
LOCALES
prepare firefox-esr firefox-esr.desktop firefox-esr
LC_ALL= LC_MESSAGES= LANG=xx_XX.UTF-8 L10N_MISSING=1 run_app
! grep -q '^apt install .*firefox-esr-l10n-' "$TEST_LOG" || fail 'missing language pack blocks installation'
grep -qx launch "$TEST_LOG" || fail 'browser not launched without language pack'
echo 'PASS: regional Firefox language packages and missing optional translations are handled'

if bash "$TEST_ROOT/fbliveapp" unknown; then fail 'unknown app accepted'; else status=$?; fi
[ "$status" -eq 2 ] || fail 'wrong unknown app status'
if bash "$TEST_ROOT/fbliveapp"; then fail 'missing app accepted'; else status=$?; fi
[ "$status" -eq 2 ] || fail 'wrong missing app status'
check_install_state_cleanup
echo 'PASS: invalid application names report an error without installation'
