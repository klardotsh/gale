return {
	-- the slop bin: mostly single- or few-character operators here, plus a few
	-- primitive types that aren't keywords themselves
	COMMENT = 'COMMENT',
	DOCSTRING = 'DOCSTRING',
	EQL = 'EQL',
	PIPE_SHORT = 'PIPE_SHORT',
	PIPE_LONG = 'PIPE_LONG',
	LCBR = 'LCBR',
	RCBR = 'RCBR',
	INDENT = 'INDENT',
	SEMICOLON = 'SEMICOLON',
	COLON = 'COLON',
	INT = 'INT',
	DOT = 'DOT',
	DOTDOT = 'DOTDOT',
	DOTDOTDOT = 'DOTDOTDOT',
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
	SLASH = 'SLASH',

	-- reserved keywords
	TRUE = 'TRUE',
	FALSE = 'FALSE',

	-- everything else
	IDENTIFIER = 'IDENTIFIER',
	STRING = 'STRING',
}

