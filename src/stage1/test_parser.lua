local lu = require('luaunit')

local parser = require('parser')
local parse_string = parser.parse_string
local Entity = parser.Entity
local EntityKind = parser.Entity.Kind
local PointInSource = parser.PointInSource

TestAST = {}

function TestAST:test_empty_string()
	lu.assertEquals(parse_string(""), {})
end

function TestAST:test_one_line_simple_comment()
	lu.assertEquals(
        parse_string("-- this is a one line comment"),
		{
			Entity({
				kind = EntityKind.Comment("this is a one line comment"),
			}),
		}
	)
end

function TestAST:test_one_line_unicode_comment()
	lu.assertEquals(
		parse_string("-- this is a one-line comment, but with Japanese characters: すてきな一日を"),
		{
			Entity({
				kind = EntityKind.Comment(
					"this is a one-line comment, but with Japanese characters: すてきな一日を"
				)
			}),
		}
	)
end

function TestAST:test_two_comments()
	lu.assertEquals(
        parse_string("-- line one\n-- line two\n"),
		{
			Entity({
				kind = EntityKind.Comment("line one"),
			}),
			Entity({
				kind = EntityKind.Comment("line two"),
			})
		}
	)
end

function TestAST:test_number_int()
    lu.assertEquals(
        parse_string("1"),
        {
			Entity({
				kind = EntityKind.Number("1"),
			})
		}
    )
end

function TestAST:test_number_int_2()
    lu.assertEquals(
        parse_string("42"),
        {
			Entity({
				kind = EntityKind.Number("42"),
			}),
		}
    )
end

function TestAST:test_number_int_with_underscores()
    lu.assertEquals(
        parse_string("12_345"),
        {
			Entity({
				kind = EntityKind.Number("12345"),
			}),
		}
    )
end

function TestAST:test_number_int_with_underscores_2()
    lu.assertEquals(
        parse_string("12_345_678"),
        {
			Entity({
				kind = EntityKind.Number("12345678"),
			}),
		}
    )
end

function TestAST:test_number_float()
    lu.assertEquals(
        parse_string("3.14"),
        {
			Entity({
				kind = EntityKind.Number("3.14"),
			}),
		}
    )
end

function TestAST:test_number_float_with_underscore()
    lu.assertEquals(
        parse_string("1_003.14"),
        {
			Entity({
				kind = EntityKind.Number("1003.14"),
			}),
		}
    )
end

function TestAST:test_number_float_with_underscore_2()
    lu.assertEquals(
        parse_string("1_003.141_5"),
        {
			Entity({
				kind = EntityKind.Number("1003.1415"),
			}),
		}
    )
end

function TestAST:test_number_with_multiple_decimal_err()
    lu.assertEquals(
        parse_string("3.14.15"),
		-- TODO: implement an error for this case, probably in the "real"
		-- compiler rather than the bootstrapper
		--[[
        Err(ParsingError::InvalidNumber(
            InvalidNumber::TooManyDecimalPoints,
            1,
            5
        )),
		]]
		{}
    )
end

function TestAST:test_number_then_a_comment()
    lu.assertEquals(
        parse_string("1_000_000 -- this was a number, tee hee"),
        {
			Entity({
				kind = EntityKind.Number("1000000"),
			}),
			Entity({
				kind = EntityKind.Comment("this was a number, tee hee"),
			}),
		}
    )
end

function TestAST:test_simple_shape_definition()
    lu.assertEquals(
        parse_string("Printable => repr :: Self -> String"),
        {
			Entity({
				kind = EntityKind.Shape({
					identifier = "Printable",
					composed_from = {},
					requisite_functions = {
						EntityKind.FunctionStub({
							identifier = "repr",
							arguments = {
								EntityKind.Argument({
									identifier = nil,
									type_identifier = "Self",
								})
							},
							returns = "String",
						})
					},
				}),
			}),
		}
    )
end

os.exit(lu.LuaUnit.run())
