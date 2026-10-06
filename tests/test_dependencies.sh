#!/bin/bash
# Check runtime launcher alternatives against a private dpkg package database.
set -eu
export LC_ALL=C
SOURCE_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
CONTROL=${1:-"$SOURCE_DIR/debian/control"}
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Parse folded control fields with dpkg's own parser. Only Depends counts:
# Recommends is deliberately ignored by minimal MiniOS image builds.
LAUNCHER_DEPS=$(perl -MDpkg::Control::Info -e '
    my $control = Dpkg::Control::Info->new($ARGV[0]);
    my $package = $control->get_pkg_by_name("flux-tools");
    die "flux-tools package is missing\n" unless $package;
    print join ", ", grep { /\b(?:libglib2\.0-bin|libgtk-3-bin)\b/ }
        split /\s*,\s*/, $package->{Depends} // "";
' "$CONTROL")
[ -n "$LAUNCHER_DEPS" ] || fail 'no required desktop launcher in Depends'

check_case() {
    local expected=$1 label=$2 actual
    shift 2
    : >"$TEST_ROOT/status"
    while [ "$#" -gt 0 ]; do
        cat >>"$TEST_ROOT/status" <<EOF
Package: $1
Status: install ok installed
Architecture: all
Version: $2
Description: Test fixture

EOF
        shift 2
    done
    if dpkg-checkbuilddeps -I -d "$LAUNCHER_DEPS" -c '' \
        --admindir="$TEST_ROOT" "$CONTROL" >"$TEST_ROOT/result" 2>&1; then
        actual=0
    else
        actual=$?
    fi
    if [ "$actual" -ne "$expected" ]; then
        cat "$TEST_ROOT/result" >&2
        fail "$label (expected status $expected, got $actual)"
    fi
    echo "PASS: $label"
}

check_case 1 'a desktop launcher is mandatory'
check_case 1 'GLib 2.56 alone is insufficient' libglib2.0-bin 2.56.4
check_case 1 'GLib 2.66 alone is insufficient' libglib2.0-bin 2.66.8
check_case 1 'GIO without the launch command is insufficient' libglib2.0-bin 2.67.1
check_case 0 'GIO with launch support is sufficient' libglib2.0-bin 2.67.2
check_case 0 'modern GIO does not require GTK tools' libglib2.0-bin 2.84.4
check_case 0 'GTK can be used without GIO tools' libgtk-3-bin 3.24.49
check_case 0 'older GLib is supported through GTK' \
    libglib2.0-bin 2.56.4 libgtk-3-bin 3.22.30
