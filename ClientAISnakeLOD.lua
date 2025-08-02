-- ClientAISnakeLOD: Client-side Level of Detail system for AI Snakes
-- This script runs on each client and manages the visibility of AI snake segments
-- based on distance from the player's camera for optimal performance

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- LOD Constants (matching AISnake module)
local VISIBILITY_CHECK_INTERVAL = 5  -- Check visibility every N frames
local RENDER_DISTANCE = 1000  -- Maximum render distance
local LOD_DISTANCE_NEAR = 200   -- Full snake visible
local LOD_DISTANCE_MID = 400    -- 70% of snake visible
local LOD_DISTANCE_FAR = 600    -- 40% of snake visible
local LOD_DISTANCE_MINIMAL = 800 -- 20% of snake visible
local MIN_VISIBLE_SEGMENTS = 10  -- Minimum segments to show even from far away
local DYNAMIC_SEGMENT_LIMIT = 800 -- Maximum physical segments

-- Progressive visibility percentages based on distance
local VISIBILITY_PERCENTAGES = {
	near = 1.0,      -- 100% of snake visible
	mid = 0.7,       -- 70% of snake visible
	far = 0.4,       -- 40% of snake visible
	minimal = 0.2,   -- 20% of snake visible
	veryFar = 0.1    -- 10% of snake visible
}

-- Track AI snake models
local aiSnakeModels = {}
local frameCounter = 0

-- Function to get camera position safely
local function getCameraPosition()
	if camera then
		return camera.CFrame.Position
	elseif player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		return player.Character.HumanoidRootPart.Position
	else
		return Vector3.new(0, 10, 0)
	end
end

-- Calculate LOD level based on distance
local function calculateLODLevel(distance)
	if distance <= LOD_DISTANCE_NEAR then
		return "near", VISIBILITY_PERCENTAGES.near
	elseif distance <= LOD_DISTANCE_MID then
		return "mid", VISIBILITY_PERCENTAGES.mid
	elseif distance <= LOD_DISTANCE_FAR then
		return "far", VISIBILITY_PERCENTAGES.far
	elseif distance <= LOD_DISTANCE_MINIMAL then
		return "minimal", VISIBILITY_PERCENTAGES.minimal
	else
		return "veryFar", VISIBILITY_PERCENTAGES.veryFar
	end
end

-- Update visibility for a single AI snake
local function updateSnakeLOD(snakeModel)
	local headPosition = snakeModel:GetAttribute("HeadPosition")
	if not headPosition then
		-- Try to find the head part directly
		local head = snakeModel:FindFirstChild("Segment0_Head")
		if head then
			headPosition = head.Position
		else
			return -- No head position available
		end
	end
	
	local cameraPos = getCameraPosition()
	local distance = (headPosition - cameraPos).Magnitude
	
	-- Check if snake is within render distance
	if distance > RENDER_DISTANCE then
		-- Hide entire snake
		for _, part in ipairs(snakeModel:GetDescendants()) do
			if part:IsA("BasePart") and part.Name:match("Segment") then
				part.Transparency = 1
			elseif part:IsA("Beam") then
				part.Enabled = false
			elseif part:IsA("PointLight") then
				part.Enabled = false
			end
		end
		return
	end
	
	-- Calculate LOD level and visibility
	local lodLevel, visibilityPercent = calculateLODLevel(distance)
	local currentLength = snakeModel:GetAttribute("CurrentLength") or 100
	local visibleSegments = math.max(
		MIN_VISIBLE_SEGMENTS,
		math.floor(math.min(currentLength, DYNAMIC_SEGMENT_LIMIT) * visibilityPercent)
	)
	
	-- Update segments visibility
	local segmentIndex = 0
	for _, part in ipairs(snakeModel:GetChildren()) do
		if part:IsA("BasePart") and (part.Name:match("Segment") or part.Name == "Segment0_Head") then
			local shouldBeVisible = segmentIndex < visibleSegments
			
			-- Update transparency
			if shouldBeVisible then
				part.Transparency = 0
				
				-- Update glow based on distance
				local glow = part:FindFirstChild("Glow")
				if glow then
					if lodLevel == "near" then
						glow.Enabled = true
						glow.Brightness = 2
					elseif lodLevel == "mid" then
						glow.Enabled = segmentIndex % 2 == 0  -- Every other segment
						glow.Brightness = 1.5
					elseif lodLevel == "far" then
						glow.Enabled = segmentIndex % 3 == 0  -- Every third segment
						glow.Brightness = 1
					else
						glow.Enabled = segmentIndex % 5 == 0  -- Every fifth segment
						glow.Brightness = 0.5
					end
				end
			else
				part.Transparency = 1
				local glow = part:FindFirstChild("Glow")
				if glow then
					glow.Enabled = false
				end
			end
			
			segmentIndex = segmentIndex + 1
		end
	end
	
	-- Update beams
	local beamHolder = snakeModel:FindFirstChild("BeamHolder")
	if beamHolder then
		for _, beam in ipairs(beamHolder:GetDescendants()) do
			if beam:IsA("Beam") then
				local beamIndex = tonumber(beam.Name:match("%d+")) or 0
				beam.Enabled = beamIndex < visibleSegments - 1
				
				-- Reduce beam quality at distance
				if lodLevel == "far" or lodLevel == "minimal" or lodLevel == "veryFar" then
					beam.Segments = 5  -- Reduced from 10
				else
					beam.Segments = 10
				end
			end
		end
	end
	
	-- Update eyes visibility
	for _, eye in ipairs(snakeModel:GetChildren()) do
		if eye.Name:match("Eye") or eye.Name:match("Pupil") then
			eye.Transparency = lodLevel == "veryFar" and 1 or 0
		end
	end
end

-- Find and track AI snake models
local function findAISnakes()
	aiSnakeModels = {}
	
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and model.Name:match("^AISnakeModel_") then
			table.insert(aiSnakeModels, model)
		end
	end
end

-- Main update loop
local function updateAllSnakeLOD()
	frameCounter = frameCounter + 1
	
	-- Only update every N frames
	if frameCounter % VISIBILITY_CHECK_INTERVAL ~= 0 then
		return
	end
	
	-- Update LOD for all AI snakes
	for _, snakeModel in ipairs(aiSnakeModels) do
		if snakeModel and snakeModel.Parent then
			updateSnakeLOD(snakeModel)
		end
	end
end

-- Listen for new AI snakes
Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child.Name:match("^AISnakeModel_") then
		table.insert(aiSnakeModels, child)
	end
end)

-- Remove destroyed AI snakes
Workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") and child.Name:match("^AISnakeModel_") then
		for i = #aiSnakeModels, 1, -1 do
			if aiSnakeModels[i] == child then
				table.remove(aiSnakeModels, i)
				break
			end
		end
	end
end)

-- Initialize
findAISnakes()

-- Connect to render loop
RunService.Heartbeat:Connect(updateAllSnakeLOD)

print("✅ ClientAISnakeLOD initialized - Managing AI snake visibility for optimal performance")