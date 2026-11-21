--!strict
-- Map looks per weather theme (data only). WeatherWorld (client) blends between them when the
-- server's workspace attribute Theme changes. Theme comes from the active front:
-- Config.FRONT_THEME (Sunny = Default, Flurry = Winter, Dusty = Desert, Rainy = Storm).
export type Look = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	specular: number,
	diffuse: number,
	exposure: number,
	atmo: { density: number, offset: number, color: Color3, decay: Color3, glare: number, haze: number },
	cc: { brightness: number, contrast: number, saturation: number, tint: Color3 },
	bloom: { intensity: number, size: number, threshold: number },
	sunrays: { intensity: number, spread: number },
	clouds: { cover: number, density: number, color: Color3 },
	terrain: { [string]: Color3 }, -- Enum.Material name -> colour
	water: { color: Color3, transparency: number, wave: number, speed: number, reflectance: number },
	ocean: Color3, -- far ocean plane (workspace.Map.OceanFar*)
	foliage: Color3, -- multiplied into tagged Foliage parts
	skyCloud: Color3, -- big drifting cloud meshes
	orb: Color3, -- Weather Tower core / light colour
	icon: string, -- Icons key shown in the orb
	lamps: number, -- PointLight brightness of lamps and windows
	wind: Vector3, -- workspace GlobalWind
	fx: { rain: number, snow: number, sand: number, motes: number, birds: number }, -- 0..1
	sound: { rain: number, wind: number, birds: number }, -- volumes
}

local function c(h: string): Color3
	return Color3.fromHex(h)
end

local Themes: { [string]: Look } = {
	Default = {
		clock = 13.6,
		brightness = 2.6,
		ambient = Color3.fromRGB(112, 112, 132),
		outdoor = Color3.fromRGB(140, 140, 162),
		specular = 0.3,
		diffuse = 0.6,
		exposure = 0.1,
		atmo = { density = 0.28, offset = 0.2, color = c("C7E6FF"), decay = c("9EC6F0"), glare = 0.3, haze = 1.2 },
		cc = { brightness = 0.02, contrast = 0.08, saturation = 0.18, tint = c("FFFFFF") },
		bloom = { intensity = 0.6, size = 24, threshold = 1.6 },
		sunrays = { intensity = 0.08, spread = 0.6 },
		clouds = { cover = 0.55, density = 0.6, color = c("FFFFFF") },
		terrain = {
			Grass = c("7CD36A"), Ground = c("8A6B4E"), Rock = c("8E89A8"), Slate = c("6F6A8E"),
			Sand = c("E8D39A"), Snow = c("F4F8FF"), Cobblestone = c("B9B4C8"), Pavement = c("D6D2E3"),
		},
		water = { color = c("1F8FD6"), transparency = 0.35, wave = 0.15, speed = 10, reflectance = 0.5 },
		ocean = c("2A8CC8"),
		foliage = c("FFFFFF"),
		skyCloud = c("FFFFFF"),
		orb = c("FFE27A"),
		icon = "sun",
		lamps = 0.5,
		wind = Vector3.new(6, 0, 3),
		fx = { rain = 0, snow = 0, sand = 0, motes = 1, birds = 1 },
		sound = { rain = 0, wind = 0.08, birds = 0.35 },
	},
	Winter = {
		clock = 14.5,
		brightness = 2.2,
		ambient = Color3.fromRGB(130, 140, 172),
		outdoor = Color3.fromRGB(172, 182, 212),
		specular = 0.5,
		diffuse = 0.7,
		exposure = 0.05,
		atmo = { density = 0.38, offset = 0.15, color = c("DDEEFF"), decay = c("A8C4EA"), glare = 0, haze = 2 },
		cc = { brightness = 0.05, contrast = 0.05, saturation = -0.12, tint = c("EAF4FF") },
		bloom = { intensity = 0.8, size = 30, threshold = 1.3 },
		sunrays = { intensity = 0.05, spread = 0.5 },
		clouds = { cover = 0.75, density = 0.7, color = c("F0F6FF") },
		terrain = {
			Grass = c("EEF4FF"), Ground = c("D8E2F0"), Rock = c("9AA6C8"), Slate = c("7E8AB0"),
			Sand = c("E6EEF8"), Snow = c("FFFFFF"), Cobblestone = c("C8D2E6"), Pavement = c("E2E8F4"),
		},
		water = { color = c("A8DCF0"), transparency = 0.05, wave = 0, speed = 0, reflectance = 0.8 },
		ocean = c("9FD3EE"),
		foliage = c("BFD8D0"),
		skyCloud = c("F0F6FF"),
		orb = c("9FEFFF"),
		icon = "snow",
		lamps = 0.9,
		wind = Vector3.new(4, 0, 2),
		fx = { rain = 0, snow = 1, sand = 0, motes = 0, birds = 0.3 },
		sound = { rain = 0, wind = 0.25, birds = 0 },
	},
	Desert = {
		clock = 16.8,
		brightness = 3,
		ambient = Color3.fromRGB(150, 122, 100),
		outdoor = Color3.fromRGB(182, 150, 120),
		specular = 0.2,
		diffuse = 0.6,
		exposure = 0.1,
		atmo = { density = 0.32, offset = 0.12, color = c("FFD6A0"), decay = c("E39A5A"), glare = 0.5, haze = 1.5 },
		cc = { brightness = 0.03, contrast = 0.12, saturation = 0.22, tint = c("FFE6C4") },
		bloom = { intensity = 0.7, size = 28, threshold = 1.4 },
		sunrays = { intensity = 0.2, spread = 0.8 },
		clouds = { cover = 0.25, density = 0.4, color = c("FFE2C0") },
		terrain = {
			Grass = c("E8B865"), Ground = c("C98A52"), Rock = c("D07A4A"), Slate = c("B5643E"),
			Sand = c("F2CF8A"), Snow = c("F6E2C0"), Cobblestone = c("D9B88E"), Pavement = c("EAD2AE"),
		},
		water = { color = c("2FC4C8"), transparency = 0.3, wave = 0.1, speed = 8, reflectance = 0.4 },
		ocean = c("3DB8C0"),
		foliage = c("D8C27A"),
		skyCloud = c("FFF4E8"),
		orb = c("FFB04A"),
		icon = "wind",
		lamps = 0.4,
		wind = Vector3.new(18, 0, 6),
		fx = { rain = 0, snow = 0, sand = 1, motes = 0, birds = 0.5 },
		sound = { rain = 0, wind = 0.35, birds = 0.1 },
	},
	Storm = {
		clock = 16.2,
		brightness = 1.9,
		ambient = Color3.fromRGB(104, 104, 156),
		outdoor = Color3.fromRGB(126, 126, 178),
		specular = 1,
		diffuse = 0.5,
		exposure = 0,
		atmo = { density = 0.4, offset = 0.08, color = c("7A80B8"), decay = c("45407A"), glare = 0, haze = 1.6 },
		cc = { brightness = 0, contrast = 0.14, saturation = -0.08, tint = c("D4D4FF") },
		bloom = { intensity = 1, size = 30, threshold = 1.1 },
		sunrays = { intensity = 0, spread = 0.3 },
		clouds = { cover = 0.9, density = 0.85, color = c("6A6A8A") },
		terrain = {
			Grass = c("3F8A5A"), Ground = c("4E3E3A"), Rock = c("5A5878"), Slate = c("46446A"),
			Sand = c("9C9070"), Snow = c("C8D0E8"), Cobblestone = c("6E6C88"), Pavement = c("8A88A6"),
		},
		water = { color = c("1A3A6A"), transparency = 0.45, wave = 0.6, speed = 24, reflectance = 0.3 },
		ocean = c("1F3A66"),
		foliage = c("7A9A8A"),
		skyCloud = c("8A8AA8"),
		orb = c("9F7BFF"),
		icon = "storm",
		lamps = 1.6,
		wind = Vector3.new(24, 0, 10),
		fx = { rain = 1, snow = 0, sand = 0, motes = 0, birds = 0 },
		sound = { rain = 0.55, wind = 0.3, birds = 0 },
	},
}

return Themes
