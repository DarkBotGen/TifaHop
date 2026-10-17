-- ViciousHop rebuild. No recovered license code or encrypted functions.
local env = getgenv()
if game.PlaceId ~= 1537690962 then error("TifaHop: join Bee Swarm Simulator first", 0) end
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Teleports = game:GetService("TeleportService")
local Run = game:GetService("RunService")
if not game:IsLoaded() then game.Loaded:Wait() end
while not Players.LocalPlayer do task.wait(0.1) end
local player = Players.LocalPlayer
local connectionPath = "TifaHop-connection-" .. tostring(player.UserId) .. ".json"
if type(readfile) == "function" then
	local ok, connection = pcall(function() return Http:JSONDecode(readfile(connectionPath)) end)
	if ok and type(connection) == "table" then
		for _, key in ipairs({"relay", "relaytoken", "room", "role"}) do
			if env[key] == nil and type(connection[key]) == "string" then env[key] = connection[key] end
		end
	end
end
local cfg = {}
local defaults = {
	delay = "0", minlvl = "1", maxlvl = "12", onlygifted = false,
	mainwait = true, hook = "", uid = "", role = "main", room = "default",
	relay = "http://127.0.0.1:8787", relaytoken = "", tweenspeed = 80,
	scanseconds = 12, searchhold = 120, fighttimeout = 180, activate = true,
	sourcepath = "ViciousHop/client.luau", autoload = true, showui = true,
}
for key, value in pairs(defaults) do
	cfg[key] = if env[key] == nil then value else env[key]
end
local sharedKeys = {"delay", "minlvl", "maxlvl", "tweenspeed", "onlygifted", "mainwait", "activate"}
local configPath = "TifaskiHop-config-" .. tostring(cfg.room):gsub("[^%w_-]", "_") .. "-" .. tostring(player.UserId) .. ".json"
local function normalizeSettings(values)
	local result = {}
	for _, spec in ipairs({{"delay", 0, 3600}, {"minlvl", 1, 12}, {"maxlvl", 1, 12}, {"tweenspeed", 1, 120}}) do
		local value = tonumber(values[spec[1]])
		assert(value and value == value and value >= spec[2] and value <= spec[3], "Invalid " .. spec[1])
		if spec[1] == "minlvl" or spec[1] == "maxlvl" then assert(value % 1 == 0, "Levels must be whole numbers") end
		result[spec[1]] = value
	end
	assert(result.minlvl <= result.maxlvl, "Minimum level exceeds maximum")
	for _, key in ipairs({"onlygifted", "mainwait", "activate"}) do
		assert(type(values[key]) == "boolean", "Invalid " .. key); result[key] = values[key]
	end
	return result
end
if type(readfile) == "function" then
	local ok, saved = pcall(function() return normalizeSettings(Http:JSONDecode(readfile(configPath))) end)
	if ok then for key, value in pairs(saved) do cfg[key] = value end end
end
local function number(value, low, high, name)
	local n = tonumber(value)
	assert(n and n == n and n >= low and n <= high, "TifaHop: invalid " .. name)
	return n
end
cfg.delay = number(cfg.delay, 0, 3600, "delay")
cfg.minlvl = number(cfg.minlvl, 1, 12, "minlvl")
cfg.maxlvl = number(cfg.maxlvl, cfg.minlvl, 12, "maxlvl")
cfg.tweenspeed = number(cfg.tweenspeed, 1, 120, "tweenspeed")
cfg.scanseconds = number(cfg.scanseconds, 3, 120, "scanseconds")
cfg.searchhold = number(cfg.searchhold, 10, 600, "searchhold")
cfg.fighttimeout = number(cfg.fighttimeout, 10, 900, "fighttimeout")
assert(cfg.minlvl % 1 == 0 and cfg.maxlvl % 1 == 0, "Levels must be integers")
assert(cfg.role == "main" or cfg.role == "searcher", "role must be main or searcher")
assert(type(cfg.relaytoken) == "string" and #cfg.relaytoken >= 24, "Set relaytoken from relay-token.txt")
assert(type(cfg.room) == "string" and #cfg.room > 0 and #cfg.room <= 100, "Invalid room")
for _, key in ipairs({"onlygifted", "mainwait", "activate", "autoload"}) do
	assert(type(cfg[key]) == "boolean", key .. " must be true or false")
end
local requestFn = (syn and syn.request) or http_request or request or (http and http.request)
assert(type(requestFn) == "function", "Executor HTTP request support is required")
assert(type(cfg.relay) == "string" and cfg.relay:match("^https?://"), "Set relay to your LAN relay URL")
cfg.relay = cfg.relay:gsub("/+$", "")
if type(writefile) == "function" then
	pcall(function() writefile(connectionPath, Http:JSONEncode({relay = cfg.relay,
		relaytoken = cfg.relaytoken, room = cfg.room, role = cfg.role})) end)
end
local queuedSource
local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport)
if cfg.autoload then
	assert(type(queueFn) == "function", "Automatic hopping requires queue_on_teleport support")
	if type(env.vh_embedded_source) == "string" and #env.vh_embedded_source > 100 then
		queuedSource = env.vh_embedded_source
	else
		assert(type(readfile) == "function", "Use the self-contained script or provide readfile support")
		local ok, source = pcall(readfile, cfg.sourcepath)
		assert(ok and type(source) == "string" and #source > 100, "Save client.luau at " .. cfg.sourcepath)
		queuedSource = source
	end
end

if env.ViciousHop and env.ViciousHop.Stop then env.ViciousHop.Stop() end
local state = {running = true, connections = {}, collisions = {}, visited = {}, ignored = {},
	cooldowns = setmetatable({}, {__mode = "k"}), counted = setmetatable({}, {__mode = "k"}), status = "Starting"}
if type(env.vh_visited) == "table" then
	for job, timestamp in pairs(env.vh_visited) do
		if type(job) == "string" and type(timestamp) == "number" and os.time() - timestamp < 1800 then
			state.visited[job] = timestamp
		end
	end
end
env.ViciousHop = state
env.TifaskiHop = state
env.TifaHop = state
-- TIFASKI_STATS_BEGIN
local createStats = function(previous, clock)
	clock = clock or os.time
	previous = if type(previous) == "table" then previous else {}
	local function count(value)
		return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else 0
	end
	local data = {
		sessionStart = if type(previous.sessionStart) == "number" then previous.sessionStart else clock(),
		totalStart = if type(previous.totalStart) == "number" then previous.totalStart else clock() - count(previous.totalSeconds),
		sessionStingers = count(previous.sessionStingers), totalStingers = count(previous.totalStingers),
		sessionKills = count(previous.sessionKills), totalKills = count(previous.totalKills),
		lastInventory = previous.lastInventory,
	}
	local api = {}
	function api.Inventory(value)
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return false end
		if type(data.lastInventory) == "number" then
			local gain = math.max(0, value - data.lastInventory)
			data.sessionStingers += gain; data.totalStingers += gain
		end
		data.lastInventory = value
		return true
	end
	function api.Defeat() data.sessionKills += 1; data.totalKills += 1 end
	function api.Reset() data.sessionStart = clock(); data.sessionStingers = 0; data.sessionKills = 0 end
	function api.Snapshot()
		local snapshot = table.clone(data)
		snapshot.totalSeconds = math.max(0, clock() - data.totalStart)
		snapshot.sessionSeconds = math.max(0, clock() - data.sessionStart)
		return snapshot
	end
	return api
end

-- TIFASKI_STATS_END
local statsPath = "TifaskiHop-stats-" .. tostring(player.UserId) .. ".json"
local previousStats = env.vh_stats
if type(previousStats) ~= "table" and type(readfile) == "function" then
	local ok, saved = pcall(function() return Http:JSONDecode(readfile(statsPath)) end)
	if ok and type(saved) == "table" then
		previousStats = {totalKills = saved.totalKills, totalStingers = saved.totalStingers, totalSeconds = saved.totalSeconds}
	end
end
state.stats = createStats(previousStats)
local function saveStats()
	env.vh_stats = state.stats.Snapshot()
	if type(writefile) == "function" then pcall(function() writefile(statsPath, Http:JSONEncode(env.vh_stats)) end) end
end
local function status(message)
	state.status = message
	print("[TifaHop] " .. message)
end
local function relay(action, body)
	body = body or {}
	body.room, body.actor = cfg.room, tostring(player.UserId)
	state.relayOnline = false
	local response = requestFn({Url = cfg.relay .. "/" .. action, Method = "POST",
		Headers = {["Content-Type"] = "application/json", Authorization = "Bearer " .. cfg.relaytoken},
		Body = Http:JSONEncode(body)})
	state.relayOnline = response and tonumber(response.StatusCode) == 200
	assert(state.relayOnline, "Relay " .. action .. " failed (check URL/token)")
	local decoded = Http:JSONDecode(response.Body)
	assert(decoded.ok, "Relay rejected " .. action)
	return decoded
end
local function applySettings(response)
	if type(response.revision) ~= "number" or response.revision <= (state.settingsRevision or 0) then return end
	local merged = {}
	for _, key in ipairs(sharedKeys) do merged[key] = cfg[key] end
	for key, value in pairs(response.values or {}) do merged[key] = value end
	local values = normalizeSettings(merged)
	for key, value in pairs(values) do cfg[key] = value; env[key] = value end
	state.settingsRevision = response.revision
	state.configSaved = false
	if type(writefile) == "function" then
		state.configSaved = pcall(function() writefile(configPath, Http:JSONEncode(values)) end)
	end
	if state.panel then state.panel.SettingsChanged() end
end
local function syncSettings() applySettings(relay("settings-get")) end
local function saveSharedSettings(values)
	local ok, result = pcall(function()
		values = normalizeSettings(values)
		local response = relay("settings-set", {revision = state.settingsRevision or 0, values = values})
		applySettings(response)
		if response.conflict then return "Settings changed elsewhere; refreshed. Review and save again." end
		return if state.configSaved then "Saved to workspace; syncing all alts." else "Saved on relay; local workspace writing unavailable."
	end)
	return ok, if ok then result else "Save failed: " .. tostring(result)
end
local function cleanupMovement()
	if state.motionConnection then state.motionConnection:Disconnect(); state.motionConnection = nil end
	if state.align then state.align:Destroy(); state.align = nil end
	if state.attachment then state.attachment:Destroy(); state.attachment = nil end
	for part, value in pairs(state.collisions) do
		if part.Parent then part.CanCollide = value end
	end
	table.clear(state.collisions)
	if state.humanoid and state.humanoid.Parent and state.humanoid.Health > 0 then
		state.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	state.humanoid, state.root = nil, nil
end
function state.Stop()
	state.running = false
	saveStats()
	if state.panel then state.panel.Destroy(); state.panel = nil end
	cleanupMovement()
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
	if state.claim then pcall(relay, "release", {job = state.claim}); state.claim = nil end
	if state.reported then pcall(relay, "withdraw", {job = game.JobId}); state.reported = nil end
	status("Stopped")
end
table.insert(state.connections, player.CharacterAdded:Connect(cleanupMovement))
local function character()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then return char, root, humanoid end
end
-- Same AlignPosition approach as Atlas's tweenTo; speed is studs/second.
local function move(goal)
	local char, root, humanoid = character()
	if not char then cleanupMovement(); return false end
	if state.root ~= root then
		cleanupMovement()
		state.root, state.humanoid = root, humanoid
		local attachment = Instance.new("Attachment")
		attachment.Name = "ViciousHopAttachment"
		attachment.Parent = root
		state.attachment = attachment
		local align = Instance.new("AlignPosition")
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.Responsiveness, align.MaxForce, align.MaxVelocity = 20, math.huge, cfg.tweenspeed
		align.Position, align.Parent = root.Position, root
		state.align = align
		state.motionConnection = Run.PreSimulation:Connect(function()
			if not state.running or not root.Parent or humanoid.Health <= 0 then cleanupMovement(); return end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					if state.collisions[part] == nil then state.collisions[part] = part.CanCollide end
					part.CanCollide = false
				end
			end
		end)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	state.align.MaxVelocity = cfg.tweenspeed
	state.align.Position = goal
	return (root.Position - goal).Magnitude < 6
end
local function fieldAt(position)
	local zones = workspace:FindFirstChild("FlowerZones")
	if not zones then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {zones}
	local hit = workspace:Raycast(position - Vector3.new(0, 35, 0), Vector3.new(0, 50, 0), params)
	return hit and hit.Instance
end
local function observe()
	local monsters = workspace:FindFirstChild("Monsters")
	local found = {}
	if not monsters then return found end
	for _, mob in ipairs(monsters:GetChildren()) do
		if mob.Name:find("Vicious", 1, true) then
			local level = tonumber(mob.Name:match("%d+"))
			local gifted = mob.Name:find("Gifted", 1, true) ~= nil
			local root = mob:FindFirstChild("HumanoidRootPart")
			local humanoid = mob:FindFirstChildOfClass("Humanoid")
			if root and level and level >= cfg.minlvl and level <= cfg.maxlvl
				and (not cfg.onlygifted or gifted) and (not humanoid or humanoid.Health > 0) then
				local field = fieldAt(root.Position)
				table.insert(found, {mob = mob, root = root, level = level, gifted = gifted, field = field})
			end
		end
	end
	table.sort(found, function(a, b) if a.gifted ~= b.gifted then return a.gifted end; return a.level < b.level end)
	return found
end
local function notify(target)
	if cfg.hook == "" then return end
	-- Notifications run only when this script reports a sighting; no remote code.
	local content = string.format("%sVicious Bee%s, level %d, %s\nServer: %s",
		if tostring(cfg.uid):match("^%d+$") then "<@" .. tostring(cfg.uid) .. "> " else "",
		if target.gifted then " (Gifted)" else "", target.level,
		if target.field then target.field.Name else "unknown field", game.JobId)
	task.spawn(function()
		local ok, response = pcall(requestFn, {Url = cfg.hook, Method = "POST",
			Headers = {["Content-Type"] = "application/json"},
			Body = Http:JSONEncode({content = content, allowed_mentions = {parse = {},
				users = if tostring(cfg.uid):match("^%d+$") then {tostring(cfg.uid)} else {}}})})
		if not ok or not response or tonumber(response.StatusCode) < 200 or tonumber(response.StatusCode) >= 300 then
			warn("[TifaHop] Webhook failed")
		end
	end)
end
local function publish(target)
	relay("report", {job = game.JobId, level = target.level, gifted = target.gifted,
		field = if target.field then target.field.Name else ""})
	state.reported = true
	if not state.notified or state.notified ~= target.mob then state.notified = target.mob; notify(target) end
end
local function activateThorn()
	if not cfg.activate then return end
	local particles = workspace:FindFirstChild("Particles")
	local thorns = particles and particles:FindFirstChild("WTs")
	if not thorns then return end
	local thorn = thorns:FindFirstChild("WaitingThorn")
	if not thorn or not thorn:IsA("BasePart") then return end
	status("Approaching dormant Vicious thorn (level/gifted status unknown until spawned)")
	local deadline = os.clock() + 25
	while state.running and not state.paused and thorn.Parent and os.clock() < deadline and #observe() == 0 do
		move(thorn.Position + Vector3.new(0, 3, 0))
		task.wait(0.15)
	end
	cleanupMovement()
end
local function queueContinuation(job)
	if not cfg.autoload then return end
	local settings = Http:JSONEncode(cfg)
	local pending = if cfg.role == "main" then job else ""
	local code = "local e=getgenv();e.vh_stats=game:GetService('HttpService'):JSONDecode(" .. string.format("%q", Http:JSONEncode(state.stats.Snapshot()))
		.. ");local c=game:GetService('HttpService'):JSONDecode(" .. string.format("%q", settings)
		.. ");for k,v in pairs(c) do e[k]=v end;e.vh_pending=" .. string.format("%q", pending)
		.. ";e.vh_visited=game:GetService('HttpService'):JSONDecode(" .. string.format("%q", Http:JSONEncode(state.visited))
		.. ");e.vh_embedded_source=" .. string.format("%q", queuedSource)
		.. ";loadstring(e.vh_embedded_source)()"
	queueFn(code)
end
local function teleport(job)
	cleanupMovement()
	if cfg.delay > 0 then
		local untilTime = os.clock() + cfg.delay
		local renew = 0
		while state.running and os.clock() < untilTime do
			if state.claim and os.clock() >= renew then relay("renew", {job = state.claim}); renew = os.clock() + 15 end
			task.wait(0.25)
		end
	end
	if not state.running or state.paused then return false end
	queueContinuation(job)
	status("Joining " .. job)
	state.teleportFailed = false
	local ok, err = pcall(function() Teleports:TeleportToPlaceInstance(game.PlaceId, job, player) end)
	if not ok then warn("[TifaHop] " .. tostring(err)); return false end
	local deadline = os.clock() + 25
	while state.running and not state.teleportFailed and os.clock() < deadline do task.wait(0.25) end
	return false -- Successful teleport destroys this execution; reaching here means failure/timeout.
end
table.insert(state.connections, Teleports.TeleportInitFailed:Connect(function(who, _, message)
	if who == player then state.teleportFailed = true; warn("[TifaHop] Teleport failed: " .. tostring(message)) end
end))
local function hop()
	state.visited[game.JobId] = os.time()
	for job, timestamp in pairs(state.visited) do if os.time() - timestamp > 1800 then state.visited[job] = nil end end
	local cursor = ""
	local attempts = 0
	for _ = 1, 5 do
		if not state.running then return end
		local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
			.. "/servers/Public?sortOrder=Asc&limit=100&cursor=" .. Http:UrlEncode(cursor)
		local response = requestFn({Url = url, Method = "GET"})
		assert(response and tonumber(response.StatusCode) == 200, "Server list unavailable; retrying later")
		local body = Http:JSONDecode(response.Body)
		for _, server in ipairs(body.data or {}) do
			if server.id ~= game.JobId and not state.visited[server.id] and server.playing < server.maxPlayers then
				local visit = relay("visit", {job = server.id})
				if not visit.available then continue end
				state.visited[server.id] = os.time()
				teleport(server.id)
				attempts += 1
				if not state.running then return end
				if attempts >= 3 then task.wait(15); return end
			end
		end
		cursor = body.nextPageCursor
		if not cursor or cursor == "" then break end
	end
	status("No joinable unvisited server; retrying in 15 seconds")
	task.wait(15)
end
local function fight(target)
	status(string.format("Following %s (level %d)", target.mob.Name, target.level))
	local deadline, renew = os.clock() + cfg.fighttimeout, 0
	local observedDefeat = false
	while state.running and not state.paused and target.mob.Parent and target.root.Parent and os.clock() < deadline do
		if target.level < cfg.minlvl or target.level > cfg.maxlvl or (cfg.onlygifted and not target.gifted) then break end
		local humanoid = target.mob:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then observedDefeat = true; break end
		local field = fieldAt(target.root.Position) or target.field
		-- Atlas farms around mob root -15Y. Clamp to the FlowerZone ground plane.
		local y = target.root.Position.Y - 15
		if field then y = math.max(y, field.Position.Y + 3) end
		move(Vector3.new(target.root.Position.X + 10, y, target.root.Position.Z))
		if state.claim and os.clock() >= renew then relay("renew", {job = state.claim}); renew = os.clock() + 15 end
		task.wait(0.15)
	end
	cleanupMovement()
	if observedDefeat and not state.counted[target.mob] then
		state.counted[target.mob] = true; state.stats.Defeat(); saveStats()
	end
	status(if target.mob.Parent then "Target follow ended; not counted as a kill" else "Target disappeared")
	return not target.mob.Parent
end
local function mainStep()
	local targets = observe()
	local target
	for _, candidate in ipairs(targets) do
		if (state.cooldowns[candidate.mob] or 0) <= os.clock() then target = candidate; break end
	end
	if target then
		if state.notified ~= target.mob then state.notified = target.mob; notify(target) end
		local finished = fight(target)
		if not finished then state.cooldowns[target.mob] = os.clock() + 60 end
		if state.claim then
			relay(if finished then "consume" else "release", {job = state.claim})
			state.ignored[state.claim] = os.clock() + 120
			state.claim = nil
		end
		if not finished then task.wait(3) end
		return
	end
	if state.claim then relay("consume", {job = state.claim}); state.claim = nil end
	local excluded = {game.JobId}
	for job, deadline in pairs(state.ignored) do
		if deadline > os.clock() then table.insert(excluded, job) else state.ignored[job] = nil end
	end
	local result = relay("claim", {minlvl = cfg.minlvl, maxlvl = cfg.maxlvl,
		onlygifted = cfg.onlygifted, exclude = excluded})
	if result.sighting then
		local job = result.sighting.job
		state.claim = job
		teleport(job)
		relay("release", {job = job})
		state.ignored[job], state.claim = os.clock() + 60, nil
	elseif cfg.mainwait then status("Waiting for searchers"); task.wait(3)
	else activateThorn(); if #observe() == 0 then hop() end end
end
local function searcherStep()
	status("Scanning this server")
	local deadline = os.clock() + cfg.scanseconds
	while state.running and not state.paused and #observe() == 0 and os.clock() < deadline do task.wait(0.5) end
	if state.paused or not state.running then return end
	if #observe() == 0 then activateThorn() end
	local target = observe()[1]
	if target then
		status("Reporting Vicious server to mains")
		local untilTime = os.clock() + cfg.searchhold
		while state.running and not state.paused and os.clock() < untilTime do
			local current = observe()[1]
			if not current then relay("withdraw", {job = game.JobId}); state.reported = nil; break end
			publish(current)
			task.wait(10)
		end
	end
	if state.running then hop() end
end

task.spawn(function()
	local ok, err = xpcall(function()
		workspace:WaitForChild("Monsters", 60)
		workspace:WaitForChild("FlowerZones", 60)
		-- Allow newly joined characters and replicated monsters to arrive.
		task.wait(cfg.scanseconds)
		syncSettings()
		relay("visit", {job = game.JobId})
		if cfg.role == "main" and type(env.vh_pending) == "string" and env.vh_pending == game.JobId then
			state.claim = game.JobId
			relay("renew", {job = game.JobId})
		end
		env.vh_pending = nil
		while state.running do
			if state.paused then task.wait(0.5); continue end
			local stepOk, stepErr = xpcall(if cfg.role == "main" then mainStep else searcherStep, debug.traceback)
			if not stepOk then
				cleanupMovement()
				status("Retrying after error: " .. tostring(stepErr))
				task.wait(5)
			end
		end
	end, debug.traceback)
	if not ok then state.Stop(); warn("[TifaHop] " .. tostring(err)) end
end)
status(if cfg.role == "main" then "Waiting for searchers" else "Scanning server")
task.spawn(function()
	while state.running do pcall(syncSettings); task.wait(3) end
end)
-- TIFASKI_UI_BEGIN
-- Atlas widget definitions with a responsive compact Info/Settings shell.
local createPanel = function(cfg, state, actions)
-- ATLAS_PARTS_BEGIN
-- Widget definitions copied from the user-supplied atlasbss.lua.
local createAtlasParts = function(uicolor)
	local uiParts = {}
	do
		local TextButton3 = Instance.new("TextButton")
		TextButton3.Name = "Button"
		TextButton3.AutoButtonColor = false
		TextButton3.BackgroundColor3 = uicolor
		TextButton3.BorderSizePixel = 0
		TextButton3.ClipsDescendants = true
		TextButton3.Font = Enum.Font.GothamBold
		TextButton3.TextColor3 = Color3.new(1, 1, 1)
		TextButton3.TextSize = 13
		TextButton3.Size = UDim2.new(0, 91, 0, 20)
		uiParts.button = TextButton3
		local UICorner5 = Instance.new("UICorner")
		UICorner5.Name = "UICorner"
		UICorner5.CornerRadius = UDim.new(0, 4)
		UICorner5.Parent = TextButton3
	end

	local TextLabel2 = Instance.new("TextLabel")
	TextLabel2.Name = "Label"
	TextLabel2.BackgroundTransparency = 1
	TextLabel2.Font = Enum.Font.GothamSemibold
	TextLabel2.TextColor3 = Color3.new(1, 1, 1)
	TextLabel2.TextSize = 13
	TextLabel2.TextXAlignment = Enum.TextXAlignment.Left
	uiParts.label = TextLabel2

	return uiParts
end

-- ATLAS_PARTS_END
-- LAYOUT_BEGIN
-- All dimensions are logical Atlas units; one UIScale transforms the whole tree.
local calculateLayout = function(width, height, multiplier, position, collapsed)
	width, height = math.max(1, width), math.max(1, height)
	multiplier = math.clamp(multiplier or 1, 0.65, 1.5)
	local scale = math.min(width / 712.5, height / 600, 0.8) * multiplier
	scale = math.min(scale, width * 0.95 / 450, height * 0.95 / 492)
	local panelWidth, panelHeight = 450 * scale, (if collapsed then 30 else 492) * scale
	local positionX, positionY = (position and position.X or 0.06) * width, (position and position.Y or 0.1775) * height
	return {scale = scale, width = panelWidth, height = panelHeight,
		x = math.clamp(positionX, 0, math.max(0, width - panelWidth)),
		y = math.clamp(positionY, 0, math.max(0, height - panelHeight))}
end

-- LAYOUT_END
	local UIS = game:GetService("UserInputService")
	local links, labels, api = {}, {}, {}
	local atlasParts = createAtlasParts(Color3.fromRGB(29, 30, 34))
	local function logicalOffset(x, y) return UDim2.fromOffset(x * 1.5, y * 1.5) end
	local function make(kind, properties, parent)
		local object = Instance.new(kind)
		for key, value in pairs(properties) do object[key] = value end
		object.Parent = parent
		return object
	end
	local function connect(signal, fn) table.insert(links, signal:Connect(fn)) end
	local gui = make("ScreenGui", {Name = "TifaskiHop", ResetOnSpawn = false, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, gethui and gethui() or game:GetService("CoreGui"))
	local host = make("Frame", {Name = "ResponsivePosition", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0)}, gui)
	local window = make("Frame", {Name = "Window", Size = logicalOffset(300, 328), Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(21, 22, 23), BorderSizePixel = 0, ClipsDescendants = true, Active = true}, host)
	local uiScale = make("UIScale", {Name = "ViewportScale", Scale = 1}, window)
	make("Frame", {Name = "TopLine", Size = UDim2.new(1, 0, 0, 1.5), BackgroundColor3 = Color3.fromRGB(65, 95, 147), BorderSizePixel = 0}, window)
	local bar = make("Frame", {Name = "Bar", Size = UDim2.new(1, 0, 0, 27), Position = logicalOffset(0, 2),
		BackgroundColor3 = Color3.fromRGB(30, 30, 34), BorderSizePixel = 0, Active = true}, window)
	local function text(parentObject, value, x, y, width, height, bold)
		local object = atlasParts.label:Clone()
		object.Text, object.TextYAlignment = value, Enum.TextYAlignment.Center
		if bold then object.Font = Enum.Font.GothamBold; object.TextSize = 14 end
		object.Position, object.Size = logicalOffset(x, y), logicalOffset(width, height)
		object.Parent = parentObject
		return object
	end
	text(bar, "TifaHop", 18, 0, 245, 17, true)
	local function button(parentObject, value, x, y, width, fn)
		local object = atlasParts.button:Clone()
		object.Text, object.Position, object.Size = value, logicalOffset(x, y), logicalOffset(width, 14)
		object.Parent = parentObject
		connect(object.MouseButton1Click, fn)
		return object
	end
	local collapsed = false
	local updateScale
	local collapse
	collapse = button(bar, "▼", 1, 0, 15, function()
		collapsed = not collapsed
		window.Size = logicalOffset(300, if collapsed then 20 else 328)
		collapse.Text = if collapsed then "▶" else "▼"
		if updateScale then updateScale() end
	end)
	collapse.BackgroundTransparency = 1
	collapse.TextSize = 20
	local tabStrip = make("Frame", {BackgroundColor3 = Color3.fromRGB(26, 25, 30), BorderSizePixel = 0,
		Position = logicalOffset(0, 22), Size = UDim2.new(1, 0, 0, 27)}, window)
	local info = make("Frame", {Name = "Info", BackgroundTransparency = 1, Position = logicalOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -60)}, window)
	local settings = make("ScrollingFrame", {Name = "Settings", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = logicalOffset(8, 44), Size = UDim2.new(1, -24, 1, -75), CanvasSize = logicalOffset(0, 465),
		ScrollBarThickness = 2, Visible = false}, window)
	local infoTab, settingsTab
	local function selectTab(showInfo)
		info.Visible, settings.Visible = showInfo, not showInfo
		infoTab.BackgroundColor3 = if showInfo then Color3.fromRGB(50, 50, 54) else Color3.fromRGB(29, 30, 34)
		settingsTab.BackgroundColor3 = if showInfo then Color3.fromRGB(29, 30, 34) else Color3.fromRGB(50, 50, 54)
	end
	infoTab = button(tabStrip, "Info", 8, 1, 30, function() selectTab(true) end)
	settingsTab = button(tabStrip, "Settings", 43, 1, 52, function() selectTab(false) end)
	infoTab.Size = logicalOffset(30, 16)
	settingsTab.Size = logicalOffset(52, 16)
	selectTab(true)
	local discord = "discord.gg/tifahop"
	text(info, discord, 8, 2, 280, 15)
	button(info, "Copy discord", 8, 21, 68, function() if type(setclipboard) == "function" then setclipboard(discord) end end)
	text(info, "open ticket in discord for help", 8, 37, 280, 15)
	labels.status = text(info, "Starting", 8, 72, 285, 15)
	labels.room = text(info, "Room: " .. cfg.room .. " [" .. (if cfg.role == "searcher" then "alt" else "main") .. "]", 8, 89, 285, 15)
	local rows = {{"sessionStingers", "Session stingers: 0"}, {"totalStingers", "Total stingers: 0"},
		{"sessionKills", "Session kills: 0"}, {"totalKills", "All time kills: 0"}, {"rate", "Stingers per hour: 0"},
		{"sessionTime", "Session time: 0s"}, {"totalTime", "Total time: 0s"}}
	for index, row in ipairs(rows) do labels[row[1]] = text(info, row[2], 8, 123 + math.floor((index - 1) * 17.5), 285, 15) end
	button(info, "Reset session", 8, 244, 69, actions.reset)
	text(settings, "Shared settings • all accounts in this room", 0, 0, 280, 18, true)
	local fields, toggles = {}, {}
	local numeric = {{"Hop delay (seconds)", "delay"}, {"Minimum level", "minlvl"}, {"Maximum level", "maxlvl"}, {"Travel speed", "tweenspeed"}}
	for index, item in ipairs(numeric) do
		local y = 25 + (index - 1) * 43
		text(settings, item[1], 0, y, 270, 15)
		fields[item[2]] = make("TextBox", {Text = tostring(cfg[item[2]]), ClearTextOnFocus = false,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(52, 53, 56),
			BorderSizePixel = 0, Position = logicalOffset(0, y + 17), Size = logicalOffset(270, 20)}, settings)
	end
	for index, item in ipairs({{"Gifted only", "onlygifted"}, {"Main waits", "mainwait"}, {"Activate dormant thorn", "activate"}}) do
		local object
		local function title() return item[1] .. ": " .. (if toggles[item[2]] then "ON" else "OFF") end
		toggles[item[2]] = cfg[item[2]]
		object = button(settings, title(), 0, 205 + (index - 1) * 24, 270, function()
			toggles[item[2]] = not toggles[item[2]]; object.Text = title()
		end)
		fields["toggle_" .. item[2]] = {object = object, title = title}
	end
	local feedback = text(settings, "Saved settings sync to all alts within 3 seconds.", 0, 312, 278, 36)
	feedback.TextWrapped = true
	button(settings, "Save & apply to all alts", 0, 282, 163, function()
		local values = {}
		for key, object in pairs(fields) do if not key:find("toggle_", 1, true) then values[key] = tonumber(object.Text) end end
		for key, value in pairs(toggles) do values[key] = value end
		local ok, message = actions.settings(values)
		feedback.Text = message or (if ok then "Saved and synced." else "Could not save.")
	end)
	text(settings, "Role: " .. cfg.role .. " • room: " .. cfg.room .. "\nRole and relay credentials stay account-specific.\nRight Shift hides/shows this panel.", 0, 355, 278, 50).TextWrapped = true
	button(settings, "Pause / resume", 0, 415, 120, actions.pause)
	button(settings, "Stop", 128, 415, 60, actions.stop)
	local dragging, resizing, startInput, startPosition
	local viewport = {X = 475, Y = 400}
	local relativePosition = {X = 0.06, Y = 0.1775}
	local resizeMultiplier = 1
	updateScale = function()
		local camera = workspace and workspace.CurrentCamera
		local size = camera and camera.ViewportSize or gui.AbsoluteSize
		if size and size.X > 0 and size.Y > 0 then viewport = size end
		local layout = calculateLayout(viewport.X, viewport.Y, resizeMultiplier, relativePosition, collapsed)
		uiScale.Scale = layout.scale
		host.Position = UDim2.fromOffset(layout.x, layout.y)
		state.uiLayout = layout
	end
	local cameraLink
	local function bindCamera()
		if cameraLink then cameraLink:Disconnect() end
		local camera = workspace and workspace.CurrentCamera
		if camera then
			cameraLink = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	if workspace then connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera) end
	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)
	bindCamera()
	local resize = make("Frame", {Name = "Resize", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(1, -30, 1, -30), Size = logicalOffset(20, 20), Active = true, ZIndex = 5}, window)
	text(resize, "◢", 5, 3, 15, 17)
	connect(resize.InputBegan, function(inputObject)
		if not collapsed and (inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch) then resizing = true; dragging = false end
	end)
	connect(bar.InputBegan, function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
			dragging, startInput, startPosition = true, inputObject.Position, state.uiLayout
		end
	end)
	connect(UIS.InputChanged, function(inputObject)
		if resizing and (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch) then
			local base = math.min(viewport.X / 712.5, viewport.Y / 600, 0.8)
			resizeMultiplier = math.clamp(math.max((inputObject.Position.X - state.uiLayout.x) / (450 * base),
				(inputObject.Position.Y - state.uiLayout.y) / (492 * base)), 0.65, 1.5)
			updateScale()
		elseif dragging and (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch) then
			local delta = inputObject.Position - startInput
			relativePosition = {X = (startPosition.x + delta.X) / viewport.X, Y = (startPosition.y + delta.Y) / viewport.Y}
			updateScale()
		end
	end)
	connect(UIS.InputEnded, function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then dragging = false; resizing = false end
	end)
	connect(UIS.InputBegan, function(inputObject, processed)
		if not processed and inputObject.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
	end)
	function api.SettingsChanged()
		for key, object in pairs(fields) do
			if key:find("toggle_", 1, true) then
				local setting = key:sub(8); toggles[setting] = cfg[setting]; object.object.Text = object.title()
			else object.Text = tostring(cfg[key]) end
		end
	end
	function api.Update(values) for key, value in pairs(values) do if labels[key] then labels[key].Text = value end end end
	function api.Destroy()
		if cameraLink then cameraLink:Disconnect() end
		for _, connection in ipairs(links) do connection:Disconnect() end
		for _, template in pairs(atlasParts) do template:Destroy() end
		gui:Destroy()
	end
	return api
end

-- TIFASKI_UI_END
if cfg.showui then
	local ok, panel = pcall(createPanel, cfg, state, {
		settings = saveSharedSettings,
		reset = function() state.stats.Reset(); saveStats() end,
		pause = function()
			state.paused = not state.paused
			if state.paused then cleanupMovement(); status("Paused") else status("Resuming") end
		end,
		stop = state.Stop,
	})
	if not ok then warn("[TifaHop] UI could not open: " .. tostring(panel))
	else
		state.panel = panel
		task.spawn(function()
			local cache, nextSave = nil, 0
			local function duration(seconds) return tostring(seconds) .. "s" end
			while state.running and state.panel == panel do
				local hasInventory = false
				local statOK, inventory = pcall(function()
					if not cache then
						local module = game:GetService("ReplicatedStorage"):FindFirstChild("ClientStatCache")
						if module then cache = require(module) end
					end
					local data = cache and cache.Get()
					return data and data.Eggs and data.Eggs.Stinger
				end)
				if statOK then hasInventory = state.stats.Inventory(inventory) end
				local s = state.stats.Snapshot()
				local displayStatus = if state.paused then "Paused" else state.status
				if displayStatus:match("^Joining ") then displayStatus = "Hopping (server list)" end
				panel.Update({status = displayStatus, room = "Room: " .. cfg.room .. " [" .. (if cfg.role == "searcher" then "alt" else "main") .. "]",
					relay = "Relay: " .. (if state.relayOnline then "connected" else "connecting / unavailable"),
					sessionStingers = "Session stingers: " .. (if hasInventory then tostring(s.sessionStingers) else "—"),
					totalStingers = "Total stingers: " .. tostring(s.totalStingers),
					sessionKills = "Session kills: " .. tostring(s.sessionKills),
					totalKills = "All time kills: " .. tostring(s.totalKills),
					rate = "Stingers per hour: " .. (if hasInventory then tostring(math.floor(s.sessionStingers * 3600 / math.max(1, s.sessionSeconds))) else "—"),
					sessionTime = "Session time: " .. duration(s.sessionSeconds), totalTime = "Total time: " .. duration(s.totalSeconds)})
				if os.clock() >= nextSave then saveStats(); nextSave = os.clock() + 10 end
				task.wait(1)
			end
		end)
	end
end
