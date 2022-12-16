.POSIX:

.PHONY: lint
lint:
	ziglint -skip todo

.PHONY: test
test:
	zig test ./src/main.zig
