--!strict
-- World life (server side). Decides, never renders - WeatherWorld (client) draws everything:
--   * workspace attribute Theme ("Default" | "Winter" | "Desert" | "Storm") from the active front
--     (Config.FRONT_THEME). Studio QA: set workspace attribute ForceTheme to pin one.
--   * ambient lightning while the Storm theme is on: Remotes.Lightning (seed, position, strikeAt)
--     so every client shows the same bolt at the same moment. Visual only, never hurts anyone.
--   * Sky Gems (workspace.Map.Gems, tag Gem): touching one pays Config.GEM_COINS once per player
--     (saved in the profile); Remotes.GemFound tells the finder.
--   * weather researcher NPCs on the NpcSpot markers, with a Talk prompt (Remotes.NpcTalk).
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
local NpcTalk = remote("NpcTalk") -- server -> player: (head, line)

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

-- researcher NPCs ------------------------------------------------------------------------
local LINES: { [string]: { string } } = {
	["Dr. Drizzle"] = {
		"Fronts roll in every few minutes. Follow the coloured ring on the ground!",
		"Clouds are shy. Gust them gently toward the jar.",
		"The Weather Tower orb shows which front is out right now.",
		"Rainy fronts bring storms. Watch for lightning!",
	},
	["Prof. Gale"] = {
		"A stronger Gust Power pushes clouds further. Gust a lot to train it!",
		"Flurry clouds are rare - they only come with winter fronts.",
		"Dusty clouds ride in on desert winds. Keep your eyes open.",
		"I heard there are Sky Gems hidden around the island...",
	},
	["Sunny Sam"] = {
		"Welcome to Pocket Weather! Cross the bridge to reach the island.",
		"Your own island with a display case is south of the meadow.",
		"Clouds in your case earn coins all the time.",
		"Spend coins on Catcher upgrades at your island's stand.",
	},
}
local THEME_LINE: { [string]: string } = {
	Default = "Lovely sunny skies today!",
	Winter = "Brrr! A winter front - Flurry clouds are about!",
	Desert = "A dusty desert wind! Dusty clouds love this heat.",
	Storm = "What a storm! Rainy clouds are everywhere.",
}

local npcFolder = Instance.new("Folder")
npcFolder.Name = "Npcs"
npcFolder.Parent = Workspace:WaitForChild("Map")

local IDLE_ANIM = "rbxassetid://507766388" -- Roblox R15 idle
local SKIN = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(160, 110, 80), Color3.fromRGB(255, 214, 180) }

local function makeNpc(spot: BasePart, index: number)
	local name = spot:GetAttribute("NpcName")
	if type(name) ~= "string" then
		return
	end
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN[(index - 1) % #SKIN + 1]
	desc.HeadColor = skin
	desc.LeftArmColor = Color3.fromRGB(245, 247, 255) -- lab coat
	desc.RightArmColor = Color3.fromRGB(245, 247, 255)
	desc.TorsoColor = Color3.fromRGB(245, 247, 255)
	desc.LeftLegColor = Color3.fromRGB(52, 59, 112)
	desc.RightLegColor = Color3.fromRGB(52, 59, 112)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[World] NPC model failed:", model)
		return
	end
	local npc = model :: Model
	npc.Name = name
	local hum = npc:FindFirstChildOfClass("Humanoid")
	-- lihfolk-ignore: findfirstchild-chain (cast only; both checked for nil just below)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (cast only; checked below)
	local head = npc:FindFirstChild("Head") :: BasePart?
	if not hum or not root or not head then
		npc:Destroy()
		return
	end
	hum.DisplayName = name
	hum.NameDisplayDistance = 60
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	npc:PivotTo(spot.CFrame + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.1, 0))
	local title = Instance.new("BillboardGui")
	title.Size = UDim2.fromOffset(200, 24)
	title.StudsOffset = Vector3.new(0, 3.2, 0)
	title.MaxDistance = 60
	title.Parent = head
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "WEATHER RESEARCHER"
	t.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(143, 227, 255)
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.fromRGB(23, 20, 42)
	s.Parent = t
	t.Parent = title
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local turn = 0
	prompt.Triggered:Connect(function(player: Player)
		turn += 1
		local list = LINES[name] or { "Hello!" }
		local line = if turn % 3 == 0 then THEME_LINE[Workspace:GetAttribute("Theme") :: string] or list[1] else list[(turn - 1) % #list + 1]
		NpcTalk:FireClient(player, head, line)
	end)
	npc.Parent = npcFolder
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local anim = Instance.new("Animation")
	anim.AnimationId = IDLE_ANIM
	local ok2, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok2 and track then
		track.Looped = true
		track:Play()
	end
end

task.spawn(function()
	for i, spot in CollectionService:GetTagged("NpcSpot") do
		if spot:IsA("BasePart") then
			makeNpc(spot, i)
		end
	end
end)
