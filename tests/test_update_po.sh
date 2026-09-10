#!/bin/bash
# Never update the working tree while testing the offline maintenance helper.
set -eu
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/source/debian" "$TEST_ROOT/source/bin"
cp "$SOURCE_DIR/update-po.sh" "$TEST_ROOT/source/"
cp "$SOURCE_DIR/debian/changelog" "$TEST_ROOT/source/debian/"
cp -a "$SOURCE_DIR/po" "$TEST_ROOT/source/"
printf '#!/bin/bash\ngettext "Translation fixture"\n' >"$TEST_ROOT/source/bin/fixture"
cp "$TEST_ROOT/source/po/messages.pot" "$TEST_ROOT/old-template"
printf '#!/bin/sh\nexit 42\n' >"$TEST_ROOT/bin/xgettext"
chmod +x "$TEST_ROOT/bin/xgettext"
if PATH="$TEST_ROOT/bin:$PATH" bash "$TEST_ROOT/source/update-po.sh" >"$TEST_ROOT/output" 2>&1; then
    echo 'FAIL: extraction error reported success' >&2; exit 1
else status=$?; fi
[ "$status" -eq 42 ] || exit 1
cmp "$TEST_ROOT/source/po/messages.pot" "$TEST_ROOT/old-template"
! grep -q 'catalogs updated' "$TEST_ROOT/output"
[ -z "$(find "$TEST_ROOT/source/po" -name '.messages.*' -print -quit)" ]
echo 'PASS: gettext extraction failure preserves the old template and removes temporary files'
bash "$TEST_ROOT/source/update-po.sh" >"$TEST_ROOT/output" 2>&1
grep -q '^msgid "Translation fixture"' "$TEST_ROOT/source/po/messages.pot"
! grep -q '^msgid "Web Browser"' "$TEST_ROOT/source/po/messages.pot"
echo 'PASS: fresh extraction removes stale messages rather than accumulating them'
