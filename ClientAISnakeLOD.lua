-- ClientAISnakeLOD: Fixed Client-side Level of Detail system for AI Snakes
-- This module should be placed in StarterPlayer.StarterPlayerScripts
-- FIXED VERSION: No more disappearing segments!

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- LOD Constants
local VISIBILITY_CHECK_INTERVAL = 10  -- Check visibility every N frames (increased for performance)
local RENDER_DISTANCE = 1000  -- Maximum render distance
local LOD_DISTANCE_NEAR = 200   -- Full quality
local LOD_DISTANCE_MID = 400    -- Medium quality
local LOD_DISTANCE_FAR = 600    -- Low quality
local LOD_DISTANCE_MINIMAL = 800 -- Minimal quality

-- Quality settings per LOD level
local LOD_SETTINGS = {
	near = {
		segmentQuality = 1.0,     -- All segments visible
		glowEnabled = true,       -- Glow effects on
		beamQuality = 1.0,        -- Full beam quality
		eyesVisible = true,       -- Eyes visible
		minTransparency = 0,      -- No transparency
		maxTransparency = 0       -- No transparency
	},
	mid = {
		segmentQuality = 0.8,     -- 80% of segments visible
		glowEnabled = true,       -- Glow effects on for first 50 segments
		beamQuality = 0.8,        -- Slightly reduced beam quality
		eyesVisible = true,       -- Eyes visible
		minTransparency = 0,      -- No base transparency
		maxTransparency = 0.2     -- Slight fade at tail
	},
	far = {
		segmentQuality = 0.5,     -- 50% of segments visible
		glowEnabled = false,      -- No glow effects
		beamQuality = 0.6,        -- Reduced beam quality
		eyesVisible = true,       -- Eyes still visible
		minTransparency = 0.1,    -- Slight base transparency
		maxTransparency = 0.4     -- More fade at tail
	},
	minimal = {
		segmentQuality = 0.3,     -- 30% of segments visible
		glowEnabled = false,      -- No glow effects
		beamQuality = 0.4,        -- Low beam quality
		eyesVisible = false,      -- Eyes hidden
		minTransparency = 0.2,    -- Base transparency
		maxTransparency = 0.6     -- Heavy fade at tail
	},
	veryFar = {
		segmentQuality = 0.15,    -- Only 15% visible
		glowEnabled = false,      -- No glow effects
		beamQuality = 0.2,        -- Minimal beam quality
		eyesVisible = false,      -- Eyes hidden
		minTransparency = 0.3,    -- High base transparency
		maxTransparency = 0.8     -- Very heavy fade
	}
}

local ClientAISnakeLOD = {}
ClientAISnakeLOD.__index = ClientAISnakeLOD

-- Module state
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local frameCounter = 0
local lodStates = {} -- Track LOD state per snake
local updateQueue = {} -- Queue for staggered updates

-- Get LOD level based on distance
local function getLODLevel(distance)
	if distance < LOD_DISTANCE_NEAR then
		return "near", LOD_SETTINGS.near
	elseif distance < LOD_DISTANCE_MID then
		return "mid", LOD_SETTINGS.mid
	elseif distance < LOD_DISTANCE_FAR then
		return "far", LOD_SETTINGS.far
	elseif distance < LOD_DISTANCE_MINIMAL then
		return "minimal", LOD_SETTINGS.minimal
	else
		return "veryFar", LOD_SETTINGS.veryFar
	end
end

-- Apply segment visibility with proper fade
local function applySegmentVisibility(segment, index, totalVisible, settings, fadeStart)
	if not segment or not segment.Parent then return end
	
	-- Never hide segments completely - use transparency instead
	if index <= totalVisible then
		-- Calculate fade based on position in snake
		local fadeFactor = 0
		if index > fadeStart then
			fadeFactor = (index - fadeStart) / (totalVisible - fadeStart)
		end
		
		-- Apply transparency with smooth gradient
		local baseTransparency = settings.minTransparency
		local fadeTransparency = fadeFactor * (settings.maxTransparency - settings.minTransparency)
		segment.Transparency = math.min(baseTransparency + fadeTransparency, 0.95) -- Never go fully transparent
		
		-- Handle glow
		local glow = segment:FindFirstChildOfClass("PointLight") or segment:FindFirstChild("Glow")
		if glow then
			if settings.glowEnabled and index <= 50 then -- Only first 50 segments get glow
				glow.Enabled = true
				glow.Brightness = 2 * (1 - segment.Transparency)
			else
				glow.Enabled = false
			end
		end
		
		return true -- Segment is visible
	else
		-- Segments beyond visible range - high transparency but not invisible
		segment.Transparency = 0.95
		
		local glow = segment:FindFirstChildOfClass("PointLight") or segment:FindFirstChild("Glow")
		if glow then
			glow.Enabled = false
		end
		
		return false -- Segment is "hidden"
	end
end

-- Update beams based on segment visibility
local function updateBeamVisibility(beam, seg1Visible, seg2Visible, settings)
	if not beam then return end
	
	-- Only show beam if both connected segments are visible
	if seg1Visible and seg2Visible then
		beam.Enabled = true
		
		-- Apply beam quality settings
		local transparency = 1 - settings.beamQuality
		beam.Transparency = NumberSequence.new(transparency)
		
		-- Adjust beam width based on quality
		local widthMultiplier = 0.5 + (settings.beamQuality * 0.5)
		local baseWidth0 = beam:GetAttribute("OriginalWidth0") or 1
		local baseWidth1 = beam:GetAttribute("OriginalWidth1") or 1
		beam.Width0 = baseWidth0 * widthMultiplier
		beam.Width1 = baseWidth1 * widthMultiplier
	else
		-- Hide beam if segments aren't visible
		beam.Enabled = false
	end
end

-- Main LOD update function for a single snake
local function updateSnakeLOD(snakeModel, distance)
	local snakeId = snakeModel.Name
	local level, settings = getLODLevel(distance)
	
	-- Check if LOD level changed
	local lastState = lodStates[snakeId]
	if lastState and lastState.level == level then
		return -- No change needed
	end
	
	-- Get snake length
	local currentLength = snakeModel:GetAttribute("CurrentLength") or 100
	
	-- Calculate visible segments based on quality setting
	local visibleSegments = math.max(10, math.floor(currentLength * settings.segmentQuality))
	local fadeStart = math.floor(visibleSegments * 0.7) -- Start fading at 70% mark
	
	-- Find all segments and beams
	local segments = {}
	local beams = {}
	local segmentVisibility = {}
	
	-- Collect segments
	for _, child in ipairs(snakeModel:GetChildren()) do
		if child:IsA("BasePart") then
			local segmentNum = tonumber(child.Name:match("Segment(%d+)"))
			if segmentNum then
				segments[segmentNum] = child
			elseif child.Name == "Segment0_Head" or child.Name == "AISnakeHead" then
				segments[0] = child
			end
		end
	end
	
	-- Collect beams
	local attachmentPart = snakeModel:FindFirstChild("AISnakeAttachmentPart")
	if attachmentPart then
		for _, child in ipairs(attachmentPart:GetChildren()) do
			if child:IsA("Beam") then
				local beamNum = tonumber(child.Name:match("(%d+)"))
				if beamNum then
					beams[beamNum] = child
					-- Store original beam width if not stored
					if not child:GetAttribute("OriginalWidth0") then
						child:SetAttribute("OriginalWidth0", child.Width0)
						child:SetAttribute("OriginalWidth1", child.Width1)
					end
				end
			end
		end
	end
	
	-- Update segments
	for i = 0, currentLength do
		local segment = segments[i]
		if segment then
			-- Head always visible with no transparency
			if i == 0 then
				segment.Transparency = 0
				segmentVisibility[i] = true
			else
				segmentVisibility[i] = applySegmentVisibility(segment, i, visibleSegments, settings, fadeStart)
			end
		end
	end
	
	-- Update beams based on segment visibility
	for i = 0, currentLength - 1 do
		local beam = beams[i]
		if beam then
			updateBeamVisibility(beam, segmentVisibility[i], segmentVisibility[i + 1], settings)
		end
	end
	
	-- Handle eyes
	local eyes = {"LeftEye", "RightEye", "LeftEyePupil", "RightEyePupil"}
	for _, eyeName in ipairs(eyes) do
		local eye = snakeModel:FindFirstChild(eyeName)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = settings.eyesVisible and 0 or 1
		end
	end
	
	-- Update state
	lodStates[snakeId] = {
		level = level,
		distance = distance,
		lastUpdate = tick(),
		visibleSegments = visibleSegments
	}
end

-- Find AI snakes in workspace
local function findAISnakes()
	local snakes = {}
	
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:match("AISnakeModel_") then
			local head = obj:FindFirstChild("Segment0_Head") or obj:FindFirstChild("AISnakeHead")
			if head then
				table.insert(snakes, {
					model = obj,
					head = head
				})
			end
		end
	end
	
	return snakes
end

-- Process update queue
local function processUpdateQueue()
	if not camera then return end
	
	local cameraPos = camera.CFrame.Position
	local processed = 0
	local maxPerFrame = 3 -- Process up to 3 snakes per frame
	
	-- Process queued updates
	while #updateQueue > 0 and processed < maxPerFrame do
		local snake = table.remove(updateQueue, 1)
		
		if snake.model.Parent and snake.head.Parent then
			local distance = (snake.head.Position - cameraPos).Magnitude
			
			if distance <= RENDER_DISTANCE then
				updateSnakeLOD(snake.model, distance)
			end
		end
		
		processed = processed + 1
	end
end

-- Queue all snakes for update
local function queueAllSnakes()
	local snakes = findAISnakes()
	
	-- Sort by distance for priority processing
	if camera then
		local cameraPos = camera.CFrame.Position
		table.sort(snakes, function(a, b)
			local distA = (a.head.Position - cameraPos).Magnitude
			local distB = (b.head.Position - cameraPos).Magnitude
			return distA < distB
		end)
	end
	
	-- Add to update queue
	for _, snake in ipairs(snakes) do
		table.insert(updateQueue, snake)
	end
end

-- Main update loop
local updateConnection
local function startLODSystem()
	updateConnection = RunService.Heartbeat:Connect(function()
		frameCounter = frameCounter + 1
		
		-- Process update queue every frame
		processUpdateQueue()
		
		-- Queue all snakes for update periodically
		if frameCounter % VISIBILITY_CHECK_INTERVAL == 0 then
			queueAllSnakes()
		end
		
		-- Clean up old LOD states every 5 seconds
		if frameCounter % 300 == 0 then
			local currentTime = tick()
			for snakeId, state in pairs(lodStates) do
				if currentTime - state.lastUpdate > 10 then
					lodStates[snakeId] = nil
				end
			end
		end
	end)
end

-- Stop the LOD system
local function stopLODSystem()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	
	-- Reset all LOD states
	lodStates = {}
	updateQueue = {}
end

-- Initialize
local function initialize()
	-- Wait for camera
	if not camera then
		camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")
	end
	
	-- Start the system
	startLODSystem()
	
	print("✅ ClientAISnakeLOD initialized (Fixed Version)")
end

-- Auto-initialize when module loads
initialize()

-- Public API
ClientAISnakeLOD.Start = startLODSystem
ClientAISnakeLOD.Stop = stopLODSystem
ClientAISnakeLOD.ForceUpdate = queueAllSnakes

return ClientAISnakeLOD