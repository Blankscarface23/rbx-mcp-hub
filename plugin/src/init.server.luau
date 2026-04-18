--[[
	rbx-mcp-hub Studio plugin.

	Long-polls the hub daemon at 127.0.0.1:44755 tagged with this Studio
	instance's PlaceId, dispatches tool calls, and posts results back.
	Multiple Studio windows = multiple plugin instances = each registers
	with its own PlaceId so the hub can route commands correctly.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Config)
local Context = require(script.Context)
Context.plugin = plugin

-- Plugins load in every DataModel (Edit, play-mode Server, play-mode
-- Client). In play-mode Server we just watch for a stop signal from
-- Edit so we can end the play session via StudioTestService:EndTest().
-- In play-mode Client we do nothing.
if not RunService:IsEdit() then
	if RunService:IsServer() then
		local GameStopUtil = require(script.Utils.GameStopUtil)
		task.spawn(GameStopUtil.monitorForStopPlay, plugin)
	end
	return
end

-- Edit DataModel: set up toolbar, long-poll the hub, dispatch tools.
local Tools = require(script.Tools)

local RUNNING = true
local USER_ENABLED = true

local TOOLBAR = plugin:CreateToolbar("rbx-mcp-hub")
local ICON = Config.ICON_ASSET_ID
	and ("rbxassetid://" .. tostring(Config.ICON_ASSET_ID))
	or "rbxasset://textures/StudioToolbox/ClassIconFallback.png"
local BUTTON = TOOLBAR:CreateButton(
	"Hub Status",
	"rbx-mcp-hub: click to toggle. Highlighted = connected.",
	ICON
)
BUTTON.ClickableWhenViewportHidden = true

local status = {
	connected = false,
	lastError = nil,
	commandsServed = 0,
	placeId = tostring(game.PlaceId),
	placeName = game.Name,
}

local function log(msg)
	print(string.format("[%s] %s", Config.PLUGIN_NAME, msg))
end

local function warnLog(msg)
	warn(string.format("[%s] %s", Config.PLUGIN_NAME, msg))
end

local function refreshButton()
	BUTTON:SetActive(USER_ENABLED and status.connected)
end

local function setConnected(connected, err)
	local changed = status.connected ~= connected
	status.connected = connected
	status.lastError = err
	refreshButton()
	if changed then
		if connected then
			log("🟢 connected")
		else
			log(string.format("🔴 disconnected · %s", tostring(err)))
		end
	end
end

local function syncPlaceId()
	-- Re-read PlaceId on every poll so publish-while-open re-registers
	-- under the new context instead of sticking on the stale one.
	local current = tostring(game.PlaceId)
	if current ~= status.placeId then
		log(string.format("🔁 PlaceId %s → %s", status.placeId, current))
		status.placeId = current
		status.placeName = game.Name
	end
end

local function hubUrl(path, query)
	local base = string.format("http://%s:%d%s", Config.HUB_HOST, Config.HUB_PORT, path)
	if query then
		local parts = {}
		for k, v in pairs(query) do
			table.insert(parts, HttpService:UrlEncode(k) .. "=" .. HttpService:UrlEncode(tostring(v)))
		end
		base = base .. "?" .. table.concat(parts, "&")
	end
	return base
end

local function postResponse(id, result, err)
	local body = HttpService:JSONEncode({
		id = id,
		result = result,
		error = err,
	})
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = hubUrl("/response"),
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = body,
	})
	if not ok then
		warnLog("⚠️  /response failed: " .. tostring(res))
	end
end

local function dispatch(cmd)
	status.commandsServed += 1
	log(string.format("🔧 %s", tostring(cmd.tool)))
	local handler = Tools[cmd.tool]
	if not handler then
		return postResponse(cmd.id, nil, "unknown tool: " .. tostring(cmd.tool))
	end
	local ok, result, err = pcall(handler, cmd.params or {})
	if not ok then
		return postResponse(cmd.id, nil, "handler crashed: " .. tostring(result))
	end
	if err then
		return postResponse(cmd.id, nil, tostring(err))
	end
	return postResponse(cmd.id, result, nil)
end

local function tryPing()
	-- Non-blocking: /status returns instantly. Lets the toolbar reflect
	-- hub reachability within ms, instead of waiting up to 15s for the
	-- first /request long-poll to return.
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = hubUrl("/status"),
		Method = "GET",
		Headers = { ["Accept"] = "application/json" },
	})
	if ok and res.StatusCode == 200 then
		setConnected(true, nil)
		return true
	end
	local err = ok and string.format("HTTP %d", res.StatusCode) or tostring(res)
	setConnected(false, err)
	return false
end

local function pollOnce()
	syncPlaceId()
	local url = hubUrl("/request", {
		context = status.placeId,
		name = status.placeName,
	})
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = url,
		Method = "GET",
		Headers = { ["Accept"] = "application/json" },
	})

	if not ok then
		setConnected(false, tostring(res))
		return false
	end

	if res.StatusCode == 200 then
		setConnected(true, nil)
		local decodeOk, cmd = pcall(HttpService.JSONDecode, HttpService, res.Body)
		if not decodeOk or type(cmd) ~= "table" then
			warnLog("⚠️  bad payload: " .. tostring(res.Body):sub(1, 200))
			return true
		end
		task.spawn(dispatch, cmd)
		return true
	end

	if res.StatusCode == 423 or res.StatusCode == 204 then
		setConnected(true, nil)
		return true
	end

	setConnected(false, string.format("HTTP %d", res.StatusCode))
	return false
end

local function pollLoop()
	while RUNNING do
		if USER_ENABLED then
			local ok = pollOnce()
			if not ok then
				task.wait(Config.RECONNECT_DELAY)
			end
		else
			task.wait(1)
		end
	end
end

BUTTON.Click:Connect(function()
	USER_ENABLED = not USER_ENABLED
	if USER_ENABLED then
		log("▶️  resumed")
		tryPing()
	else
		log("⏸️  paused")
		status.connected = false
		status.lastError = "paused"
		refreshButton()
	end
end)

plugin.Unloading:Connect(function()
	RUNNING = false
end)

log(string.format(
	"🔌 v%s · PlaceId=%s · Name=%s · hub %s:%d",
	Config.VERSION, status.placeId, status.placeName, Config.HUB_HOST, Config.HUB_PORT
))
tryPing()
task.spawn(pollLoop)
