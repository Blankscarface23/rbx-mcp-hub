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
local Tools = require(script.Tools)

local RUNNING = true
local TOOLBAR = plugin:CreateToolbar("rbx-mcp-hub")
local BUTTON = TOOLBAR:CreateButton(
	"Hub Status",
	"rbx-mcp-hub: connection status",
	"rbxasset://textures/StudioToolbox/ClassIconFallback.png"
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

local function updateButtonIcon()
	if status.connected then
		BUTTON.Icon = "rbxasset://textures/StudioToolbox/ClassIconFallback.png"
	else
		BUTTON.Icon = "rbxasset://textures/StudioToolbox/ClassIconFallback.png"
	end
end

BUTTON.Click:Connect(function()
	print(string.format(
		"[%s v%s] PlaceId=%s Name=%s connected=%s commands=%d lastError=%s",
		Config.PLUGIN_NAME,
		Config.VERSION,
		status.placeId,
		status.placeName,
		tostring(status.connected),
		status.commandsServed,
		tostring(status.lastError)
	))
end)

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
		warnLog("failed to POST /response: " .. tostring(res))
	end
end

local function dispatch(cmd)
	status.commandsServed += 1
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

local function pollOnce()
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
		status.connected = false
		status.lastError = tostring(res)
		return false
	end

	if res.StatusCode == 200 then
		status.connected = true
		status.lastError = nil
		local decodeOk, cmd = pcall(HttpService.JSONDecode, HttpService, res.Body)
		if not decodeOk or type(cmd) ~= "table" then
			warnLog("invalid command payload: " .. tostring(res.Body):sub(1, 200))
			return true
		end
		task.spawn(dispatch, cmd)
		return true
	end

	if res.StatusCode == 423 or res.StatusCode == 204 then
		status.connected = true
		status.lastError = nil
		return true
	end

	status.connected = false
	status.lastError = string.format("HTTP %d %s", res.StatusCode, res.StatusMessage or "")
	return false
end

local function pollLoop()
	log(string.format("starting poll loop against %s:%d (PlaceId=%s)", Config.HUB_HOST, Config.HUB_PORT, status.placeId))
	while RUNNING do
		local ok = pollOnce()
		if not ok then
			task.wait(Config.RECONNECT_DELAY)
		end
		updateButtonIcon()
	end
	log("poll loop stopped")
end

plugin.Unloading:Connect(function()
	RUNNING = false
end)

task.spawn(pollLoop)
log(string.format("v%s loaded. PlaceId=%s", Config.VERSION, status.placeId))
