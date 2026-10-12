-- Luacheck config for Minemon. Lua 5.1 / LuaJIT only; Luanti 5.17 API (core.*).
std = "luajit"
max_line_length = 120
codes = true

-- Read-only: Luanti / VoxeLibre globals and the shared minemon table.
read_globals = {
    "core",
    "vector",
    "ItemStack",
    "PcgRandom",
    "VoxelManip",
    "dump",
    "minetest",
    "minemon",
    "mcl_mobs",
    "mcl_util",
}

-- Only minemon_core may assign the global minemon table.
files["mods/minemon/minemon_core/"] = {
    globals = { "minemon" },
}

-- Busted specs.
files["tests/unit/"] = {
    std = "+busted",
}
