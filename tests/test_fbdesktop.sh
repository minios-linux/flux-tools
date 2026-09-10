#!/bin/bash
# Exercise the real MIME cache updater without touching the login user's files.
set -eu
unset XDG_DATA_HOME

SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
REAL_DESKTOP_UPDATE=$(command -v update-desktop-database)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export REAL_DESKTOP_UPDATE
export HOME="$TEST_ROOT/home with spaces"
mkdir -p "$TEST_ROOT/bin" "$HOME"
export PATH="$TEST_ROOT/bin:$PATH"

# Only identity and application availability are stubbed; cache generation is real.
printf '#!/bin/sh\necho 1000\n' > "$TEST_ROOT/bin/id"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/pcmanfm"
cat > "$TEST_ROOT/bin/update-desktop-database" <<'EOF'
#!/bin/sh
if [ -n "${CACHE_TEST_FAILURE:-}" ]; then
    exit "$CACHE_TEST_FAILURE"
fi
exec "$REAL_DESKTOP_UPDATE" "$@"
EOF
chmod +x "$TEST_ROOT/bin/"*

APPDIR="$HOME/.local/share/applications"
MARKER="$HOME/.fluxbox/fbdesktop.initialized"
run_fbdesktop() { bash "$SOURCE_DIR/bin/fbdesktop"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

run_fbdesktop
[ -f "$MARKER" ] || fail 'first run did not create the marker'
grep -q '^inode/directory=pcmanfm-flux.desktop;' "$APPDIR/mimeinfo.cache" ||
    fail 'first run did not register the folder handler'
echo 'PASS: initial entries are registered in the MIME cache'

# An initialized profile still needs cache repair, not launcher regeneration.
sed -i 's/^Name=.*/Name=My custom file manager/' "$APPDIR/pcmanfm-flux.desktop"
cp "$APPDIR/pcmanfm-flux.desktop" "$TEST_ROOT/custom-entry"
mkdir -p "$HOME/.config"
printf '[Default Applications]\ninode/directory=chosen-folder.desktop;\n' > "$HOME/.config/mimeapps.list"
cp "$HOME/.config/mimeapps.list" "$TEST_ROOT/mimeapps.list"
rm "$APPDIR/mimeinfo.cache"
run_fbdesktop
grep -q '^inode/directory=pcmanfm-flux.desktop;' "$APPDIR/mimeinfo.cache" ||
    fail 'initialized profile did not repair its MIME cache'
cmp "$APPDIR/pcmanfm-flux.desktop" "$TEST_ROOT/custom-entry" ||
    fail 'customized launcher was overwritten'
cmp "$HOME/.config/mimeapps.list" "$TEST_ROOT/mimeapps.list" ||
    fail 'default applications were overwritten'
echo 'PASS: cache is repaired without changing launchers or preferences'

rm "$APPDIR/pcmanfm-flux.desktop"
run_fbdesktop
[ ! -e "$APPDIR/pcmanfm-flux.desktop" ] || fail 'deleted launcher was recreated'
if grep -q 'pcmanfm-flux.desktop' "$APPDIR/mimeinfo.cache"; then
    fail 'deleted launcher remains registered in the cache'
fi
echo 'PASS: deleted entries are removed from the cache, not recreated'

mv "$APPDIR" "$TEST_ROOT/removed-applications"
run_fbdesktop
[ ! -e "$APPDIR" ] || fail 'removed application directory was recreated'
echo 'PASS: an initialized profile may have no application directory'

# A failed first cache update must not mark initialization as successful.
export HOME="$TEST_ROOT/failure-profile"
mkdir -p "$HOME"
if CACHE_TEST_FAILURE=42 run_fbdesktop; then
    fail 'cache update failure was ignored'
else
    status=$?
    [ "$status" -eq 42 ] || fail "unexpected cache failure status: $status"
fi
[ ! -e "$HOME/.fluxbox/fbdesktop.initialized" ] ||
    fail 'failed initialization created a success marker'
run_fbdesktop
[ -f "$HOME/.fluxbox/fbdesktop.initialized" ] || fail 'retry did not initialize'
echo 'PASS: cache failure is reported and initialization can be retried'


export HOME="$TEST_ROOT/partial-profile"
APPDIR="$HOME/.local/share/applications"
mkdir -p "$APPDIR/firefox-esr-flux.desktop"
if run_fbdesktop; then fail 'a failed desktop write was accepted'; fi
[ ! -e "$HOME/.fluxbox/fbdesktop.initialized" ] || fail 'failed write set the marker'
rmdir "$APPDIR/firefox-esr-flux.desktop"
printf 'personal launcher\n' >"$APPDIR/pcmanfm-flux.desktop"
run_fbdesktop
[ -f "$APPDIR/firefox-esr-flux.desktop" ] || fail 'retry did not finish initialization'
grep -qx 'personal launcher' "$APPDIR/pcmanfm-flux.desktop" || fail 'retry overwrote an existing file'
echo 'PASS: failed writes leave initialization retryable without replacing existing entries'

export HOME="$TEST_ROOT/xdg-profile" XDG_DATA_HOME="$TEST_ROOT/xdg data"
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/gpicview"
chmod +x "$TEST_ROOT/bin/gpicview"
run_fbdesktop
APPDIR="$XDG_DATA_HOME/applications"
[ -f "$APPDIR/pcmanfm-flux.desktop" ] || fail 'XDG_DATA_HOME ignored'
[ ! -e "$HOME/.local/share/applications" ] || fail 'hardcoded app directory created'
grep -q '^image/png=.*gpicview-flux.desktop' "$APPDIR/mimeinfo.cache" || fail 'PNG viewer not registered'
grep -qx 'NoDisplay=true' "$APPDIR/gpicview-flux.desktop" || fail 'image viewer not hidden from the menu'
! grep -q '^Hidden=true' "$APPDIR/gpicview-flux.desktop" || fail 'image handler is disabled'
for desktop in "$APPDIR/"*.desktop; do desktop-file-validate "$desktop" || fail 'invalid desktop'; done
echo 'PASS: XDG paths and concrete image handlers produce valid desktop entries'
unset XDG_DATA_HOME

# Redirect the root-only system path. Test real umask/cache semantics as a user.
export HOME="$TEST_ROOT/root-profile"
printf '#!/bin/sh\necho 0\n' >"$TEST_ROOT/bin/id"
sed "s|/usr/share/applications|$TEST_ROOT/system-applications|g" "$SOURCE_DIR/bin/fbdesktop" >"$TEST_ROOT/fbdesktop-root"
(umask 077; bash "$TEST_ROOT/fbdesktop-root")
for file in "$TEST_ROOT/system-applications/"*.desktop "$TEST_ROOT/system-applications/mimeinfo.cache"; do
    [ "$(stat -c %a "$file")" = 644 ] || fail "unreadable system entry: $file"
done
echo 'PASS: system desktop entries and MIME caches are readable with umask 077'
