--[[
	Shared plugin-level state. init.server.luau sets Context.plugin on load;
	tool handlers that need the plugin (e.g. for plugin:SetSetting-based
	cross-DataModel signaling) read it from here.
]]
return {
	plugin = nil,
}
