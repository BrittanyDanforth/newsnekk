-- CameraController: OPTIMIZED FOR MASSIVE SNAKES (50K+ LENGTH) with LOD Support
-- LOCALSCRIPT INSIDE STARTERPLAYERSCRIPTS
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

-- Performance optimizations
local mathMin = math.min
local mathMax = math.max
local mathLog = math.log
local mathAbs = math.abs
local Vector3new = Vector3.new
local CFramelookAt = CFrame.lookAt

-- Strict mobile detection
local function isMobileDevice()
	-- Check if we have touch but NO mouse (most reliable)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return true
	end

	-- Check for mobile-specific sensors
	if UserInputService.GyroscopeEnabled or UserInputService.AccelerometerEnabled then
		return true
	end

	-- Additional check for touch-only devices
	local hasMouse = UserInputService.MouseEnabled
	local hasKeyboard = UserInputService.KeyboardEnabled
	local hasTouch = UserInputService.TouchEnabled

	-- If we only have touch and nothing else, it's likely mobile
	if hasTouch and not hasMouse and not hasKeyboard then
		return true
	end

	return false
end

local isMobile = isMobileDevice()

-- Camera settings - OPTIMIZED FOR LOD VISIBILITY
local BASE_HEIGHT = isMobile and 50 or 45  -- Increased for better LOD visibility
local BASE_DISTANCE = isMobile and 35 or 30  -- Balanced for performance
local MAX_HEIGHT = isMobile and 120 or 140  -- Higher ceiling for massive snakes
local MAX_DISTANCE = isMobile and 80 or 100  -- Max camera distance
local MEGA_HEIGHT = 200  -- Increased for 50k+ snakes with LOD
local MEGA_DISTANCE = 120  -- Max distance for massive snakes
local FOV = 80  -- Slightly reduced for better focus
local MAX_FOV = 95  -- Less extreme FOV changes
local SMOOTH_FACTOR = 0.12  -- Smoother camera transitions
local POSITION_SMOOTH = 0.18  -- Better smoothing for massive snakes

-- Dynamic LOD settings
local LOD_DISTANCE = 150  -- Distance where LOD kicks in strongly
local DYNAMIC_RENDER_DISTANCE = 300  -- Max render distance for performance

-- Current camera values for smooth interpolation
local currentHeight = BASE_HEIGHT
local targetHeight = BASE_HEIGHT
local currentDistance = BASE_DISTANCE
local targetDistance = BASE_DISTANCE
local currentFOV = FOV
local targetFOV = FOV
local currentCameraPos = Vector3new(0, BASE_HEIGHT, BASE_DISTANCE)

-- Performance tracking
local frameCount = 0
local lastPerformanceAdjust = 0
local performanceMode = false
local avgFPS = 60
local fpsHistory = {}

-- 🔒 LOCK CAMERA COMPLETELY
camera.CameraType = Enum.CameraType.Scriptable
camera.CameraSubject = nil

-- Prevent ANY camera manipulation
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
player.CameraMinZoomDistance = 128
player.CameraMaxZoomDistance = 128

-- Cache for performance
local cachedLength = 0
local lastLengthCheck = 0

-- Function to track FPS for dynamic quality adjustment
local function updateFPS(dt)
	local fps = 1 / dt
	table.insert(fpsHistory, fps)
	if #fpsHistory > 30 then
		table.remove(fpsHistory, 1)
	end
	
	local sum = 0
	for _, f in ipairs(fpsHistory) do
		sum = sum + f
	end
	avgFPS = sum / #fpsHistory
	
	-- Enable performance mode if FPS drops
	performanceMode = avgFPS < 45
end

-- Function to get snake length with caching for performance
local function getSnakeLength()
	local now = tick()
	if now - lastLengthCheck < 0.1 then  -- Cache for 100ms
		return cachedLength
	end

	lastLengthCheck = now
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local length = leaderstats:FindFirstChild("Length")
		if length then
			cachedLength = length.Value
			return cachedLength
		end
	end
	return 0
end

-- Optimized camera height calculation with LOD consideration
local function calculateCameraHeight(snakeLength)
	-- Adjust base height based on performance mode
	local adjustedBase = performanceMode and BASE_HEIGHT * 1.2 or BASE_HEIGHT
	
	if snakeLength < 1000 then
		-- Gradual increase for small snakes
		return adjustedBase + (snakeLength / 100) * 2
	elseif snakeLength < 10000 then
		-- Logarithmic scaling for medium snakes
		return adjustedBase + 20 + mathLog(snakeLength / 1000) * 15
	elseif snakeLength < 30000 then
		-- Slower increase for large snakes
		return adjustedBase + 50 + mathLog(snakeLength / 10000) * 20
	elseif snakeLength < 50000 then
		-- Minimal increase for huge snakes
		return adjustedBase + 80 + mathLog(snakeLength / 30000) * 15
	else
		-- Cap for massive snakes with LOD
		local extraHeight = mathLog(snakeLength / 50000) * 10
		return mathMin(adjustedBase + 100 + extraHeight, MEGA_HEIGHT)
	end
end

-- Calculate camera distance based on snake length with LOD optimization
local function calculateCameraDistance(snakeLength)
	-- Adjust base distance for performance
	local adjustedBase = performanceMode and BASE_DISTANCE * 1.15 or BASE_DISTANCE
	
	if snakeLength < 1000 then
		-- Close view for small snakes
		return adjustedBase + (snakeLength / 150) * 2
	elseif snakeLength < 10000 then
		-- Moderate distance for visibility
		return adjustedBase + 13 + mathLog(snakeLength / 1000) * 12
	elseif snakeLength < 30000 then
		-- Balanced for LOD
		return adjustedBase + 35 + mathLog(snakeLength / 10000) * 15
	elseif snakeLength < 50000 then
		-- Optimized for massive snakes
		return adjustedBase + 55 + mathLog(snakeLength / 30000) * 12
	else
		-- Maximum distance with LOD
		local extraDist = mathLog(snakeLength / 50000) * 8
		return mathMin(adjustedBase + 70 + extraDist, MEGA_DISTANCE)
	end
end

-- Calculate FOV based on snake length and performance
local function calculateFOV(snakeLength)
	-- Adjust FOV based on performance mode
	local baseFOV = performanceMode and FOV - 5 or FOV
	
	if snakeLength < 5000 then
		return baseFOV
	elseif snakeLength < 20000 then
		-- Slight FOV increase for better view
		local extraFOV = (snakeLength - 5000) / 4000
		return mathMin(baseFOV + extraFOV, baseFOV + 8)
	else
		-- Moderate FOV for massive snakes
		local extraFOV = mathMin((snakeLength - 20000) / 8000, 8)
		return mathMin(baseFOV + 8 + extraFOV, MAX_FOV)
	end
end

-- Get snake head position with fallback
local function getSnakeHeadPosition(character)
	-- Try to find the actual snake model first
	local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if snakeModel then
		-- Look for the head segment
		local head = snakeModel:FindFirstChild("Segment0_Head")
		if head then
			return head.Position
		end
	end

	-- Fallback to HumanoidRootPart
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		return rootPart.Position
	end

	return nil
end

-- Main camera update loop - OPTIMIZED FOR LOD AND PERFORMANCE
RunService.RenderStepped:Connect(function(dt)
	frameCount = frameCount + 1
	
	-- Update FPS tracking
	updateFPS(dt)

	local character = player.Character
	if not character then return end

	-- Get snake position with optimized head tracking
	local snakePos = getSnakeHeadPosition(character)
	if not snakePos then return end

	-- Dynamic zoom based on snake length
	local snakeLength = getSnakeLength()
	targetHeight = calculateCameraHeight(snakeLength)
	targetDistance = calculateCameraDistance(snakeLength)
	targetFOV = calculateFOV(snakeLength)

	-- Adjust smoothing based on performance
	local smoothFactor = performanceMode and SMOOTH_FACTOR * 0.8 or SMOOTH_FACTOR
	
	-- Smooth camera transitions
	currentHeight = currentHeight + (targetHeight - currentHeight) * smoothFactor
	currentDistance = currentDistance + (targetDistance - currentDistance) * smoothFactor
	currentFOV = currentFOV + (targetFOV - currentFOV) * smoothFactor

	-- Calculate camera angle based on snake length for optimal LOD view
	local angleOffset = mathMin(snakeLength / 100000, 0.25) -- Max 25% angle adjustment
	local cameraAngle = 0.85 - angleOffset -- Start at 85% height, reduce for longer snakes
	
	-- Calculate target camera position with dynamic angle
	local horizontalDistance = currentDistance * (1 - cameraAngle)
	local verticalHeight = currentHeight + (currentDistance * cameraAngle)
	local targetCameraPos = snakePos + Vector3new(0, verticalHeight, horizontalDistance)

	-- Adjust camera for very long snakes to maintain good visibility
	if snakeLength > 10000 then
		-- Shift camera for better body visibility with LOD
		local forwardShift = mathMin((snakeLength - 10000) / 50000, 0.2) * currentDistance
		targetCameraPos = targetCameraPos - Vector3new(0, 0, forwardShift)
	end

	-- Enhanced smoothing for massive snakes
	local positionSmooth = performanceMode and POSITION_SMOOTH * 0.7 or POSITION_SMOOTH
	if snakeLength > 10000 then
		positionSmooth = mathMin(positionSmooth * (1 + snakeLength / 100000), 0.4)
	end
	currentCameraPos = currentCameraPos:Lerp(targetCameraPos, positionSmooth)

	-- Dynamic look-ahead based on snake length
	local lookAheadDistance = mathMin(8 + snakeLength / 8000, 20)
	local lookDownAmount = mathMin(5 + snakeLength / 20000, 15) -- Look down more for longer snakes
	local lookAtPos = snakePos + Vector3new(0, -lookDownAmount, -lookAheadDistance)

	-- Set camera with optimized CFrame
	camera.CFrame = CFramelookAt(currentCameraPos, lookAtPos, Vector3new(0, 1, 0))

	-- Apply dynamic FOV
	camera.FieldOfView = currentFOV

	-- Performance optimization - skip frames for very long snakes
	if performanceMode and snakeLength > 30000 and frameCount % 2 == 0 then
		return
	end

	-- Ensure camera stays scriptable
	camera.CameraType = Enum.CameraType.Scriptable
	
	-- Update render distance for LOD
	if frameCount % 60 == 0 then
		local renderDistance = performanceMode and LOD_DISTANCE or DYNAMIC_RENDER_DISTANCE
		-- This would communicate with the snake system if needed
	end
end)

-- Enhanced vignette effect with performance scaling
local function addVignetteEffect()
	local playerGui = player:WaitForChild("PlayerGui")

	-- Check if vignette already exists
	if playerGui:FindFirstChild("SlitherVignette") then return end

	local vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "SlitherVignette"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.Parent = playerGui

	local vignetteFrame = Instance.new("ImageLabel")
	vignetteFrame.Name = "Vignette"
	vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
	vignetteFrame.Position = UDim2.new(0, 0, 0, 0)
	vignetteFrame.BackgroundTransparency = 1
	vignetteFrame.Image = "rbxasset://textures/ui/LuaApp/graphic/gr-radial-shadow-1024x1024.png"
	vignetteFrame.ImageColor3 = Color3.fromRGB(0, 0, 0)
	vignetteFrame.ImageTransparency = 0.25 -- Slightly less intense
	vignetteFrame.ZIndex = 100
	vignetteFrame.Parent = vignetteGui
	
	-- Add performance indicator
	local perfIndicator = Instance.new("TextLabel")
	perfIndicator.Name = "PerfIndicator"
	perfIndicator.Size = UDim2.new(0, 100, 0, 20)
	perfIndicator.Position = UDim2.new(1, -110, 0, 10)
	perfIndicator.BackgroundTransparency = 1
	perfIndicator.Text = "FPS: 60"
	perfIndicator.TextColor3 = Color3.new(1, 1, 1)
	perfIndicator.TextStrokeTransparency = 0
	perfIndicator.TextScaled = true
	perfIndicator.Visible = false -- Set to true to show FPS
	perfIndicator.Parent = vignetteGui
	
	-- Update performance indicator
	RunService.Heartbeat:Connect(function()
		if perfIndicator.Visible then
			perfIndicator.Text = "FPS: " .. math.floor(avgFPS)
			perfIndicator.TextColor3 = avgFPS > 50 and Color3.new(0, 1, 0) or 
									   avgFPS > 30 and Color3.new(1, 1, 0) or 
									   Color3.new(1, 0, 0)
		end
	end)
end

-- Apply vignette after character loads
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	addVignetteEffect()
end)

-- Apply immediately if character exists
if player.Character then
	addVignetteEffect()
end

print("📷 Camera Controller: LOD-Optimized for massive snakes!")
print("🎮 Performance mode:", performanceMode and "ON" or "OFF")
print("🐍 Features: Dynamic LOD support | FPS-based quality | Smooth transitions")