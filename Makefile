PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
BIN = $(shell swift build -c release --show-bin-path)/pkexec

PREFIX := $(HOME)/.local

.PHONY: test build install

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(PLUGINS)

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/pkexec
