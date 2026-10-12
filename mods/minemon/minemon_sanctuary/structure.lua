-- minemon_sanctuary: the shrine itself (T-28, D-030). Glue: it builds the nodes with code (no schematic file).
-- Layout, from the floor centre F = (x, y0, z), with y0 the floor node:
--   floor      9 x 9 stonebrick at y0, cleared air above it up to y0 + 8 (an open roof: the sky stays)
--   pillars    4 stonebrick columns at the corners, y0 + 1 .. y0 + 4, each topped by a lantern at y0 + 5
--   frame      stonebrick beams along the edges at y0 + 4, between the pillars
--   altar      the centre, at y0 + 1 (the sanctuary centre); its air above is the respawn point
--   PC         west side, at (x - 2, y0 + 1, z); the keeper's counter on the east side, at (x + 2, y0 + 1, z)
-- Ground: the search reads the real nodes (core.get_node_or_nil), never the mapgen estimate, so a world that was
-- changed by players or by another mod is searched as it is. A shrine is never built over water, air or an
-- unloaded node. When no ground is usable, foundation() builds its own stone support (a pillar, or a 3 x 3 platform).
-- Pure: nothing here reads the world except core.get_node_or_nil, core.set_node, core.registered_nodes and mcl_spawn's
-- world spawn.
-- luacheck: read_globals core mcl_spawn

local M = {}

local NODE = {
	altar = "minemon_sanctuary:altar",
	pc = "minemon_sanctuary:pc",
	counter = "minemon_sanctuary:counter",
	lantern = "minemon_sanctuary:lantern",
	floor = "mcl_core:stonebrick",
}
M.NODE = NODE
local FOUNDATION = "mcl_core:stone" -- the plain stone of the foundation (pillar or platform)

local HALF = 4 -- the floor is 9 x 9: offsets -4 .. 4
local PILLAR = 3 -- the corner pillars stand at offsets +-3
local ROOF_CLEAR = 8 -- air is cleared up to y0 + ROOF_CLEAR
local BEAM_Y = 4 -- frame beams at y0 + 4 (the top of the pillars)
local LANTERN_Y = 5 -- the corner lanterns at y0 + 5

-- Places the sanctuary with its floor centre at floor_pos (the floor node). Returns the altar position (the centre),
-- or nil when the position is unusable. The caller registers the centre.
function M.place(floor_pos)
	if floor_pos == nil then
		return nil
	end
	local x, y0, z = floor_pos.x, floor_pos.y, floor_pos.z
	-- Clear the volume first, so nothing of the old terrain is left in the way.
	for dx = -HALF, HALF do
		for dz = -HALF, HALF do
			core.set_node({ x = x + dx, y = y0, z = z + dz }, { name = NODE.floor })
			for dy = 1, ROOF_CLEAR do
				core.set_node({ x = x + dx, y = y0 + dy, z = z + dz }, { name = "air" })
			end
		end
	end
	-- Frame beams along the four edges, corners excluded (the pillars stand there).
	for d = -PILLAR + 1, PILLAR - 1 do
		core.set_node({ x = x + d, y = y0 + BEAM_Y, z = z - PILLAR }, { name = NODE.floor })
		core.set_node({ x = x + d, y = y0 + BEAM_Y, z = z + PILLAR }, { name = NODE.floor })
		core.set_node({ x = x - PILLAR, y = y0 + BEAM_Y, z = z + d }, { name = NODE.floor })
		core.set_node({ x = x + PILLAR, y = y0 + BEAM_Y, z = z + d }, { name = NODE.floor })
	end
	-- Corner pillars and their lanterns.
	for _, sx in ipairs({ -PILLAR, PILLAR }) do
		for _, sz in ipairs({ -PILLAR, PILLAR }) do
			for dy = 1, BEAM_Y do
				core.set_node({ x = x + sx, y = y0 + dy, z = z + sz }, { name = NODE.floor })
			end
			core.set_node({ x = x + sx, y = y0 + LANTERN_Y, z = z + sz }, { name = NODE.lantern })
		end
	end
	-- The altar at the centre, the PC and the counter on the sides.
	local altar = { x = x, y = y0 + 1, z = z }
	core.set_node(altar, { name = NODE.altar })
	core.set_node({ x = x - 2, y = y0 + 1, z = z }, { name = NODE.pc })
	core.set_node({ x = x + 2, y = y0 + 1, z = z }, { name = NODE.counter })
	return altar
end

-- Ground ------------------------------------------------------------------------------------------------------------

-- The search radii, in nodes, from the world spawn. Attempt 0 searches the first three rings; each later attempt
-- widens the search by one ring, up to the widest one. Attempts from LAST_RESORT_ATTEMPT on fall back to foundation().
M.RADII = { 8, 12, 16, 24, 32, 48 }
M.LAST_RESORT_ATTEMPT = 6

-- Pure: the radii searched by a placement attempt (0 based), nearest first.
function M.radii_for(attempt)
	local reach = math.min(attempt + 3, #M.RADII)
	local out = {}
	for i = 1, reach do
		out[i] = M.RADII[i]
	end
	return out
end

local SCAN_TOP = 96
local SCAN_BOTTOM = -48

local function node_at(x, y, z)
	return core.get_node_or_nil({ x = x, y = y, z = z })
end

-- A node that can carry a floor: a registered, walkable, non-liquid node that is not air.
local function is_dry_solid(node_name)
	local def = core.registered_nodes[node_name]
	return def ~= nil and (def.liquidtype or "none") == "none" and def.walkable ~= false and node_name ~= "air"
		and node_name ~= "ignore"
end

-- True when the whole 9 x 9 floor centred on (x, y0, z) stands on dry solid nodes. An unloaded node fails the check.
local function floor_ok(x, y0, z)
	for dx = -HALF, HALF do
		for dz = -HALF, HALF do
			local node = node_at(x + dx, y0, z + dz)
			if node == nil or not is_dry_solid(node.name) then
				return false
			end
		end
	end
	return true
end

-- The highest floor in the column (x, z): a dry solid node with air above it, whose 9 x 9 floor passes floor_ok.
-- Scans the loaded nodes from SCAN_TOP down. Nil when the column has none (or none is loaded).
local function column_floor(x, z)
	local above = node_at(x, SCAN_TOP + 1, z)
	for y = SCAN_TOP, SCAN_BOTTOM, -1 do
		local node = node_at(x, y, z)
		if node ~= nil and above ~= nil and above.name == "air" and is_dry_solid(node.name) and floor_ok(x, y, z) then
			return { x = x, y = y, z = z }
		end
		above = node
	end
	return nil
end

-- The floor node for a sanctuary near the point (cx, cz), or nil. The rings of the given radii are searched nearest
-- first, then the centre column. A floor is returned only when it passes floor_ok: an unchecked floor could build over
-- water or air.
function M.find_ground(cx, cz, ring_points, radii)
	for _, radius in ipairs(radii) do
		for _, p in ipairs(ring_points(cx, cz, radius, 8)) do
			local floor = column_floor(p.x, p.z)
			if floor ~= nil then
				return floor
			end
		end
	end
	return column_floor(math.floor(cx + 0.5), math.floor(cz + 0.5))
end

-- Last resort: a stone foundation under the floor node, so the shrine stands on solid ground it has made itself.
-- Walks down the centre column from the node under the floor, at most max_depth nodes. On solid ground, a 3 x 3 stone
-- pillar fills the nodes between that ground and the floor. With no ground in reach, a 3 x 3 stone platform is laid
-- under the floor instead. Returns "ground" (the floor was already supported, nothing is built), "pillar" or
-- "platform"; nil when the nodes involved are not loaded yet (nothing is built, the caller retries later).
function M.foundation(floor_pos, max_depth)
	local x, y0, z = floor_pos.x, floor_pos.y, floor_pos.z
	local top = y0 - 1
	-- Every node of the floor must be loaded, or the floor would be placed into nothing.
	for dx = -HALF, HALF do
		for dz = -HALF, HALF do
			if node_at(x + dx, y0, z + dz) == nil then
				return nil
			end
		end
	end
	local ground = nil
	for y = top, top - max_depth + 1, -1 do
		local node = node_at(x, y, z)
		if node == nil then
			return nil
		end
		if is_dry_solid(node.name) then
			ground = y
			break
		end
	end
	if ground == top then
		return "ground"
	end
	local from = ground ~= nil and ground + 1 or top
	for y = from, top do
		for dx = -1, 1 do
			for dz = -1, 1 do
				if node_at(x + dx, y, z + dz) == nil then
					return nil
				end
			end
		end
	end
	for y = from, top do
		for dx = -1, 1 do
			for dz = -1, 1 do
				core.set_node({ x = x + dx, y = y, z = z + dz }, { name = FOUNDATION })
			end
		end
	end
	return ground ~= nil and "pillar" or "platform"
end

-- The world spawn point (the static spawn, mcl_spawn's world spawn, or the origin).
function M.world_spawn()
	if mcl_spawn and mcl_spawn.get_world_spawn_pos then
		local ok, pos = pcall(mcl_spawn.get_world_spawn_pos)
		if ok and pos then
			return pos
		end
	end
	return { x = 0, y = 8, z = 0 }
end

return M
