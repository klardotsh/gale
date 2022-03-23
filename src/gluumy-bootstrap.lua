#!/usr/bin/env lua

-- gluumy-bootstrap: the beginning of the end of all that was ever holy
--
-- Released under your choice of either of the licenses found in the `LICENSES`
-- directory of gluumy's source tree:
--
-- * `@ThatVeryQuinn@witches.town`'s Guthrie Public License
-- * Creative Commons Zero 1.0
--
-- Whichever you choose, have fun with it, build cool stuff with it, don't
-- exploit your fellow humans or the world at large with it, and generally
-- don't be an ass within or outside of the project or anything written with
-- it.

-- cheereo: a minimal type system for pessimists
local cheereo = require('cheereo')

-- third party pure-lua dependency, currently only their prettystr function is
-- used, maybe just borrow this with copyright credit as a gluumy stdlib
-- function?
local prettystr = require('luaunit').prettystr

-- Bonjour and welcome to the shitshow. This file is pretty extensively
-- commented, but I _will_ assume you've read the README that should have
-- shipped with this copy of this file and try to avoid repeating what's
-- already been covered there. Thus, let's just dive right into implementing
-- our Forth-alike, shall we?
local Runtime = {}
function Runtime.bare()
	local runtime = {
		-- First, we'll need the number one defining feature of every Forth: a
		-- stack! In general, except when asked to store data in the "heap"
		-- (which we'll see later), gluumy uses just one stack which functions
		-- access directly: avoiding stack underruns is the type system's
		-- problem.
		stack = setmetatable({}, {
			__index = {
				__is_gluumy_stack = true,

				dup = function(self)
					table.insert(self, self[#self])
				end,

				peek = function(self)
					return self[#self]
				end,

				peekn = function(self, n)
					local vals = {}

					local idx = 0
					while idx < n do
						table.insert(vals, self[#self - idx])
						idx = idx + 1
					end

					return vals
				end,

				pop = function(self)
					if #self <= 0 then
						error("stack underflow")
					end

					local top = self[#self]
					table.remove(self, #self)
					return top
				end,

				push = function(self, value)
					table.insert(self, value)
				end,

				swap_top_2 = function(self)
					local old_last = self:pop()
					local new_last = self:pop()
					self:push(old_last)
					self:push(new_last)
				end,
			},
		}),
	}

	-- A stack on its own is cute and all, but we need ways to manipulate that
	-- stack, and in Forths, those are called words. We'll stick to that
	-- verbiage. For now, this table will remain empty: in gluumy, the word is
	-- one of a few interdependent primitives, and we have a bit of a
	-- chicken-and-egg problem: notably, that we haven't built a type system
	-- yet!
	local words = {}
	runtime.words = words
	function runtime:register_word(name, input_types, output_types, definition)
		local word = {
			__is_gluumy_word = true,
			name = name,
			input_types = input_types,
			output_types = output_types,
			definition = definition,
		}

		setmetatable(word, {
			__call = function(self, stack, input_stream)
				return self.definition(stack, input_stream)
			end
		})

		self.words[name] = self.words[name] and self.words[name] or {}
		table.insert(self.words[name], word)

		return word
	end


	setmetatable(runtime, {
	})

	return runtime
end

function Runtime.new()
	local runtime = Runtime.bare()

	runtime:register_word(
		"drop",
		{ "Infer" },
		{ },
		function(stack)
			stack:pop()
		end
	)

	runtime:register_word(
		"swap",
		{ "Infer", "Infer" },
		{ "@2", "@1" }, -- TODO: how to implement?
		function(stack)
			stack:swap_top_2()
		end
	)

	runtime:register_word(
		"dup",
		{ "Infer" },
		{ "@1" },
		function(stack)
			stack:dup()
		end
	)

	runtime:register_word(
		"+",
		{ "Number", "Number" },
		{ "Number" },
		function(stack)
			local b = stack:pop()
			local a = stack:pop()
			stack:push(a + b)
		end
	)

	runtime:register_word(
		"-",
		{ "Number", "Number" },
		{ "Number" },
		function(stack)
			local b = stack:pop()
			local a = stack:pop()
			stack:push(b - a)
		end
	)

	runtime:register_word(
		"*",
		{ "Number", "Number" },
		{ "Number" },
		function(stack)
			local b = stack:pop()
			local a = stack:pop()
			stack:push(a * b)
		end
	)

	return runtime
end


-- div and mod can fail, need to figure out composites in this type system
-- before I can model a Result

local function parse_stream(stream)
	local char = nil
	local cur_word = nil
end

return {
	Word = Word,
	Shape = Shape,
	ShapeField = ShapeField,

	Runtime = Runtime,

	parse_stream = parse_stream,
}
