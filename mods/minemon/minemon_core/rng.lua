-- Seeded random source (minemon_core). Pure: no Luanti API, so busted can test it.
-- Park-Miller "minimal standard" generator (multiplier 48271, modulus 2^31 - 1).
-- Every intermediate product stays below 2^53, so plain Lua numbers give exact integers.
-- The same seed always gives the same sequence.

local M = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Rng = {}
Rng.__index = Rng

local function normalize_seed(seed)
	local s = math.floor(math.abs(tonumber(seed) or 0))
	return (s % (MODULUS - 1)) + 1
end

local function step(self)
	self._state = (self._state * MULTIPLIER) % MODULUS
	return self._state
end

-- Uniform float in (0, 1).
function Rng:float()
	return step(self) / MODULUS
end

-- Uniform integer in [a, b], both ends included.
function Rng:int(a, b)
	a = math.floor(a)
	b = math.floor(b)
	assert(b >= a, "rng:int needs a <= b")
	local span = b - a + 1
	local index = math.floor(self:float() * span)
	if index >= span then
		index = span - 1
	end
	return a + index
end

function M.new(seed)
	return setmetatable({ seed = seed, _state = normalize_seed(seed) }, Rng)
end

return M
