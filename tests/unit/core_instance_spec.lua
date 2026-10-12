-- Unit tests for mods/minemon/minemon_core/instance.lua (pure logic, no Luanti): the Dread flag (T-30, D-031) in the
-- serialize and deserialize round trip, old saves without the flag (they load as not Dread), and the Dread stat
-- multiplier (x1.25 while wild, x1.10 once owned, on hp, atk, spa and spe only).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local F = dofile(here .. "/../../mods/minemon/minemon_core/formulas.lua")
local R = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")
local INSTANCE = dofile(here .. "/../../mods/minemon/minemon_core/instance.lua")
local I = INSTANCE.create(F, {
	get_move = function()
		return { pp = 20 }
	end,
})

-- Cyndaquil (species 155): base stats from data/species.json. Only the fields instance.lua reads.
local CYNDAQUIL = {
	id = 155,
	growth_rate = "medium_fast",
	base_stats = { hp = 39, atk = 52, def = 43, spa = 60, spd = 50, spe = 65 },
	learnset = { { level = 1, move = "tackle" } },
}

local function fresh(dread)
	local inst = I.new(CYNDAQUIL, 20, R.new(12345))
	inst.dread = dread
	return inst
end

describe("instance Dread flag (T-30)", function()
	it("is false on a new instance", function()
		assert.is_false(I.new(CYNDAQUIL, 20, R.new(1)).dread)
	end)

	it("survives the serialize and deserialize round trip", function()
		local inst = fresh(true)
		local back = I.deserialize(I.serialize(inst))
		assert.is_true(back.dread)
		assert.equals(inst.level, back.level)
		assert.equals(inst.uid, back.uid)
	end)

	it("keeps a normal instance not Dread after the round trip", function()
		assert.is_false(I.deserialize(I.serialize(fresh(false))).dread)
	end)

	it("loads an old save without the field as not Dread", function()
		local old = I.serialize(fresh(false))
		old.dread = nil
		assert.is_false(I.deserialize(old).dread)
	end)

	it("treats any value other than true as not Dread", function()
		local t = I.serialize(fresh(false))
		t.dread = "yes"
		assert.is_false(I.deserialize(t).dread)
	end)
end)

describe("instance.stats with the Dread multiplier (T-30)", function()
	it("gives a normal instance the plain stats", function()
		local inst = fresh(false)
		local st = I.stats(inst, CYNDAQUIL)
		local plain = F.calc_stats(CYNDAQUIL.base_stats, inst.level, inst.ivs, inst.bond)
		assert.equals(plain.hp, st.hp)
		assert.equals(plain.atk, st.atk)
	end)

	it("multiplies hp, atk, spa and spe by 1.25 while wild", function()
		local inst = fresh(true)
		local plain = F.calc_stats(CYNDAQUIL.base_stats, inst.level, inst.ivs, inst.bond)
		local st = I.stats(inst, CYNDAQUIL)
		assert.equals(math.floor(plain.hp * 1.25), st.hp)
		assert.equals(math.floor(plain.atk * 1.25), st.atk)
		assert.equals(math.floor(plain.spa * 1.25), st.spa)
		assert.equals(math.floor(plain.spe * 1.25), st.spe)
	end)

	it("leaves def and spd alone", function()
		local inst = fresh(true)
		local plain = F.calc_stats(CYNDAQUIL.base_stats, inst.level, inst.ivs, inst.bond)
		local st = I.stats(inst, CYNDAQUIL)
		assert.equals(plain.def, st.def)
		assert.equals(plain.spd, st.spd)
	end)

	it("uses x1.10 once the creature has an owner", function()
		local inst = fresh(true)
		inst.owner = "Tester"
		local plain = F.calc_stats(CYNDAQUIL.base_stats, inst.level, inst.ivs, inst.bond)
		local st = I.stats(inst, CYNDAQUIL)
		assert.equals(math.floor(plain.hp * 1.10), st.hp)
		assert.equals(math.floor(plain.atk * 1.10), st.atk)
	end)

	it("keeps the constants of the design", function()
		assert.equals(1.25, INSTANCE.DREAD_MULT_WILD)
		assert.equals(1.10, INSTANCE.DREAD_MULT_OWNED)
	end)
end)
