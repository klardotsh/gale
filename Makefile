.POSIX:

.PHONY: lint
lint:
	ziglint -skip todo

.PHONY: test
test:
	zig build test
