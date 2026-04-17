--[[
	get_studio_mode: best-effort mode detection from within the Edit DataModel.
]]
local RunService = game:GetService("RunService")

return function(_params)
	local mode
	if RunService:IsRunning() then
		if RunService:IsClient() and RunService:IsServer() then
			mode = "play_solo"
		elseif RunService:IsServer() then
			mode = "run_server"
		elseif RunService:IsClient() then
			mode = "play_client"
		else
			mode = "running"
		end
	elseif RunService:IsEdit() then
		mode = "edit"
	else
		mode = "unknown"
	end

	return {
		mode = mode,
		placeId = game.PlaceId,
		placeName = game.Name,
		placeVersion = game.PlaceVersion,
	}
end
