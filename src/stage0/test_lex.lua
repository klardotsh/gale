local lu = require('luaunit')

local lex = require('lex')
local symbols = require('symbols')

function parsed(generator)
	return ast.parse_stream(coroutine.create(generator))
end

TestAST = {}

function TestAST:test_one_line_string_assignment()
	lu.assertEquals(
		parsed(function()
			coroutine.yield({ kind = SYMBOLS.IDENTIFIER, contents = 'foo', lineno = 1 })
			coroutine.yield({ kind = SYMBOLS.EQUAL, lineno = 1 })
			coroutine.yield({ kind = SYMBOLS.IDENTIFIER, contents = 'bar', lineno = 1 })
		end),
		{
			kind = ast.node_kinds.LET_EQ,
			let_name = 'foo',
			let_target = {
				kind = ast.node_kinds.PRIMITIVE,
				prim_type = ast.prim_types.STRING,
				prim_value = 'bar',
			},
		}
	)
end

os.exit(lu.LuaUnit.run())
