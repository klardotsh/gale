function pprint(it)
	local typeof = type(it)
	if typeof == 'number' then return it
	elseif typeof == 'string' then return '"' .. it .. '"'
	elseif typeof == 'nil' then return '<nil>'
	elseif typeof == 'boolean' then if it then return 'true' else return 'false' end
	elseif typeof == 'table' then
		local ret = ''

		for name, val in pairs(it) do
			ret = ret .. name .. '=' .. pprint(val) .. '; '
		end

		-- asymmetry is intentional here, sorry :)
		return string.format('{ %s}', ret)
	else
		assert(false, string.format('HARNESS ERROR(pprint): unhandled type %s', typeof))
	end
end

function eq(it, exp)
	local typeof = type(it)
	if not (typeof == type(exp)) then return false end

	if typeof == 'table' then
		local num_keys_it = 0
		local num_keys_exp = 0

		for name, val in pairs(it) do
			if not (eq(val, exp[name])) then
				return false
			end

			num_keys_it = num_keys_it + 1
		end

		for _, _ in pairs(exp) do num_keys_exp = num_keys_exp + 1 end

		return num_keys_it == num_keys_exp
	else
		return it == exp
	end
end

function expect(it)
	return {
		to = {
			equal = function(exp)
				assert(eq(it, exp), string.format(
					"\nexpected %s\ngot %s",
					pprint(exp),
					pprint(it)
				))
			end
		}
	}
end

function describe(name, block)
	print(string.format('===> [TEST] %s:', name))
	block(function(desc, iblock)
		io.stdout:write(string.format("  ---> [TEST] %s", desc))
		iblock(expect)
		io.stdout:write(string.format("\r  ---> [PASS] %s\n", desc))
	end)
	print(string.format('===> [PASS] %s', name))
end

return describe
