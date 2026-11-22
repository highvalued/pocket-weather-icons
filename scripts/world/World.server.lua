--!strict
-- World life (server side). Decides, never renders - WeatherWorld (client) draws everything:
--   * workspace attribute Theme ("Default" | "Winter" | "Desert" | "Storm") from the active front
--     (Config.FRONT_THEME). Studio QA: set workspace attribute ForceTheme to pin one.
--   * ambient lightning while the Storm theme is on: Remotes.Lightning (seed, position, strikeAt)
--     so every client shows the same bolt at the same moment. Visual only, never hurts anyone.
--   * Sky Gems (workspace.Map.Gems, tag Gem): touching one pays Config.GEM_COINS once per player
--     (saved in the profile); Remotes.GemFound tells the finder.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("PocketWeather")
local Config = require(shared:WaitForChild("Config") :: ModuleScript)
local Data = require(script.Parent:WaitForChild("Data") :: ModuleScript)
local remotes = shared:WaitForChild("Remotes")

local function remote(name: string): RemoteEvent
	local r = remotes:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = remotes
	return e
end
local Lightning = remote("Lightning") -- server -> all: (seed, position, strikeAt)
local GemFound = remote("GemFound") -- server -> finder: (gemId, coins)

-- theme ------------------------------------------------------------------------------
local function updateTheme()
	local forced = Workspace:GetAttribute("ForceTheme")
	local kind = Workspace:GetAttribute("FrontKind")
	local theme = if type(forced) == "string" and forced ~= "" then forced else (if type(kind) == "string" then Config.FRONT_THEME[kind] else nil)
	Workspace:SetAttribute("Theme", theme or "Default")
end
Workspace:GetAttributeChangedSignal("FrontKind"):Connect(updateTheme)
Workspace:GetAttributeChangedSignal("ForceTheme"):Connect(updateTheme)
updateTheme()

-- lightning ----------------------------------------------------------------------------
task.spawn(function()
	local rng = Random.new()
	while true do
		task.wait(rng:NextNumber(3.5, 8))
		if Workspace:GetAttribute("Theme") == "Storm" then
			local a = rng:NextNumber() * math.pi * 2
			local r = rng:NextNumber(70, 340)
			local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r - 30)
			Lightning:FireAllClients(rng:NextInteger(1, 1000000), pos, Workspace:GetServerTimeNow() + 0.15)
		end
	end
end)

-- sky gems -----------------------------------------------------------------------------
local touchGate: { [Player]: number } = {}
local function hookGem(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	inst.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		if not player then
			return
		end
		local id = inst:GetAttribute("GemId")
		if type(id) ~= "number" then
			return
		end
		local now = os.clock()
		if (touchGate[player] or 0) > now then
			return
		end
		touchGate[player] = now + 0.5
		if Data.claimGem(player, id) then
			GemFound:FireClient(player, id, Config.GEM_COINS)
		end
	end)
end
CollectionService:GetInstanceAddedSignal("Gem"):Connect(hookGem)
for _, g in CollectionService:GetTagged("Gem") do
	hookGem(g)
end
Players.PlayerRemoving:Connect(function(p)
	touchGate[p] = nil
end)
