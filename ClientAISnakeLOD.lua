-- ClientAISnakeLOD: Client-side Level of Detail system for AI Snakes
-- This module should be placed in StarterPlayer.StarterPlayerScripts
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- LOD Constants (matching AISnake module)
local VISIBILITY_CHECK_INTERVAL = 5  -- Check visibility every N frames
local RENDER_DISTANCE = 1000  -- Maximum render distance
local LOD_DISTANCE_NEAR = 200   -- Full snake visible
local LOD_DISTANCE_MID = 400    -- 70% of snake visible
local LOD_DISTANCE_FAR = 600    -- 40% of snake visible
local LOD_DISTANCE_MINIMAL = 800 -- 20% of snake visible (head + some body)
local BEAM_SYNC_INTERVAL = 3    -- Sync beams with parts every N frames
local FORCE_RENDER_SEGMENTS = 150  -- Always force render first N segments for nearby snakes
local MIN_VISIBLE_SEGMENTS = 10    -- Minimum segments to show even from far away
local MAX_VISIBLE_SEGMENTS = 2000  -- Maximum visible segments at once
local DYNAMIC_SEGMENT_LIMIT = 800  -- Initial physical segment creation limit

-- Progressive visibility percentages based on distance
local VISIBILITY_PERCENTAGES = {
	near = 1.0,      -- 100% of snake visible
	mid = 0.7,       -- 70% of snake visible
	far = 0.4,       -- 40% of snake visible
	minimal = 0.2,   -- 20% of snake visible
	veryFar = 0.1    -- 10% of snake visible (at least head + few segments)
}

local ClientAISnakeLOD = {}
ClientAISnakeLOD.__index = ClientAISnakeLOD

-- Module state
local activeSnakes = {} -- Store AI snake references
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local frameCounter = 0

-- LOD State Manager
local lodManager = {
	snakeStates = {},
	lastUpdateTime = 0
}

-- Calculate visibility percentage based on distance
local function calculateVisibilityPercentage(distance)
	if distance < LOD_DISTANCE_NEAR then
		return VISIBILITY_PERCENTAGES.near
	elseif distance < LOD_DISTANCE_MID then
		-- Interpolate between near and mid
		local t = (distance - LOD_DISTANCE_NEAR) / (LOD_DISTANCE_MID - LOD_DISTANCE_NEAR)
		return VISIBILITY_PERCENTAGES.near + (VISIBILITY_PERCENTAGES.mid - VISIBILITY_PERCENTAGES.near) * t
	elseif distance < LOD_DISTANCE_FAR then
		-- Interpolate between mid and far
		local t = (distance - LOD_DISTANCE_MID) / (LOD_DISTANCE_FAR - LOD_DISTANCE_MID)
		return VISIBILITY_PERCENTAGES.mid + (VISIBILITY_PERCENTAGES.far - VISIBILITY_PERCENTAGES.mid) * t
	elseif distance < LOD_DISTANCE_MINIMAL then
		-- Interpolate between far and minimal
		local t = (distance - LOD_DISTANCE_FAR) / (LOD_DISTANCE_MINIMAL - LOD_DISTANCE_FAR)
		return VISIBILITY_PERCENTAGES.far + (VISIBILITY_PERCENTAGES.minimal - VISIBILITY_PERCENTAGES.far) * t
	else
		return VISIBILITY_PERCENTAGES.veryFar
	end
end

-- Force beam synchronization to fix visibility issues
local function forceBeamSync(snake, isVisible)
	-- Find all beams in the snake model
	local beams = {}
	local attachmentPart = snake.Model:FindFirstChild("AISnakeAttachmentPart")
	if attachmentPart then
		for _, child in ipairs(attachmentPart:GetChildren()) do
			if child:IsA("Beam") then
				table.insert(beams, child)
			end
		end
	end

	for _, beam in ipairs(beams) do
		-- Critical: Set BOTH properties to ensure complete hiding
		beam.Enabled = isVisible
		if not isVisible then
			-- Force complete invisibility for hidden heads
			beam.Transparency = NumberSequence.new(1)
			beam.Width0 = 0
			beam.Width1 = 0
		else
			-- Restore normal beam properties
			beam.Transparency = NumberSequence.new(0)
			beam.Width0 = beam:GetAttribute("OriginalWidth0") or 1
			beam.Width1 = beam:GetAttribute("OriginalWidth1") or 1
		end
	end
end

-- Atomic visibility update for all components
local function updateAISnakeVisibility(snake, distance)
	local visibility = calculateVisibilityPercentage(distance)
	local snakeId = snake.Model.Name

	-- Check if state changed significantly
	local oldState = lodManager.snakeStates[snakeId]
	if oldState and math.abs(oldState.visibility - visibility) < 0.05 and 
	   oldState.distance and math.abs(oldState.distance - distance) < 10 then
		return -- No significant change
	end

	-- Determine how many segments to show
	local currentLength = snake.Model:GetAttribute("CurrentLength") or 100
	local segmentsToShow

	if distance < LOD_DISTANCE_NEAR then
		segmentsToShow = currentLength  -- Show all
	elseif distance < LOD_DISTANCE_MID then
		segmentsToShow = math.floor(currentLength * 0.8)  -- 80%
	elseif distance < LOD_DISTANCE_FAR then
		segmentsToShow = math.floor(currentLength * 0.5)  -- 50%
	elseif distance < LOD_DISTANCE_MINIMAL then
		segmentsToShow = math.max(30, math.floor(currentLength * 0.3))  -- 30% but at least 30
	else
		segmentsToShow = math.max(15, math.floor(currentLength * 0.15))  -- 15% but at least 15
	end

	-- Clamp to limits
	segmentsToShow = math.min(segmentsToShow, currentLength, DYNAMIC_SEGMENT_LIMIT)

	-- Find all segments
	local segments = {}
	local head = nil
	
	for _, child in ipairs(snake.Model:GetChildren()) do
		if child:IsA("BasePart") then
			-- Check for head first
			if child.Name == "Segment0_Head" or child.Name == "AISnakeHead" then
				head = child
				segments[0] = child
			elseif child.Name:match("Segment") or child.Name:match("AISegment") then
				local index = child:GetAttribute("SegmentIndex") or tonumber(child.Name:match("%d+"))
				if index then
					segments[index] = child
				end
			end
		end
	end

	-- CRITICAL: Ensure head is ALWAYS visible and NEVER transparent
	if head then
		head.Transparency = 0
		head.LocalTransparencyModifier = 0
		
		-- Make sure head glow is visible when close
		local headGlow = head:FindFirstChild("Glow") or head:FindFirstChildOfClass("PointLight")
		if headGlow then
			headGlow.Enabled = distance < 600
			if headGlow.Enabled then
				headGlow.Brightness = 2
			end
		end
	end

	-- Update segments (skip head since we already handled it)
	for i = 1, currentLength do
		local segment = segments[i]

		if segment and segment.Parent then
			if i <= segmentsToShow then
				-- This segment should be visible
				-- Calculate transparency
				local baseTransparency = 0
				if distance < 200 then
					baseTransparency = 0
				elseif distance < 400 then
					baseTransparency = 0.1
				elseif distance < 600 then
					baseTransparency = 0.2
				else
					baseTransparency = 0.3  -- Max 30% transparent, not 50%
				end

				-- Fade out segments near the cutoff point
				local fadeStart = segmentsToShow * 0.7  -- Start fading at 70%
				if i > fadeStart and i < segmentsToShow then
					-- Gradual fade for last 30% of visible segments
					local fadeProgress = (i - fadeStart) / (segmentsToShow - fadeStart)
					segment.Transparency = math.min(0.7, baseTransparency + fadeProgress * 0.5)
				else
					segment.Transparency = baseTransparency
				end

				-- Update glow
				local glow = segment:FindFirstChild("Glow") or segment:FindFirstChildOfClass("PointLight")
				if glow then
					if distance < 600 and i <= 100 then -- Only show glow for first 100 segments when close
						glow.Enabled = true
						glow.Brightness = 2 * (1 - segment.Transparency)
					else
						glow.Enabled = false
					end
				end
			else
				-- This segment should be completely hidden
				segment.Transparency = 1

				local glow = segment:FindFirstChild("Glow") or segment:FindFirstChildOfClass("PointLight")
				if glow then
					glow.Enabled = false
				end
			end
		end
	end

	-- Handle eyes visibility - SYNCHRONIZED with head visibility
	local eyeVisible = distance < 600 and head and head.Transparency == 0
	local eyes = {"LeftEye", "RightEye", "LeftEyePupil", "RightEyePupil"}
	for _, eyeName in ipairs(eyes) do
		local eye = snake.Model:FindFirstChild(eyeName)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = eyeVisible and 0 or 1
		end
	end

	-- Beams require synchronized update
	local beams = {}
	local attachmentPart = snake.Model:FindFirstChild("AISnakeAttachmentPart")
	if attachmentPart then
		for _, child in ipairs(attachmentPart:GetChildren()) do
			if child:IsA("Beam") then
				local beamIndex = tonumber(child.Name:match("%d+")) or 0
				beams[beamIndex] = child
			end
		end
	end

	-- Update beams based on segment visibility
	for i = 0, segmentsToShow do
		local beam = beams[i]
		if beam then
			local seg1 = segments[i]
			local seg2 = segments[i + 1]

			-- Special handling for head beam (beam 0)
			if i == 0 and seg1 and seg2 then
				-- Head beam should always be visible if head is visible
				beam.Enabled = true
				beam.Transparency = NumberSequence.new(0)
				-- Store original widths if not already stored
				if not beam:GetAttribute("OriginalWidth0") then
					beam:SetAttribute("OriginalWidth0", beam.Width0)
					beam:SetAttribute("OriginalWidth1", beam.Width1)
				end
			elseif seg1 and seg2 and seg1.Transparency < 0.9 and seg2.Transparency < 0.9 then
				beam.Enabled = true
				-- Use average transparency but add a bit more for beams
				local avgTransparency = (seg1.Transparency + seg2.Transparency) / 2
				beam.Transparency = NumberSequence.new(math.min(avgTransparency + 0.1, 0.8))

				-- Store original widths if not already stored
				if not beam:GetAttribute("OriginalWidth0") then
					beam:SetAttribute("OriginalWidth0", beam.Width0)
					beam:SetAttribute("OriginalWidth1", beam.Width1)
				end
			else
				-- Hide beam if segments are too transparent
				beam.Enabled = false
				beam.Transparency = NumberSequence.new(1)
			end
		end
	end

	-- Hide beams beyond visible segments
	for i = segmentsToShow + 1, currentLength do
		local beam = beams[i]
		if beam then
			beam.Enabled = false
			beam.Transparency = NumberSequence.new(1)
		end
	end

	-- Update LOD state
	lodManager.snakeStates[snakeId] = {
		distance = distance,
		visibility = visibility,
		segmentsToShow = segmentsToShow,
		timestamp = tick()
	}
end

-- Find AI snake models in workspace
local function findAISnakes()
	local snakes = {}

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:match("AISnakeModel_") then
			-- Verify it's an AI snake by checking for key components
			local hasHead = obj:FindFirstChild("Segment0_Head") or obj:FindFirstChild("AISnakeHead")

			if hasHead then
				table.insert(snakes, {
					Model = obj,
					Head = hasHead
				})
			end
		end
	end

	return snakes
end

-- Main update loop
local function updateAllSnakeLOD()
	if not camera then 
		camera = workspace.CurrentCamera
		if not camera then return end
	end

	local cameraPosition = camera.CFrame.Position

	-- Update active snakes list periodically
	if frameCounter % 60 == 0 then -- Every second
		activeSnakes = findAISnakes()
	end

	-- Update LOD for all snakes
	for _, snake in ipairs(activeSnakes) do
		if snake.Model.Parent and snake.Head.Parent then
			local distance = (snake.Head.Position - cameraPosition).Magnitude

			-- Only update if within render distance
			if distance <= RENDER_DISTANCE then
				updateAISnakeVisibility(snake, distance)
			else
				-- For very distant snakes, just hide non-essential parts
				-- But NEVER hide the head completely
				if lodManager.snakeStates[snake.Model.Name] then
					lodManager.snakeStates[snake.Model.Name].visibility = 0
					
					-- Ensure head stays visible even at distance
					snake.Head.Transparency = 0.5 -- Slight transparency but still visible
					
					-- Hide eyes at extreme distance
					local eyes = {"LeftEye", "RightEye", "LeftEyePupil", "RightEyePupil"}
					for _, eyeName in ipairs(eyes) do
						local eye = snake.Model:FindFirstChild(eyeName)
						if eye and eye:IsA("BasePart") then
							eye.Transparency = 1
						end
					end
				end
			end
		end
	end
end

-- Initialize the LOD system
local function initialize()
	-- Wait for camera
	camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")
	
	-- Connect update loop
	RunService.Heartbeat:Connect(function()
		frameCounter = frameCounter + 1

		-- Update visibility every N frames
		if frameCounter % VISIBILITY_CHECK_INTERVAL == 0 then
			updateAllSnakeLOD()
		end

		-- Force beam sync less frequently
		if frameCounter % (BEAM_SYNC_INTERVAL * 10) == 0 then
			for _, snake in ipairs(activeSnakes) do
				if snake.Model.Parent then
					local state = lodManager.snakeStates[snake.Model.Name]
					if state and state.visibility > 0 then
						forceBeamSync(snake, true)
					end
				end
			end
		end
	end)

	print("✅ ClientAISnakeLOD initialized (Polished)")
end

-- Start the system
initialize()

return ClientAISnakeLOD