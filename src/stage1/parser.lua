local success, lpeg = pcall(require, "lpeg")
lpeg = success and lpeg or require"lulpeg":register(not _ENV and _G)

local re = require('re')

local pretty = require('luaunit').prettystr

function pprint(input, ...)
	return print(pretty(input), unpack(arg))
end

local ENTITY_KIND_COMMENT = 0
local ENTITY_KIND_NUMBER = 1
local ENTITY_KIND_SHAPE = 2
local ENTITY_KIND_FUNCTION_STUB = 3
local ENTITY_KIND_FUNCTION = 4
local ENTITY_KIND_ARGUMENT = 5

local EntityKind = {
	is_inst = function(candidate)
		return candidate._entity_kind == true
	end,

	Comment = {
		_meta = {
			__call = function(self, comment)
				return {
					_entity_kind = true,
					_kind = ENTITY_KIND_COMMENT,
					value = comment,
				}
			end
		}
	},

	Number = {
		_meta = {
			__call = function(self, num)
				return {
					_entity_kind = true,
					_kind = ENTITY_KIND_NUMBER,
					value = num,
				}
			end
		}
	},

	Shape = {
		_meta = {
			__call = function(self, args)
				local identifier = args.identifier
				local composed_from = args.composed_from
				local requisite_functions = args.requisite_functions

				assert(identifier ~= nil)
				assert(composed_from ~= nil)
				assert(requisite_functions ~= nil)

				return {
					_entity_kind = true,
					_kind = ENTITY_KIND_SHAPE,
					identifier = identifier,
					composed_from = composed_from,
					requisite_functions = requisite_functions,
				}
			end
		}
	},

	FunctionStub = {
		_meta = {
			__call = function(self, args)
				local identifier = args.identifier
				local arguments = args.arguments
				local returns = args.returns

				assert(identifier ~= nil)
				assert(arguments ~= nil)
				assert(returns ~= nil)

				return {
					_entity_kind = true,
					_kind = ENTITY_KIND_FUNCTION_STUB,
					identifier = identifier,
					arguments = arguments,
					returns = returns,
				}
			end
		}
	},

	Argument = {
		_meta = {
			__call = function(self, args)
				local identifier = args.identifier
				local type_identifier = args.type_identifier

				return {
					_entity_kind = true,
					_kind = ENTITY_KIND_ARGUMENT,
					identifier = identifier,
					type_identifier = type_identifier,
				}
			end
		}
	},
}
setmetatable(EntityKind.Comment, EntityKind.Comment._meta)
setmetatable(EntityKind.Number, EntityKind.Number._meta)
setmetatable(EntityKind.Shape, EntityKind.Shape._meta)
setmetatable(EntityKind.FunctionStub, EntityKind.FunctionStub._meta)
setmetatable(EntityKind.Argument, EntityKind.Argument._meta)

function new_entity(args)
	assert(EntityKind.is_inst(args.kind))

	return {
		_entity = true,
		kind = args.kind,
	}
end

local Entity = {
	is_inst = function(candidate)
		return candidate._entity == true
	end,

	comment_from_grammar = function(parsed, line_no)
		local line_no = line_no == nil and 1 or line_no

		return new_entity({
			kind = EntityKind.Comment(parsed[2]),
		})
	end,

	number_from_grammar = function(parsed, line_no)
		local line_no = line_no == nil and 1 or line_no

		return new_entity({
			kind = EntityKind.Number(parsed[2]),
		})
	end,

	Kind = EntityKind,

	_meta = {
		__call = function(_, args)
			return new_entity(args)
		end
	},
}
setmetatable(Entity, Entity._meta)

function strip_underscores(it)
	return it:gsub("_", "")
end

local WHEREIS = lpeg.Cp()
local P_NEWLINE = lpeg.S("\r\n")
local P_NB_WHITESPACE = lpeg.S(" \t")
local P_WHITESPACE = P_NEWLINE + P_NB_WHITESPACE
local P_INTEGER = lpeg.R("09") ^ 1
local P_NUMBER = re.compile([[
	-- there is no rule about where or when underscores are valid. 1_2_3 is
	-- totally legit
	[0-9_]+
	(
		[\.]^-1
		[0-9_]+
	)?
]]) - re.compile([[
	-- however, multiple dots are never allowed in a number, so we'll use this
	-- negative match group to match anything with extraneous dots
	[0-9_]+
	[.]^-1
	[0-9_]+
	[.]+
]])
local P_ESCAPE = lpeg.P('\\')
local P_COMMENT_DELIM = lpeg.P('--')
local P_COMMENT_BEGIN = (P_COMMENT_DELIM - (P_ESCAPE * P_COMMENT_DELIM)) * P_WHITESPACE
local P_DOCSTRING_DELIM = lpeg.P('---')
local P_SHAPE_DELIM = lpeg.P('=>')
local P_SUMSHAPE_DELIM = lpeg.P('~>')
local P_FN_DEF_DELIM = lpeg.P('::')
local P_FN_CHUNK_DELIM = lpeg.P('->')
-- an identifier is anything legal that doesn't fit into any other category.
-- you're a jerk if you do it (unless, oh future visitor, emojis become the
-- native language of some culture, in which case the simulation has clearly
-- gone wrong, but like, go for it), but technically emojis are totally valid
-- shape/sumshape/function/variable names
local P_IDENTIFIER = lpeg.P(
	1 -
	P_WHITESPACE -
	P_ESCAPE -
	P_COMMENT_DELIM -
	P_DOCSTRING_DELIM -
	P_SHAPE_DELIM -
	P_SUMSHAPE_DELIM -
	P_FN_CHUNK_DELIM -
	P_FN_DEF_DELIM -
	P_NUMBER
)
local CG_CONTENTS_TO_EOL = lpeg.Cg((1 - P_NEWLINE) ^ 0)
local CG_INTEGERS_TO_WHITESPACE = lpeg.Cg((P_INTEGER - P_WHITESPACE) ^ 0)
local CF_COMMENT = lpeg.Ct(
	WHEREIS * P_COMMENT_BEGIN * CG_CONTENTS_TO_EOL ^ -1 * WHEREIS
)
local CF_NUMBER = lpeg.Ct(WHEREIS * (lpeg.Cg(P_NUMBER) / strip_underscores) * WHEREIS)
local CF_SHAPE = lpeg.Ct(
	WHEREIS *
	lpeg.Cg(P_IDENTIFIER ^ 1) *
	WHEREIS *
	(P_WHITESPACE ^ 1) *
	P_SHAPE_DELIM *
	WHEREIS
)

local COMMENT, NUMBER, SHAPE, NODE =
	lpeg.V("COMMENT"),
	lpeg.V("NUMBER"),
	lpeg.V("SHAPE"),
	lpeg.V("NODE")
local GLUUMY_GRAMMAR = lpeg.P{
	"GLUUMY",
	GLUUMY = lpeg.Ct(NODE ^ 0),
	NODE = COMMENT + NUMBER + SHAPE + P_WHITESPACE,
	COMMENT = CF_COMMENT / Entity.comment_from_grammar,
	NUMBER = CF_NUMBER / Entity.number_from_grammar,
	SHAPE = CF_SHAPE,
}

function parse_string(input)
	return GLUUMY_GRAMMAR:match(input)
end

return {
	Entity = Entity,
	parse_string = parse_string,
}
