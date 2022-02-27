local lu = require('luaunit')

local parser = require('parser')
local Entity = parser.Entity
local EntityKind = parser.Entity.Kind
local PointInSource = parser.PointInSource

TestAST = {}

function TestAST:test_one_line_simple_comment()
	lu.assertEquals(
        parser.parse_string("-- this is a one line comment"),
		Entity({
			start = PointInSource({
				line = 1,
				column = 1,
			}),
			["end"] = PointInSource({
				line = 1,
				column = 30,
			}),
			kind = EntityKind.Comment("this is a one line comment"),
		})
	)
end
--[[
function TestAST:test_merge_two_line_comment()
	lu.assertEquals(
        parser.parse_string("-- line one\n-- line two"),
		Entity({
			start = PointInSource({
				line = 1,
				column = 1,
			}),
			["end"] = PointInSource({
				line = 2,
				column = 11,
			}),
			kind = EntityKind.Comment("line one line two"),
		})
	)
end
]]

os.exit(lu.LuaUnit.run())
