local lu = require('luaunit')
local bs = require('gluumy-bootstrap')

TestStackItself = {}

function TestStackItself:test_starts_with_empty_stack()
	lu.assertEquals(
		bs.Runtime.bare().stack,
		{}
	)
end

function TestStackItself:test_push()
	local rt = bs.Runtime.bare()
	rt.stack:push("something")

	lu.assertEquals(
		rt.stack,
		{ "something" }
	)
end

function TestStackItself:test_dup()
	local rt = bs.Runtime.bare()
	rt.stack:push("something")
	rt.stack:dup()

	lu.assertEquals(
		rt.stack,
		{ "something", "something" }
	)
end

function TestStackItself:test_pop()
	local rt = bs.Runtime.bare()
	rt.stack:push("something")
	rt.stack:pop()

	lu.assertEquals(rt.stack, {})
end

function TestStackItself:test_pop_underflow()
	local rt = bs.Runtime.bare()
	lu.assertErrorMsgContains(
		"stack underflow",
		function() rt.stack:pop() end
	)
end

function TestStackItself:test_peek()
	local rt = bs.Runtime.bare()
	rt.stack:push("something")

	lu.assertEquals(
		rt.stack:peek(),
		"something"
	)

	-- also assert that this operation is non-destructive
	lu.assertEquals(
		rt.stack,
		{ "something" }
	)
end

function strings_in_the_stack(rt)
	rt.stack:push("something")
	rt.stack:push("in")
	rt.stack:push("the")
	rt.stack:push("way")
	return rt
end

function TestStackItself:test_peekn()
	local rt = strings_in_the_stack(bs.Runtime.bare())
	lu.assertEquals(
		rt.stack:peekn(2),
		{ "way", "the" }
	)

	-- also assert that this operation is non-destructive
	lu.assertEquals(
		rt.stack,
		{
			"something",
			"in",
			"the",
			"way",
		}
	)
end

function TestStackItself:test_swap_top_2()
	local rt = strings_in_the_stack(bs.Runtime.bare())
	rt.stack:swap_top_2()
	lu.assertEquals(
		rt.stack,
		{ "something", "in", "way", "the" }
	)
end


os.exit(lu.LuaUnit.run())
