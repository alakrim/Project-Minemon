-- Pure rules for Dread variants (T-30, D-031): the spawn roll, the level bump, the nametag, the reward counts and the
-- hunting range. Must not touch `core` (see docs/CONVENTIONS.md), so busted can test it without Luanti. The glue is in
-- init.lua (the spawn), dread_fx.lua (the look), runtime.lua and wild_brain.lua (behaviour) and minemon_dread (rewards,
-- dawn, sting).
--
-- A Dread creature is a rare corrupted wild creature that walks only at night. Its odds rise with the distance from
-- the world origin, and it is never spawned inside a Sanctuary ward.

local M = {}

M.CHANCE_NEAR = 1 / 40 -- chance of a Dread spawn near the origin
M.CHANCE_FAR = 1 / 12 -- chance at FAR_DISTANCE nodes and beyond
M.FAR_DISTANCE = 1500 -- nodes from the origin (xz) at which CHANCE_FAR is reached
M.NIGHT_LO = 0.23 -- time of day below this is night (VoxeLibre time of day, 0..1)
M.NIGHT_HI = 0.77 -- time of day above this is night
M.LEVEL_BUMP_MIN = 5 -- levels added to the normal wild level, inclusive
M.LEVEL_BUMP_MAX = 12
M.LEVEL_CAP = 100
M.HURT_PITCH = 0.6 -- sound pitch of a Dread creature's hurt cry (the same sound as a normal one, lower)
M.HUNT_RANGE = 20 -- nodes: a Dread creature hunts the nearest player or owned creature this close
M.STING_RANGE = 16 -- nodes: the first time a player comes this close at night, the sting plays once
M.SHARD_MIN = 1 -- Dread Shards dropped by a defeated Dread creature, inclusive
M.SHARD_MAX = 2
M.DREAD_CAUGHT_BOND = 20 -- bond of a captured Dread creature (a normal catch starts at 70)
M.NAME_PREFIX = "Dread "
M.NAMETAG_COLOUR = "#B0102A" -- deep red for the nametag of a wild Dread creature

-- True when the time of day is night for Dread purposes (below NIGHT_LO or above NIGHT_HI).
function M.is_night(timeofday)
	return timeofday < M.NIGHT_LO or timeofday > M.NIGHT_HI
end

-- The chance of a Dread spawn at a horizontal distance from the origin, at a time of day. Zero by day.
-- Linear from CHANCE_NEAR at the origin to CHANCE_FAR at FAR_DISTANCE and beyond.
function M.chance(distance, timeofday)
	if not M.is_night(timeofday) then
		return 0
	end
	local d = math.max(0, math.min(tonumber(distance) or 0, M.FAR_DISTANCE))
	return M.CHANCE_NEAR + (M.CHANCE_FAR - M.CHANCE_NEAR) * d / M.FAR_DISTANCE
end

-- The spawn roll. in_ward (a Sanctuary ward) refuses it outright. rng is a minemon.rng (float()). Returns true when the
-- spawn is Dread. The roll always draws one float when the chance is not zero, so the same seed gives the same result.
function M.roll(distance, timeofday, in_ward, rng)
	if in_ward == true then
		return false
	end
	local p = M.chance(distance, timeofday)
	if p <= 0 then
		return false
	end
	return rng:float() < p
end

-- The level of a Dread creature: the normal wild level plus LEVEL_BUMP_MIN..LEVEL_BUMP_MAX, capped at LEVEL_CAP.
function M.dread_level(base_level, rng)
	local bump = rng:int(M.LEVEL_BUMP_MIN, M.LEVEL_BUMP_MAX)
	return math.min(M.LEVEL_CAP, math.floor(base_level) + bump)
end

-- The nametag: "Dread Rattata Lv 14" for a Dread creature, the normal text otherwise.
function M.nametag(base_text, dread)
	if dread == true then
		return M.NAME_PREFIX .. base_text
	end
	return base_text
end

-- How many Dread Shards a defeated Dread creature drops, 1 or 2.
function M.shard_count(rng)
	return rng:int(M.SHARD_MIN, M.SHARD_MAX)
end

-- True when a player at distance d sees a Dread creature for the first time at night (the sting range).
function M.in_sting_range(distance, timeofday)
	return M.is_night(timeofday) and tonumber(distance) ~= nil and distance <= M.STING_RANGE
end

return M
