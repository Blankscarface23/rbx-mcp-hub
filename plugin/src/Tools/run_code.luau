--[[
	run_code: execute arbitrary Luau in the Edit DataModel; capture
	print / warn output and return values; emit a tagged output string.

	Output format (matches the archived Roblox/studio-rust-mcp-server):
	- `[COMPILE ERROR] <msg>`    if loadstring fails
	- `[OUTPUT] arg1\targ2\t…`  for each `print(...)` call
	- `[WARNING] arg1\targ2\t…` for each `warn(...)` call
	- `[RETURNED RESULTS] v1\tv2\t…` for the full tuple the chunk
	  returned (empty if nothing was returned)
	- `[UNEXPECTED ERROR] <msg>` if the chunk threw

	Complex values are serialized recursively:
	- `deepClone` handles cyclic tables via an identity cache.
	- `serializeValue` replaces userdata (CFrame, Vector3, Instance, …)
	  with `tostring(…)` and coerces mixed-key tables so JSONEncode
	  can still handle them.
	- Leaf tables get `JSONEncode`'d; primitives are `tostring`'d.

	`print` and `warn` are tee'd — they still go to Studio's Output
	window as well as into the returned string, so the user can watch
	progress visually during a long-running snippet.

	Pattern ported from Roblox/studio-rust-mcp-server (MIT).
]]

local HttpService = game:GetService("HttpService")

local function getTableType(t)
	local hasArray, hasAssoc = false, false
	for key, _ in pairs(t) do
		if typeof(key) == "number" then
			hasArray = true
		else
			hasAssoc = true
		end
		if hasArray and hasAssoc then
			break
		end
	end
	return hasArray, hasAssoc
end

local function serializeValue(arg)
	if typeof(arg) == "table" then
		local _, isAssoc = getTableType(arg)
		local out = {}
		for key, value in pairs(arg) do
			local newKey = serializeValue(key)
			if isAssoc then
				newKey = tostring(newKey)
			end
			out[newKey] = serializeValue(value)
		end
		return out
	elseif type(arg) == "userdata" then
		return tostring(arg) or "UNABLE_TO_SERIALIZE"
	end
	return arg
end

local function deepClone(t, cache)
	local clone = {}
	for key, value in pairs(t) do
		local newKey = key
		if typeof(key) == "table" then
			if not cache[key] then
				cache[key] = deepClone(key, cache)
			end
			newKey = cache[key]
		end
		local newValue = value
		if typeof(value) == "table" then
			if not cache[value] then
				cache[value] = deepClone(value, cache)
			end
			newValue = cache[value]
		end
		clone[newKey] = newValue
	end
	return clone
end

local function toStrTable(packed)
	local cloned = deepClone(packed, {})
	local n = packed.n or #packed
	local out = table.create(n)
	for i = 1, n do
		local s = serializeValue(cloned[i])
		if typeof(s) == "table" then
			out[i] = HttpService:JSONEncode(s)
		elseif s == nil then
			out[i] = "nil"
		else
			out[i] = tostring(s)
		end
	end
	return out
end

return function(params)
	local code = params.code
	if type(code) ~= "string" then
		return nil, "param 'code' must be a string"
	end

	local output = ""
	local function addToOutput(header, ...)
		local parts = toStrTable(table.pack(...))
		output ..= header .. " " .. table.concat(parts, "\t") .. "\n"
	end

	local chunk, compileErr = loadstring(code, "run_code")
	if not chunk then
		addToOutput("[COMPILE ERROR]", tostring(compileErr))
		return output
	end

	local chunkfenv = getfenv(chunk)
	local oldPrint = print
	local oldWarn = warn
	chunkfenv.print = function(...)
		oldPrint(...)
		addToOutput("[OUTPUT]", ...)
	end
	chunkfenv.warn = function(...)
		oldWarn(...)
		addToOutput("[WARNING]", ...)
	end

	local packed = table.pack(pcall(chunk))
	local ok = packed[1]
	if not ok then
		addToOutput("[UNEXPECTED ERROR]", packed[2])
		return output
	end

	if packed.n > 1 then
		local results = { n = packed.n - 1 }
		for i = 2, packed.n do
			results[i - 1] = packed[i]
		end
		local parts = toStrTable(results)
		output ..= "[RETURNED RESULTS] " .. table.concat(parts, "\t") .. "\n"
	end

	return output
end
