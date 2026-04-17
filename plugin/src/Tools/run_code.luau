--[[
	run_code: execute arbitrary Luau in the plugin environment.
	Returns stdout + any returned value; surfaces errors cleanly.
]]
local HttpService = game:GetService("HttpService")

return function(params)
	local code = params.code
	if type(code) ~= "string" then
		return nil, "param 'code' must be a string"
	end

	local captured = {}
	local sandboxPrint = function(...)
		local args = table.pack(...)
		local parts = {}
		for i = 1, args.n do
			parts[i] = tostring(args[i])
		end
		table.insert(captured, table.concat(parts, "\t"))
	end

	local env = setmetatable({
		print = sandboxPrint,
		warn = sandboxPrint,
		game = game,
		workspace = workspace,
		script = script,
	}, { __index = getfenv() })

	local chunk, compileErr = loadstring(code, "run_code")
	if not chunk then
		return nil, "compile error: " .. tostring(compileErr)
	end
	setfenv(chunk, env)

	local ok, result = pcall(chunk)
	if not ok then
		return nil, "runtime error: " .. tostring(result)
	end

	local output = {
		stdout = table.concat(captured, "\n"),
		returnValue = nil,
	}
	if result ~= nil then
		local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, result)
		output.returnValue = okEncode and encoded or tostring(result)
	end
	return output
end
