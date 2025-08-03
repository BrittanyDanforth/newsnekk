-- CameraControllerPatch - Add this to StarterPlayerScripts
-- This patches the existing CameraController to respect the CameraLocked attribute

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Store the last camera position when locked
local lockedCameraPosition = nil
local lockedCameraLookAt = nil

-- Override camera updates when locked
RunService.RenderStepped:Connect(function()
	-- Check if camera is locked
	if player:GetAttribute("CameraLocked") then
		-- First time locking, store current camera state
		if not lockedCameraPosition then
			lockedCameraPosition = camera.CFrame.Position
			lockedCameraLookAt = camera.CFrame.Position + camera.CFrame.LookVector * 10
			print("📷 Camera locked at position:", lockedCameraPosition)
		end
		
		-- Keep camera at locked position
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CFrame = CFrame.lookAt(lockedCameraPosition, lockedCameraLookAt)
		end
	else
		-- Camera unlocked, clear stored position
		if lockedCameraPosition then
			print("📷 Camera unlocked")
			lockedCameraPosition = nil
			lockedCameraLookAt = nil
		end
	end
end)

-- Clear lock on character added (backup)
player.CharacterAdded:Connect(function()
	player:SetAttribute("CameraLocked", false)
	lockedCameraPosition = nil
	lockedCameraLookAt = nil
end)

print("✅ CameraControllerPatch loaded - camera will lock on death")