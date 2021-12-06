local symbols = require('symbols')

function ast_parse_stream(stream)
	local tree = {}
	local cur_seq = {}
	local cur_seq_is_ast_until_idx = 1
	local cur_seq_is_done_until_idx = 1
	local ok, next = coroutine.resume(stream)

	function end_node()
		assert(
			cur_seq_is_ast_until_idx == (#cur_seq + 1),
			'sequence still includes non-AST components while being ended'
		)

		tree[#tree + 1] = cur_seq
		cur_seq = {}
		cur_seq_is_ast_until_idx = 1
		cur_seq_is_done_until_idx = 1
	end

	while ok and next do
		--[[
		I've probably already fucked up by going down this length-based
		approach with a single sequence iterable to populate - I'm gonna have
		to deal with nested, potentially anonymous, values later, which are
		their own tree branches, which I don't think this pattern is gonna be
		especially great at handling. I blame coding on a plane after eating
		basically nothing today :)

		-- JK 26 Nov 2021
		]]

		if #cur_seq == 0 then
			if next.kind == symbols.IDENTIFIER then
				-- on its own an identifier basically means nothing, so we'll
				-- gather more context on the next iteration
				cur_seq[1] = next
			end
		end

		if #cur_seq == 1 then
			if cur_seq[1].kind == symbols.IDENTIFIER then
				if next.kind == symbols.SPACES then
					-- explicitly do nothing, spaces are ignored
				elseif next.kind == symbols.EQUAL then
					cur_seq[1] = {
						kind = ast.node_kinds.LET_EQ,
						let_name = cur_seq[1].contents,
					}
					cur_seq_is_ast_until_idx = cur_seq_is_ast_until_idx + 1
				end
			end
		end

		ok, next = coroutine.resume(stream)
	end

	return tree
end

return {
	parse_stream = ast_parse_stream,

	node_kinds = {
		LET_EQ = 'LET_EQ',
		PRIMITIVE = 'PRIMITIVE',
	},

	prim_types = {
		STRING = 'STRING',
	},
}
