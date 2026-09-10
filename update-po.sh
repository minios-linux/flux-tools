#!/bin/bash
# Offline gettext template/catalog maintenance. Normal project translations
# are orchestrated by Lokit; this script never calls a translation provider.
set -euo pipefail
export LC_ALL=C
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
APPNAME=$(dpkg-parsechangelog -S Source)
VERSION=$(dpkg-parsechangelog -S Version)
mkdir -p po
TEMPFILE=$(mktemp po/.messages.XXXXXX)
trap 'rm -f -- "$TEMPFILE"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Every installed program is a Bash script. Do not extract fixtures, tests,
# old templates or this maintenance script into the application catalog.
xgettext --language=Shell --keyword=gettext --add-comments=TRANSLATORS \
    --from-code=UTF-8 --sort-output --force-po \
    --package-name="$APPNAME" --package-version="$VERSION" \
    --msgid-bugs-address=support@minios.dev --copyright-holder='MiniOS Linux' \
    --output="$TEMPFILE" bin/*
# Keep the previous template intact when extraction fails.
mv -fT -- "$TEMPFILE" po/messages.pot
for catalog in po/*.po; do
    [ -f "$catalog" ] || continue
    msgmerge --update --backup=off "$catalog" po/messages.pot
    printf '%s: ' "$catalog"
    msgfmt --check --statistics --output-file=/dev/null "$catalog"
done
printf '%s\n' 'Gettext catalogs updated.'
