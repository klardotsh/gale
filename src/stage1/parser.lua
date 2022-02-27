local success, lpeg = pcall(require, "lpeg")
lpeg = success and lpeg or require"lulpeg":register(not _ENV and _G)

local pretty = require('luaunit').prettystr

function pprint(input, ...)
	return print(pretty(input), unpack(arg))
end

local ENTITY_KIND_COMMENT = 0

local PointInSource = {
	is_inst = function(candidate)
		return candidate._point_in_source == true
	end,

	_meta = {
		__call = function(self, args)
			return {
				_point_in_source = true,
				line = args.line,
				column = args.column,
			}
		end
	}
}
setmetatable(PointInSource, PointInSource._meta)

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
	}
}
setmetatable(EntityKind.Comment, EntityKind.Comment._meta)

function new_entity(args)
	assert(EntityKind.is_inst(args.kind))

	return {
		_entity = true,
		start = args.start,
		["end"] = args["end"],
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
			start = PointInSource({
				line = line_no,
				column = parsed[1],
			}),
			["end"] = PointInSource({
				line = line_no,
				column = parsed[3],
			}),
			kind = EntityKind.Comment(parsed[2]),
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

local WHEREIS = lpeg.Cp()
local P_NEWLINE = lpeg.S("\r\n") ^ 1
local P_WHITESPACE = lpeg.S(" \t\r\n") ^ 0
local P_INTEGER = lpeg.R("09") ^ 1
local P_ESCAPE = lpeg.P('\\')
local P_COMMENT_DELIM = lpeg.P('--')
local P_COMMENT_BEGIN = (P_COMMENT_DELIM - (P_ESCAPE * P_COMMENT_DELIM)) * P_WHITESPACE
local P_DOCSTRING_DELIM = lpeg.P('---')
local P_SHAPE_DELIM = lpeg.P('=>')
local P_SUMSHAPE_DELIM = lpeg.P('~>')
local P_FN_DEF_DELIM = lpeg.P('::')
local P_FN_CHUNK_DELIM = lpeg.P('->')
local CG_CONTENTS_TO_EOL = lpeg.Cg((1 - P_NEWLINE) ^ 0)
local CF_COMMENT = lpeg.Ct(
	(
		WHEREIS *
		P_COMMENT_BEGIN *
		CG_CONTENTS_TO_EOL
	)
	^ 0
	* WHEREIS
) / Entity.comment_from_grammar

function parse_string(input)
	return CF_COMMENT:match(input)
end

return {
	Entity = Entity,
	PointInSource = PointInSource,
	parse_string = parse_string,
}
