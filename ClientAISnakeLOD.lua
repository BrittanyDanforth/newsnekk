-- ClientAISnakeLOD - Place in StarterPlayer > StarterPlayerScripts
-- Handles AI Snake LOD (Level of Detail) client-side for smooth performance
-- Each player sees AI snakes fade based on their own camera position

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Performance optimizations
local mathMin = math.min
local mathMax = math.max
local mathAbs = math.abs

-- LOD Settings - Polished for smooth transitions
local LOD_UPDATE_RATE = 0.1 -- Update every 100ms for smooth performance
local TRANSITION_SPEED = 0.15 -- How fast transparency changes (lower = smoother)

-- Distance thresholds for ultra-smooth fading
local FADE_DISTANCES = {
	{ distance = 200, transparency = 0 },      -- Very close: fully opaque
	{ distance = 400, transparency = 0 },      -- Close: still fully visible
	{ distance = 600, transparency = 0.05 },   -- Starting to fade slightly
	{ distance = 800, transparency = 0.1 },    -- Barely noticeable fade
	{ distance = 1000, transparency = 0.15 },  -- Slight fade
	{ distance = 1200, transparency = 0.2 },   -- More noticeable
	{ distance = 1500, transparency = 0.3 },   -- Fading more
	{ distance = 1800, transparency = 0.4 },   -- Half way faded
	{ distance = 2200, transparency = 0.5 },   -- Getting transparent
	{ distance = 2600, transparency = 0.6 },   -- Very faded
	{ distance = 3000, transparency = 0.65 },  -- Almost gone
	{ distance = 3500, transparency = 0.7 },   -- Nearly invisible
	{ distance = 4000, transparency = 0.75 },  -- Max fade
}

-- Cache for smooth transitions
local segmentTransparencies = {} -- [model][segment] = {current, target}
local beamStates = {} -- [model][beam] = {enabled, transparency}
local lastUpdate = 0

-- Get interpolated transparency based on distance
local function getTargetTransparency(distance, segmentIndex, totalSegments)
	-- Find the two nearest distance points
	local lowerBound = FADE_DISTANCES[1]
	local upperBound = FADE_DISTANCES[#FADE_DISTANCES]
	
	for i = 1, #FADE_DISTANCES - 1 do
		if distance >= FADE_DISTANCES[i].distance and distance <= FADE_DISTANCES[i + 1].distance then
			lowerBound = FADE_DISTANCES[i]
			upperBound = FADE_DISTANCES[i + 1]
			break
		end
	end
	
	-- Interpolate between the two points for smooth transition
	local t = (distance - lowerBound.distance) / (upperBound.distance - lowerBound.distance)
	local baseTransparency = lowerBound.transparency + (upperBound.transparency - lowerBound.transparency) * t
	
	-- Add slight extra fade for tail segments (last 25% of snake)
	if segmentIndex > totalSegments * 0.75 then
		local tailFade = (segmentIndex - totalSegments * 0.75) / (totalSegments * 0.25)
		baseTransparency = mathMin(0.8, baseTransparency + tailFade * 0.1)
	end
	
	return baseTransparency
end

-- Smooth lerp function
local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Process a single AI snake model
local function processAISnake(snakeModel)
	if not snakeModel:GetAttribute("IsAISnake") then return end
	
	-- Find snake parts
	local segmentFolder = snakeModel:FindFirstChild("Segments")
	if not segmentFolder then return end
	
	-- Get head position (Segment0_Head or first segment)
	local head = segmentFolder:FindFirstChild("Segment0_Head") or segmentFolder:FindFirstChild("Segment0")
	if not head then return end
	
	local headPos = head.Position
	local cameraPos = camera.CFrame.Position
	local headDistance = (headPos - cameraPos).Magnitude
	
	-- Initialize cache for this snake if needed
	if not segmentTransparencies[snakeModel] then
		segmentTransparencies[snakeModel] = {}
		beamStates[snakeModel] = {}
	end
	
	local cache = segmentTransparencies[snakeModel]
	local beamCache = beamStates[snakeModel]
	
	-- Count total segments
	local totalSegments = 0
	for _, segment in pairs(segmentFolder:GetChildren()) do
		if segment:IsA("BasePart") and string.match(segment.Name, "Segment%d+") then
			totalSegments = totalSegments + 1
		end
	end
	
	-- Process each segment
	for _, segment in pairs(segmentFolder:GetChildren()) do
		if segment:IsA("BasePart") then
			local segmentMatch = string.match(segment.Name, "Segment(%d+)")
			if segmentMatch then
				local segmentIndex = tonumber(segmentMatch)
				local segmentDistance = (segment.Position - cameraPos).Magnitude
				
				-- Calculate target transparency
				local targetTransparency = 0
				
				if segmentIndex == 0 then
					-- Head is ALWAYS fully visible
					targetTransparency = 0
				else
					-- Body segments fade based on their own distance
					targetTransparency = getTargetTransparency(segmentDistance, segmentIndex, totalSegments)
				end
				
				-- Initialize or get current transparency
				if not cache[segment] then
					cache[segment] = {
						current = segment.Transparency,
						target = targetTransparency
					}
				else
					cache[segment].target = targetTransparency
				end
				
				-- Smooth transition
				local data = cache[segment]
				data.current = lerp(data.current, data.target, TRANSITION_SPEED)
				
				-- Apply transparency
				segment.Transparency = data.current
				
				-- Update glow
				local glow = segment:FindFirstChild("Glow")
				if glow then
					if segmentIndex == 0 then
						-- Head glow always on
						glow.Enabled = true
						glow.Brightness = 3
					elseif data.current < 0.5 then
						glow.Enabled = true
						glow.Brightness = 3 * (1 - data.current)
						glow.Range = 10 * (1 - data.current * 0.5)
					else
						glow.Enabled = false
					end
				end
			end
		end
	end
	
	-- Process beams
	local beamFolder = snakeModel:FindFirstChild("Beams") or snakeModel
	for _, obj in pairs(beamFolder:GetDescendants()) do
		if obj:IsA("Beam") then
			-- Get the segments this beam connects
			local attachment0 = obj.Attachment0
			local attachment1 = obj.Attachment1
			
			if attachment0 and attachment1 then
				-- Try to determine which segments this beam connects
				local segmentIndex = tonumber(string.match(obj.Name, "Beam(%d+)") or "-1")
				
				if segmentIndex >= 0 then
					-- Find the corresponding segments
					local seg1 = segmentFolder:FindFirstChild("Segment" .. segmentIndex)
					local seg2 = segmentFolder:FindFirstChild("Segment" .. (segmentIndex + 1))
					
					if seg1 and seg2 and cache[seg1] and cache[seg2] then
						local trans1 = cache[seg1].current or 0
						local trans2 = cache[seg2].current or 0
						local avgTrans = (trans1 + trans2) / 2
						
						-- Initialize beam cache
						if not beamCache[obj] then
							beamCache[obj] = {
								enabled = obj.Enabled,
								transparency = obj.Transparency.Keypoints[1].Value
							}
						end
						
						-- Head beam (index 0) is always visible
						if segmentIndex == 0 then
							obj.Enabled = true
							obj.Transparency = NumberSequence.new(0)
							obj.Brightness = 2
						else
							-- Body beams fade with segments
							if avgTrans < 0.65 then
								obj.Enabled = true
								-- Make beams slightly more transparent than segments
								local beamTrans = mathMin(avgTrans + 0.1, 0.75)
								obj.Transparency = NumberSequence.new(beamTrans)
								obj.Brightness = mathMax(0.5, 2 * (1 - beamTrans))
							else
								obj.Enabled = false
							end
						end
					end
				elseif string.find(obj.Name, "overlap") then
					-- Overlap beams fade earlier
					local index = tonumber(string.match(obj.Name, "overlap(%d+)"))
					if index then
						local seg = segmentFolder:FindFirstChild("Segment" .. index)
						if seg and cache[seg] then
							local trans = cache[seg].current or 0
							if trans < 0.5 then
								obj.Enabled = true
								obj.Transparency = NumberSequence.new(mathMin(0.9, trans + 0.4))
							else
								obj.Enabled = false
							end
						end
					end
				end
			end
		end
	end
end

-- Main update loop
local function updateLOD()
	local now = tick()
	if now - lastUpdate < LOD_UPDATE_RATE then return end
	lastUpdate = now
	
	-- Find all AI snakes (they're directly in workspace with name pattern)
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and string.find(obj.Name, "AISnakeModel_") then
			processAISnake(obj)
		end
	end
	
	-- Clean up cache for destroyed snakes
	for model, _ in pairs(segmentTransparencies) do
		if not model.Parent then
			segmentTransparencies[model] = nil
			beamStates[model] = nil
		end
	end
end

-- Connect to render loop
RunService.Heartbeat:Connect(updateLOD)

print("Client-side AI Snake LOD system initialized!")