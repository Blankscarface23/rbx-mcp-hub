--[[
	run_script_in_play_mode: one-shot test runner.

	1. Stop any current play session.
	2. Inject a wrapper Script into ServerScriptService. The wrapper pcalls
	   the user's code, captures LogService output, and calls
	   StudioTestService:EndTest() with a structured result.
	3. Call StudioTestService:ExecutePlayModeAsync({}) for `mode="play"`
	   (full Play Solo — client + server + character) or
	   StudioTestService:ExecuteRunModeAsync({}) for `mode="run"`
	   (server-only, no character spawning). Both yield until the wrapper's
	   EndTest runs. The EndTest payload flows back as the return value.
	4. Remove the injected Script.

	Only side="server" is implemented. Client-side injection is a TODO.

	Pattern ported from Roblox/studio-rust-mcp-server (MIT).
]]

local StudioTestService = game:GetService("StudioTestService")
local ServerScriptService = game:GetService("ServerScriptService")

local Context = require(script.Parent.Parent.Context)
local GameStopUtil = require(script.Parent.Parent.Utils.GameStopUtil)

local TEST_SCRIPT_NAME = "_rbx_mcp_hub_TestRunner"

local function buildRunnerSource(userCode, timeoutSec)
	return string.format(
		[[
local StudioTestService = game:GetService("StudioTestService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

if not RunService:IsRunning() then
	return
end

local capturedLogs = {}
local MESSAGE_TYPE = {
	[Enum.MessageType.MessageOutput] = "output",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warning",
	[Enum.MessageType.MessageError] = "error",
}

local logConn = LogService.MessageOut:Connect(function(message, messageType)
	-- Filter out our own plugin chatter so it doesn't pollute test logs.
	if string.sub(message, 1, 14) == "[rbx-mcp-hub]" then
		return
	end
	table.insert(capturedLogs, {
		level = MESSAGE_TYPE[messageType] or "output",
		message = message,
	})
end)

local startClock = os.clock()
local ended = false
local isTimeout = false

local function endOnce(success, value, errorMsg)
	if ended then
		return
	end
	ended = true
	task.wait(0.05)
	if logConn then
		logConn:Disconnect()
	end
	StudioTestService:EndTest({
		success = success,
		returnValue = value,
		error = errorMsg,
		logs = capturedLogs,
		duration = os.clock() - startClock,
		isTimeout = isTimeout,
	})
end

task.spawn(function()
	task.wait(%s)
	if not ended then
		isTimeout = true
		endOnce(false, nil, "timeout after %s seconds")
	end
end)

local ok, result = pcall(function()
%s
end)

if ok then
	endOnce(true, if result ~= nil then tostring(result) else nil, nil)
else
	endOnce(false, nil, tostring(result))
end
]],
		tostring(timeoutSec),
		tostring(timeoutSec),
		userCode
	)
end

local function removeExistingRunner()
	local existing = ServerScriptService:FindFirstChild(TEST_SCRIPT_NAME)
	if existing then
		existing:Destroy()
	end
end

local function injectRunner(userCode, timeoutSec)
	removeExistingRunner()
	local s = Instance.new("Script")
	s.Name = TEST_SCRIPT_NAME
	s.Source = buildRunnerSource(userCode, timeoutSec)
	s.Parent = ServerScriptService
end

return function(params)
	local code = params.code
	if type(code) ~= "string" or code == "" then
		return nil, "param 'code' must be a non-empty string"
	end

	local side = params.side or "server"
	if side ~= "server" then
		return nil, "only side='server' is implemented; client-side injection is a TODO"
	end

	local mode = params.mode or "play"
	if mode ~= "play" and mode ~= "run" then
		return nil, "param 'mode' must be 'play' or 'run' (default 'play')"
	end

	local timeoutSec = params.timeoutSeconds
	if timeoutSec == nil then
		timeoutSec = 10
	elseif type(timeoutSec) ~= "number" or timeoutSec <= 0 then
		return nil, "param 'timeoutSeconds' must be a positive number"
	end

	if not Context.plugin then
		return nil, "plugin context not initialized"
	end

	-- Flush any previous session so the injected runner lands in a clean
	-- play-mode DataModel.
	GameStopUtil.stopPlay(Context.plugin)
	task.wait(0.2)

	injectRunner(code, timeoutSec)

	local endTestPayload
	local ok, err = pcall(function()
		if mode == "play" then
			endTestPayload = StudioTestService:ExecutePlayModeAsync({})
		else
			endTestPayload = StudioTestService:ExecuteRunModeAsync({})
		end
	end)

	removeExistingRunner()

	if not ok then
		return nil, string.format("failed to run %s mode: %s", mode, tostring(err))
	end

	return {
		action = "run_script_in_play_mode",
		mode = mode,
		result = endTestPayload,
	}
end
