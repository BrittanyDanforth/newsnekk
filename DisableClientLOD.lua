-- DisableClientLOD: Minimal script to disable client-side LOD
-- Place this in StarterPlayer.StarterPlayerScripts instead of ClientAISnakeLOD
-- This lets the server handle all rendering decisions

local RunService = game:GetService("RunService")

-- Simply ensure AI snakes remain visible as the server intends
local function ensureSnakesVisible()
	-- Do nothing - let server handle everything
	-- This script exists just to replace ClientAISnakeLOD without any LOD logic
end

-- Optional: If you want to ensure maximum quality for all snakes
local function forceMaxQuality()
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:match("AISnakeModel_") then
			-- Ensure model streaming doesn't interfere
			obj:SetAttribute("ClientLODDisabled", true)
		end
	end
end

-- Run once on start
forceMaxQuality()

-- Run periodically for new snakes
local counter = 0
RunService.Heartbeat:Connect(function()
	counter = counter + 1
	if counter % 300 == 0 then -- Every 5 seconds
		forceMaxQuality()
	end
end)

print("✅ Client-side LOD disabled - Server handles all rendering")

return {}