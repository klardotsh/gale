-- gluumy is copyfree software with no warranty, released under the CC0-1.0
-- public-domain-esque dedication found in COPYING in gluumy's source tree, or
-- at https://creativecommons.org/publicdomain/zero/1.0/

-- gluumy stage0 compiler: duct tape o'plenty
--
-- welcome to the shitshow. this is a quick and dirty transpiler from gluumy
-- source to lua source, without type checking or any other validations. it's a
-- straight-up source rewriter, usable only to bootstrap the real compiler (in
-- extremely unoptimal form, at that). it must never have dependencies a base
-- implementation of PUC Lua 5.1 doesn't provide on a Linux, FreeBSD, or
-- OpenBSD system (though it'd be nice for this bootstrapper to be able to run
-- anywhere, of course)

local READ_NEXT_LINE = '*line'

local SYMBOLS = {
	-- the slop bin: mostly single- or few-character operators here, plus a few
	-- primitive types that aren't keywords themselves
	COMMENT = 'COMMENT',
	DOCSTRING = 'DOCSTRING',
	VAST_EMPTINESS = 'VAST_EMPTINESS', -- I politely didn't name this "WYOMING", yw
	EQL = 'EQL',
	PIPE_SHORT = 'PIPE_SHORT',
	PIPE_LONG = 'PIPE_LONG',
	LCBR = 'LCBR',
	RCBR = 'RCBR',
	INDENT = 'INDENT',
	SEMICOLON = 'SEMICOLON',
	COLON = 'COLON',
	INT = 'INT',
	FLOAT = 'FLOAT',
	DOT = 'DOT',
	EXCLAIM = 'EXCLAIM',
	NEWLINE = 'NEWLINE',
	LPRN = 'LPRN',
	RPRN = 'RPRN',
	LBRC = 'LBRC',
	RBRC = 'RBRC',
	SPACES = 'SPACES',
	ARROW = 'ARROW',
	LEFT_THICC_ARROW = 'LEFT_THICC_ARROW',
	RIGHT_THICC_ARROW = 'RIGHT_THICC_ARROW',
	HYDRA_THICC_ARROW = 'HYDRA_THICC_ARROW', -- I guess it actually only has two heads, w/e
	SQUIGGLY_ARROW = 'SQUIGGLY_ARROW',
	EQUAL = 'EQUAL',
	LT = 'LT',
	GT = 'GT',
	FFI = 'FFI',

	-- reserved keywords
	TRUE = 'TRUE',
	FALSE = 'FALSE',

	-- everything else
	IDENTIFIER = 'IDENTIFIER',
	STRING = 'STRING',
}

-- this lookup table _should_ be the most efficient method of implementing a
-- lexer if I'm understanding
-- https://web.archive.org/web/20211107021217/https://stackoverflow.com/questions/829063/how-to-iterate-individual-characters-in-lua-string/34451343
-- correctly
local CHARS = {
	SPACE = string.byte(' '),
	TAB = string.byte("\t"),
	NEWLINE = string.byte("\n"),
	PIPE = string.byte('|'),
	GT = string.byte('>'),
	LT = string.byte('<'),
	EQL = string.byte('='),
	SQUOTE = string.byte("'"),
	DQUOTE = string.byte('"'),
	LBRC = string.byte('['),
	RBRC = string.byte(']'),
	LCBR = string.byte('{'),
	RCBR = string.byte('}'),
	COLON = string.byte(':'),
	SEMICOLON = string.byte(';'),
	DOT = string.byte('.'),
	EXCLAIM = string.byte('!'),
	DASH = string.byte('-'),
	TILDE = string.byte('~'),
	EQUAL = string.byte('='),
	BSLSH = string.byte('\\'),
	LPRN = string.byte('('),
	RPRN = string.byte(')'),
}

function main()
	local args
	local entrypoint

	args = _G['arg']
	if not args then
		die("no _G for args, are we running under standalone Lua?")
	end

	--[[
	for idx, arg in ipairs(args) do
		print(idx, arg)
	end
	]]

	entrypoint = io.open(args[1])

	if not entrypoint then
		die(string.format("could not open file %s for reading", args[1]))
	end

	local lineno = 1
	local line = entrypoint:read(READ_NEXT_LINE)
	while line do
		local sym_start = 1
		local sym_done = false

		local idx = 1

		while idx <= #line do
			cur = line:byte(idx)
			next = line:byte(idx + 1)
			nextnext = line:byte(idx + 2)
			nextnextnext = line:byte(idx + 3)

			if cur == CHARS.DASH then
				if next == CHARS.DASH then
					if nextnext == CHARS.DASH then
						symbol_print(symbol(
							SYMBOLS.DOCSTRING, lineno, idx, #line,
							string.sub(line, idx + 3, #line)
						))
						idx = #line
					else
						symbol_print(symbol(
							SYMBOLS.COMMENT, lineno, idx, #line,
							string.sub(line, idx + 2, #line)
						))
						idx = #line
					end
				elseif next == CHARS.GT then
					symbol_print(symbol(SYMBOLS.ARROW, lineno, idx, idx + 2))
					idx = idx + 1
				else
					die('dash can only be followed by more dashes or >')
				end
			elseif cur == CHARS.TILDE then
				if next == CHARS.GT then
					symbol_print(symbol(SYMBOLS.SQUIGGLY_ARROW, lineno, idx, idx + 2))
					idx = idx + 1
				else
					die('tilde can only be followed by >')
				end
			elseif cur == CHARS.EQUAL then
				if next == CHARS.GT then
					symbol_print(symbol(SYMBOLS.RIGHT_THICC_ARROW, lineno, idx, idx + 2))
					idx = idx + 1
				else
					symbol_print(symbol(SYMBOLS.EQUAL, lineno, idx, idx + 1))
				end
			elseif cur == CHARS.LT then
				if next == CHARS.EQUAL then
					if nextnext == CHARS.GT then
						symbol_print(symbol(SYMBOLS.HYDRA_THICC_ARROW, lineno, idx, idx + 3))
						idx = idx + 2
					else
						symbol_print(symbol(SYMBOLS.LEFT_THICC_ARROW, lineno, idx, idx + 2))
						idx = idx + 1
					end
				else
					symbol_print(symbol(SYMBOLS.LT, lineno, idx, idx + 1))
				end
			elseif cur == CHARS.COLON then
				symbol_print(symbol(SYMBOLS.COLON, lineno, idx, idx + 1))
			elseif cur == CHARS.SEMICOLON then
				symbol_print(symbol(SYMBOLS.SEMICOLON, lineno, idx, idx + 1))
			elseif cur == CHARS.TAB then
				symbol_print(symbol(SYMBOLS.INDENT, lineno, idx, idx + 1))
			elseif cur == CHARS.SPACE then
				-- TODO merge consecutive spaces into one entity
				symbol_print(symbol(SYMBOLS.SPACES, lineno, idx, idx + 1))
			elseif cur == CHARS.DOT then
				symbol_print(symbol(SYMBOLS.DOT, lineno, idx, idx + 1))
			elseif cur == CHARS.LCBR then
				symbol_print(symbol(SYMBOLS.LCBR, lineno, idx, idx + 1))
			elseif cur == CHARS.RCBR then
				symbol_print(symbol(SYMBOLS.RCBR, lineno, idx, idx + 1))
			elseif cur == CHARS.LPRN then
				symbol_print(symbol(SYMBOLS.LPRN, lineno, idx, idx + 1))
			elseif cur == CHARS.RPRN then
				symbol_print(symbol(SYMBOLS.RPRN, lineno, idx, idx + 1))
			elseif cur == CHARS.EXCLAIM then
				if next == CHARS.DASH and nextnext == CHARS.GT then
					-- one-liner FFI reads to EOL only
					if nextnextnext then
						symbol_print(symbol(
							SYMBOLS.FFI, lineno, idx, #line,
							string.sub(line, idx + 4, #line)
						))
						idx = #line
					else
						-- look, this is really the parser's job and I'm
						-- reaching out of scope here, but that's on me for
						-- having a tricky to handle FFI syntax, whatever, it's
						-- 2021, rules are fake. since I have no interest in
						-- also parsing lua syntax (at least in the bootstrap
						-- compiler which will run over reasonably trusted
						-- inputs - the real compiler may have some better
						-- understanding of Lua), we're going to just treat it
						-- as a completely opaque blob that includes each
						-- consecutive line at the expected indentation level
						local lineno_og = lineno
						local _, indent_level_begin = line:find("\t*")
						indent_level_exp = indent_level_begin + 1

						contents = ""

						line = entrypoint:read(READ_NEXT_LINE)
						lineno = lineno + 1
						while line do
							local _, indent_level = line:find("\t*")
							if indent_level >= indent_level_exp then
								contents = contents .. string.sub(line, indent_level + 1, #line) .. "\n"
								line = entrypoint:read(READ_NEXT_LINE)
								lineno = lineno + 1
							else
								leaving_ffi = true
								break
							end
						end

						-- trim trailing newline just because it makes debug output ugly
						contents = string.sub(contents, 1, -2)

						symbol_print(symbol(SYMBOLS.FFI, lineno_og, idx, -1, contents))
					end
				else
					symbol_print(symbol(SYMBOLS.EXCLAIM, lineno, idx, idx + 1))
				end
			elseif cur == CHARS.PIPE then
				if next == CHARS.GT then
					if nextnext == CHARS.GT then
						symbol_print(symbol(SYMBOLS.PIPE_LONG, lineno, idx, idx + 3))
						idx = idx + 2
					else
						symbol_print(symbol(SYMBOLS.PIPE_SHORT, lineno, idx, idx + 2))
						idx = idx + 1
					end
				else
					die('pipe can only be followed by > or >>')
				end
			elseif cur == CHARS.DQUOTE or cur == CHARS.SQUOTE then
				local last = cur
				local string_idx = idx + 1
				local str_cur = line:byte(string_idx)
				while string_idx < #line do
					if str_cur == cur and not (last == CHARS.BSLSH) then
						symbol_print(symbol(
							SYMBOLS.STRING, lineno, idx, string_idx,
							string.sub(line, idx + 1, string_idx - 1)
						))
						idx = string_idx
						break
					else
						last = str_cur
						string_idx = string_idx + 1
						str_cur = line:byte(string_idx)

						if string_idx >= #line then
							symbol_print(symbol(
								SYMBOLS.STRING, lineno, idx, string_idx,
								string.sub(line, idx + 1, string_idx - 1)
							))
							idx = string_idx
							break
						end
					end
				end
			else
				-- everything else is assumed to be an identifier
				local ident_idx = idx + 1
				local ident_cur = line:byte(ident_idx)
				while ident_idx <= #line do
					if identifier_breaker(ident_cur) then
						symbol_print(symbol(
							SYMBOLS.IDENTIFIER, lineno, idx, ident_idx,
							string.sub(line, idx, ident_idx - 1)
						))
						idx = ident_idx - 1
						break
					else
						ident_idx = ident_idx + 1
						ident_cur = line:byte(ident_idx)

						if ident_idx > #line then
							symbol_print(symbol(
								SYMBOLS.IDENTIFIER, lineno, idx, ident_idx,
								string.sub(line, idx, ident_idx - 1)
							))
							idx = ident_idx - 1
							break
						end
					end
				end
			end

			-- sometimes we get into weird states if a file ends with an FFI
			-- block where there's no more lines to read, so just hack around
			-- those
			if not line then break end

			idx = idx + 1
		end

		if leaving_ffi then
			leaving_ffi = false
		elseif line then
			line = entrypoint:read(READ_NEXT_LINE)
			lineno = lineno + 1
		end
	end
end

function die(msg, code)
	msg = msg or "NO MESSAGE SPECIFIED, COMPILER ERROR DETECTED"
	code = code or 1
	io.stderr:write(string.format("fatal: %s\n", msg))
	io.stderr:flush()
	os.exit(code)
end

function symbol(kind, lineno, col_start, col_end, contents)
	return {
		kind = kind,
		lineno = lineno,
		col_start = col_start,
		col_end = col_end,
		contents = contents,
	}
end

function symbol_print(sym)
	print(string.format(
		"{ kind = %s; lineno = %d; cols = [%d, %d]%s }",
		sym.kind, sym.lineno, sym.col_start, sym.col_end,
		sym.contents and string.format("; contents = \"%s\"", sym.contents) or ""
	))
end

function identifier_breaker(byte)
	return byte == CHARS.SPACE or
		byte == CHARS.TAB or
		byte == CHARS.NEWLINE or
		byte == CHARS.PIPE or
		byte == CHARS.GT or
		byte == CHARS.LT or
		byte == CHARS.EQL or
		byte == CHARS.SQUOTE or
		byte == CHARS.DQUOTE or
		byte == CHARS.LBRC or
		byte == CHARS.RBRC or
		byte == CHARS.LCBR or
		byte == CHARS.RCBR or
		byte == CHARS.COLON or
		byte == CHARS.SEMICOLON or
		byte == CHARS.DOT or
		byte == CHARS.EXCLAIM or
		byte == CHARS.DASH or
		byte == CHARS.TILDE or
		byte == CHARS.EQUAL or
		byte == CHARS.LPRN or
		byte == CHARS.RPRN
end

main()
