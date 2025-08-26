# Variables
EXECUTABLES = $(shell find bin -type f)
SHARE = share
MAN_PAGES = $(shell find man -name "*.1" 2>/dev/null)

BINDIR = usr/bin
SHAREDIR = usr/share
LOCALEDIR = usr/share/locale
MANDIR = usr/share/man/man1

PO_FILES  = $(shell find po -name "*.po")
MO_FILES  = $(patsubst %.po,%.mo,$(PO_FILES))

# Build rules
build: po

# Compilation rules
po: $(MO_FILES)

%.mo: %.po
	@echo "Generating mo file for $<"
	msgfmt -o $@ $<
	chmod 644 $@

# Clean rule
clean:
	rm -rf $(MO_FILES)

# Install rule
install: build
	install -d $(DESTDIR)/$(BINDIR)
	install -m755 $(EXECUTABLES) $(DESTDIR)/$(BINDIR)
	install -d $(DESTDIR)/$(SHAREDIR)
	cp -R $(SHARE)/* $(DESTDIR)/$(SHAREDIR)/

	for MO_FILE in $(MO_FILES); do \
		LOCALE=$$(basename $$MO_FILE .mo); \
		echo "Copying mo file $$MO_FILE to $(DESTDIR)/$(LOCALEDIR)/$$LOCALE/LC_MESSAGES/flux-tools.mo"; \
		install -Dm644 "$$MO_FILE" "$(DESTDIR)/$(LOCALEDIR)/$$LOCALE/LC_MESSAGES/flux-tools.mo"; \
	done

	if [ -d man ]; then \
		install -d $(DESTDIR)/$(MANDIR); \
		for MAN_FILE in $(MAN_PAGES); do \
			echo "Installing manual page $$MAN_FILE"; \
			install -m644 "$$MAN_FILE" "$(DESTDIR)/$(MANDIR)/"; \
		done; \
	fi