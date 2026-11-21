--!strict
-- Pocket Weather island terrain (edit-time generator; run once, result is saved in the place).
-- ServerStorage.WorldGen.TerrainGen.build() rewrites the voxels in the island region:
--   * main island: flat meadow (y = 1) over the whole gameplay area (fronts and jars use
--     x, z in +-95; plot bridges start at z = 150), stepped cliffs and mountains to the north,
--     terraces east and west, a canyon with a pond under the waterfall, a river to the sea,
--     cobblestone paths and a paved plaza in the middle (Weather Tower goes on it)
--   * the ocean (sea level SEA_Y), the spawn island to the east, a ring of small islets and a
--     line of stepping stones to a secret islet
-- The old terrain is backed up in ServerStorage.MapBackup_v1.Terrain_before_rebuild.
local Workspace = game:GetService("Workspace")

local G = {}

G.SEA_Y = -12
G.PLAIN_Y = 1
G.SPAWN_ISLAND = Vector3.new(250, 1, 0)
G.SECRET_ISLET = Vector3.new(-282, 1, 44)
G.POND = Vector3.new(-40, 0, -146)
G.WATERFALL_X = -40
G.TIER1_Z = -128
G.TIER2_Z = -160
G.STEPPING = {} :: { Vector3 }

local CELL = 4
local X0, X1 = -320, 320
local Z0, Z1 = -340, 320
local Y0, Y1 = -48, 112
local SEED = 7.31

local M = Enum.Material

local function noise(x: number, z: number, s: number, k: number): number
	return math.noise(x / s, z / s, SEED + k)
end
local function smooth(a: number, b: number, t: number): number
	local u = math.clamp((t - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end

-- stepping stones from the west village shore to the secret islet
do
	local from, to = Vector3.new(-176, 1, 30), G.SECRET_ISLET
	local n = 9
	for i = 1, n do
		local p = from:Lerp(to, i / (n + 1))
		table.insert(G.STEPPING, p + Vector3.new(0, 0, math.sin(i * 1.3) * 5))
	end
end

type Islet = { x: number, z: number, r: number, h: number, flat: boolean? }
local ISLETS: { Islet } = {
	{ x = G.SPAWN_ISLAND.X, z = G.SPAWN_ISLAND.Z, r = 34, h = G.PLAIN_Y, flat = true },
	{ x = G.SECRET_ISLET.X, z = G.SECRET_ISLET.Z, r = 16, h = G.PLAIN_Y, flat = true },
	{ x = 228, z = -150, r = 26, h = 12 },
	{ x = 262, z = 140, r = 20, h = 8 },
	{ x = -250, z = -110, r = 30, h = 16 },
	{ x = -236, z = 176, r = 22, h = 9 },
	{ x = 120, z = 262, r = 18, h = 6 },
	{ x = -120, z = 268, r = 16, h = 5 },
	{ x = 190, z = -286, r = 22, h = 14 },
	{ x = -190, z = -296, r = 20, h = 12 },
}
G.ISLETS = ISLETS

-- is (x, z) on a path? returns "plaza" | "path" | nil
local function pathAt(x: number, z: number): string?
	local d = math.sqrt(x * x + z * z)
	if d <= 38 then
		return "plaza"
	end
	local w = 5
	if math.abs(z) <= w and x > 0 and x < 175 then
		return "path" -- east: to the spawn bridge
	end
	if math.abs(x) <= w and z > 0 and z < 142 then
		return "path" -- south: to the plot bridges
	end
	if math.abs(x) <= w and z < 0 and z > -112 then
		return "path" -- north: to the river and waterfall
	end
	if math.abs(z) <= w and x < 0 and x > -150 then
		return "path" -- west: to the village
	end
	if z >= 136 and z <= 146 and math.abs(x) <= 112 then
		return "path" -- south promenade along the plot bridges
	end
	return nil
end
G.pathAt = pathAt

-- river: from the pond (canyon) south to z = -116, then east to the sea
local function riverAt(x: number, z: number): boolean
	if x >= -48 and x <= -32 and z <= -112 and z >= -134 then
		return true
	end
	if z >= -122 and z <= -110 and x >= -48 and x <= 190 then
		return true
	end
	return false
end
G.riverAt = riverAt

-- land height and top material before the shore falloff
local function landAt(x: number, z: number): (number, any)
	local h = G.PLAIN_Y
	local mat = M.Grass
	local ax = math.abs(x)
	-- east / west terraces (keep the east valley to the spawn bridge open)
	local flankEdge = 122 + noise(x, z, 38, 1) * 8
	if ax > flankEdge and not (x > 0 and math.abs(z) < 16) and z < 128 then
		h = 10 + noise(x, z, 45, 2) * 3
		local plateauEdge = 150 + noise(x, z, 30, 3) * 6
		if ax > plateauEdge then
			h = 20 + noise(x, z, 50, 4) * 4
		end
	end
	-- north: tier 1, tier 2, mountains
	local e1 = G.TIER1_Z + noise(x, z, 40, 5) * 7
	local e2 = G.TIER2_Z + noise(x, z, 34, 6) * 6
	local canyon = x >= -54 and x <= -26
	if z < e1 and not canyon then
		h = math.max(h, 16 + noise(x, z, 30, 7) * 2)
	end
	if z < e2 then
		h = math.max(h, 34 + noise(x, z, 30, 8) * 3)
		local m = -190 + noise(x, z, 50, 9) * 10
		if z < m then
			local ridge = 1 - math.abs(noise(x, z, 70, 10)) * 1.6
			local rise = math.clamp((m - z) / 70, 0, 1)
			h = math.max(h, 34 + rise * (28 + math.max(0, ridge) * 46) + noise(x, z, 18, 11) * 4)
		end
	end
	if canyon and z < e1 and z >= e2 then
		h = G.PLAIN_Y -- canyon floor: the waterfall drops into it
	end
	-- material
	local p = pathAt(x, z)
	if h <= G.PLAIN_Y + 0.5 and p then
		mat = if p == "plaza" then M.Pavement else M.Cobblestone
	end
	if h > 74 then
		mat = M.Snow
	end
	return h, mat
end

local function shoreT(x: number, z: number): number
	local az = if z < 0 then 262 else 175
	local ax = 178
	local s = ((math.abs(x) / ax) ^ 4 + (math.abs(z) / az) ^ 4) ^ 0.25 + noise(x, z, 60, 12) * 0.05
	local t = smooth(0.93, 1.0, s)
	-- straight-ish south shore at the plot bridges (z = 150)
	if z > 0 and math.abs(x) < 125 then
		t = math.max(t, smooth(150, 160, z))
	end
	return t
end

local function isletHeight(x: number, z: number): (number?, boolean)
	local best: number? = nil
	local flat = false
	for _, il in ISLETS do
		local d = math.sqrt((x - il.x) ^ 2 + (z - il.z) ^ 2)
		if d < il.r then
			local h: number
			if il.flat then
				h = if d < il.r - 10 then il.h else il.h + (G.SEA_Y - 12 - il.h) * smooth(il.r - 10, il.r, d)
			else
				local k = d / il.r
				h = il.h * (1 - k * k) + noise(x, z, 12, 13) * 2 + (G.SEA_Y - 10) * k * k
			end
			if not best or h > best then
				best = h
				flat = il.flat == true
			end
		end
	end
	for _, s in G.STEPPING do
		local d = math.sqrt((x - s.X) ^ 2 + (z - s.Z) ^ 2)
		if d < 5 then
			local h = G.PLAIN_Y - smooth(3, 5, d) * 30
			if not best or h > best then
				best = h
				flat = true
			end
		end
	end
	return best, flat
end

-- final surface: height, top material, water level (or nil), carve cave?
local function columnAt(x: number, z: number): (number, any, number?)
	local h, mat = landAt(x, z)
	local t = shoreT(x, z)
	local water: number? = nil
	if t > 0 then
		local seabed = -34 + noise(x, z, 40, 14) * 6
		h = h + (seabed - h) * t
		if t > 0.15 then
			local beach = noise(x, z, 55, 15) > 0.25 and z > -150
			mat = if beach then M.Sand else M.Rock
		end
	end
	local ih, flatIslet = isletHeight(x, z)
	if ih and ih > h then
		h = ih
		mat = if flatIslet then M.Grass else (if ih > G.SEA_Y + 3 then M.Grass else M.Sand)
		if ih < G.SEA_Y + 3 then
			mat = M.Sand
		end
	end
	if h < G.SEA_Y + 1 then
		mat = M.Sand
	end
	-- pond in the canyon and the river
	local dp = math.sqrt((x - G.POND.X) ^ 2 + (z - G.POND.Z) ^ 2)
	if dp < 15 then
		h = math.min(h, -6 + smooth(9, 15, dp) * 6)
		mat = M.Sand
		water = 0
	elseif riverAt(x, z) and h <= G.PLAIN_Y + 0.5 then
		h = -5
		mat = M.Ground
		water = 0
	end
	return h, mat, water
end
G.columnAt = columnAt

function G.surfaceY(x: number, z: number): number
	local h = columnAt(x, z)
	return h
end

-- cave behind the waterfall: hollow box in the tier-2 cliff
local CAVE_MIN = Vector3.new(G.WATERFALL_X - 7, G.PLAIN_Y, G.TIER2_Z - 26)
local CAVE_MAX = Vector3.new(G.WATERFALL_X + 7, G.PLAIN_Y + 12, G.TIER2_Z + 2)
G.CAVE_CENTER = (CAVE_MIN + CAVE_MAX) / 2

function G.build(log: ((string) -> ())?)
	local T = Workspace.Terrain
	local nx = (X1 - X0) // CELL
	local nz = (Z1 - Z0) // CELL
	local ny = (Y1 - Y0) // CELL
	-- 1. height field
	local H: { { number } } = {}
	local MAT: { { any } } = {}
	local W: { { number | false } } = {}
	for i = 1, nx do
		H[i], MAT[i], W[i] = {}, {}, {}
		local x = X0 + (i - 0.5) * CELL
		for k = 1, nz do
			local z = Z0 + (k - 0.5) * CELL
			local h, m, w = columnAt(x, z)
			H[i][k], MAT[i][k], W[i][k] = h, m, w or false
		end
		if i % 20 == 0 then
			task.wait()
		end
	end
	-- 2. steep tops become rock
	for i = 2, nx - 1 do
		for k = 2, nz - 1 do
			local h = H[i][k]
			local dmax = math.max(math.abs(h - H[i - 1][k]), math.abs(h - H[i + 1][k]), math.abs(h - H[i][k - 1]), math.abs(h - H[i][k + 1]))
			local m = MAT[i][k]
			if dmax > 5 and (m == M.Grass or m == M.Snow) then
				MAT[i][k] = M.Rock
			end
		end
	end
	if log then
		log("heights done")
	end
	-- 3. voxels, chunk by chunk
	local CH = 48
	for ci = 0, nx - 1, CH do
		for ck = 0, nz - 1, CH do
			local sx = math.min(CH, nx - ci)
			local sz = math.min(CH, nz - ck)
			local mats, occ = {}, {}
			for a = 1, sx do
				local i = ci + a
				mats[a], occ[a] = {}, {}
				for b = 1, ny do
					mats[a][b], occ[a][b] = {}, {}
				end
				for c = 1, sz do
					local k = ck + c
					local h, top, w = H[i][k], MAT[i][k], W[i][k]
					local x = X0 + (i - 0.5) * CELL
					local z = Z0 + (k - 0.5) * CELL
					for b = 1, ny do
						local y0 = Y0 + (b - 1) * CELL
						local yc = y0 + CELL / 2
						local m, o = M.Air, 0
						if y0 < h then
							o = math.clamp((h - y0) / CELL, 0, 1)
							if h - y0 <= CELL then
								m = top
							elseif top == M.Grass and h - y0 <= CELL * 2 then
								m = M.Ground
							elseif top == M.Sand and h - y0 <= CELL * 3 then
								m = M.Sand
							else
								m = if math.floor(yc / 10) % 3 == 0 then M.Slate else M.Rock
							end
						end
						-- cave behind the waterfall
						if x > CAVE_MIN.X and x < CAVE_MAX.X and z > CAVE_MIN.Z and z < CAVE_MAX.Z and yc > CAVE_MIN.Y and yc < CAVE_MAX.Y then
							m, o = M.Air, 0
						end
						if o < 1 then
							local level = if w ~= false then w else G.SEA_Y
							if yc < level and (w ~= false or h < G.SEA_Y + 1 or y0 >= h) then
								m, o = M.Water, 1
							end
						end
						mats[a][b][c] = m
						occ[a][b][c] = o
					end
				end
			end
			local lo = Vector3.new(X0 + ci * CELL, Y0, Z0 + ck * CELL)
			local hi = lo + Vector3.new(sx * CELL, ny * CELL, sz * CELL)
			T:WriteVoxels(Region3.new(lo, hi), CELL, mats, occ)
			task.wait()
		end
		if log then
			log("column block " .. ci)
		end
	end
	-- 4. open ocean outside the region (water only, sea floor at Y0)
	local far = 700
	local seaTop = G.SEA_Y
	local function fill(minV: Vector3, maxV: Vector3)
		local size = maxV - minV
		T:FillBlock(CFrame.new((minV + maxV) / 2), size, M.Water)
	end
	local d = seaTop - Y0
	fill(Vector3.new(-far, Y0, -far), Vector3.new(far, seaTop, Z0))
	fill(Vector3.new(-far, Y0, Z1), Vector3.new(far, seaTop, far))
	fill(Vector3.new(-far, Y0, Z0), Vector3.new(X0, seaTop, Z1))
	fill(Vector3.new(X1, Y0, Z0), Vector3.new(far, seaTop, Z1))
	-- sand floor under the open ocean
	local floorT = 8
	T:FillBlock(CFrame.new(0, Y0 - floorT / 2, 0), Vector3.new(far * 2, floorT, far * 2), M.Sand)
	assert(d > 0)
	if log then
		log("ocean done")
	end
end

return G
