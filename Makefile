# Variables
EXECUTABLES = $(shell find bin -type f)
SHARE = share

BINDIR = usr/bin
SHAREDIR = usr/share
LOCALEDIR = usr/share/locale

DOC_FILES = $(shell find doc -name "*.md")
MAN_FILES = $(patsubst doc/%.md, man/%.1, $(DOC_FILES))

PO_FILES  = $(shell find po -name "*.po")
MO_FILES  = $(patsubst %.po,%.mo,$(PO_FILES))

# Build rules
ifeq (,$(findstring nodoc,$(DEB_BUILD_PROFILES)))
ifeq (,$(findstring nodoc,$(DEB_BUILD_OPTIONS)))
build: man
endif
endif
build: po

# Compilation rules
man: $(MAN_FILES)

man/%.1: doc/%.md
	@echo "Generating man file for $<"
	mkdir -p $(@D)
	pandoc -s -t man $< -o $@

po: $(MO_FILES)

%.mo: %.po
	@echo "Generating mo file for $<"
	msgfmt -o $@ $<
	chmod 644 $@

# Clean rule
clean:
	rm -rf man $(MO_FILES)

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