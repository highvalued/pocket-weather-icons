--!strict
-- Player islands south of the Sky Meadow, reached by the bridges in workspace.Map.Bridges
-- (ISLAND_Z / SPACING must match those). One per player. Each island is a low-poly floating
-- miniature (WorldKit "PlotIsland": grass top tinted by the weather theme, layered cliff below) with:
--   * an entrance path from the bridge, lantern posts and the owner's sign
--   * a spawn pad (Plots.spawnCFrame) - players spawn and respawn here
--   * the glass display case (shelf of caught clouds, grows with the Case upgrade)
--   * the upgrade kiosk (ShopStand + ShopPrompt opens the Catcher Upgrades menu)
--   * an empty, stone-edged build area kept free for future buildings
--   * trees, bushes, flowers, rocks and grass from the kit (winter snow comes with the kit pieces)
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage").PocketWeather.Config)
local makeCloud = require(script.Parent.CloudModel)

type Plot = {
	center: Vector3,
	shelf: Folder,
	plinth: BasePart,
	sign: TextLabel,
	glass: BasePart,
	roof: BasePart,
	signGui: BillboardGui,
	spawn: BasePart,
	cap: number, -- case slots currently built for (Case upgrade)
}

local Plots = {}
local plots: { Plot } = {}
local owner: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}

local ISLAND_Z = 195
local SPACING = 40
local CASE_SIZE = Vector3.new(22, 6, 5)
local CASE_Z = 14 -- display case sits at the back of the island
local SPAWN_Z = -8 -- spawn pad, just inside the entrance
local ISLAND_SCALE = 0.9 -- kit island is ~38 x 50 studs; 0.9 keeps a gap between neighbours
local ISLAND_SHIFT = 5 -- island mesh centre is pushed back so its front edge meets the bridge end

local WK = ServerStorage:WaitForChild("WorldKit")
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local M = Enum.Material

local folder = Instance.new("Folder")
folder.Name = "Islands"
folder.Parent = Workspace

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function block(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, cls: string?): BasePart
	local p = Instance.new(cls or "Part") :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decor(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis is X; rotate to Y

local function disc(name: string, height: number, d: number, at: Vector3, color: Color3, mat: Enum.Material, parent: Instance): BasePart
	local p = block(name, Vector3.new(height, d, d), CFrame.new(at) * UPRIGHT, color, mat, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function kit(name: string, cf: CFrame, scale: number, parent: Instance): Model
	local m = (WK:WaitForChild(name) :: Model):Clone()
	if math.abs(scale - 1) > 1e-3 then
		m:ScaleTo(scale)
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

local function signLabel(parent: Instance, text: string): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.FontFace = FREDOKA
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	local ink = Instance.new("UIStroke")
	ink.Color = hex("160F2B")
	ink.Thickness = 3
	ink.LineJoinMode = Enum.LineJoinMode.Round
	ink.Parent = t
	t.Text = text
	t.Parent = parent
	return t
end

local function lantern(at: Vector3, parent: Instance)
	local m = kit("Lamp_A", CFrame.new(at), 0.72, parent)
	-- lihfolk-ignore: findfirstchild-chain (cast only; nil-checked on the next line)
	local glass = m:FindFirstChild("Glow") :: BasePart?
	if glass then
		local l = Instance.new("PointLight")
		l.Color = hex("FFD27A")
		l.Range = 14
		l.Brightness = 0.6
		l.Shadows = false
		l.Parent = glass
	end
end

local WOOD = hex("A06A43")
local WOOD_DARK = hex("6E4528")
local STONE = hex("C9C3DA")
local STONE_DARK = hex("A39CB8")

local function buildIsland(i: number, center: Vector3): Plot
	local model = Instance.new("Model")
	model.Name = "Island" .. i
	local rng = Random.new(1000 + i)
	local function at(x: number, z: number, y: number?): Vector3
		return center + Vector3.new(x, y or 0, z)
	end

	-- floating island (top flush with the bridges, y = 0)
	local isl = kit("PlotIsland", CFrame.new(at(0, ISLAND_SHIFT)) * CFrame.Angles(0, if i % 2 == 0 then math.pi else 0, 0), ISLAND_SCALE, model)
	isl.Name = "Ground"

	-- entrance: stepping-stone path from the bridge to the case, lanterns, fence wings, owner sign
	local z = -17
	local k = 0
	while z < CASE_Z - 4 do
		local off = if k % 2 == 0 then -0.6 else 0.6
		local s = disc("PathStone", 0.25, rng:NextNumber(2.6, 3.2), at(off, z, 0.08), if k % 3 == 0 then STONE_DARK else STONE, M.SmoothPlastic, model)
		s.CastShadow = false
		z += 2.7
		k += 1
	end
	lantern(at(-3.6, -15), model)
	lantern(at(3.6, -15), model)
	for side = -1, 1, 2 do
		for j = 0, 3 do
			local x = side * (5 + j * 2.2)
			block("Picket", Vector3.new(0.45, 2.2, 0.45), CFrame.new(at(x, -16.2 + j * 0.35, 1.1)), WOOD, M.Wood, model)
		end
		local a, b = at(side * 5, -16.2, 1.6), at(side * 11.6, -15.15, 1.6)
		block("Rail", Vector3.new(0.3, 0.35, (b - a).Magnitude + 0.4), CFrame.lookAt((a + b) / 2, b), WOOD_DARK, M.Wood, model)
		local a2, b2 = a - Vector3.new(0, 0.8, 0), b - Vector3.new(0, 0.8, 0)
		block("Rail", Vector3.new(0.3, 0.35, (b2 - a2).Magnitude + 0.4), CFrame.lookAt((a2 + b2) / 2, b2), WOOD_DARK, M.Wood, model)
	end
	-- owner sign on a post by the entrance
	local post = block("SignPost", Vector3.new(0.5, 4.2, 0.5), CFrame.new(at(-6.2, -12.5, 2.1)), WOOD_DARK, M.Wood, model)
	post.CastShadow = true
	local board = block("SignBoard", Vector3.new(5.6, 1.8, 0.35), CFrame.lookAt(at(-6.2, -12.5, 3.6), at(-6.2, -30, 3.6)), WOOD, M.WoodPlanks, model)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 140
	gui.Parent = board
	local sign = signLabel(gui, "Free island")

	-- spawn pad
	local pad = disc("SpawnPad", 0.3, 6, at(0, SPAWN_Z, 0.12), hex("E9E4F2"), M.SmoothPlastic, model)
	pad.CastShadow = false
	local ring = disc("SpawnRing", 0.32, 6.6, at(0, SPAWN_Z, 0.1), hex("5FD8FF"), M.Neon, model)
	decor(ring)
	CollectionService:AddTag(ring, "Glow")
	pad:SetAttribute("PlotSpawn", i)

	-- display case at the back
	local casePos = at(0, CASE_Z)
	local caseBase = block("CaseBase", Vector3.new(27, 0.4, 9), CFrame.new(casePos + Vector3.new(0, 0.18, 0)), STONE_DARK, M.SmoothPlastic, model)
	caseBase.CastShadow = false
	local plinth = block("Plinth", Vector3.new(CASE_SIZE.X + 1, 1.2, CASE_SIZE.Z + 1), CFrame.new(casePos + Vector3.new(0, 0.6, 0)), hex("966846"), M.WoodPlanks, model)
	local glass = block("Glass", CASE_SIZE, CFrame.new(casePos + Vector3.new(0, 1.2 + CASE_SIZE.Y / 2, 0)), hex("C8EBFF"), M.Glass, model)
	glass.Transparency = 0.8
	glass.CanCollide = false
	glass.CastShadow = false
	local roof = block("Roof", Vector3.new(CASE_SIZE.X + 1, 0.6, CASE_SIZE.Z + 1), CFrame.new(casePos + Vector3.new(0, 1.5 + CASE_SIZE.Y, 0)), hex("966846"), M.WoodPlanks, model)
	local caseGui = Instance.new("BillboardGui")
	caseGui.Size = UDim2.fromOffset(240, 34)
	caseGui.StudsOffset = Vector3.new(0, CASE_SIZE.Y + 3, 0)
	caseGui.MaxDistance = 60
	caseGui.Parent = plinth
	signLabel(caseGui, "CLOUD COLLECTION")

	-- upgrade kiosk (right of the path): plank deck, counter, striped awning, glowing sign
	local kioskCF = CFrame.lookAt(at(10, -2), at(0, -2))
	for j = -2, 2 do
		block("Deck", Vector3.new(1.3, 0.35, 7.6), kioskCF * CFrame.new(j * 1.4, 0.18, 0.6), if j % 2 == 0 then WOOD else hex("8E5C38"), M.WoodPlanks, model)
	end
	local stand = block("ShopStand", Vector3.new(5, 3, 2.2), kioskCF * CFrame.new(0, 1.85, -1.2), hex("966846"), M.WoodPlanks, model)
	block("ShopTop", Vector3.new(5.6, 0.4, 2.8), stand.CFrame * CFrame.new(0, 1.7, 0), hex("FFD359"), M.SmoothPlastic, model)
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			block("AwningPost", Vector3.new(0.4, 6.2, 0.4), kioskCF * CFrame.new(sx * 3.1, 3.4, sz * 2.4 + 0.6), WOOD_DARK, M.Wood, model)
		end
	end
	for j = 0, 5 do
		local stripe = block("Awning", Vector3.new(1.15, 0.3, 6.2), kioskCF * CFrame.new(-2.9 + j * 1.15, 6.6, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), if j % 2 == 0 then hex("FF6F90") else hex("FFF3E0"), M.SmoothPlastic, model)
		stripe.CastShadow = true
	end
	local glowSign = block("KioskSign", Vector3.new(4.4, 1.2, 0.3), kioskCF * CFrame.new(0, 7.6, -2.3), hex("5FD8FF"), M.Neon, model)
	decor(glowSign)
	CollectionService:AddTag(glowSign, "Glow")
	local kioskLight = Instance.new("PointLight")
	kioskLight.Color = hex("FFE2A8")
	kioskLight.Range = 12
	kioskLight.Brightness = 0.7
	kioskLight.Shadows = false
	kioskLight.Parent = glowSign
	local standGui = Instance.new("BillboardGui")
	standGui.Size = UDim2.fromOffset(200, 44)
	standGui.StudsOffset = Vector3.new(0, 3.2, 0)
	standGui.MaxDistance = 45
	standGui.Parent = glowSign
	signLabel(standGui, "UPGRADES")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open shop"
	prompt.ObjectText = "Catcher upgrades"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	-- build area (left of the path): stone-edged grass square kept empty for future buildings
	local bc = at(-10, 0)
	for _, e in { { 0, -5, 10.6, 0.8 }, { 0, 5, 10.6, 0.8 }, { -5, 0, 0.8, 9.4 }, { 5, 0, 0.8, 9.4 } } do
		local edge = block("BuildEdge", Vector3.new(e[3], 0.35, e[4]), CFrame.new(bc + Vector3.new(e[1], 0.17, e[2])), STONE_DARK, M.SmoothPlastic, model)
		edge.CastShadow = false
	end
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			block("BuildCorner", Vector3.new(1, 0.9, 1), CFrame.new(bc + Vector3.new(sx * 5, 0.45, sz * 5)), STONE, M.SmoothPlastic, model)
		end
	end
	local area = block("BuildArea", Vector3.new(9, 0.2, 9), CFrame.new(bc + Vector3.new(0, 0.1, 0)), Color3.new(1, 1, 1), M.SmoothPlastic, model)
	area.Transparency = 1
	decor(area)
	area:SetAttribute("BuildArea", true)

	-- nature: firs and an oak behind the case, bushes, flowers, rocks, grass along the edges
	local fir = { "Fir_A", "Fir_B", "Fir_C" }
	kit(fir[(i - 1) % 3 + 1], CFrame.new(at(-13, 20)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), 0.9, model)
	kit(fir[i % 3 + 1], CFrame.new(at(-15, 10)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), 0.7, model)
	kit("Fir_D", CFrame.new(at(15.5, 14)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), 0.9, model)
	kit(if i % 2 == 0 then "Oak_A" else "Oak_B", CFrame.new(at(12, 21)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), 0.85, model)
	for _, b in { { 14.5, 4 }, { -15, -4 }, { 13.5, -11 }, { -4, 23 } } do
		kit(({ "Bush_A", "Bush_B", "Bush_C" })[rng:NextInteger(1, 3)], CFrame.new(at(b[1], b[2], -0.2)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), rng:NextNumber(0.8, 1.05), model)
	end
	for _, f in { { 2.6, -12 }, { -2.6, -6 }, { 2.8, 2 }, { -2.7, 8 }, { 6, 10 }, { -7, 13 }, { 9, -13 } } do
		kit(if rng:NextNumber() < 0.5 then "Flowers_A" else "Flowers_B", CFrame.new(at(f[1], f[2], -0.1)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), rng:NextNumber(0.9, 1.3), model)
	end
	for _, r in { { 15, -15, 0.8 }, { -16, 16, 1 }, { 16, 25, 0.7 }, { -13, -16, 0.6 } } do
		kit(({ "Rock_A", "Rock_B", "Rock_D" })[rng:NextInteger(1, 3)], CFrame.new(at(r[1], r[2], -0.3)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), r[3], model)
	end
	for _ = 1, 14 do
		local a = rng:NextNumber() * math.pi * 2
		local x, zz = math.cos(a) * rng:NextNumber(12, 15.5), ISLAND_SHIFT + math.sin(a) * rng:NextNumber(17, 20)
		kit("Grass_A", CFrame.new(at(x, zz, -0.1)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), rng:NextNumber(1, 1.6), model)
	end

	local shelf = Instance.new("Folder")
	shelf.Name = "Shelf"
	shelf.Parent = model
	model.Parent = folder
	return { center = center, shelf = shelf, plinth = plinth, sign = sign, glass = glass, roof = roof, signGui = caseGui, spawn = pad, cap = Config.CASE_MAX }
end

for i = 1, Config.PLOT_COUNT do
	local center = Vector3.new(-(Config.PLOT_COUNT - 1) * SPACING / 2 + (i - 1) * SPACING, 0, ISLAND_Z)
	plots[i] = buildIsland(i, center)
end

-- Case slots upgrade: 6 clouds per row, so the glass grows taller (and the roof and sign with it).
local function fitCase(plot: Plot, cap: number)
	plot.cap = cap
	local rows = math.ceil(cap / 6)
	local h = math.max(CASE_SIZE.Y, rows * 2.6 + 1.2)
	local y = plot.plinth.Position.Y
	plot.glass.Size = Vector3.new(CASE_SIZE.X, h, CASE_SIZE.Z)
	plot.glass.Position = Vector3.new(plot.glass.Position.X, y + 0.6 + h / 2, plot.glass.Position.Z)
	plot.roof.Position = Vector3.new(plot.roof.Position.X, y + 0.9 + h, plot.roof.Position.Z)
	plot.signGui.StudsOffset = Vector3.new(0, h + 3, 0)
end

-- Returns nil when every island is taken: the player still plays (spawning at the hub), and gets
-- the next island that frees up (Main listens to Plots.Freed).
local freed = Instance.new("BindableEvent")
Plots.Freed = freed.Event

function Plots.assign(player: Player): number?
	if plotOf[player] then
		return plotOf[player]
	end
	for i = 1, Config.PLOT_COUNT do
		if not owner[i] then
			owner[i] = player
			plotOf[player] = i
			plots[i].sign.Text = player.DisplayName .. "'s island"
			player:SetAttribute("Plot", i)
			return i
		end
	end
	return nil
end

function Plots.release(player: Player)
	local i = plotOf[player]
	if not i then
		return
	end
	owner[i] = nil
	plotOf[player] = nil
	plots[i].shelf:ClearAllChildren()
	plots[i].shelf:SetAttribute("Sig", nil)
	plots[i].sign.Text = "Free island"
	fitCase(plots[i], Config.CASE_MAX)
	Plots.paint(i, "Classic")
	freed:Fire(i)
end

function Plots.has(player: Player): boolean
	return plotOf[player] ~= nil
end

-- Case theme colours (shop: Decor).
function Plots.paint(i: number, themeId: string)
	local def = Config.THEMES[themeId] or Config.THEMES.Classic
	local plot = plots[i]
	plot.glass.Color = def.glass
	for _, part in { plot.roof, plot.plinth } do
		part.Color = def.frame
		part.Material = def.material
	end
end

function Plots.setTheme(player: Player, themeId: string)
	local i = plotOf[player]
	if i then
		Plots.paint(i, themeId)
	end
end

-- Standing on the spawn pad, facing the bridge (toward the meadow and the fronts).
function Plots.spawnCFrame(player: Player): CFrame?
	local i = plotOf[player]
	if not i then
		return nil
	end
	local p = plots[i].spawn.Position
	return CFrame.lookAt(p + Vector3.new(0, 3.2, 0), p + Vector3.new(0, 3.2, -40))
end

-- Redraw the case: first CASE_MAX clouds in Config.ORDER, rows of 6.
function Plots.render(player: Player, kinds: { [string]: number })
	local i = plotOf[player]
	if not i then
		return
	end
	local plot = plots[i]
	local cap = Config.statFor(player, "CASE_MAX")
	if plot.cap ~= cap then
		fitCase(plot, cap)
	end
	-- income ticks fire Changed every 10 s: rebuild only when the collection itself changed
	local sig = { tostring(cap) }
	for _, kind in Config.ORDER do
		table.insert(sig, tostring(math.min(kinds[kind] or 0, cap)))
	end
	local key = table.concat(sig, ",")
	if plot.shelf:GetAttribute("Sig") == key then
		return
	end
	plot.shelf:SetAttribute("Sig", key)
	plot.shelf:ClearAllChildren()
	local base = plot.plinth.Position + Vector3.new(0, 0.6, 0)
	local n = 0
	for _, kind in Config.ORDER do
		for _ = 1, kinds[kind] or 0 do
			if n >= cap then
				return
			end
			local col, row = n % 6, n // 6
			local pos = base + Vector3.new(-9 + col * 3.6, 1.4 + row * 2.6, 0)
			local mood = ({ "Happy", "Sleepy", "Blush", "Happy" })[(n % 4) + 1]
			makeCloud(kind, 0.36, CFrame.lookAt(pos, pos - Vector3.zAxis), mood).Parent = plot.shelf
			n += 1
		end
	end
end

return Plots
