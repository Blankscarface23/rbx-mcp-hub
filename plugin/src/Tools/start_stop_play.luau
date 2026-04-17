--[[
	start_stop_play: stub for v0.1. Studio does not expose a public plugin API
	for toggling play/run mode, so this is a best-effort stub that returns a
	clear message. Future versions may use private APIs or require user input.
]]
return function(params)
	return nil,
		"start_stop_play is not yet implemented in v0.1. "
			.. "Studio does not expose a public plugin API for toggling play mode. "
			.. "Use the F5/F7/F8 keyboard shortcuts manually."
end
