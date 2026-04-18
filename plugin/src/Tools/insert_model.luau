--[[
	insert_model: load a Creator Store asset into workspace.

	Accepts either:
	- `query` — a free-form marketplace search string. We call
	  `InsertService:GetFreeModels(query, 0)` and take the first
	  result's AssetId.
	- `assetId` — a direct Creator Store asset id (string or number).

	The asset is loaded via `game:GetObjects`, collapsed into a Model
	(when any child is a PVInstance) or a Folder (multiple non-physical
	children), renamed uniquely, and parented to workspace. Model roots
	are then pivoted to the point where the Studio camera is looking so
	the inserted model lands at the user's focus, not at the origin.

	Pattern ported from Roblox/studio-rust-mcp-server (MIT). We accept
	`assetId` as an additional input so users who already have an id
	don't need to round-trip through the marketplace search.
]]

local InsertService = game:GetService("InsertService")

local INSERT_MAX_SEARCH_DEPTH = 2048
local INSERT_MAX_DISTANCE_AWAY = 20

local function getInsertPosition()
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.new(0, 0, 0)
	end
	local viewportPoint = camera.ViewportSize / 2
	local unitRay = camera:ViewportPointToRay(viewportPoint.X, viewportPoint.Y, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.BruteForceAllSlow = true

	local result = workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * INSERT_MAX_SEARCH_DEPTH,
		raycastParams
	)
	if result then
		return result.Position
	end
	return camera.CFrame.Position + unitRay.Direction * INSERT_MAX_DISTANCE_AWAY
end

local function toTitleCase(s)
	local function titleCase(first, rest)
		return first:upper() .. rest:lower()
	end
	local intermediate = string.gsub(s, "(%a)([%w_']*)", titleCase :: (string, string) -> string)
	return (intermediate:gsub("%s+", ""))
end

local function collapseIntoContainer(objects)
	local isPhysical = false
	for _, obj in ipairs(objects) do
		if obj:IsA("PVInstance") then
			isPhysical = true
			break
		end
	end
	if isPhysical then
		local model = Instance.new("Model")
		for _, obj in ipairs(objects) do
			obj.Parent = model
		end
		return model
	end
	if #objects > 1 then
		local folder = Instance.new("Folder")
		for _, obj in ipairs(objects) do
			obj.Parent = folder
		end
		return folder
	end
	return objects[1]
end

local function uniqueName(base)
	if not base or base == "" then
		base = "InsertedModel"
	end
	local name = base
	local i = 1
	while workspace:FindFirstChild(name) do
		i = i + 1
		name = base .. i
	end
	return name
end

local function searchFreeModels(query)
	local ok, results = pcall(function()
		return InsertService:GetFreeModels(query, 0)
	end)
	if not ok then
		return nil, "GetFreeModels failed: " .. tostring(results)
	end
	if type(results) ~= "table" or not results[1] or type(results[1].Results) ~= "table" then
		return nil, "GetFreeModels returned unexpected shape"
	end
	local rows = results[1].Results
	if #rows == 0 then
		return nil, "no marketplace matches for query: " .. tostring(query)
	end
	return rows[1].AssetId, nil
end

local function loadAssetObjects(assetId)
	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(assetId))
	end)
	if not ok then
		return nil, "GetObjects failed: " .. tostring(objects)
	end
	if type(objects) ~= "table" or #objects == 0 then
		return nil, "asset " .. tostring(assetId) .. " returned no objects"
	end
	return objects, nil
end

return function(params)
	local assetIdParam = params.assetId
	local query = params.query

	local hasAssetId = assetIdParam ~= nil and assetIdParam ~= ""
	local hasQuery = type(query) == "string" and query ~= ""

	if not hasAssetId and not hasQuery then
		return nil, "provide either 'assetId' (number/string) or 'query' (string)"
	end
	if hasAssetId and hasQuery then
		return nil, "provide only one of 'assetId' or 'query', not both"
	end

	local assetId
	local source
	if hasQuery then
		local resolved, searchErr = searchFreeModels(query)
		if not resolved then
			return nil, searchErr
		end
		assetId = resolved
		source = { kind = "query", query = query, resolvedAssetId = resolved }
	else
		assetId = tonumber(assetIdParam)
		if not assetId then
			return nil, "param 'assetId' must be numeric"
		end
		source = { kind = "assetId", assetId = assetId }
	end

	local objects, loadErr = loadAssetObjects(assetId)
	if not objects then
		return nil, loadErr
	end

	local root = collapseIntoContainer(objects)
	if not root then
		return nil, "asset contained no instances"
	end

	local baseName
	if hasQuery then
		baseName = toTitleCase(query)
	else
		baseName = root.Name
	end
	root.Name = uniqueName(baseName)
	root.Parent = workspace

	local placedAt
	if root:IsA("Model") then
		local pos = getInsertPosition()
		local ok = pcall(function()
			root:PivotTo(CFrame.new(pos))
		end)
		if ok then
			placedAt = { x = pos.X, y = pos.Y, z = pos.Z }
		end
	end

	return {
		source = source,
		root = {
			name = root.Name,
			className = root.ClassName,
			path = root:GetFullName(),
		},
		placedAt = placedAt,
	}
end
