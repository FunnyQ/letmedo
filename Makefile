PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
BIN := .build/release/pkexec

.PHONY: test build

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(PLUGINS)

build:
	swift build -c release
	codesign --force --sign pkexec-local --identifier cc.funnyq.pkexec --options runtime $(BIN)
	codesign --verify --strict $(BIN)
