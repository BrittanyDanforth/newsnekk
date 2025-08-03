-- CameraControllerPatch for V7.0 - Add to StarterPlayerScripts
-- This adds camera locking on death to your existing camera controller

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Check for camera lock every frame with minimal overhead
RunService.RenderStepped:Connect(function()
	-- Only do anything if CameraLocked is true
	if player:GetAttribute("CameraLocked") then
		-- Your camera controller already handles the camera, we just need to stop it
		-- The easiest way is to temporarily disable mouse input
		game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.LockCenter
		
		-- You could also set a flag that your main camera controller checks
		-- For example:
		_G.CameraMovementDisabled = true
	else
		-- Re-enable normal behavior
		game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
		_G.CameraMovementDisabled = false
	end
end)

print("✅ Camera death lock patch loaded for V7.0")