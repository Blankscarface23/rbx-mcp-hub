--[[
	Cross-DataModel signaling for stopping Play mode.

	StudioTestService:EndTest() — the only way to stop a session started by
	:ExecutePlayModeAsync() — must be called from inside the play-mode Server
	DataModel, not from Edit. So Edit sets a plugin setting; a watcher that
	lives in the play-mode Server DataModel polls for it and calls EndTest
	when it flips. plugin:SetSetting / :GetSetting are shared across
	DataModels for the same plugin instance, so this works as a poor-man's
	IPC channel.

	Pattern ported from Roblox/studio-rust-mcp-server (MIT).
]]

local StudioTestService = game:GetService("StudioTestService")

local STOP_PLAY_KEY = "rbx-mcp-hub:stop_play"
local POLL_INTERVAL = 0.5

local GameStopUtil = {}

function GameStopUtil.stopPlay(plugin)
	plugin:SetSetting(STOP_PLAY_KEY, true)
end

function GameStopUtil.monitorForStopPlay(plugin)
	-- Clear on start so a stale flag from a previous session doesn't
	-- immediately end this one.
	plugin:SetSetting(STOP_PLAY_KEY, false)
	while true do
		if plugin:GetSetting(STOP_PLAY_KEY) then
			plugin:SetSetting(STOP_PLAY_KEY, false)
			pcall(function()
				StudioTestService:EndTest({})
			end)
		end
		task.wait(POLL_INTERVAL)
	end
end

return GameStopUtil
