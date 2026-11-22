--!strict
-- WeatherWorld: renders the map's weather on this client (server decides, see World script).
--   * blends lighting, atmosphere, clouds, colour grade, terrain colours, water, ocean, foliage
--     tint and sounds between the looks in ReplicatedStorage.PocketWeather.Themes whenever the
--     workspace attribute Theme changes (Default / Winter / Desert / Storm)
--   * shows the theme-only props (tags OnlyWinter / OnlyDesert / OnlyStorm: snow caps, cacti...)
--   * camera-local weather particles (rain + splashes, snow, sand sheets, sunny motes)
--   * lightning bolts + flash + thunder from Remotes.Lightning (server schedules them)
--   * map life: Weather Tower orb (symbol, colour, orbit ring), turbines, flags, waterfalls,
--     drifting sky clouds, birds, gems, info boards, NPC speech bubbles, gem toast
-- Everything here is local; StreamingEnabled is on, so tagged parts are picked up as they stream in.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("PocketWeather")
local Themes = require(shared:WaitForChild("Themes") :: ModuleScript) :: { [string]: any }
local Icons = require(shared:WaitForChild("Icons") :: ModuleScript) :: { [string]: string }
local Config = require(shared:WaitForChild("Config") :: ModuleScript)
local Kit = require(shared:WaitForChild("UiKit") :: ModuleScript)
local remotes = shared:WaitForChild("Remotes")

local player = Players.LocalPlayer
local terrain = Workspace.Terrain

local TEX = {
	raindrop = "rbxassetid://134727482209288",
	snowflake = "rbxassetid://107414217750523",
	ring = "rbxassetid://18682826321",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
}
local SND = {
	rain = "rbxassetid://9112855479", -- Pro Sound Effects: Rain On Water 3
	wind = "rbxassetid://9125742262", -- Pro Sound Effects: airy windy whoosh loop
	birds = "rbxassetid://9112750044", -- Pro Sound Effects: Birds Quiet And Tranquil 1
	thunder = "rbxassetid://9113169432", -- Pro Sound Effects: Artillery Distant 2 (thunder use)
	waterfall = "rbxassetid://9118187543", -- Pro Sound Effects: River Water 1
}

-- ======================================================================= helpers
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function mul(a: Color3, b: Color3): Color3
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end
local function tween(o: Instance, t: number, props: { [string]: any })
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props):Play()
end
-- run fn for every instance with the tag, now and when it streams in later
local function tagged(tag: string, fn: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(fn)
	for _, i in CollectionService:GetTagged(tag) do
		task.spawn(fn, i)
	end
end
local function lightObj(class: string): Instance
	local o = Lighting:FindFirstChildOfClass(class)
	if not o then
		o = Instance.new(class)
		o.Parent = Lighting
	end
	return o :: Instance
end

local atmo = lightObj("Atmosphere") :: Atmosphere
local grade = lightObj("ColorCorrectionEffect") :: ColorCorrectionEffect
local bloom = lightObj("BloomEffect") :: BloomEffect
local sunrays = lightObj("SunRaysEffect") :: SunRaysEffect
local flash = Instance.new("ColorCorrectionEffect")
flash.Name = "LightningFlash"
flash.Parent = Lighting
local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
clouds.Parent = terrain

-- ======================================================================= theme blending
type Look = any
local function lerpLook(a: Look, b: Look, t: number): Look
	local terr = {}
	for k, v in b.terrain do
		terr[k] = (a.terrain[k] or v):Lerp(v, t)
	end
	local function n(x: number, y: number): number
		return lerp(x, y, t)
	end
	return {
		clock = n(a.clock, b.clock),
		brightness = n(a.brightness, b.brightness),
		ambient = a.ambient:Lerp(b.ambient, t),
		outdoor = a.outdoor:Lerp(b.outdoor, t),
		specular = n(a.specular, b.specular),
		diffuse = n(a.diffuse, b.diffuse),
		exposure = n(a.exposure, b.exposure),
		atmo = {
			density = n(a.atmo.density, b.atmo.density),
			offset = n(a.atmo.offset, b.atmo.offset),
			color = a.atmo.color:Lerp(b.atmo.color, t),
			decay = a.atmo.decay:Lerp(b.atmo.decay, t),
			glare = n(a.atmo.glare, b.atmo.glare),
			haze = n(a.atmo.haze, b.atmo.haze),
		},
		cc = {
			brightness = n(a.cc.brightness, b.cc.brightness),
			contrast = n(a.cc.contrast, b.cc.contrast),
			saturation = n(a.cc.saturation, b.cc.saturation),
			tint = a.cc.tint:Lerp(b.cc.tint, t),
		},
		bloom = { intensity = n(a.bloom.intensity, b.bloom.intensity), size = n(a.bloom.size, b.bloom.size), threshold = n(a.bloom.threshold, b.bloom.threshold) },
		sunrays = { intensity = n(a.sunrays.intensity, b.sunrays.intensity), spread = n(a.sunrays.spread, b.sunrays.spread) },
		clouds = { cover = n(a.clouds.cover, b.clouds.cover), density = n(a.clouds.density, b.clouds.density), color = a.clouds.color:Lerp(b.clouds.color, t) },
		terrain = terr,
		water = {
			color = a.water.color:Lerp(b.water.color, t),
			transparency = n(a.water.transparency, b.water.transparency),
			wave = n(a.water.wave, b.water.wave),
			speed = n(a.water.speed, b.water.speed),
			reflectance = n(a.water.reflectance, b.water.reflectance),
		},
		ocean = a.ocean:Lerp(b.ocean, t),
		foliage = a.foliage:Lerp(b.foliage, t),
		skyCloud = a.skyCloud:Lerp(b.skyCloud, t),
		orb = a.orb:Lerp(b.orb, t),
		icon = if t < 0.5 then a.icon else b.icon,
		lamps = n(a.lamps, b.lamps),
		wind = a.wind:Lerp(b.wind, t),
		fx = { rain = n(a.fx.rain, b.fx.rain), snow = n(a.fx.snow, b.fx.snow), sand = n(a.fx.sand, b.fx.sand), motes = n(a.fx.motes, b.fx.motes), birds = n(a.fx.birds, b.fx.birds) },
		sound = { rain = n(a.sound.rain, b.sound.rain), wind = n(a.sound.wind, b.sound.wind), birds = n(a.sound.birds, b.sound.birds) },
	}
end

local oceanParts: { BasePart } = {}
local skyClouds: { BasePart } = {}
local lampLights: { PointLight } = {}
local shown: Look = Themes.Default
local function applyLook(l: Look)
	Lighting.ClockTime = l.clock
	Lighting.Brightness = l.brightness
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoor
	Lighting.EnvironmentSpecularScale = l.specular
	Lighting.EnvironmentDiffuseScale = l.diffuse
	Lighting.ExposureCompensation = l.exposure
	atmo.Density, atmo.Offset, atmo.Color, atmo.Decay, atmo.Glare, atmo.Haze = l.atmo.density, l.atmo.offset, l.atmo.color, l.atmo.decay, l.atmo.glare, l.atmo.haze
	grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor = l.cc.brightness, l.cc.contrast, l.cc.saturation, l.cc.tint
	bloom.Intensity, bloom.Size, bloom.Threshold = l.bloom.intensity, l.bloom.size, l.bloom.threshold
	sunrays.Intensity, sunrays.Spread = l.sunrays.intensity, l.sunrays.spread
	clouds.Cover, clouds.Density, clouds.Color = l.clouds.cover, l.clouds.density, l.clouds.color
	for name, col in l.terrain do
		local mat = (Enum.Material :: any)[name]
		if mat then
			terrain:SetMaterialColor(mat, col)
		end
	end
	terrain.WaterColor = l.water.color
	terrain.WaterTransparency = l.water.transparency
	terrain.WaterWaveSize = l.water.wave
	terrain.WaterWaveSpeed = l.water.speed
	terrain.WaterReflectance = l.water.reflectance
	for _, p in oceanParts do
		p.Color = l.ocean
	end
	for _, p in skyClouds do
		p.Color = l.skyCloud
	end
	for _, light in lampLights do
		light.Brightness = l.lamps
	end
	Workspace.GlobalWind = l.wind
	shown = l
end

-- ======================================================================= theme-only props, foliage
local currentTheme = "Default"
local ONLY = { "Winter", "Desert", "Storm" }
local function fadeOnly(p: Instance, theme: string, instant: boolean)
	if not p:IsA("BasePart") then
		return
	end
	local base = p:GetAttribute("BaseT")
	local target = if currentTheme == theme then (if type(base) == "number" then base else 0) else 1
	if instant then
		p.Transparency = target
	else
		tween(p, 2.5, { Transparency = target })
	end
end
for _, theme in ONLY do
	tagged("Only" .. theme, function(p)
		fadeOnly(p, theme, true)
	end)
end

local function tintFoliage(p: Instance, instant: boolean)
	if not p:IsA("BasePart") then
		return
	end
	local base = p:GetAttribute("BaseColor")
	if typeof(base) ~= "Color3" then
		base = p.Color
		p:SetAttribute("BaseColor", base)
	end
	local target = mul(base :: Color3, Themes[currentTheme].foliage)
	if instant then
		p.Color = target
	else
		tween(p, 4, { Color = target })
	end
end
tagged("Foliage", function(p)
	tintFoliage(p, true)
end)

-- hub paving: snowed over in winter, sandy in the desert, wet and dark in storms
local HUB_FLOOR: { [string]: Color3 } = {
	Default = Color3.fromHex("C3BCD3"),
	Winter = Color3.fromHex("EEF3FA"),
	Desert = Color3.fromHex("E2CFA6"),
	Storm = Color3.fromHex("8F89A6"),
}
local function paintHubFloor(p: Instance, instant: boolean)
	if not p:IsA("BasePart") then
		return
	end
	local target = HUB_FLOOR[currentTheme] or HUB_FLOOR.Default
	if instant then
		p.Color = target
	else
		tween(p, 4, { Color = target })
	end
end
tagged("HubFloor", function(p)
	paintHubFloor(p, true)
end)

-- part-built ground (player islands): takes the theme's grass colour
local function paintGround(p: Instance, instant: boolean)
	if not p:IsA("BasePart") then
		return
	end
	local target = Themes[currentTheme].terrain.Grass
	if instant then
		p.Color = target
	else
		tween(p, 4, { Color = target })
	end
end
tagged("ThemeGround", function(p)
	paintGround(p, true)
end)

tagged("Glow", function(p)
	local light = p:FindFirstChildOfClass("PointLight")
	if light then
		table.insert(lampLights, light)
		light.Brightness = shown.lamps
	end
end)
tagged("SkyCloud", function(p)
	if p:IsA("BasePart") then
		table.insert(skyClouds, p)
		p.Color = shown.skyCloud
	end
end)
task.spawn(function()
	local map = Workspace:WaitForChild("Map")
	local function addOcean(c: Instance)
		if c:IsA("BasePart") and string.sub(c.Name, 1, 8) == "OceanFar" then
			table.insert(oceanParts, c)
			c.Color = shown.ocean
		end
	end
	map.ChildAdded:Connect(addOcean)
	for _, c in map:GetChildren() do
		addOcean(c)
	end
end)

-- ======================================================================= weather tower orb
type Spinner3 = { part: BasePart, offset: CFrame, tilt: number, speed: number }
type Orb = { core: BasePart, light: PointLight?, icon: ImageLabel?, sparkle: ParticleEmitter?, ring: { BasePart }, offsets: { CFrame }, center: Vector3, symbols: { [string]: { BasePart } }, energy: { Spinner3 } }
local orbs: { Orb } = {}
local function paintOrb(o: Orb, instant: boolean)
	local look = Themes[currentTheme]
	if o.icon then
		o.icon.Image = Icons[look.icon] or ""
	end
	-- the globe's 3D weather symbol: sun / snowflake / lightning / wind
	for theme, parts in o.symbols do
		local target = if theme == currentTheme then 0 else 1
		for _, sp in parts do
			if instant then
				sp.Transparency = target
			else
				tween(sp, 1.2, { Transparency = target })
			end
		end
	end
	if instant then
		o.core.Color = look.orb
	else
		tween(o.core, 3, { Color = look.orb })
	end
	if o.light then
		tween(o.light, 3, { Color = look.orb })
	end
	if o.sparkle then
		o.sparkle.Color = ColorSequence.new(look.orb:Lerp(Color3.new(1, 1, 1), 0.5))
	end
	for _, b in o.ring do
		tween(b, 3, { Color = look.orb:Lerp(Color3.fromRGB(95, 216, 255), 0.4) })
	end
end
tagged("TowerOrb", function(m)
	local core = m:WaitForChild("Core", 10)
	local ringM = m:WaitForChild("OrbitRing", 10)
	if not core or not core:IsA("BasePart") or not ringM then
		return
	end
	local center = ringM:GetAttribute("Center")
	local c = if typeof(center) == "Vector3" then center else core.Position
	local ring, offsets = {}, {}
	for _, b in ringM:GetChildren() do
		if b:IsA("BasePart") then
			table.insert(ring, b)
			table.insert(offsets, CFrame.new(c):ToObjectSpace(b.CFrame))
		end
	end
	local symbol = core:FindFirstChild("Symbol")
	local symbols: { [string]: { BasePart } } = {}
	local energy: { Spinner3 } = {}
	for _, child in m:GetChildren() do
		local theme = child:GetAttribute("Theme")
		if child:IsA("Model") and type(theme) == "string" then
			local parts = {}
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			symbols[theme] = parts
		elseif child:IsA("Model") and child:GetAttribute("Tilt") ~= nil then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(energy, {
						part = d,
						offset = CFrame.new(c):ToObjectSpace(d.CFrame),
						tilt = math.rad(tonumber(child:GetAttribute("Tilt")) or 0),
						speed = tonumber(child:GetAttribute("Speed")) or 0.5,
					})
				end
			end
		end
	end
	local o: Orb = {
		core = core,
		light = core:FindFirstChildOfClass("PointLight"),
		icon = if symbol then symbol:FindFirstChildOfClass("ImageLabel") else nil,
		sparkle = core:FindFirstChildOfClass("ParticleEmitter"),
		ring = ring,
		offsets = offsets,
		center = c,
		symbols = symbols,
		energy = energy,
	}
	table.insert(orbs, o)
	paintOrb(o, true)
end)

-- ======================================================================= spinners, flags, falls, gems
type Spinner = { parts: { BasePart }, offsets: { CFrame }, center: Vector3, speed: number, axisX: boolean, angle: number }
local spinners: { Spinner } = {}
tagged("Spin", function(m)
	local center = m:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then
		return
	end
	local parts, offsets = {}, {}
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(offsets, CFrame.new(center):ToObjectSpace(p.CFrame))
		end
	end
	local sp = m:GetAttribute("Speed")
	table.insert(spinners, { parts = parts, offsets = offsets, center = center, speed = if type(sp) == "number" then sp else 1, axisX = m:GetAttribute("Axis") == "X", angle = 0 })
end)

type Flag = { strips: { BasePart }, base: Vector3, phase: number }
local flags: { Flag } = {}
tagged("Flag", function(m)
	local base = m:GetAttribute("Base")
	if typeof(base) ~= "Vector3" then
		return
	end
	local strips = {}
	for i = 1, 5 do
		local s = m:WaitForChild("Strip" .. i, 5)
		if s and s:IsA("BasePart") then
			strips[i] = s
		end
	end
	if #strips == 5 then
		table.insert(flags, { strips = strips, base = base, phase = math.random() * 6 })
	end
end)

type Fall = { tex: Texture, speed: number }
local falls: { Fall } = {}
local mists: { ParticleEmitter } = {}
tagged("Waterfall", function(p)
	local t = p:FindFirstChildOfClass("Texture")
	local sp = p:GetAttribute("Speed")
	if t then
		table.insert(falls, { tex = t, speed = if type(sp) == "number" then sp else 14 })
	end
end)
tagged("WaterfallMist", function(e)
	if e:IsA("ParticleEmitter") then
		table.insert(mists, e)
		e.Enabled = currentTheme ~= "Winter"
	end
end)
local sprays: { ParticleEmitter } = {}
tagged("FountainSpray", function(e)
	if e:IsA("ParticleEmitter") then
		table.insert(sprays, e)
		e.Enabled = currentTheme ~= "Winter"
	end
end)

-- gems: spin, bob, hidden once found
local gems: { BasePart } = {}
local function foundSet(): { [number]: boolean }
	local s = {}
	local v = player:GetAttribute("Gems")
	if type(v) == "string" then
		for id in string.gmatch(v, "%d+") do
			s[tonumber(id) :: number] = true
		end
	end
	return s
end
local function paintGem(g: BasePart)
	local id = g:GetAttribute("GemId")
	local found = type(id) == "number" and foundSet()[id] == true
	g.LocalTransparencyModifier = if found then 1 else 0
	for _, c in g:GetChildren() do
		if c:IsA("ParticleEmitter") or c:IsA("PointLight") then
			c.Enabled = not found
		end
	end
end
tagged("Gem", function(g)
	if g:IsA("BasePart") then
		g:SetAttribute("BaseCF", g.CFrame)
		table.insert(gems, g)
		paintGem(g)
	end
end)
player:GetAttributeChangedSignal("Gems"):Connect(function()
	for _, g in gems do
		paintGem(g)
	end
end)

-- ======================================================================= sounds
local function loop(id: string, name: string): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end
local sRain = loop(SND.rain, "WeatherRain")
local sWind = loop(SND.wind, "WeatherWind")
local sBirds = loop(SND.birds, "WeatherBirds")
local thunder = Instance.new("Sound")
thunder.SoundId = SND.thunder
thunder.Parent = SoundService
task.spawn(function()
	local fallsF = Workspace:WaitForChild("Map"):WaitForChild("Waterfalls", 30)
	if not fallsF then
		return
	end
	local function addSound(m: Instance)
		local foam = m:WaitForChild("Foam", 10)
		if foam and foam:IsA("BasePart") and not foam:FindFirstChild("FallSound") then
			local s = Instance.new("Sound")
			s.Name = "FallSound"
			s.SoundId = SND.waterfall
			s.Looped = true
			s.Volume = 0.5
			s.RollOffMaxDistance = 140
			s.RollOffMinDistance = 15
			s.Parent = foam
			s:Play()
		end
	end
	fallsF.ChildAdded:Connect(addSound)
	for _, m in fallsF:GetChildren() do
		task.spawn(addSound, m)
	end
end)

-- ======================================================================= camera-local particles
local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientWeatherFx"
fxFolder.Parent = Workspace
local function host(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = fxFolder
	return p
end
local function ns(...: number): NumberSequence
	local pts = { ... }
	local kps = {}
	for i = 1, #pts, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(pts[i], pts[i + 1]))
	end
	return NumberSequence.new(kps)
end
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end
local skyHost = host("SkyHost", Vector3.new(110, 2, 110)) -- above the camera
local nearHost = host("NearHost", Vector3.new(36, 2, 36))
local airHost = host("AirHost", Vector3.new(120, 26, 120)) -- around the camera
local RAIN_MAX, RAIN_NEAR_MAX, SNOW_MAX, SAND_MAX, GRAIN_MAX, MOTE_MAX = 700, 120, 220, 8, 160, 14
local rainFar = emitter(skyHost, {
	Name = "RainFar", Texture = TEX.raindrop, Color = ColorSequence.new(Color3.fromRGB(200, 220, 255)),
	Size = ns(0, 0.3, 1, 0.3), Squash = ns(0, -2.5, 1, -2.5), Lifetime = NumberRange.new(0.9, 1.1), -- negative squash = tall thin streak
	Speed = NumberRange.new(80, 95), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4),
	Orientation = Enum.ParticleOrientation.VelocityParallel, Transparency = ns(0, 0.35, 1, 0.5),
	LightEmission = 0.3, LightInfluence = 0.2, WindAffectsDrag = true, Drag = 0.4,
})
local rainNear = emitter(nearHost, {
	Name = "RainNear", Texture = TEX.raindrop, Color = ColorSequence.new(Color3.fromRGB(220, 235, 255)),
	Size = ns(0, 0.45, 1, 0.45), Squash = ns(0, -2.5, 1, -2.5), Lifetime = NumberRange.new(0.5, 0.6),
	Speed = NumberRange.new(70, 80), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(3, 3),
	Orientation = Enum.ParticleOrientation.VelocityParallel, Transparency = ns(0, 0.3, 1, 0.45),
	LightEmission = 0.3, LightInfluence = 0.2, WindAffectsDrag = true, Drag = 0.4,
})
local snow = emitter(skyHost, {
	Name = "Snow", Texture = TEX.snowflake, Color = ColorSequence.new(Color3.new(1, 1, 1)),
	Size = ns(0, 0.5, 1, 0.4), Lifetime = NumberRange.new(6, 8), Speed = NumberRange.new(4, 7),
	EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(25, 25), Drag = 0.8,
	WindAffectsDrag = true, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
	Transparency = ns(0, 1, 0.1, 0.05, 0.85, 0.1, 1, 1), LightEmission = 0.25, LightInfluence = 0.6,
})
-- big soft flakes drifting right in front of the camera (depth for the winter snowfall)
local snowNear = emitter(nearHost, {
	Name = "SnowNear", Texture = TEX.snowflake, Color = ColorSequence.new(Color3.new(1, 1, 1)),
	Size = ns(0, 0.9, 1, 0.7), Lifetime = NumberRange.new(3, 4), Speed = NumberRange.new(2.5, 4.5),
	EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(35, 35), Drag = 0.6,
	WindAffectsDrag = true, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
	Transparency = ns(0, 1, 0.15, 0.15, 0.8, 0.25, 1, 1), LightEmission = 0.35, LightInfluence = 0.5,
})
local sand = emitter(airHost, {
	Name = "SandSheets", Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(232, 182, 120)),
	Size = ns(0, 6, 1, 12), Lifetime = NumberRange.new(3.5, 5), Speed = NumberRange.new(1, 3),
	SpreadAngle = Vector2.new(180, 180), Drag = 1.2, WindAffectsDrag = true, Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-15, 15), Transparency = ns(0, 1, 0.3, 0.9, 0.7, 0.92, 1, 1), LightInfluence = 0.8,
})
local grains = emitter(airHost, {
	Name = "SandGrains", Texture = TEX.raindrop, Color = ColorSequence.new(Color3.fromRGB(226, 176, 110)),
	Size = ns(0, 0.1, 1, 0.1), Squash = ns(0, -1.6, 1, -1.6), Lifetime = NumberRange.new(1.2, 1.8),
	Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(180, 180), Drag = 3, WindAffectsDrag = true,
	Orientation = Enum.ParticleOrientation.VelocityParallel, Transparency = ns(0, 0.4, 1, 0.8), LightInfluence = 0.8,
})
local motes = emitter(airHost, {
	Name = "Motes", Texture = TEX.sparkle, Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)),
	Size = ns(0, 0, 0.3, 0.28, 1, 0), Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(0.3, 1),
	SpreadAngle = Vector2.new(180, 180), Drag = 0.5, WindAffectsDrag = true, LightEmission = 1, LightInfluence = 0,
	Transparency = ns(0, 1, 0.3, 0.3, 1, 1),
})
-- splashes: a pool of attachments on one part, moved to where drops land
local splashPart = host("Splashes", Vector3.one)
local splashAtts: { Attachment } = {}
for i = 1, 12 do
	local a = Instance.new("Attachment")
	a.Parent = splashPart
	splashAtts[i] = a
	emitter(a, {
		Name = "Splash", Texture = TEX.ring, Color = ColorSequence.new(Color3.fromRGB(215, 235, 255)),
		Size = ns(0, 0.2, 1, 1.4), Lifetime = NumberRange.new(0.22, 0.3), Speed = NumberRange.new(0.01, 0.01),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
		Transparency = ns(0, 0.2, 1, 1), LightInfluence = 0.6,
	})
end
local splashParams = RaycastParams.new()
splashParams.FilterType = Enum.RaycastFilterType.Exclude
splashParams.FilterDescendantsInstances = { fxFolder }
local splashIdx = 0
local splashClock = 0

-- ======================================================================= birds
type Bird = { body: BasePart, wingL: BasePart, wingR: BasePart, r: number, h: number, speed: number, phase: number }
local birds: { Bird } = {}
do
	local folder = Instance.new("Folder")
	folder.Name = "Birds"
	folder.Parent = fxFolder
	local function piece(size: Vector3, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Parent = folder
		return p
	end
	for i = 1, 7 do
		table.insert(birds, {
			body = piece(Vector3.new(1, 0.9, 2.2), Color3.fromRGB(250, 250, 255), Enum.PartType.Ball),
			wingL = piece(Vector3.new(2.2, 0.15, 1.1), Color3.fromRGB(235, 240, 250)),
			wingR = piece(Vector3.new(2.2, 0.15, 1.1), Color3.fromRGB(235, 240, 250)),
			r = 110 + i * 14,
			h = 58 + (i % 3) * 9,
			speed = 0.12 + (i % 4) * 0.02,
			phase = i * 0.9,
		})
	end
end

-- ======================================================================= lightning
local boltFolder = Instance.new("Folder")
boltFolder.Name = "Bolts"
boltFolder.Parent = fxFolder
local lastFlash = 0
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { terrain }
local function strike(seed: number, pos: Vector3)
	local rng = Random.new(seed)
	local hit = Workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -400, 0), groundParams)
	local bottom = if hit then hit.Position else Vector3.new(pos.X, 0, pos.Z)
	local top = bottom + Vector3.new(rng:NextNumber(-40, 40), 260, rng:NextNumber(-40, 40))
	-- midpoint displacement
	local pts = { top, bottom }
	local amp = 36
	for _ = 1, 5 do
		local nextPts = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid = (a + b) / 2 + Vector3.new(rng:NextNumber(-amp, amp), rng:NextNumber(-amp, amp) * 0.3, rng:NextNumber(-amp, amp))
			table.insert(nextPts, mid)
			table.insert(nextPts, b)
		end
		pts = nextPts
		amp *= 0.55
	end
	local segs: { BasePart } = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		for layer = 1, 2 do
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = if layer == 1 then Color3.fromRGB(245, 240, 255) else Color3.fromRGB(170, 140, 255)
			p.Transparency = if layer == 1 then 0 else 0.6
			local w = if layer == 1 then 0.9 else 2.6
			p.Size = Vector3.new(w, w, (b - a).Magnitude + w * 0.5)
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
			p.Parent = boltFolder
			table.insert(segs, p)
		end
	end
	local cam = Workspace.CurrentCamera
	local dist = if cam then (cam.CFrame.Position - bottom).Magnitude else 300
	-- flash (limited to one strong flash per 0.6 s)
	local now = os.clock()
	if now - lastFlash > 0.6 then
		lastFlash = now
		local power = math.clamp(1 - dist / 900, 0.25, 1)
		flash.Brightness = 0.45 * power
		flash.TintColor = Color3.fromRGB(225, 225, 255)
		tween(flash, 0.3, { Brightness = 0 })
	end
	-- flicker: off, weaker second stroke, gone
	task.delay(0.09, function()
		for _, s in segs do
			s.Transparency = 1
		end
		task.wait(0.06)
		for i, s in segs do
			s.Transparency = if i % 2 == 1 then 0.2 else 0.75
		end
		task.wait(0.08)
		for _, s in segs do
			tween(s, 0.25, { Transparency = 1 })
		end
		task.wait(0.3)
		for _, s in segs do
			s:Destroy()
		end
	end)
	-- thunder: later and quieter the further away (stylised sound speed)
	task.delay(math.clamp(dist / 650, 0.05, 2.5), function()
		local s = thunder:Clone()
		s.Volume = math.clamp(1.1 - dist / 900, 0.25, 1)
		s.PlaybackSpeed = 0.85 + math.random() * 0.25
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end)
end
local Lightning = remotes:WaitForChild("Lightning", 30) :: RemoteEvent?
if Lightning then
	Lightning.OnClientEvent:Connect(function(seed: number, pos: Vector3, at: number)
		task.delay(math.max(0, at - Workspace:GetServerTimeNow()), strike, seed, pos)
	end)
end

-- ======================================================================= info boards
local REPORT_TIPS = {
	"Follow the coloured ring: clouds drift inside it.",
	"Rare fronts bring rare clouds.",
	"The tower orb shows the active front.",
}
local TIPS = {
	"Press E near a cloud to start herding it.",
	"Gust (E / tap) pushes the cloud away from you.",
	"Bigger jar = easier catch. Upgrade it!",
	"Gust Power trains itself as you gust.",
	"Clouds on display earn coins every 10 seconds.",
	"Six Sky Gems are hidden on the island...",
}
local HOWTO = {
	"1. Cross the bridge to the island",
	"2. Find a weather front (coloured ring)",
	"3. Press E near a cloud to herd it",
	"4. Gust it into the glowing jar!",
	"5. Your island case pays coins forever",
}
type Board = { kind: string, main: TextLabel?, sub: TextLabel?, tip: TextLabel?, title: TextLabel?, page: number }
local boards: { Board } = {}
local function clock(s: number): string
	local v = math.max(0, math.ceil(s))
	return string.format("%d:%02d", v // 60, v % 60)
end
local function paintBoard(b: Board)
	local now = Workspace:GetServerTimeNow()
	local kind = Workspace:GetAttribute("FrontKind")
	if b.kind == "report" then
		if b.title then
			b.title.Text = "WEATHER REPORT"
		end
		if type(kind) == "string" then
			local endsAt = Workspace:GetAttribute("FrontEndsAt")
			if b.main then
				b.main.Text = string.upper(kind) .. " FRONT"
			end
			if b.sub then
				b.sub.Text = (if type(endsAt) == "number" then clock(endsAt - now) .. " LEFT  -  " else "") .. "catch clouds!"
			end
		else
			local nextAt = Workspace:GetAttribute("NextFrontAt")
			if b.main then
				b.main.Text = "CALM SKIES"
			end
			if b.sub then
				b.sub.Text = if type(nextAt) == "number" then "Next front in " .. clock(nextAt - now) else "A front is coming..."
			end
		end
		if b.tip then
			b.tip.Text = REPORT_TIPS[(b.page - 1) % #REPORT_TIPS + 1]
		end
	else
		local list = if b.kind == "howto" then HOWTO else TIPS
		if b.title then
			b.title.Text = if b.kind == "howto" then "HOW TO PLAY" else "WEATHER TIPS"
		end
		if b.main then
			b.main.Text = list[(b.page - 1) % #list + 1]
		end
		if b.sub then
			b.sub.Text = string.format("%d / %d", (b.page - 1) % #list + 1, #list)
		end
		if b.tip then
			b.tip.Text = "Press E for the next one"
		end
	end
end
tagged("InfoBoard", function(m)
	local kind = m:GetAttribute("Kind")
	local screen = m:WaitForChild("Screen", 10)
	local gui = screen and screen:WaitForChild("Display", 10)
	local bg = gui and gui:FindFirstChildOfClass("Frame")
	if not bg then
		return
	end
	local b: Board = {
		kind = if type(kind) == "string" then kind else "report",
		-- lihfolk-ignore: findfirstchild-chain (optional cast, checked before every use)
		title = bg:FindFirstChild("Title") :: TextLabel?,
		-- lihfolk-ignore: findfirstchild-chain (optional cast, checked before every use)
		main = bg:FindFirstChild("Main") :: TextLabel?,
		-- lihfolk-ignore: findfirstchild-chain (optional cast, checked before every use)
		sub = bg:FindFirstChild("Sub") :: TextLabel?,
		-- lihfolk-ignore: findfirstchild-chain (optional cast, checked before every use)
		tip = bg:FindFirstChild("Tip") :: TextLabel?,
		page = math.random(1, 6),
	}
	table.insert(boards, b)
	paintBoard(b)
	local panel = m:FindFirstChild("Panel")
	local prompt = panel and panel:FindFirstChild("ReadPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			b.page += 1
			paintBoard(b)
			Kit.sfx("click")
		end)
	end
end)
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, b in boards do
			paintBoard(b)
		end
	end
end)

-- ======================================================================= gem toast
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "WorldToast"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = 9
toastGui.Parent = player:WaitForChild("PlayerGui")
local GemFound = remotes:WaitForChild("GemFound", 30) :: RemoteEvent?
if GemFound then
	GemFound.OnClientEvent:Connect(function(_id: number, coins: number)
		local n = 0
		for _ in foundSet() do
			n += 1
		end
		local holder = Kit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(460, 96), BackgroundTransparency = 1 }, toastGui)
		local fx = Kit.new("UIScale", { Scale = 0.6 }, holder)
		local card = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, holder)
		Kit.corner(card, 22)
		Kit.stroke(card, 6)
		Kit.gradStops(card, { Color3.fromHex("8FF7FF"), Color3.fromHex("3FB8F0"), Color3.fromHex("6A5CFF") }, 90)
		Kit.image(card, "sparkle", UDim2.fromOffset(70, 70), UDim2.fromOffset(14, 13))
		Kit.text(card, "SKY GEM FOUND!", 36, { Position = UDim2.fromOffset(96, 8) })
		Kit.text(card, string.format("+%d coins   -   %d / %d found", coins, math.max(n, 1), Config.GEM_COUNT), 22, { Position = UDim2.fromOffset(98, 54), TextColor3 = Color3.fromHex("FFF7B0") })
		Kit.tween(fx, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.sfx("buy")
		task.delay(3, function()
			Kit.tween(fx, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.2)
			holder:Destroy()
		end)
	end)
end

-- ======================================================================= theme changes
local blendFrom: Look = Themes.Default
local blendTo: Look = Themes.Default
local blendStart = -1e9
local blendDur = 5
local blending = false

local function setTheme(name: string, instant: boolean)
	local look = Themes[name]
	if not look then
		name = "Default"
		look = Themes.Default
	end
	currentTheme = name
	blendFrom = shown
	blendTo = look
	blendDur = if name == "Default" then 6 else 4
	blendStart = os.clock()
	blending = not instant
	if instant then
		applyLook(look)
	end
	for _, theme in ONLY do
		for _, p in CollectionService:GetTagged("Only" .. theme) do
			fadeOnly(p, theme, instant)
		end
	end
	for _, p in CollectionService:GetTagged("Foliage") do
		tintFoliage(p, instant)
	end
	for _, p in CollectionService:GetTagged("ThemeGround") do
		paintGround(p, instant)
	end
	for _, p in CollectionService:GetTagged("HubFloor") do
		paintHubFloor(p, instant)
	end
	for _, o in orbs do
		paintOrb(o, instant)
	end
	for _, e in mists do
		e.Enabled = name ~= "Winter"
	end
	for _, e in sprays do
		e.Enabled = name ~= "Winter"
	end
end
local function readTheme(): string
	local t = Workspace:GetAttribute("Theme")
	return if type(t) == "string" then t else "Default"
end
Workspace:GetAttributeChangedSignal("Theme"):Connect(function()
	setTheme(readTheme(), false)
end)
setTheme(readTheme(), true)

-- ======================================================================= per frame
local t0 = os.clock()
local orbParts: { BasePart } = {}
local orbCFs: { CFrame } = {}
RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock() - t0
	-- theme blend
	if blending then
		local a = math.clamp((os.clock() - blendStart) / blendDur, 0, 1)
		local e = a * a * (3 - 2 * a)
		applyLook(lerpLook(blendFrom, blendTo, e))
		if a >= 1 then
			blending = false
		end
	end
	local fx = shown.fx
	-- particle hosts follow the camera (snap, no lerp)
	local cam = Workspace.CurrentCamera
	if cam then
		local p = cam.CFrame.Position
		skyHost.CFrame = CFrame.new(p + Vector3.new(0, 30, 0))
		nearHost.CFrame = CFrame.new(p + Vector3.new(0, 14, 0) + cam.CFrame.LookVector * 8)
		airHost.CFrame = CFrame.new(p)
		rainFar.Rate = RAIN_MAX * fx.rain
		rainNear.Rate = RAIN_NEAR_MAX * fx.rain
		snow.Rate = SNOW_MAX * fx.snow
		snowNear.Rate = 45 * fx.snow
		sand.Rate = SAND_MAX * fx.sand
		grains.Rate = GRAIN_MAX * fx.sand
		motes.Rate = MOTE_MAX * fx.motes
		-- splashes where drops land
		splashClock += dt
		if fx.rain > 0.05 and splashClock > 0.06 then
			splashClock = 0
			for _ = 1, math.ceil(4 * fx.rain) do
				local ang = math.random() * math.pi * 2
				local r = math.sqrt(math.random()) * 34
				local from = p + Vector3.new(math.cos(ang) * r, 40, math.sin(ang) * r)
				local hit = Workspace:Raycast(from, Vector3.new(0, -120, 0), splashParams)
				if hit then
					splashIdx = splashIdx % #splashAtts + 1
					local att = splashAtts[splashIdx]
					att.WorldPosition = hit.Position + hit.Normal * 0.05
					local e = att:FindFirstChildOfClass("ParticleEmitter")
					if e then
						e:Emit(1)
					end
				end
			end
		end
	end
	-- sounds
	sRain.Volume = shown.sound.rain
	sWind.Volume = shown.sound.wind
	sBirds.Volume = shown.sound.birds
	-- tower orb ring
	for _, o in orbs do
		table.clear(orbParts)
		table.clear(orbCFs)
		local spin = CFrame.new(o.center) * CFrame.Angles(0, t * 0.5, 0)
		for i, b in o.ring do
			table.insert(orbParts, b)
			table.insert(orbCFs, spin * o.offsets[i])
		end
		-- energy rings turn on tilted axes; the active symbol spins and bobs
		for k, e in o.energy do
			table.insert(orbParts, e.part)
			table.insert(orbCFs, CFrame.new(o.center) * CFrame.Angles(e.tilt, k * 0.9, 0) * CFrame.Angles(0, t * e.speed, 0) * e.offset)
		end
		-- the symbol turns to face this player's camera (readable from every side), with a gentle sway
		local camPos = if cam then cam.CFrame.Position else o.center + Vector3.zAxis
		local flat = Vector3.new(camPos.X, o.center.Y, camPos.Z)
		local bob = CFrame.lookAt(o.center, if (flat - o.center).Magnitude > 0.1 then flat else o.center + Vector3.zAxis) * CFrame.new(0, math.sin(t * 1.6) * 0.5, 0) * CFrame.Angles(0, math.pi + math.sin(t * 1.3) * 0.45, 0)
		for _, parts in o.symbols do
			for _, sp in parts do
				table.insert(orbParts, sp)
				table.insert(orbCFs, bob)
			end
		end
		Workspace:BulkMoveTo(orbParts, orbCFs, Enum.BulkMoveMode.FireCFrameChanged)
		o.core.Size = Vector3.one * (if next(o.symbols) then 4.6 + math.sin(t * 2.2) * 0.3 else 7 + math.sin(t * 2.2) * 0.4)
	end
	-- turbines and the anemometer (faster in strong wind)
	local windK = math.clamp(shown.wind.Magnitude / 8, 0.4, 3)
	for _, s in spinners do
		s.angle += dt * s.speed * windK
		local rot = if s.axisX then CFrame.Angles(s.angle, 0, 0) else CFrame.Angles(0, s.angle, 0)
		local base = CFrame.new(s.center) * rot
		local cfs = table.create(#s.parts)
		for i = 1, #s.parts do
			cfs[i] = base * s.offsets[i]
		end
		Workspace:BulkMoveTo(s.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- flags stream with the wind
	local wdir = if shown.wind.Magnitude > 0.1 then shown.wind.Unit else Vector3.xAxis
	local yaw = math.atan2(-wdir.Z, wdir.X)
	local amp = math.clamp(shown.wind.Magnitude / 30, 0.15, 0.6)
	for _, f in flags do
		local pos = f.base
		local heading = yaw
		local parts, cfs = {}, {}
		for i, s in f.strips do
			heading = yaw + math.sin(t * 6 + f.phase - i * 0.8) * amp
			local dir = Vector3.new(math.cos(heading), 0, -math.sin(heading))
			local c = pos + dir * 0.6
			parts[i] = s
			cfs[i] = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, math.pi / 2, 0)
			pos += dir * 1.2
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- waterfalls scroll (frozen in winter)
	local flow = if currentTheme == "Winter" then 0 else 1
	for _, f in falls do
		f.tex.OffsetStudsV = (f.tex.OffsetStudsV - f.speed * dt * flow) % 1000
	end
	-- sky clouds drift with the wind and wrap around
	local drift = shown.wind * 0.25 * dt
	for _, c in skyClouds do
		local np = c.Position + drift
		if np.X > 520 then
			np -= Vector3.new(1040, 0, 0)
		elseif np.X < -520 then
			np += Vector3.new(1040, 0, 0)
		end
		if np.Z > 520 then
			np -= Vector3.new(0, 0, 1040)
		elseif np.Z < -520 then
			np += Vector3.new(0, 0, 1040)
		end
		c.CFrame = c.CFrame.Rotation + np
	end
	-- birds circle the island
	local nBirds = math.floor(#birds * fx.birds + 0.5)
	for i, b in birds do
		local on = i <= nBirds
		local tr = if on then 0 else 1
		b.body.Transparency, b.wingL.Transparency, b.wingR.Transparency = tr, tr, tr
		if on then
			local a = t * b.speed + b.phase
			local pos = Vector3.new(math.cos(a) * b.r, b.h + math.sin(t * 0.7 + i) * 4, math.sin(a) * b.r - 30)
			local ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
			local cf = CFrame.lookAt(pos, pos + ahead)
			local flap = math.sin(t * 9 + i) * 0.6
			b.body.CFrame = cf
			b.wingL.CFrame = cf * CFrame.Angles(0, 0, flap) * CFrame.new(-1.3, 0, 0)
			b.wingR.CFrame = cf * CFrame.Angles(0, 0, -flap) * CFrame.new(1.3, 0, 0)
		end
	end
	-- gems spin and bob
	for _, g in gems do
		local base = g:GetAttribute("BaseCF")
		if typeof(base) == "CFrame" then
			g.CFrame = CFrame.new(base.Position + Vector3.new(0, math.sin(t * 2) * 0.5, 0)) * CFrame.Angles(0, t * 1.6, 0) * base.Rotation
		end
	end
end)
