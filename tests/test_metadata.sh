#!/bin/bash
# Keep release metadata aligned with the Debian-native package authority.
set -eu
export LC_ALL=C

SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd -- "$SOURCE_DIR"
fail() { echo "FAIL: $*" >&2; exit 1; }

PACKAGE=$(dpkg-parsechangelog -S Source)
VERSION=$(dpkg-parsechangelog -S Version)
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    fail "release version must use MAJOR.MINOR.PATCH: $VERSION"
[ "$(cat debian/source/format)" = '3.0 (native)' ] ||
    fail 'review version mirroring when changing the Debian source format'
[ "$(dpkg-parsechangelog -S Distribution)" = unstable ] ||
    fail 'MiniOS changelog distribution must be unstable'
EXPECTED="$PACKAGE $VERSION"

for file in man/*.1; do
    [ -f "$file" ] || fail 'no manual pages found'
    actual=$(awk -F '"' 'NR == 1 && /^\.TH / { print $4 }' "$file")
    [ "$actual" = "$EXPECTED" ] ||
        fail "$file: expected '$EXPECTED', found '$actual'"
done

for file in po/messages.pot po/*.po; do
    [ -f "$file" ] || fail "missing gettext catalog: $file"
    actual=$(sed -n 's/^"Project-Id-Version: \(.*\)\\n"$/\1/p' "$file")
    [ "$actual" = "$EXPECTED" ] ||
        fail "$file: expected '$EXPECTED', found '$actual'"
done

echo "PASS: $EXPECTED matches every manual page and gettext catalog"
