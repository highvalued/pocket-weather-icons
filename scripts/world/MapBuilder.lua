--!strict
-- Pocket Weather props and landmarks (edit-time builder; run after TerrainGen.build()).
-- ServerStorage.WorldGen.MapBuilder.build() clears and rebuilds these folders in workspace.Map:
--   WeatherTower, Plaza, Lamps, Boards, Village, SpawnIsland, GrandBridge, Waterfalls, Nature,
--   ThemeProps (Winter / Desert / Storm extras), Gems, SkyClouds, Turbines
-- It never touches workspace.Map.Bridges (plot bridges) or the player islands (built by Plots).
-- Tags (CollectionService) the runtime scripts look for:
--   OnlyWinter / OnlyDesert / OnlyStorm  hidden parts shown by WeatherWorld for that theme
--   Foliage      tinted per theme          Glow     lights brighten in storms
--   TowerOrb     the orb model             Spin     turbine / anemometer rotors (attribute Speed)
--   Flag         waving flag model         Gem      Sky Gem collectible (attribute GemId)
--   Waterfall    scrolling sheet part      SkyCloud big drifting cloud (casts moving shadows)
--   InfoBoard    SurfaceGui board
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Gen = require(script.Parent:WaitForChild("TerrainGen")) :: any

local B = {}

local kit = ServerStorage:WaitForChild("NatureKitParts")
-- low-poly Blender kit (scripts/kit/kit.py): Models with Body (+ Snow / Glow), pivot at the bottom centre
local WK = ServerStorage:WaitForChild("WorldKit")
local rng = Random.new(20261121)
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y

local function hex(h: string): Color3
	return Color3.fromHex(h)
end
local C = {
	stone = hex("DCD7EA"),
	stoneDark = hex("A9A3C4"),
	trim = hex("343B70"),
	white = hex("F2F4FA"),
	neon = hex("5FD8FF"),
	warm = hex("FFD27A"),
	wood = hex("A06A43"),
	woodDark = hex("6E4528"),
	leaf = hex("4DB35A"),
	leafDark = hex("2E8B57"),
	trunk = hex("7A5233"),
	snow = hex("F4F8FF"),
	cactus = hex("5FA548"),
	ink = hex("17142A"),
}

local M = Enum.Material

-- ------------------------------------------------------------------ helpers
local function tag(i: Instance, t: string)
	CollectionService:AddTag(i, t)
end

local function folder(name: string, parent: Instance): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, cls: string?): BasePart
	local p = Instance.new(cls or "Part") :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cyl(name: string, height: number, diameter: number, at: Vector3, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = part(name, Vector3.new(height, diameter, diameter), CFrame.new(at) * UP, color, mat, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(name: string, d: Vector3, at: CFrame, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = part(name, d, at, color, mat, parent) :: Part
	p.Shape = Enum.PartType.Ball
	return p
end

local function decor(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- hidden until a theme shows it
local function only(p: BasePart, theme: string)
	p:SetAttribute("BaseT", p.Transparency)
	p.Transparency = 1
	p.CastShadow = false
	decor(p)
	tag(p, "Only" .. theme)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }
rayParams.IgnoreWater = true
local function groundAt(x: number, z: number): (number, Enum.Material?)
	local hit = Workspace:Raycast(Vector3.new(x, 250, z), Vector3.new(0, -400, 0), rayParams)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return Gen.SEA_Y, nil
end
local function waterAt(x: number, z: number): boolean
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 250, z), Vector3.new(0, -400, 0), p)
	return hit ~= nil and hit.Material == M.Water
end

local function text(gui: Instance, str: string, size: UDim2, pos: UDim2, color: Color3?, scaled: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FREDOKA
	t.Text = str
	t.TextScaled = scaled ~= false
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Size = size
	t.Position = pos
	local s = Instance.new("UIStroke")
	s.Color = C.ink
	s.Thickness = 3
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = gui
	return t
end

-- ------------------------------------------------------------------ nature pieces (WorldKit)
-- One kit model, placed by its bottom-centre pivot, scaled and turned. Snow parts are tagged
-- OnlyWinter in the kit, so every tree, bush, rock, roof and lamp gets its own winter shape.
local function kitModel(name: string, cf: CFrame, scale: number, parent: Instance): Model
	local m = (WK:WaitForChild(name) :: Model):Clone()
	if math.abs(scale - 1) > 1e-3 then
		m:ScaleTo(scale)
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

local function pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function yawAt(at: Vector3, sink: number?): CFrame
	return CFrame.new(at - Vector3.new(0, sink or 0.25, 0)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0)
end

-- old kitPiece names map onto the new kit (Bush / Flowers / Rock), with sizes matched to the old ones
local function kitPiece(name: string, at: Vector3, scale: number, yaw: number, parent: Instance, sink: number?): Model
	local cf = CFrame.new(at - Vector3.new(0, sink or 0.25, 0)) * CFrame.Angles(0, yaw, 0)
	if name == "Bush" then
		return kitModel(pick({ "Bush_A", "Bush_B", "Bush_C" }), cf, scale * 0.8, parent)
	elseif name == "Flowers" then
		return kitModel(pick({ "Flowers_A", "Flowers_B" }), cf, scale, parent)
	end
	return kitModel(pick({ "Rock_A", "Rock_B", "Rock_C", "Rock_D" }), cf, scale * 0.75, parent)
end

local function roundTree(at: Vector3, scale: number, parent: Instance)
	return kitModel(pick({ "Oak_A", "Oak_A", "Oak_B", "Oak_C" }), yawAt(at), scale * rng:NextNumber(1.05, 1.3), parent)
end

local function pine(at: Vector3, s: number, parent: Instance)
	-- mostly full-size firs, with a few young ones (Fir_D) so groves read as grown, not stamped
	local name = if rng:NextNumber() < 0.2 then "Fir_D" else pick({ "Fir_A", "Fir_B", "Fir_C" })
	return kitModel(name, yawAt(at), s * rng:NextNumber(0.85, 1.1), parent)
end

local function palm(at: Vector3, s: number, parent: Instance)
	return kitModel(pick({ "Palm_A", "Palm_B" }), yawAt(at), s * 1.1, parent)
end

local function grassTuft(at: Vector3, parent: Instance)
	return kitModel("Grass_A", yawAt(at, 0.1), rng:NextNumber(1, 1.8), parent)
end

local function cactus(at: Vector3, s: number, parent: Instance)
	local m = model("Cactus", parent)
	local body = cyl("Body", 6 * s, 1.8 * s, at + Vector3.new(0, 3 * s, 0), C.cactus, M.SmoothPlastic, m)
	only(body, "Desert")
	local cap = ball("Top", Vector3.one * 1.8 * s, CFrame.new(at + Vector3.new(0, 6 * s, 0)), C.cactus, M.SmoothPlastic, m)
	only(cap, "Desert")
	for side = -1, 1, 2 do
		local arm = cyl("Arm", 2.4 * s, 1.1 * s, at + Vector3.new(side * 1.6 * s, (3 + side * 0.6) * s + 1.2 * s, 0), C.cactus, M.SmoothPlastic, m)
		only(arm, "Desert")
		local link = part("Link", Vector3.new(1.4 * s, 1 * s, 1 * s), CFrame.new(at + Vector3.new(side * 1 * s, (3 + side * 0.6) * s, 0)), C.cactus, M.SmoothPlastic, m)
		only(link, "Desert")
	end
	local flower = ball("Flower", Vector3.one * 0.7 * s, CFrame.new(at + Vector3.new(0, 6.8 * s, 0)), hex("FF6FB0"), M.SmoothPlastic, m)
	only(flower, "Desert")
end

local function rock(at: Vector3, s: number, parent: Instance)
	return kitPiece("Rock", at, s, rng:NextNumber() * 6.28, parent, 0.3 * s)
end

-- ------------------------------------------------------------------ lamps
local function lamp(at: Vector3, parent: Instance)
	local m = kitModel("Lamp_A", CFrame.new(at) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), 1, parent)
	m.Name = "Lamp"
	local glass = m:FindFirstChild("Glow") :: BasePart?
	if glass then
		local light = Instance.new("PointLight")
		light.Color = C.warm
		light.Range = 18
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = glass
	end
	return m
end

-- ------------------------------------------------------------------ boards
local function board(name: string, at: Vector3, facing: Vector3, parent: Instance, kind: string): Model
	local m = model(name, parent)
	local cf = CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z))
	for side = -1, 1, 2 do
		part("Post", Vector3.new(0.8, 8, 0.8), cf * CFrame.new(side * 5, 4, 0), C.trim, M.Metal, m)
	end
	local panel = part("Panel", Vector3.new(10.6, 6.2, 0.6), cf * CFrame.new(0, 6.2, 0), C.trim, M.SmoothPlastic, m)
	local screen = part("Screen", Vector3.new(9.8, 5.4, 0.1), cf * CFrame.new(0, 6.2, -0.33), hex("1E2350"), M.SmoothPlastic, m)
	decor(screen)
	part("Roof", Vector3.new(11.4, 0.5, 1.6), cf * CFrame.new(0, 9.55, 0), C.trim, M.Metal, m)
	local snow = part("SnowTop", Vector3.new(11.4, 0.4, 1.6), cf * CFrame.new(0, 10, 0), C.snow, M.Snow, m)
	only(snow, "Winter")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(490, 270)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = hex("1E2350")
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(hex("2C3A8C"), hex("181C45"))
	g.Rotation = 90
	g.Parent = bg
	text(bg, "WEATHER REPORT", UDim2.new(1, -30, 0, 46), UDim2.fromOffset(15, 10), hex("8FE3FF")).Name = "Title"
	text(bg, "", UDim2.new(1, -30, 0, 70), UDim2.fromOffset(15, 70)).Name = "Main"
	text(bg, "", UDim2.new(1, -30, 0, 40), UDim2.fromOffset(15, 150), hex("FFE14A")).Name = "Sub"
	text(bg, "", UDim2.new(1, -30, 0, 34), UDim2.fromOffset(15, 210), hex("C9CCE6")).Name = "Tip"
	m:SetAttribute("Kind", kind)
	tag(m, "InfoBoard")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ReadPrompt"
	prompt.ActionText = "Next tip"
	prompt.ObjectText = "Weather board"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = panel
	return m
end

-- ------------------------------------------------------------------ hub leaderboards
-- Stand with a big screen; ServerScriptService.PocketWeather.Leaderboards fills Screen with the
-- top 10 for the board's Stat (real saved stats only).
local function leaderboard(stat: string, accent: Color3, at: Vector3, facing: Vector3, parent: Instance): Model
	local m = model("Leaderboard_" .. stat, parent)
	local cf = CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z))
	local W, Hs = 14, 17.7
	-- stepped base
	part("Step1", Vector3.new(W + 6, 0.8, 7), cf * CFrame.new(0, 0.4, 0), C.stoneDark, M.SmoothPlastic, m)
	part("Step2", Vector3.new(W + 4, 0.8, 5), cf * CFrame.new(0, 1.2, 0), C.stone, M.SmoothPlastic, m)
	local trimGlow = part("StepGlow", Vector3.new(W + 4.2, 0.2, 5.2), cf * CFrame.new(0, 1.65, 0), accent, M.Neon, m)
	decor(trimGlow)
	tag(trimGlow, "Glow")
	-- pillars with caps and orbs
	for side = -1, 1, 2 do
		local pil = part("Pillar", Vector3.new(2, Hs + 4, 2), cf * CFrame.new(side * (W / 2 + 1), 1.6 + (Hs + 4) / 2, 0), C.stone, M.SmoothPlastic, m)
		pil.CastShadow = true
		part("PillarCap", Vector3.new(2.8, 0.8, 2.8), cf * CFrame.new(side * (W / 2 + 1), 2 + Hs + 4, 0), C.trim, M.Metal, m)
		local orb = ball("PillarOrb", Vector3.one * 1.6, cf * CFrame.new(side * (W / 2 + 1), 3.3 + Hs + 4, 0), accent, M.Neon, m)
		decor(orb)
		tag(orb, "Glow")
		local l = Instance.new("PointLight")
		l.Color = accent
		l.Range = 14
		l.Brightness = 0.8
		l.Shadows = false
		l.Parent = orb
		local snowCap = part("SnowCap", Vector3.new(2.9, 0.35, 2.9), cf * CFrame.new(side * (W / 2 + 1), 2.55 + Hs + 4, 0), C.snow, M.Snow, m)
		only(snowCap, "Winter")
	end
	-- frame + screen
	part("Frame", Vector3.new(W + 0.8, Hs + 0.8, 0.8), cf * CFrame.new(0, 2.4 + Hs / 2, 0.1), C.trim, M.Metal, m)
	local screen = part("Screen", Vector3.new(W, Hs, 0.2), cf * CFrame.new(0, 2.4 + Hs / 2, -0.4), hex("1E2350"), M.SmoothPlastic, m)
	decor(screen)
	local glow = part("FrameGlow", Vector3.new(W + 1.2, 0.3, 1), cf * CFrame.new(0, 2.4 + Hs + 0.55, 0), accent, M.Neon, m)
	decor(glow)
	tag(glow, "Glow")
	-- little gable roof with its winter snow
	for side = -1, 1, 2 do
		part("Roof", Vector3.new(W + 4, 1.6, 2), cf * CFrame.new(0, 3.9 + Hs + 0.8, side * 1) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.trim, M.SmoothPlastic, m, "WedgePart")
		local sn = part("SnowRoof", Vector3.new(W + 4.1, 0.9, 2.05), cf * CFrame.new(0, 4.5 + Hs + 0.9, side * 1) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.snow, M.Snow, m, "WedgePart")
		only(sn, "Winter")
	end
	-- uplight on the screen
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 14
	spot.Brightness = 0.6
	spot.Color = accent
	spot.Parent = trimGlow
	m:SetAttribute("Stat", stat)
	tag(m, "Leaderboard")
	return m
end

-- ------------------------------------------------------------------ weather tower
local function buildTower(root: Instance)
	local m = model("WeatherTower", root)
	local base = Vector3.new(0, 1, 0)
	cyl("Step1", 1.4, 44, base + Vector3.new(0, 0.7, 0), C.stoneDark, M.SmoothPlastic, m)
	cyl("Step2", 1.4, 36, base + Vector3.new(0, 2.1, 0), C.stone, M.SmoothPlastic, m)
	local ring = cyl("GlowRing", 0.3, 36.6, base + Vector3.new(0, 2.7, 0), C.neon, M.Neon, m)
	decor(ring)
	tag(ring, "TowerGlow")
	local y0 = base.Y + 2.8
	local H = 44
	local body = cyl("Body", H, 15, Vector3.new(0, y0 + H / 2, 0), C.white, M.SmoothPlastic, m)
	body.CastShadow = true
	-- glowing window columns on four sides
	for q = 0, 3 do
		local a = q * math.pi / 2 + math.pi / 4
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		for k = 0, 5 do
			local y = y0 + 6 + k * 6
			local w = part("Window", Vector3.new(2.6, 3.6, 0.6), CFrame.lookAt(dir * 7.35 + Vector3.new(0, y, 0), dir * 20 + Vector3.new(0, y, 0)), C.neon, M.Neon, m)
			decor(w)
			tag(w, "TowerGlow")
			part("Frame", Vector3.new(3.4, 4.4, 0.5), CFrame.lookAt(dir * 7.2 + Vector3.new(0, y, 0), dir * 20 + Vector3.new(0, y, 0)), C.trim, M.Metal, m)
		end
	end
	for _, y in { 12, 26, 40 } do
		cyl("Collar", 2, 17, Vector3.new(0, y0 + y, 0), C.trim, M.Metal, m)
		local band = cyl("CollarGlow", 0.35, 17.3, Vector3.new(0, y0 + y + 1.1, 0), C.neon, M.Neon, m)
		decor(band)
		tag(band, "TowerGlow")
	end
	-- stone plinth and buttresses: a wider, stepped base so the tower sits heavy on the plaza
	cyl("Plinth", 5, 19, Vector3.new(0, y0 + 2.5, 0), C.stoneDark, M.SmoothPlastic, m)
	cyl("PlinthCap", 0.8, 20.4, Vector3.new(0, y0 + 5.2, 0), C.trim, M.Metal, m)
	for q = 0, 7 do
		local a = q * math.pi / 4
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		if q ~= 0 then -- q = 0 is the door side
			local bt = part("Buttress", Vector3.new(1.6, 9, 4.4), CFrame.lookAt(dir * 10.4 + Vector3.new(0, y0 + 4.5, 0), dir * 30 + Vector3.new(0, y0 + 4.5, 0)), C.stone, M.SmoothPlastic, m, "WedgePart")
			bt.CastShadow = true
		end
		-- vertical energy strip between the window columns
		local strip = part("EnergyStrip", Vector3.new(0.6, H - 10, 0.4), CFrame.lookAt(dir * 7.55 + Vector3.new(0, y0 + 6 + (H - 10) / 2, 0), dir * 20 + Vector3.new(0, y0 + 6 + (H - 10) / 2, 0)), C.neon, M.Neon, m)
		decor(strip)
		strip.Transparency = 0.1
		tag(strip, "TowerGlow")
	end
	-- corbels under the deck
	for i = 0, 15 do
		local a = i * math.pi * 2 / 16
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		part("Corbel", Vector3.new(1.2, 2.4, 3.2), CFrame.lookAt(dir * 9.3 + Vector3.new(0, y0 + H - 1.4, 0), dir * 30 + Vector3.new(0, y0 + H - 1.4, 0)) * CFrame.Angles(0, 0, math.pi), C.trim, M.Metal, m, "WedgePart")
	end
	-- door (south, facing the spawn road and the plot bridges)
	local door = part("Door", Vector3.new(5, 8, 1), CFrame.new(0, y0 + 4, 7.3), hex("2A3166"), M.SmoothPlastic, m)
	door.CanCollide = true
	local dglow = part("DoorGlow", Vector3.new(5.6, 0.4, 1.2), CFrame.new(0, y0 + 8.3, 7.4), C.neon, M.Neon, m)
	decor(dglow)
	tag(dglow, "TowerGlow")
	-- deck and railing
	local deckY = y0 + H + 1
	cyl("Deck", 2, 24, Vector3.new(0, deckY, 0), C.stone, M.SmoothPlastic, m)
	local deckGlow = cyl("DeckGlow", 0.3, 24.4, Vector3.new(0, deckY - 1.1, 0), C.neon, M.Neon, m)
	decor(deckGlow)
	tag(deckGlow, "TowerGlow")
	for i = 0, 11 do
		local a = i * math.pi * 2 / 12
		part("Rail", Vector3.new(0.5, 3, 0.5), CFrame.new(math.cos(a) * 11.3, deckY + 2.5, math.sin(a) * 11.3), C.trim, M.Metal, m)
	end
	for i = 0, 11 do
		local a1, a2 = i * math.pi * 2 / 12, (i + 1) * math.pi * 2 / 12
		local p1 = Vector3.new(math.cos(a1) * 11.3, deckY + 4, math.sin(a1) * 11.3)
		local p2 = Vector3.new(math.cos(a2) * 11.3, deckY + 4, math.sin(a2) * 11.3)
		part("RailTop", Vector3.new(0.4, 0.4, (p2 - p1).Magnitude + 0.4), CFrame.lookAt((p1 + p2) / 2, p2), C.trim, M.Metal, m)
	end
	-- orb on four arms
	local orbC = Vector3.new(0, deckY + 14, 0)
	local orbM = model("Orb", m)
	orbM.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- symbols and rings arrive with the core
	tag(orbM, "TowerOrb")
	for q = 0, 3 do
		local a = q * math.pi / 2
		local foot = Vector3.new(math.cos(a) * 8, deckY + 1, math.sin(a) * 8)
		local top = orbC + Vector3.new(math.cos(a) * 6, -6, math.sin(a) * 6)
		part("Arm", Vector3.new(1, 1, (top - foot).Magnitude), CFrame.lookAt((foot + top) / 2, top), C.trim, M.Metal, m)
	end
	cyl("Cradle", 1.4, 12, orbC + Vector3.new(0, -9.2, 0), C.trim, M.Metal, m)
	local glass = ball("Glass", Vector3.one * 20, CFrame.new(orbC), hex("D6EEFF"), M.Glass, orbM)
	glass.Transparency = 0.55
	glass.CastShadow = false
	decor(glass)
	local core = ball("Core", Vector3.one * 7, CFrame.new(orbC), hex("FFE27A"), M.Neon, orbM)
	core.Transparency = 0.15
	decor(core)
	local light = Instance.new("PointLight")
	light.Name = "OrbLight"
	light.Range = 45
	light.Brightness = 2
	light.Color = hex("FFE27A")
	light.Shadows = false
	light.Parent = core
	-- weather symbols inside the globe (WorldKit meshes); WeatherWorld shows the one for the theme
	-- and spins it: Sunny = sun, Winter = snowflake, Storm = lightning bolt, Desert = wind swirl
	for _, sd in { { "Default", "Sym_Sun", "FFD84A" }, { "Winter", "Sym_Snowflake", "8FEFFF" }, { "Storm", "Sym_Bolt", "C08CFF" }, { "Desert", "Sym_Wind", "FF9A3C" } } do
		local sym = kitModel(sd[2], CFrame.new(orbC), 1.25, orbM)
		sym.Name = "Symbol_" .. sd[1]
		sym:SetAttribute("Theme", sd[1])
		for _, sp in sym:GetDescendants() do
			if sp:IsA("BasePart") then
				sp.Color = hex(sd[3])
				sp.Transparency = if sd[1] == "Default" then 0 else 1
			end
		end
		tag(sym, "TowerSymbol")
	end
	-- energy rings around the globe (WeatherWorld turns them on tilted axes)
	for k, rd in { { 0.92, 22, 0.8 }, { 1.12, -34, -0.55 }, { 1.3, 70, 0.35 } } do
		local r = kitModel("GlobeRing", CFrame.new(orbC), rd[1], orbM)
		r.Name = "EnergyRing" .. k
		r:SetAttribute("Center", orbC)
		r:SetAttribute("Tilt", rd[2])
		r:SetAttribute("Speed", rd[3])
		for _, rp in r:GetDescendants() do
			if rp:IsA("BasePart") then
				rp.Color = C.neon
				rp.Transparency = 0.15
				tag(rp, "TowerGlow")
			end
		end
		tag(r, "TowerRing")
	end
	local swirl = Instance.new("ParticleEmitter")
	swirl.Name = "Energy"
	swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swirl.Rate = 14
	swirl.Lifetime = NumberRange.new(1.5, 2.5)
	swirl.Speed = NumberRange.new(0.5, 1.5)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.RotSpeed = NumberRange.new(-90, 90)
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.9), NumberSequenceKeypoint.new(1, 0) })
	swirl.Color = ColorSequence.new(hex("7FE6FF"))
	swirl.Shape = Enum.ParticleEmitterShape.Sphere
	swirl.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	swirl.Parent = glass
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Rate = 10
	sparkle.Lifetime = NumberRange.new(1.2, 2)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(hex("FFF2B0"))
	sparkle.Parent = core
	-- orbit ring of small lights (spun by WeatherWorld)
	local ringM = model("OrbitRing", orbM) -- kept empty: the WorldKit energy rings replaced the light bits
	for i = 0, -1 do
		local a = i * math.pi * 2 / 16
		local b = part("Bit", Vector3.new(1.1, 1.1, 1.1), CFrame.new(orbC + Vector3.new(math.cos(a) * 14, math.sin(a * 2) * 1.2, math.sin(a) * 14)) * CFrame.Angles(0, -a, math.rad(45)), C.neon, M.Neon, ringM)
		decor(b)
		b.CastShadow = false
		tag(b, "TowerGlow")
	end
	ringM.PrimaryPart = ringM:FindFirstChildOfClass("Part")
	ringM:SetAttribute("Center", orbC)
	-- energy beams from the deck to the core
	local att0 = Instance.new("Attachment")
	att0.Name = "CoreAtt"
	att0.Parent = core
	for q = 0, 3 do
		local a = q * math.pi / 2 + math.pi / 4
		local pad = part("BeamPad", Vector3.new(1.6, 0.6, 1.6), CFrame.new(math.cos(a) * 9.5, deckY + 1.3, math.sin(a) * 9.5), C.neon, M.Neon, m)
		decor(pad)
		tag(pad, "TowerGlow")
		local att1 = Instance.new("Attachment")
		att1.Parent = pad
		local beam = Instance.new("Beam")
		beam.Name = "Energy"
		beam.Attachment0 = att1
		beam.Attachment1 = att0
		beam.Width0 = 0.9
		beam.Width1 = 0.4
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.25)
		beam.Color = ColorSequence.new(C.neon)
		beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 3
		beam.TextureSpeed = 2
		beam.Parent = pad
		tag(beam, "TowerBeam")
	end
	-- lightning rod
	cyl("Rod", 8, 0.5, orbC + Vector3.new(0, 14, 0), C.trim, M.Metal, m)
	local tip = ball("RodTip", Vector3.one * 1.3, CFrame.new(orbC + Vector3.new(0, 18.4, 0)), C.neon, M.Neon, m)
	decor(tip)
	tag(tip, "TowerGlow")
	-- snow on the deck and collars (winter)
	local snowDeck = cyl("SnowDeck", 0.5, 23.6, Vector3.new(0, deckY + 1.25, 0), C.snow, M.Snow, m)
	only(snowDeck, "Winter")
	local snowStep = cyl("SnowStep", 0.4, 35.6, base + Vector3.new(0, 3, 0), C.snow, M.Snow, m)
	only(snowStep, "Winter")
	-- flag on the deck
	return m
end

-- waving flag: pole + 5 cloth strips (WeatherWorld swings the strips)
local function flag(at: Vector3, color: Color3, parent: Instance, height: number?)
	local h = height or 12
	local m = model("Flag", parent)
	cyl("Pole", h, 0.5, at + Vector3.new(0, h / 2, 0), C.trim, M.Metal, m)
	ball("Knob", Vector3.one * 0.9, CFrame.new(at + Vector3.new(0, h + 0.3, 0)), C.warm, M.SmoothPlastic, m)
	for i = 1, 5 do
		local s = part("Strip" .. i, Vector3.new(1.2, 3, 0.15), CFrame.new(at + Vector3.new(0.6 + (i - 1) * 1.2 + 0.3, h - 1.8, 0)), if i % 2 == 0 then color:Lerp(Color3.new(1, 1, 1), 0.25) else color, M.Fabric, m)
		decor(s)
		s.CastShadow = false
	end
	m:SetAttribute("Base", at + Vector3.new(0, h - 1.8, 0))
	tag(m, "Flag")
	return m
end

-- ------------------------------------------------------------------ houses
local function house(at: Vector3, facing: Vector3, variant: string, parent: Instance, name: string)
	local m = kitModel(variant, CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z)), 1.15, parent)
	m.Name = name
	local glow = m:FindFirstChild("Glow") :: BasePart?
	if glow then
		local pl = Instance.new("PointLight")
		pl.Color = C.warm
		pl.Range = 14
		pl.Brightness = 0.5
		pl.Shadows = false
		pl.Parent = glow
	end
	return m
end

local function bench(at: Vector3, facing: Vector3, parent: Instance)
	local m = model("Bench", parent)
	local cf = CFrame.lookAt(at, at + facing)
	part("Seat", Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.6, 0), C.wood, M.Wood, m)
	part("Back", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.6, 0.75) * CFrame.Angles(math.rad(-10), 0, 0), C.wood, M.Wood, m)
	for side = -1, 1, 2 do
		part("Leg", Vector3.new(0.4, 1.6, 1.4), cf * CFrame.new(side * 2.1, 0.8, 0), C.trim, M.Metal, m)
	end
	local snow = part("Snow", Vector3.new(5, 0.25, 1.5), cf * CFrame.new(0, 1.92, 0), C.snow, M.Snow, m)
	only(snow, "Winter")
end

local function fountain(at: Vector3, parent: Instance, r: number?)
	local R = r or 8
	local m = model("Fountain", parent)
	cyl("Basin", 1.6, R * 2, at + Vector3.new(0, 0.8, 0), C.stone, M.SmoothPlastic, m)
	local water = cyl("Water", 0.3, R * 2 - 1.4, at + Vector3.new(0, 1.55, 0), hex("5CC8F0"), M.Glass, m)
	water.Transparency = 0.25
	decor(water)
	tag(water, "FountainWater")
	cyl("Column", 4, 2, at + Vector3.new(0, 3, 0), C.stone, M.SmoothPlastic, m)
	cyl("Bowl", 0.8, 5, at + Vector3.new(0, 5.2, 0), C.stone, M.SmoothPlastic, m)
	local spout = part("Spout", Vector3.new(1, 1, 1), CFrame.new(at + Vector3.new(0, 6, 0)), C.stone, M.SmoothPlastic, m)
	decor(spout)
	spout.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Name = "Spray"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(hex("E6F8FF"))
	e.Rate = 30
	e.Lifetime = NumberRange.new(0.8, 1.1)
	e.Speed = NumberRange.new(9, 12)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, -24, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = spout
	tag(e, "FountainSpray")
	local ice = cyl("Ice", 0.35, R * 2 - 1.4, at + Vector3.new(0, 1.62, 0), hex("DDF3FF"), M.Ice, m)
	only(ice, "Winter")
	return m
end

-- ------------------------------------------------------------------ waterfalls
local function waterfall(name: string, top: Vector3, bottomY: number, width: number, facing: Vector3, parent: Instance)
	local m = model(name, parent)
	local h = top.Y - bottomY
	local cf = CFrame.lookAt(Vector3.new(top.X, bottomY + h / 2, top.Z), Vector3.new(top.X, bottomY + h / 2, top.Z) + facing)
	for layer = 0, 1 do
		local sheet = part("Sheet", Vector3.new(width - layer * 2, h, 0.4), cf * CFrame.new(0, 0, -layer * 0.6), if layer == 0 then hex("7FD3FF") else hex("C8F0FF"), M.SmoothPlastic, m)
		sheet.Transparency = if layer == 0 then 0.15 else 0.45
		decor(sheet)
		sheet.CastShadow = false
		local tex = Instance.new("Texture")
		tex.Texture = "rbxasset://textures/particles/smoke_main.dds"
		tex.Face = Enum.NormalId.Front
		tex.StudsPerTileU = 6
		tex.StudsPerTileV = 10
		tex.Transparency = 0.35
		tex.Color3 = Color3.new(1, 1, 1)
		tex.Parent = sheet
		tag(sheet, "Waterfall")
		sheet:SetAttribute("Speed", 14 + layer * 6)
	end
	local lip = part("Lip", Vector3.new(width + 1, 1, 1.6), cf * CFrame.new(0, h / 2, 0), hex("E8FAFF"), M.SmoothPlastic, m)
	decor(lip)
	lip.Transparency = 0.2
	local foot = part("Foam", Vector3.new(width, 1, 4), cf * CFrame.new(0, -h / 2 + 0.5, -2), Color3.new(1, 1, 1), M.SmoothPlastic, m)
	foot.Transparency = 1
	decor(foot)
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1))
	mist.Rate = 18
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(3, 6)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	mist.Parent = foot
	tag(mist, "WaterfallMist")
	-- frozen look (winter): an ice sheet in front
	local ice = part("IceSheet", Vector3.new(width + 0.5, h, 0.6), cf * CFrame.new(0, 0, -1.2), hex("DDF3FF"), M.Ice, m)
	only(ice, "Winter")
	ice:SetAttribute("BaseT", 0.1)
	return m
end

-- find where the cliff edge (lip) is along a line, from low ground toward high ground
local function findLip(x: number, zFrom: number, zTo: number, step: number): (Vector3, number)
	local prevY = groundAt(x, zFrom)
	local z = zFrom
	while (step > 0 and z <= zTo) or (step < 0 and z >= zTo) do
		local y = groundAt(x, z)
		if y > prevY + 10 then
			return Vector3.new(x, y, z), prevY
		end
		prevY = y
		z += step
	end
	return Vector3.new(x, prevY, z), prevY
end

-- ------------------------------------------------------------------ gems
local function gem(id: number, at: Vector3, parent: Instance)
	local p = part("SkyGem" .. id, Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), hex("7FF3FF"), M.Neon, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p:SetAttribute("GemId", id)
	local l = Instance.new("PointLight")
	l.Color = hex("7FF3FF")
	l.Range = 10
	l.Brightness = 1.5
	l.Parent = p
	local s = Instance.new("ParticleEmitter")
	s.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	s.Rate = 6
	s.Lifetime = NumberRange.new(0.8, 1.4)
	s.Speed = NumberRange.new(1, 2)
	s.SpreadAngle = Vector2.new(180, 180)
	s.LightEmission = 1
	s.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	s.Parent = p
	tag(p, "Gem")
	return p
end

-- ------------------------------------------------------------------ build
function B.build(log: ((string) -> ())?)
	local function say(s: string)
		if log then
			log(s)
		end
	end
	local map = Workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	-- tower and plaza --------------------------------------------------------
	local towerF = folder("WeatherTower", map)
	buildTower(towerF)
	say("tower")
	local plaza = folder("Plaza", map)
	local lamps = folder("Lamps", map)
	local boards = folder("Boards", map)
	local themeProps = folder("ThemeProps", map)
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		lamp(Vector3.new(math.cos(a) * 34, 1, math.sin(a) * 34), lamps)
	end
	for i, a in { 45, 135, 225, 315 } do
		local r = math.rad(a)
		local at = Vector3.new(math.cos(r) * 27, 1, math.sin(r) * 27)
		if i <= 2 then -- two boards on the south side, facing out toward players coming in
			board("PlazaBoard" .. i, at, at, boards, if i % 2 == 0 then "tips" else "report")
		end
		bench(Vector3.new(math.cos(r + 0.32) * 31, 1, math.sin(r + 0.32) * 31), -at, plaza)
	end
	-- planters (bush + flowers) around the tower
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local at = Vector3.new(math.cos(a) * 21, 1, math.sin(a) * 21)
		if i % 2 == 1 then
			cyl("Planter", 1.4, 6, at + Vector3.new(0, 0.7, 0), C.stoneDark, M.SmoothPlastic, plaza)
			kitPiece("Bush", at + Vector3.new(0, 1.4, 0), 1.6, a, plaza)
			kitPiece("Flowers", at + Vector3.new(0, 1.4, 1.2), 1.1, a, plaza)
		end
	end
	-- puddles (storm)
	for i = 1, 7 do
		local a = rng:NextNumber() * 6.28
		local r = rng:NextNumber(14, 34)
		local p = cyl("Puddle", 0.1, rng:NextNumber(3, 6), Vector3.new(math.cos(a) * r, 1.06, math.sin(a) * r), hex("3B4C7A"), M.Glass, themeProps)
		p.Reflectance = 0.4
		only(p, "Storm")
		p:SetAttribute("BaseT", 0.3)
	end
	flag(Vector3.new(-6, 49.8, -6), hex("4FB8FF"), towerF, 7)
	say("plaza")

	-- leaderboard hub: paved ring around the tower, four boards, fountains, benches, trees ------
	local hub = folder("Hub", map)
	local floor = cyl("HubFloor", 0.3, 112, Vector3.new(0, 0.98, 0), hex("C3BCD3"), M.SmoothPlastic, hub)
	floor.CastShadow = false
	tag(floor, "HubFloor")
	-- ring of darker tiles at r = 40 and a curb at the edge
	for i = 0, 47 do
		local a = i * math.pi * 2 / 48
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		part("RingTile", Vector3.new(4.9, 0.32, 3), CFrame.lookAt(dir * 40 + Vector3.new(0, 1.02, 0), dir * 80 + Vector3.new(0, 1.02, 0)), if i % 2 == 0 then hex("9F98B6") else hex("8F88A8"), M.SmoothPlastic, hub)
		local isPath = (i % 12 == 0) or (i % 12 == 1) or (i % 12 == 11)
		if not isPath then
			part("Curb", Vector3.new(7.2, 0.9, 1.4), CFrame.lookAt(dir * 56 + Vector3.new(0, 1.2, 0), dir * 80 + Vector3.new(0, 1.2, 0)), hex("9C95B5"), M.SmoothPlastic, hub)
		end
	end
	for _, b in { { "Gust", hex("7AD7FF"), 225 }, { "Coins", hex("FFD23F"), 315 }, { "Clouds", hex("F2F4FA"), 135 }, { "Upgrades", hex("B98CFF"), 45 } } do
		local a = math.rad(b[3])
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		leaderboard(b[1], b[2], dir * 47 + Vector3.new(0, 1, 0), -dir, hub)
		-- benches facing the board, lamps and flower beds beside it
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for sgn = -1, 1, 2 do
			bench(dir * 38 + side * sgn * 4 + Vector3.new(0, 1, 0), dir, hub)
			kitPiece("Flowers", dir * 50 + side * sgn * 13 + Vector3.new(0, 1, 0), 1.5, rng:NextNumber() * 6.28, hub)
			kitPiece("Bush", dir * 52 + side * sgn * 16 + Vector3.new(0, 1, 0), 1.5, rng:NextNumber() * 6.28, hub)
		end
	end
	-- two fountains flanking the tower (east / west)
	fountain(Vector3.new(31, 1, 0), hub, 5)
	fountain(Vector3.new(-31, 1, 0), hub, 5)
	-- trees ring just outside the floor, clear of the four paths
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		roundTree(dir * 62 + Vector3.new(0, groundAt(dir.X * 62, dir.Z * 62), 0), 1.05, hub)
		grassTuft(dir * 59 + Vector3.new(2, 1, 0), hub)
	end
	for _, a in { 0, 90, 180, 270 } do
		local r = math.rad(a)
		local dir = Vector3.new(math.cos(r), 0, math.sin(r))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		flag(dir * 57 + side * 7 + Vector3.new(0, 1, 0), hex("4FB8FF"), hub, 9)
		flag(dir * 57 - side * 7 + Vector3.new(0, 1, 0), hex("FFD23F"), hub, 9)
	end
	say("hub")

	-- path lamps ---------------------------------------------------------------
	local function lampLine(from: Vector3, to: Vector3, every: number, side: Vector3)
		local d = (to - from)
		local n = math.floor(d.Magnitude / every)
		for i = 0, n do
			local p = from + d.Unit * (i * every) + side * (if i % 2 == 0 then 1 else -1)
			local y = groundAt(p.X, p.Z)
			lamp(Vector3.new(p.X, y, p.Z), lamps)
		end
	end
	lampLine(Vector3.new(48, 0, 0), Vector3.new(196, 0, 0), 26, Vector3.new(0, 0, 8))
	lampLine(Vector3.new(0, 0, 48), Vector3.new(0, 0, 128), 26, Vector3.new(8, 0, 0))
	lampLine(Vector3.new(0, 0, -48), Vector3.new(0, 0, -100), 26, Vector3.new(8, 0, 0))
	lampLine(Vector3.new(-48, 0, 0), Vector3.new(-112, 0, 0), 26, Vector3.new(0, 0, 8))
	for x = -96, 96, 32 do
		lamp(Vector3.new(x + 16, 1, 133), lamps)
	end
	say("lamps")

	-- footbridge over the river (north path) -----------------------------------
	local foot = folder("Footbridges", map)
	for _, x in { 0, 96 } do
		local m = model("Footbridge", foot)
		for i = -8, 8 do
			part("Plank", Vector3.new(7, 0.5, 1.1), CFrame.new(x, 1.3 + math.cos(i / 8 * 1.4) * 1.2, -116 + i * 1.2), C.wood, M.WoodPlanks, m)
		end
		for side = -1, 1, 2 do
			part("Rail", Vector3.new(0.4, 0.4, 20), CFrame.new(x + side * 3.4, 3.6, -116), C.woodDark, M.Wood, m)
			for i = -2, 2 do
				part("Post", Vector3.new(0.5, 3, 0.5), CFrame.new(x + side * 3.4, 2.3, -116 + i * 4.8), C.woodDark, M.Wood, m)
			end
		end
	end

	-- village (west) -------------------------------------------------------------
	local village = folder("Village", map)
	house(Vector3.new(-72, 1, -24), Vector3.new(0, 0, 1), "House_A", village, "HouseRed")
	house(Vector3.new(-104, 1, -26), Vector3.new(0.3, 0, 1), "House_B", village, "HouseBlue")
	house(Vector3.new(-78, 1, 26), Vector3.new(0, 0, -1), "House_C", village, "HouseGreen")
	house(Vector3.new(-108, 1, 28), Vector3.new(0.3, 0, -1), "House_D", village, "HouseOrange")
	-- village dressing: flower beds by the doors, a fir behind each pair
	for _, d in { { -72, -14 }, { -104, -16 }, { -78, 16 }, { -108, 18 } } do
		kitPiece("Flowers", Vector3.new(d[1] + 5, 1, d[2]), 1.2, rng:NextNumber() * 6.28, village)
		kitPiece("Bush", Vector3.new(d[1] - 6, 1, d[2]), 1.4, rng:NextNumber() * 6.28, village)
	end
	pine(Vector3.new(-88, 1, -40), 1.1, village)
	pine(Vector3.new(-120, 1, -38), 0.9, village)
	pine(Vector3.new(-92, 1, 42), 1.0, village)
	roundTree(Vector3.new(-124, 1, 40), 1, village)
	fountain(Vector3.new(-90, 1, 0), village, 7)
	flag(Vector3.new(-60, 1, 10), hex("FF6F90"), village)
	flag(Vector3.new(-60, 1, -10), hex("FFD23F"), village)
	bench(Vector3.new(-90, 1, 11), Vector3.new(0, 0, -1), village)
	bench(Vector3.new(-90, 1, -11), Vector3.new(0, 0, 1), village)
	board("VillageBoard", Vector3.new(-122, 1, 8), Vector3.new(1, 0, -0.2), boards, "tips")
	-- weather station: rain gauge + anemometer
	local station = model("WeatherStation", village)
	cyl("Pole", 10, 0.5, Vector3.new(-64, 6, -44), C.trim, M.Metal, station)
	local rotor = model("Anemometer", station)
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		part("Arm", Vector3.new(3, 0.25, 0.25), CFrame.new(-64, 11.2, -44) * CFrame.Angles(0, a, 0) * CFrame.new(1.5, 0, 0), C.trim, M.Metal, rotor)
		ball("Cup", Vector3.one * 0.9, CFrame.new(-64, 11.2, -44) * CFrame.Angles(0, a, 0) * CFrame.new(3, 0, 0), hex("FF6F90"), M.SmoothPlastic, rotor)
	end
	rotor:SetAttribute("Speed", 4)
	rotor:SetAttribute("Center", Vector3.new(-64, 11.2, -44))
	tag(rotor, "Spin")
	cyl("RainGauge", 3, 1.4, Vector3.new(-60, 2.5, -44), hex("D6EEFF"), M.Glass, station)
	say("village")

	-- east islet (old spawn island): a quiet lookout with a fountain - no gate, no spawn -------
	local spawnF = folder("SpawnIsland", map)
	local SI = Gen.SPAWN_ISLAND
	fountain(Vector3.new(SI.X + 6, 1, 0), spawnF, 6)
	for _, p in { Vector3.new(SI.X - 6, 1, 18), Vector3.new(SI.X - 6, 1, -18), Vector3.new(SI.X + 16, 1, 16), Vector3.new(SI.X + 16, 1, -16) } do
		lamp(p, lamps)
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		bench(Vector3.new(SI.X + 6 + math.cos(a) * 11, 1, math.sin(a) * 11), -Vector3.new(math.cos(a), 0, math.sin(a)), spawnF)
	end
	board("SpawnBoard", Vector3.new(SI.X - 4, 1, -20), Vector3.new(-0.8, 0, 1), boards, "howto")
	flag(Vector3.new(SI.X + 4, 1, 22), hex("7A5CFF"), spawnF)
	flag(Vector3.new(SI.X + 4, 1, -22), hex("4FB8FF"), spawnF)
	for _, fp in { Vector3.new(SI.X - 12, 1, 8), Vector3.new(SI.X - 12, 1, -8), Vector3.new(SI.X + 18, 1, 4) } do
		kitPiece("Flowers", fp, 1.3, rng:NextNumber() * 6.28, spawnF)
		kitPiece("Bush", fp + Vector3.new(2.5, 0, 2), 1.2, rng:NextNumber() * 6.28, spawnF)
	end
	-- fallback spawn (players without an island) sits on the hub's south side, facing the tower;
	-- everyone else spawns on their own island (Plots.spawnCFrame)
	local sp = Workspace:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if sp then
		sp.CFrame = CFrame.new(0, 1.1, 62) * CFrame.Angles(0, 0, 0)
		sp.Size = Vector3.new(10, 0.4, 10)
		sp.Transparency = 1
		sp.CanCollide = false
		sp.Neutral = true
		sp.Duration = 0
	end
	-- grand bridge from the island's east shore to the spawn island
	local bridge = folder("GrandBridge", map)
	local x0 = 188
	while x0 < SI.X - 30 do
		local y = groundAt(x0, 0)
		if y < -3 then
			break
		end
		x0 += 2
	end
	x0 -= 8
	local x1 = SI.X - 21
	local deckY = 1.2
	local width = 12
	local n = math.floor((x1 - x0) / 1.3)
	for i = 0, n do
		local x = x0 + i * 1.3
		local p = part("Plank", Vector3.new(1.15, 0.5, width + rng:NextNumber(-0.3, 0.3)), CFrame.new(x, deckY, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-1, 1))), if i % 3 == 0 then C.woodDark:Lerp(C.wood, 0.5) else C.wood, M.WoodPlanks, bridge)
		p.CastShadow = true
	end
	for side = -1, 1, 2 do
		part("Beam", Vector3.new(x1 - x0 + 2, 0.8, 0.8), CFrame.new((x0 + x1) / 2, deckY - 0.5, side * (width / 2 - 0.4)), C.woodDark, M.Wood, bridge)
		part("Rope", Vector3.new(x1 - x0, 0.35, 0.35), CFrame.new((x0 + x1) / 2, deckY + 3.6, side * (width / 2 + 0.2)), hex("D9C08A"), M.Fabric, bridge)
		local px = x0
		while px <= x1 do
			part("Post", Vector3.new(0.9, 5, 0.9), CFrame.new(px, deckY + 1.4, side * (width / 2 + 0.2)), C.woodDark, M.Wood, bridge)
			local pile = cyl("Pile", deckY - Gen.SEA_Y + 10, 1.4, Vector3.new(px, (deckY + Gen.SEA_Y - 10) / 2, side * (width / 2 - 0.6)), C.woodDark, M.Wood, bridge)
			pile.CastShadow = false
			local lan = part("Lantern", Vector3.new(0.9, 1, 0.9), CFrame.new(px, deckY + 4.4, side * (width / 2 + 0.2)), C.warm, M.Neon, bridge)
			decor(lan)
			tag(lan, "Glow")
			px += 10
		end
	end
	say("spawn + bridge")

	-- waterfalls ---------------------------------------------------------------
	local falls = folder("Waterfalls", map)
	do
		local lip, low = findLip(Gen.WATERFALL_X, -132, -200, -1)
		waterfall("CanyonFall", lip + Vector3.new(0, 0, 0.8), math.max(low, 0), 13, Vector3.new(0, 0, 1), falls)
		-- second fall from the east plateau into the sea
		local ex = 0
		for x = 210, 160, -1 do
			if groundAt(x, -70) > 8 then
				ex = x
				break
			end
		end
		if ex ~= 0 then
			local topY = groundAt(ex - 3, -70)
			waterfall("SeaFall", Vector3.new(ex + 1.5, topY, -70), Gen.SEA_Y, 9, Vector3.new(1, 0, 0), falls)
		end
		-- third: north mountain into tier 2 (left of the canyon)
		local lip3, low3 = findLip(-110, -150, -215, -1)
		if lip3.Y - low3 > 12 then
			waterfall("MountainFall", lip3 + Vector3.new(0, 0, 0.8), low3, 8, Vector3.new(0, 0, 1), falls)
		end
	end
	say("waterfalls")

	-- nature ---------------------------------------------------------------------
	local nature = folder("Nature", map)
	local function freeSpot(x: number, z: number): boolean
		if Gen.pathAt(x, z) then
			return false
		end
		if Gen.riverAt(x, z) or waterAt(x, z) then
			return false
		end
		if x > -130 and x < -50 and z > -50 and z < 50 then
			return false -- village
		end
		if math.abs(x) < 112 and z > 122 then
			return false -- plot bridges strip
		end
		if math.sqrt(x * x + z * z) < 66 then
			return false -- hub
		end
		local y = groundAt(x, z)
		return y > Gen.SEA_Y + 2
	end
	local placed = 0
	-- clusters: centre, radius, count, kind
	local clusters = {
		{ -165, -60, 26, 7, "round" }, { -175, 40, 24, 6, "pine" }, { -160, 100, 20, 5, "round" },
		{ 165, -80, 26, 7, "pine" }, { 175, 60, 24, 6, "round" }, { 160, 108, 18, 4, "pine" },
		{ -110, -150, 30, 8, "pine" }, { 60, -150, 34, 9, "pine" }, { 120, -175, 26, 6, "pine" },
		{ -60, -220, 40, 8, "pine" }, { 40, -235, 40, 8, "pine" }, { -150, -200, 30, 6, "pine" },
		{ 104, -60, 14, 3, "round" }, { -104, 92, 14, 3, "round" }, { 100, 100, 12, 3, "round" },
		{ -100, -96, 14, 3, "round" }, { 60, -104, 10, 2, "round" }, { -150, 140, 14, 3, "palm" },
		{ 150, 140, 14, 3, "palm" }, { 200, 34, 10, 2, "palm" }, { 200, -34, 10, 2, "palm" },
	}
	for _, c in clusters do
		for _ = 1, c[4] do
			local a = rng:NextNumber() * 6.28
			local r = c[3] * math.sqrt(rng:NextNumber())
			local x, z = c[1] + math.cos(a) * r, c[2] + math.sin(a) * r
			if freeSpot(x, z) then
				local y = groundAt(x, z)
				local s = rng:NextNumber(0.8, 1.25)
				if c[5] == "pine" then
					pine(Vector3.new(x, y - 0.3, z), s * 1.15, nature)
				elseif c[5] == "palm" then
					palm(Vector3.new(x, y - 0.3, z), s, nature)
				else
					roundTree(Vector3.new(x, y, z), s, nature)
				end
				placed += 1
			end
		end
	end
	-- islets: a palm or pine and rocks
	for _, il in Gen.ISLETS do
		if not il.flat then
			for k = 1, 2 do
				local a = rng:NextNumber() * 6.28
				local x, z = il.x + math.cos(a) * il.r * 0.3, il.z + math.sin(a) * il.r * 0.3
				local y = groundAt(x, z)
				if y > Gen.SEA_Y + 2 then
					if k == 1 then
						palm(Vector3.new(x, y - 0.3, z), rng:NextNumber(0.9, 1.2), nature)
					else
						rock(Vector3.new(x, y, z), rng:NextNumber(2, 4), nature)
					end
				end
			end
		end
	end
	-- secret islet
	do
		local s = Gen.SECRET_ISLET
		palm(Vector3.new(s.X - 4, 0.7, s.Z + 3), 1.1, nature)
		palm(Vector3.new(s.X + 3, 0.7, s.Z - 4), 0.9, nature)
	end
	-- spawn island trees
	for _, p in { Vector3.new(SI.X + 20, 1, 24), Vector3.new(SI.X + 22, 1, -22), Vector3.new(SI.X + 8, 1, 26) } do
		palm(p - Vector3.new(0, 0.3, 0), 1.1, nature)
	end
	-- rocks, bushes, flowers in the meadow (sparse in play space, denser at the edges)
	for _ = 1, 140 do
		local x, z = rng:NextNumber(-200, 200), rng:NextNumber(-240, 150)
		if freeSpot(x, z) then
			local y = groundAt(x, z)
			local edge = math.max(math.abs(x) / 120, math.abs(z) / 110)
			local roll = rng:NextNumber()
			if edge < 0.8 and roll < 0.55 then
				continue -- keep the herding field open
			end
			if roll < 0.35 then
				kitPiece("Flowers", Vector3.new(x, y, z), rng:NextNumber(1, 1.6), rng:NextNumber() * 6.28, nature)
			elseif roll < 0.7 then
				kitPiece("Bush", Vector3.new(x, y, z), rng:NextNumber(1.3, 2.2), rng:NextNumber() * 6.28, nature)
			else
				rock(Vector3.new(x, y, z), rng:NextNumber(1.5, 3.5), nature)
			end
		end
	end
	-- cliff-foot boulders along the tiers
	for _ = 1, 26 do
		local x = rng:NextNumber(-190, 190)
		local z = Gen.TIER1_Z + rng:NextNumber(4, 14)
		if freeSpot(x, z) then
			rock(Vector3.new(x, groundAt(x, z), z), rng:NextNumber(3, 6), nature)
		end
	end
	-- grass tufts: small clumps around trees and along the cliff feet, never in the open field
	for _ = 1, 220 do
		local x, z = rng:NextNumber(-200, 200), rng:NextNumber(-250, 160)
		local edge = math.max(math.abs(x) / 120, math.abs(z) / 110)
		if edge > 0.75 and freeSpot(x, z) then
			local y = groundAt(x, z)
			for k = 1, rng:NextInteger(2, 4) do
				grassTuft(Vector3.new(x + rng:NextNumber(-2.5, 2.5), y, z + rng:NextNumber(-2.5, 2.5)), nature)
			end
		end
	end
	say("nature " .. placed)

	-- desert extras: cacti (only in the Desert theme) -------------------------------
	local desert = folder("Desert", themeProps)
	for _ = 1, 26 do
		local x, z = rng:NextNumber(-180, 180), rng:NextNumber(-140, 130)
		if freeSpot(x, z) and (math.abs(x) > 60 or math.abs(z) > 60) then
			cactus(Vector3.new(x, groundAt(x, z) - 0.2, z), rng:NextNumber(0.9, 1.5), desert)
		end
	end
	-- winter extras: snowmen
	local winter = folder("Winter", themeProps)
	for _, p in { Vector3.new(-84, 1, 14), Vector3.new(SI.X - 2, 1, 14), Vector3.new(14, 1, -70) } do
		local m = model("Snowman", winter)
		for k, s in { 4, 3, 2.2 } do
			local b = ball("Snow" .. k, Vector3.one * s, CFrame.new(p + Vector3.new(0, ({ 2, 5.2, 7.6 })[k], 0)), C.snow, M.Snow, m)
			only(b, "Winter")
		end
		local nose = part("Nose", Vector3.new(0.3, 0.3, 1), CFrame.new(p + Vector3.new(0, 7.6, -1.4)), hex("FF8A2E"), M.SmoothPlastic, m)
		only(nose, "Winter")
	end

	-- wind turbines on the east plateau -------------------------------------------
	local turb = folder("Turbines", map)
	for i, z in { -40, 70 } do
		local x = 196
		local y = groundAt(x, z)
		local m = model("Turbine" .. i, turb)
		cyl("Tower", 22, 1.4, Vector3.new(x, y + 11, z), C.white, M.SmoothPlastic, m)
		part("Nacelle", Vector3.new(3, 2, 2), CFrame.new(x, y + 22.5, z), C.white, M.SmoothPlastic, m)
		local rotor = model("Rotor", m)
		local hub = Vector3.new(x - 1.8, y + 22.5, z)
		ball("Hub", Vector3.one * 1.4, CFrame.new(hub), C.trim, M.SmoothPlastic, rotor)
		for k = 0, 2 do
			local b = part("Blade", Vector3.new(0.3, 9, 1), CFrame.new(hub) * CFrame.Angles(k * math.pi * 2 / 3, 0, 0) * CFrame.new(0, 4.6, 0), C.white, M.SmoothPlastic, rotor)
			decor(b)
		end
		rotor:SetAttribute("Speed", 1.6)
		rotor:SetAttribute("Center", hub)
		rotor:SetAttribute("Axis", "X")
		tag(rotor, "Spin")
	end

	-- gems -------------------------------------------------------------------------
	local gems = folder("Gems", map)
	gem(1, Gen.CAVE_CENTER - Vector3.new(0, 5, 4), gems)
	gem(2, Gen.SECRET_ISLET + Vector3.new(0, -0.2, 0), gems)
	do
		local best, bp = -1e9, Vector3.zero
		for x = -200, 200, 8 do
			for z = -340, -190, 8 do
				local y = groundAt(x, z)
				if y > best then
					best, bp = y, Vector3.new(x, y, z)
				end
			end
		end
		gem(3, bp, gems) -- the highest peak
	end
	gem(4, Vector3.new(-112, 1, -42), gems) -- behind the blue house
	gem(5, Vector3.new(SI.X + 26, 1, 0), gems) -- behind the spawn fountain
	do
		local x, z = 186, 112
		gem(6, Vector3.new(x, groundAt(x, z), z), gems) -- east plateau, among the trees
	end

	-- big sky clouds (drift slowly, cast moving shadows) ------------------------------
	local sky = folder("SkyClouds", map)
	for i = 1, 9 do
		local c = (kit:WaitForChild("CloudPuff") :: MeshPart):Clone()
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = true
		local s = rng:NextNumber(12, 20)
		c.Size *= s
		c.CFrame = CFrame.new(rng:NextNumber(-420, 420), rng:NextNumber(150, 190), rng:NextNumber(-420, 420)) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0)
		c.Parent = sky
		tag(c, "SkyCloud")
	end
	say("done")
end

return B
