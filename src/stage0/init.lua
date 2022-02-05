-- gluumy stage0 compiler: duct tape o'plenty
--
-- welcome to the shitshow. this is a quick and dirty, half-featured-at-best
-- gluumy compiler usable only to bootstrap the real compiler (in extremely
-- unoptimal form, at that). it must never have dependencies a base
-- implementation of PUC Lua 5.1 doesn't provide on a Linux, FreeBSD, or
-- OpenBSD system (though it'd be nice for this bootstrapper to be able to run
-- anywhere, of course)

local READ_NEXT_LINE = '*line'

local SYMBOLS = require('symbols')
local lex = require('lex')

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
	SLASH = string.byte('/'),
	BSLSH = string.byte('\\'),
	LPRN = string.byte('('),
	RPRN = string.byte(')'),
	N0 = string.byte('0'),
	N1 = string.byte('1'),
	N2 = string.byte('2'),
	N3 = string.byte('3'),
	N4 = string.byte('4'),
	N5 = string.byte('5'),
	N6 = string.byte('6'),
	N7 = string.byte('7'),
	N8 = string.byte('8'),
	N9 = string.byte('9'),
}

local THINGS = {
	IMPORT = 'IMPORT',
}

function main()
	local args
	local entrypoint

	args = _G['arg']
	if not args then
		die("no _G for args, are we running under standalone Lua?")
	end

	entrypoint = io.open(args[1])

	if not entrypoint then
		die(string.format("could not open file %s for reading", args[1]))
	end

	local co = coroutine.create(lex.lex)
	local next_line = entrypoint:read(READ_NEXT_LINE)
	local ok, sym = coroutine.resume(co, entrypoint)
	local last = nil
	local last_line_no = 0
	local thing = nil

	while ok and sym do
		if not (
			-- the real compiler will care about these, stage0 does not
			sym.kind == SYMBOLS.COMMENT or
			sym.kind == SYMBOLS.DOCSTRING
		) then
			--symbol_print(sym)
			if sym.lineno > last_line_no and not (thing == nil) then
				-- dump symbol
				print_thing(thing)
				thing = nil
			end
		end

		last = sym
		last_line_no = sym.lineno
		next_line = entrypoint:read(READ_NEXT_LINE)
		ok, sym = coroutine.resume(co, next_line)
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

main()
