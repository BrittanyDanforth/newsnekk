-- CLIENT PERFORMANCE OPTIMIZER
-- Place in StarterPlayer/StarterPlayerScripts
-- Automatically adjusts quality settings based on FPS to maintain smooth gameplay

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserSettings = UserSettings()
local GameSettings = UserSettings.GameSettings

local player = Players.LocalPlayer

-- Performance monitoring
local frameTimeHistory = {}
local historySize = 30
local lastOptimization = 0
local optimizationCooldown = 5 -- Wait 5 seconds between optimizations

-- Quality levels
local QualityLevels = {
	Ultra = {
		RenderDistance = 500,
		GraphicsMode = Enum.SavedQualitySetting.Automatic,
		Particles = true,
		Shadows = true,
		SegmentQuality = 1.0
	},
	High = {
		RenderDistance = 400,
		GraphicsMode = Enum.SavedQualitySetting.QualityLevel7,
		Particles = true,
		Shadows = false,
		SegmentQuality = 0.9
	},
	Medium = {
		RenderDistance = 300,
		GraphicsMode = Enum.SavedQualitySetting.QualityLevel5,
		Particles = false,
		Shadows = false,
		SegmentQuality = 0.7
	},
	Low = {
		RenderDistance = 200,
		GraphicsMode = Enum.SavedQualitySetting.QualityLevel3,
		Particles = false,
		Shadows = false,
		SegmentQuality = 0.5
	},
	Potato = {
		RenderDistance = 150,
		GraphicsMode = Enum.SavedQualitySetting.QualityLevel1,
		Particles = false,
		Shadows = false,
		SegmentQuality = 0.3
	}
}

local currentQuality = "High"
local targetFPS = 50 -- Try to maintain 50 FPS

-- Apply quality settings
local function applyQualityLevel(level)
	local settings = QualityLevels[level]
	if not settings then return end
	
	currentQuality = level
	
	-- Apply graphics mode
	pcall(function()
		GameSettings.SavedQualityLevel = settings.GraphicsMode
	end)
	
	-- Apply render distance
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.CameraMaxZoomDistance = settings.RenderDistance
	end
	
	-- Notify other systems
	_G.ClientQualityLevel = level
	_G.SegmentQualityMultiplier = settings.SegmentQuality
	
	-- Disable particles if needed
	if not settings.Particles then
		for _, v in pairs(workspace:GetDescendants()) do
			if v:IsA("ParticleEmitter") and v.Name ~= "OrbParticle" then
				v.Enabled = false
			end
		end
	end
	
	print("📊 Quality level changed to:", level)
end

-- Calculate average FPS
local function getAverageFPS()
	if #frameTimeHistory < 10 then
		return 60 -- Default to 60 if not enough data
	end
	
	local sum = 0
	for _, frameTime in ipairs(frameTimeHistory) do
		sum = sum + frameTime
	end
	
	local avgFrameTime = sum / #frameTimeHistory
	return 1 / avgFrameTime
end

-- Monitor performance
local lastFrameTime = tick()
RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	local frameTime = currentTime - lastFrameTime
	lastFrameTime = currentTime
	
	-- Add to history
	table.insert(frameTimeHistory, frameTime)
	if #frameTimeHistory > historySize then
		table.remove(frameTimeHistory, 1)
	end
	
	-- Check if we should optimize
	if currentTime - lastOptimization < optimizationCooldown then
		return
	end
	
	local avgFPS = getAverageFPS()
	
	-- Get current snake length
	local snakeLength = 10
	if player.Character then
		local lengthValue = player.Character:FindFirstChild("Length")
		if lengthValue then
			snakeLength = lengthValue.Value
		end
	end
	
	-- Adjust target FPS based on snake length
	local adjustedTargetFPS = targetFPS
	if snakeLength > 5000 then
		adjustedTargetFPS = 40 -- Lower target for huge snakes
	elseif snakeLength > 10000 then
		adjustedTargetFPS = 30
	end
	
	-- Determine if we need to change quality
	local needsChange = false
	local newQuality = currentQuality
	
	if avgFPS < adjustedTargetFPS - 10 then
		-- FPS too low, decrease quality
		if currentQuality == "Ultra" then
			newQuality = "High"
		elseif currentQuality == "High" then
			newQuality = "Medium"
		elseif currentQuality == "Medium" then
			newQuality = "Low"
		elseif currentQuality == "Low" then
			newQuality = "Potato"
		end
		needsChange = newQuality ~= currentQuality
		
	elseif avgFPS > adjustedTargetFPS + 20 then
		-- FPS high, can increase quality
		if currentQuality == "Potato" and snakeLength < 10000 then
			newQuality = "Low"
		elseif currentQuality == "Low" and snakeLength < 5000 then
			newQuality = "Medium"
		elseif currentQuality == "Medium" and snakeLength < 2000 then
			newQuality = "High"
		elseif currentQuality == "High" and snakeLength < 1000 then
			newQuality = "Ultra"
		end
		needsChange = newQuality ~= currentQuality
	end
	
	-- Apply changes if needed
	if needsChange then
		applyQualityLevel(newQuality)
		lastOptimization = currentTime
		
		-- Notify the user
		local StarterGui = game:GetService("StarterGui")
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Performance Optimizer",
				Text = "Quality adjusted to " .. newQuality .. " (FPS: " .. math.floor(avgFPS) .. ")",
				Duration = 3
			})
		end)
	end
end)

-- Initial setup
task.wait(2) -- Wait for game to load
applyQualityLevel("High") -- Start with High quality

-- Monitor snake spawning to adjust immediately
if player.Character then
	applyQualityLevel("High")
end

player.CharacterAdded:Connect(function(character)
	task.wait(1)
	applyQualityLevel("High")
end)

print("✅ Client Performance Optimizer initialized")
print("🎯 Target FPS:", targetFPS)
print("📊 Starting quality:", currentQuality)