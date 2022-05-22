VERSION := $(shell cat .version )

PROGNAME = fs_indexer
PROGNAME_VERSION = $(PROGNAME)-$(VERSION)
TARGZ_FILENAME = $(PROGNAME)-$(VERSION).tar.gz
TARGZ_CONTENTS = fs_indexer.sh README.md Makefile .version

PREFIX = /opt/fs_indexer
PWD = $(shell pwd)
TMPDIR = $(shell mktemp -d)

export PROGROOT=$(PWD)/$(PROGNAME_VERSION)

.PHONY: all version build clean install test

$(TARGZ_FILENAME):
	tar -zvcf "$(TARGZ_FILENAME)" "$(PROGNAME_VERSION)"

build:
	mkdir -vp "$(PROGNAME_VERSION)"
	cp -vR $(TARGZ_CONTENTS) "$(PROGNAME_VERSION)/"
	sed -i"" -e "s/VERSION=.*/VERSION='$(VERSION)'/" "$(PROGNAME_VERSION)/fs_indexer.sh"
	[ -f "$(PROGNAME_VERSION)/fs_indexer.sh-e" ] && rm "$(PROGNAME_VERSION)/fs_indexer.sh-e" || :

compress: $(TARGZ_FILENAME)

version:
	@echo "Version: $(VERSION)"

clean:
	rm -vfr "$(PROGNAME_VERSION)"
	rm -vf "$(TARGZ_FILENAME)"

test:
	export SCAN_ROOT=${PWD}
	@cp -v "$(PROGNAME_VERSION)/fs_indexer.sh" "$(TMPDIR)"

	cd "$(TMPDIR)"
	@echo "TMPDIR: $(TMPDIR)"

	bash fs_indexer.sh
	ls -la .

	sqlite3 database.sqlite3 "select * from fs_scan_history"
	sqlite3 database.sqlite3 "select * from fs_checksum"
	sqlite3 database.sqlite3 "select * from fs_index"

	@echo "noop"


install:
	install -d $(DESTDIR)/usr/share/doc/$(PROGNAME_VERSION)
	install -d $(DESTDIR)/usr/bin
	install -m 755 fs_indexer.sh $(DESTDIR)/usr/bin
	install -m 644 README.md $(DESTDIR)/usr/share/doc/$(PROGNAME_VERSION)

