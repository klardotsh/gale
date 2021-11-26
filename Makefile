.POSIX:

##### Tests and Test Accessories

TEST_LUA ?= luajit

.PHONY: test
test: test-stage0-ast

.PHONY: test-stage0-ast
test-stage0-ast:
	cd src/stage0 && $(TEST_LUA) test_ast.lua
