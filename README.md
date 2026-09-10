# Flux Tools

Shell helpers for the MiniOS Flux desktop. The package keeps the existing X11
and GTK toolchain: no new runtime packages, service or application registry are
required by these fixes.

## Launching applications

`fbdesktop` seeds the standard launchers once. `fbappselect` shows the list
produced by `xlunch_genquick`, and `fbliveapp APPLICATION [ARGUMENT...]` offers
to install a supported application when it is missing.

Desktop files are launched through `gio launch`; older GLib versions use
`gtk-launch` with the desktop ID from the same XDG application directories.
Quoted arguments, field codes, `TryExec`, `Path` and terminal requests are left
to the desktop launcher rather than interpreted as shell code. Free-form
commands typed into xlunch run in a terminal and retain shell syntax.

Only one application menu and one startup-cursor watcher run per user/display.
The watcher restores the cursor after at most ten seconds if no window appears.
A menu invocation no longer kills all xlunch processes.

## User settings

The initialization marker remains `~/.fluxbox/fbdesktop.initialized`.
Successful initialization does not replace existing launchers; subsequent
runs refresh the MIME cache without recreating deleted entries. Failed writes
do not set the marker, so the next run can complete initialization.

For ordinary users, application entries follow `XDG_DATA_HOME`, defaulting to
`~/.local/share/applications`. Root's standard entries stay in
`/usr/share/applications` and are readable by other users. User-selected MIME
associations are never changed. The hidden image viewer uses `NoDisplay`, not
`Hidden`, so it still handles images when absent from the application menu.

VLC and Chromium use `guest` only when invoked from a root session. Installer
and Configurator request root privileges with pkexec when needed; other MiniOS
applications retain their own privilege handling. VLC's initial privacy
setting is written only for a missing config, as its owner, outside the
privileged package installation. Existing files and symlinks are preserved.
Firefox language packs are optional and use regional package names.

## Session helpers

`fbsetkb LAYOUT` saves a layout only after applying it successfully.
`fbscreensize MODE [-n]` selects the primary connected display, or the first
connected display when there is no primary. After a successful mode change,
it reinitializes only this display's Compton with SIGUSR1; `-n` omits that step.

`fbprintscreen` saves into the XDG pictures directory (or `~/Pictures`), then
uses gpicview or feh when available. Capture failures remove partial images.
`fblogout` ends only the current user's Fluxbox on the current display. Power
actions use the system reboot/poweroff commands and pkexec for non-root users.
Failures remove the temporary blank overlay and are reported to the caller.

`gtk-bookmarks-update` maintains root's automounted-volume bookmarks. It uses
a bounded flock in `/root/.fluxbox`, preserves personal bookmarks and encodes
volume names as file URIs. Other users' bookmarks are not modified.

## Compatibility with 1.x

Version 2.0.0 includes deliberate default-behavior changes, not only fixes.
Free-form launcher input always runs in a terminal. Resolution changes
prefer the primary display and reinitialize an existing Compton rather
than starting or replacing it. Invalid arguments and failed actions now
return nonzero statuses; callers must handle these failures.

Command names, the initialization marker and user data formats remain
unchanged. No migration or new dependency is required.

## Tests and development

Run `make test` for metadata, shell syntax and regression tests. System-changing
commands are stubbed and files are confined to temporary directories; these
tests do not install packages, signal desktop processes or power off the host.
They use the existing build dependencies and base-system utilities.

`make test-launch` additionally exercises the actual GIO launcher.
`FORCE_GTK=1 make test-launch` tests the GTK fallback and requires an X display;
on a headless development machine it can run under an existing Xvfb setup.
No test packages are added to the runtime dependencies.

The Debian-native release authority is `debian/changelog`. `make test` checks
that every manual and gettext catalog has the same version. Run translations
from the minios-live workspace with `lokit translate --target flux-tools`.
`update-po.sh` is an offline gettext maintenance helper, not a translation
provider; extraction errors preserve the previous template and return failure.

## Scope

Desktop discovery, icon lookup and visibility filtering belong to xlunch.
Flux Tools does not add a second application filter. The current policy for
removing package launcher duplicates after a successful fbliveapp installation
is retained; external package installations are not intercepted. No automatic
migration or restoration of user-deleted launchers is performed.
