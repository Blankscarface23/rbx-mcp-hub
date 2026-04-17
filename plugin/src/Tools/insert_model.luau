--[[
	insert_model: load a Creator Store asset and parent it to Workspace.
]]
local InsertService = game:GetService("InsertService")

return function(params)
	local assetId = tonumber(params.assetId)
	if not assetId then
		return nil, "param 'assetId' must be a number or numeric string"
	end

	local ok, modelOrErr = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		return nil, "LoadAsset failed: " .. tostring(modelOrErr)
	end

	local container = modelOrErr
	local children = container:GetChildren()
	local inserted = {}
	for _, child in ipairs(children) do
		child.Parent = workspace
		table.insert(inserted, {
			name = child.Name,
			className = child.ClassName,
			path = child:GetFullName(),
		})
	end
	container:Destroy()

	return {
		assetId = assetId,
		inserted = inserted,
	}
end
