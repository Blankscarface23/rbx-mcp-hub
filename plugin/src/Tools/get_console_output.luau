--[[
	get_console_output: returns the last N lines from LogService.
]]
local LogService = game:GetService("LogService")

return function(params)
	local lines = tonumber(params.lines) or 200
	if lines < 1 then lines = 1 end
	if lines > 2000 then lines = 2000 end

	local history = LogService:GetLogHistory()
	local start = math.max(1, #history - lines + 1)
	local out = {}
	for i = start, #history do
		local entry = history[i]
		table.insert(out, {
			message = entry.message,
			messageType = entry.messageType.Name,
			timestamp = entry.timestamp,
		})
	end

	return {
		totalAvailable = #history,
		returned = #out,
		lines = out,
	}
end
