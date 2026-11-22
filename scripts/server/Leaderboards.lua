--!strict
-- Global leaderboards for the hub boards (workspace.Map.Hub, tag "Leaderboard", attribute Stat).
-- Only real saved stats are shown:
--   Coins    profile.Coins                      "RICHEST"
--   Clouds   sum of profile.Kinds (clouds caught) "MOST CLOUDS"
--   Gust     profile.GustXp (Gust Power trained)  "TOP PLAYERS"
--   Upgrades sum of bought upgrade levels         "UPGRADE MASTERS"
-- Every REFRESH seconds: write each loaded player's stats to an OrderedDataStore per stat, read the
-- top 10, then merge live values of players in this server (so a fresh catch shows at once).
-- Players whose data failed to load are never written (their blank profile would overwrite the real
-- score). Empty boards say so; nothing is ever made up.
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("PocketWeather"):WaitForChild("Config") :: ModuleScript)

local Leaderboards = {}

local REFRESH = 90
local TOP = 10
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")

type Entry = { userId: number, value: number, name: string? }
type StatDef = { id: string, title: string, sub: string, color: Color3, fmt: (number) -> string }

local function short(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	local v = n
	while v >= 1000 and i < #units do
		v /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(v))
	end
	return (if v < 10 then string.format("%.2f", v) elseif v < 100 then string.format("%.1f", v) else string.format("%d", math.floor(v))) .. units[i]
end

local STATS: { StatDef } = {
	{ id = "Gust", title = "TOP PLAYERS", sub = "by Gust Power", color = Color3.fromHex("7AD7FF"), fmt = function(xp: number)
		return "Lv " .. tostring((Config.gustProgress(xp)))
	end },
	{ id = "Coins", title = "RICHEST", sub = "coins", color = Color3.fromHex("FFD23F"), fmt = short },
	{ id = "Clouds", title = "MOST CLOUDS", sub = "clouds caught", color = Color3.fromHex("F2F4FA"), fmt = short },
	{ id = "Upgrades", title = "UPGRADE MASTERS", sub = "upgrade levels", color = Color3.fromHex("B98CFF"), fmt = short },
}

local function statValue(id: string, p: any): number
	if id == "Coins" then
		return p.Coins
	elseif id == "Clouds" then
		local t = 0
		for _, n in p.Kinds do
			t += n
		end
		return t
	elseif id == "Gust" then
		return p.GustXp
	elseif id == "Upgrades" then
		local t = 0
		for id2, lvl in p.Up do
			if id2 ~= "Power" then -- Gust Power is trained, it has its own board
				t += lvl
			end
		end
		return t
	end
	return 0
end

local stores: { [string]: OrderedDataStore } = {}
for _, s in STATS do
	local ok, st = pcall(function()
		return DataStoreService:GetOrderedDataStore("PW_LB1_" .. s.id)
	end)
	if ok then
		stores[s.id] = st
	end
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string?
	local live = Players:GetPlayerByUserId(userId)
	if live then
		return live.DisplayName
	end
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(n) == "string" then
		nameCache[userId] = n
		return n
	end
	return nil
end

local thumbCache: { [number]: string } = {}
local function thumbOf(userId: number): string
	if thumbCache[userId] then
		return thumbCache[userId]
	end
	local ok, url = pcall(function()
		return (Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48))
	end)
	if ok and type(url) == "string" then
		thumbCache[userId] = url
		return url
	end
	return ""
end

local lastWritten: { [Player]: { [string]: number } } = {}

local function writePlayer(player: Player, p: any)
	if player:GetAttribute("DataLoadFailed") or player:GetAttribute("SaveBlocked") then
		return
	end
	local prev = lastWritten[player] or {}
	lastWritten[player] = prev
	for _, s in STATS do
		local st = stores[s.id]
		local v = math.floor(statValue(s.id, p))
		if st and v > 0 and prev[s.id] ~= v then
			local ok = pcall(function()
				st:SetAsync(tostring(player.UserId), v)
			end)
			if ok then
				prev[s.id] = v
			end
		end
	end
end

local function readTop(id: string): { Entry }
	local st = stores[id]
	local out: { Entry } = {}
	if not st then
		return out
	end
	local ok, pages = pcall(function()
		return st:GetSortedAsync(false, TOP)
	end)
	if ok and pages then
		local okPage, page = pcall(function()
			return (pages :: DataStorePages):GetCurrentPage()
		end)
		if okPage then
			for _, item in page do
				local uid = tonumber(item.key)
				if uid and type(item.value) == "number" and item.value > 0 then
					table.insert(out, { userId = uid, value = item.value })
				end
			end
		end
	end
	return out
end

-- board ui ----------------------------------------------------------------------------------
type BoardUi = { rows: { { frame: Frame, rank: TextLabel, name: TextLabel, value: TextLabel, face: ImageLabel } }, empty: TextLabel }
local boardUi: { [Instance]: BoardUi } = {}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FREDOKA
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	local ta: any = t
	for k, v in props do
		ta[k] = v
	end
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromHex("17142A")
	s.Thickness = 3
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

local MEDAL = { Color3.fromHex("FFD23F"), Color3.fromHex("D9E2F2"), Color3.fromHex("E59A5B") }

local function buildBoard(screen: BasePart, def: StatDef): BoardUi
	local old = screen:FindFirstChild("Board")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(600, 760)
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.MaxDistance = 220
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromHex("2C3A8C"), Color3.fromHex("161A40"))
	g.Rotation = 90
	g.Parent = bg
	label(bg, { Text = def.title, Size = UDim2.new(1, -40, 0, 74), Position = UDim2.fromOffset(20, 14), TextColor3 = def.color })
	label(bg, { Text = string.upper(def.sub), Size = UDim2.new(1, -40, 0, 30), Position = UDim2.fromOffset(20, 88), TextColor3 = Color3.fromHex("A9B4E6") })
	local rows = {}
	for i = 1, TOP do
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, -40, 0, 56)
		f.Position = UDim2.fromOffset(20, 128 + (i - 1) * 62)
		f.BackgroundColor3 = if i <= 3 then MEDAL[i] else Color3.fromHex("3A4AA6")
		f.BackgroundTransparency = if i <= 3 then 0.55 else 0.7
		f.BorderSizePixel = 0
		f.Visible = false
		f.Parent = bg
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 14)
		c.Parent = f
		local rank = label(f, { Text = "#" .. i, Size = UDim2.fromOffset(70, 44), Position = UDim2.fromOffset(6, 6), TextColor3 = if i <= 3 then MEDAL[i] else Color3.new(1, 1, 1) })
		local face = Instance.new("ImageLabel")
		face.BackgroundColor3 = Color3.fromHex("1E2350")
		face.Size = UDim2.fromOffset(46, 46)
		face.Position = UDim2.fromOffset(80, 5)
		face.Parent = f
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(1, 0)
		fc.Parent = face
		local name = label(f, { Text = "", Size = UDim2.fromOffset(270, 40), Position = UDim2.fromOffset(136, 8), TextXAlignment = Enum.TextXAlignment.Left })
		local value = label(f, { Text = "", Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -150, 0, 8), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = def.color })
		rows[i] = { frame = f, rank = rank, name = name, value = value, face = face }
	end
	local empty = label(bg, { Text = "No scores yet - be the first!", Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(40, 360), Visible = false, TextColor3 = Color3.fromHex("C9CCE6") })
	return { rows = rows, empty = empty }
end

local function paint(ui: BoardUi, def: StatDef, list: { Entry })
	ui.empty.Visible = #list == 0
	for i, row in ui.rows do
		local e = list[i]
		row.frame.Visible = e ~= nil
		if e then
			row.name.Text = e.name or ("Player " .. e.userId)
			row.value.Text = def.fmt(e.value)
			row.face.Image = thumbOf(e.userId)
		end
	end
end

local Data: any = nil

local function refresh()
	local loaded = Data.loaded()
	for player, p in loaded do
		writePlayer(player, p)
	end
	for _, def in STATS do
		local list = readTop(def.id)
		-- merge live values from this server (fresher than the store)
		local byUser: { [number]: Entry } = {}
		for _, e in list do
			byUser[e.userId] = e
		end
		for player, p in loaded do
			if not player:GetAttribute("DataLoadFailed") then
				local v = math.floor(statValue(def.id, p))
				if v > 0 then
					local e = byUser[player.UserId]
					if e then
						e.value = v
					else
						e = { userId = player.UserId, value = v }
						byUser[player.UserId] = e
						table.insert(list, e)
					end
				end
			end
		end
		table.sort(list, function(a, b)
			return a.value > b.value
		end)
		while #list > TOP do
			table.remove(list)
		end
		for _, e in list do
			e.name = nameOf(e.userId)
		end
		for board, ui in boardUi do
			if board:GetAttribute("Stat") == def.id then
				paint(ui, def, list)
			end
		end
	end
end

local function hook(board: Instance)
	local stat = board:GetAttribute("Stat")
	local screen = board:FindFirstChild("Screen", true)
	if not screen or not screen:IsA("BasePart") then
		return
	end
	for _, def in STATS do
		if def.id == stat then
			boardUi[board] = buildBoard(screen, def)
		end
	end
end

function Leaderboards.start(data: any)
	Data = data
	for _, b in CollectionService:GetTagged("Leaderboard") do
		hook(b)
	end
	CollectionService:GetInstanceAddedSignal("Leaderboard"):Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		local p = Data.get(player)
		if p then
			writePlayer(player, p)
		end
		lastWritten[player] = nil
	end)
	game:BindToClose(function()
		local pending = 0
		for player, p in Data.loaded() do
			pending += 1
			task.spawn(function()
				writePlayer(player, p)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 10 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		task.wait(8) -- first profiles load
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[Leaderboards]", err)
			end
			task.wait(REFRESH)
		end
	end)
end

return Leaderboards
