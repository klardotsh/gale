-- gluumy is copyfree software with no warranty, released under the CC0-1.0
-- public-domain-esque dedication found in COPYING in gluumy's source tree, or
-- at https://creativecommons.org/publicdomain/zero/1.0/

local describe = require('test_harness')

local ast = require('ast')
local symbols = require('symbols')

describe('AST unit', function(it)
	function parsed(generator)
		return ast.parse_stream(coroutine.create(generator))
	end

	it('can parse a one-line string assignment', function(expect)
		expect(parsed(function()
			coroutine.yield({ kind = SYMBOLS.IDENTIFIER, contents = 'foo', lineno = 1 })
			coroutine.yield({ kind = SYMBOLS.EQUAL, lineno = 1 })
			coroutine.yield({ kind = SYMBOLS.IDENTIFIER, contents = 'bar', lineno = 1 })
		end))
			.to.equal({
				{
					kind = ast.node_kinds.LET_EQ,
					let_name = 'foo',
					let_target = {
						kind = ast.node_kinds.PRIMITIVE,
						prim_type = ast.prim_types.STRING,
						prim_value = 'bar',
					},
				}
			})
	end)
end)

describe('LEX+AST integration', function(it)
end)
