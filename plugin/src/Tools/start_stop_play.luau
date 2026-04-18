--[[
	start_stop_play: toggle Play / Run / Stop via StudioTestService.

	- mode="play": StudioTestService:ExecutePlayModeAsync({})
	- mode="run":  StudioTestService:ExecuteRunModeAsync({})
	- mode="stop": sets a plugin setting flag watched by the play-mode
	  Server DataModel's monitor; the monitor calls EndTest to end.

	The ExecutePlayModeAsync call yields for the lifetime of the play
	session. We race it against a short timeout: if the call returns
	within the window, it short-circuited (usually "already in play
	mode"); otherwise it's yielding as expected and we report success
	without waiting for the play session to end.

	Pattern ported from Roblox/studio-rust-mcp-server (MIT).
]]

local StudioTestService = game:GetService("StudioTestService")

local Context = require(script.Parent.Parent.Context)
local GameStopUtil = require(script.Parent.Parent.Utils.GameStopUtil)

local YIELD_PROBE_SEC = 0.2

-- Returns (yielded: boolean, shortCircuitResult: any).
-- yielded=true  → the async function is still running after YIELD_PROBE_SEC
--                 (normal path for ExecutePlayModeAsync).
-- yielded=false → the async function returned or errored within the window
--                 (e.g. "already in play mode" or similar).
local function raceYield(fn)
	local done = false
	local result
	task.spawn(function()
		local ok, r = pcall(fn)
		result = if ok then r else tostring(r)
		done = true
	end)
	task.wait(YIELD_PROBE_SEC)
	return not done, result
end

return function(params)
	local mode = params.mode
	if type(mode) ~= "string" then
		return nil, "param 'mode' must be one of 'play' | 'run' | 'stop'"
	end

	if not Context.plugin then
		return nil, "plugin context not initialized"
	end

	if mode == "stop" then
		GameStopUtil.stopPlay(Context.plugin)
		return { action = "stop", message = "stop signal sent to play-mode Server" }
	end

	if mode == "play" then
		local yielded, short = raceYield(function()
			return StudioTestService:ExecutePlayModeAsync({})
		end)
		if yielded then
			return { action = "play", message = "Play mode started" }
		end
		return nil, "could not start play: " .. tostring(short or "already in play mode")
	end

	if mode == "run" then
		local yielded, short = raceYield(function()
			return StudioTestService:ExecuteRunModeAsync({})
		end)
		if yielded then
			return { action = "run", message = "Run mode started" }
		end
		return nil, "could not start run: " .. tostring(short or "already running")
	end

	return nil, "invalid 'mode'; must be one of 'play' | 'run' | 'stop'"
end
