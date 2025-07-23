-- Optimized Snake System V8 - ULTRA PERFORMANCE FOR 5K+ LENGTH
-- Eliminates lag with aggressive optimizations while maintaining smooth visuals

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- ULTRA PERFORMANCE CONSTANTS
local SEGMENT_POOL_SIZE = 1000 -- Reduced pool size
local NETWORK_UPDATE_RATE = 10 -- Reduced to 10 Hz for less network traffic
local MAX_VISIBLE_SEGMENTS = 150 -- Much less segments visible
local BOOST_VISIBLE_SEGMENTS = 120 -- Even less when boosting
local HISTORY_SIZE = 500 -- Smaller history buffer
local GAP_CHECK_INTERVAL = 30 -- Check gaps less frequently
local COLLISION_SEGMENTS = 50 -- Only first 50 segments have collision

-- Adaptive LOD based on length
local LOD_THRESHOLDS = {
	{ length = 1000, visible = 150, history = 500 },
	{ length = 3000, visible = 100, history = 400 },
	{ length = 5000, visible = 80, history = 300 },
	{ length = 10000, visible = 60, history = 250 },
	{ length = 20000, visible = 40, history = 200 }
}

-- Gap healing settings
local MAX_SEGMENT_DISTANCE = 10 -- More lenient gap detection
local GAP_HEAL_SPEED = 0.5 -- Faster gap healing

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil
local tick = tick

-- Segment Pool with lazy initialization
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {}
local PoolInitialized = false

-- Lazy pool initialization
local function getSegmentFromPool()
	-- Initialize pool on first use
	if not PoolInitialized then
		for i = 1, SEGMENT_POOL_SIZE do
			local segment = Instance.new("Part")
			segment.Name = "PooledSegment"
			segment.Size = Vector3.new(4, 4, 4)
			segment.Shape = Enum.PartType.Ball
			segment.Material = Enum.Material.SmoothPlastic -- Less expensive than Neon
			segment.TopSurface = Enum.SurfaceType.Smooth
			segment.BottomSurface = Enum.SurfaceType.Smooth
			segment.CanCollide = false
			segment.CanQuery = false
			segment.CanTouch = false
			segment.Anchored = true
			segment.CastShadow = false -- Disable shadows for performance
			segment.Parent = nil
			
			-- No glow for segments - only head has glow
			SegmentPool[i] = segment
			ActiveSegments[segment] = false
		end
		PoolInitialized = true
		print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
	end
	
	-- Find available segment
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = SegmentPool[i]
		if not ActiveSegments[segment] then
			ActiveSegments[segment] = true
			return segment
		end
	end
	
	-- Reuse oldest
	SegmentPoolIndex = (SegmentPoolIndex % SEGMENT_POOL_SIZE) + 1
	local segment = SegmentPool[SegmentPoolIndex]
	ActiveSegments[segment] = true
	return segment
end

-- Return segment to pool
local function returnSegmentToPool(segment)
	if segment then
		ActiveSegments[segment] = false
		segment.Parent = nil
		segment.CFrame = CFramenew(0, -10000, 0)
	end
end

-- Create network events (lazy)
local remoteEvents = {}
local eventsCreated = false
local function ensureNetworkEvents()
	if eventsCreated then return end
	
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end

	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate", "UpdateBoostState"}
	for _, eventName in ipairs(events) do
		local event = folder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = folder
		end
		remoteEvents[eventName:lower()] = event
	end
	eventsCreated = true
end

-- Snake Class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)

	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config

	if not self.player then
		warn("Failed to get player from character")
		return nil
	end

	-- Hide character (optimized)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
			part.CastShadow = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end

	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true

	-- Snake data
	self.length = config.InitialLength or 55
	self.segments = {}
	self.segmentPositions = {}
	self.visibleSegmentCount = 0
	self.isBoosting = false
	self.lastGapCheck = 0
	self.gapCheckFrame = 0
	self.frameCount = 0

	-- Adaptive settings
	self:updateAdaptiveSettings()

	-- Position history (circular buffer)
	self.positionHistory = {}
	self.historyIndex = 0
	self.historyWriteIndex = 0
	
	-- Model with LOD
	self.model = Instance.new("Model")
	self.model.Name = "SnakeModel_" .. self.player.UserId
	self.model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	self.model.Parent = workspace

	-- Initialize
	self:createHead()
	self:initializeSegments()
	self:setupUpdateLoop()

	-- Store in global for other systems
	if not _G.PlayerSnakes then
		_G.PlayerSnakes = {}
	end
	_G.PlayerSnakes[self.player] = self

	return self
end

function Snake:updateAdaptiveSettings()
	-- Adjust settings based on length
	local settings = LOD_THRESHOLDS[#LOD_THRESHOLDS]
	for _, threshold in ipairs(LOD_THRESHOLDS) do
		if self.length <= threshold.length then
			settings = threshold
			break
		end
	end
	
	self.adaptiveMaxVisible = settings.visible
	self.adaptiveHistorySize = settings.history
	
	-- Network rate also scales with length
	if self.length > 5000 then
		NETWORK_UPDATE_RATE = 8 -- Even slower updates
	end
end

function Snake:addToHistory(pos, look)
	-- Circular buffer with adaptive size
	if not self.historyInitialized then
		-- Initialize history
		for i = 1, self.adaptiveHistorySize do
			self.positionHistory[i] = {
				position = pos,
				lookVector = look,
				time = tick()
			}
		end
		self.historyInitialized = true
	end
	
	self.historyWriteIndex = (self.historyWriteIndex % self.adaptiveHistorySize) + 1
	self.positionHistory[self.historyWriteIndex] = {
		position = pos,
		lookVector = look,
		time = tick()
	}
end

function Snake:getFromHistory(stepsBack)
	local index = self.historyWriteIndex - stepsBack
	if index < 1 then
		index = index + self.adaptiveHistorySize
	end
	return self.positionHistory[index] or self.positionHistory[self.historyWriteIndex]
end

function Snake:createHead()
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.CastShadow = false
	head.Transparency = 0
	head.Parent = self.model

	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Only head has glow
	local glow = Instance.new("PointLight")
	glow.Brightness = 1.5 -- Reduced brightness
	glow.Range = 6
	glow.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	glow.Parent = head

	-- Simplified eyes (no pupils for performance)
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.SmoothPlastic
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.Anchored = true
		eye.CastShadow = false
		eye.Transparency = 0
		eye.Parent = self.model
		return eye
	end

	self.leftEye = createEye("LeftEye", -0.7)
	self.rightEye = createEye("RightEye", 0.7)
	self.head = head
end

function Snake:calculateGrowthFactor()
	local length = self.length
	-- Reduced growth for better performance
	if length <= 500 then
		return 1.0
	elseif length <= 5000 then
		return 1.0 + (length - 500) / 4500 * 1.5 -- Max 2.5x at 5000
	elseif length <= 20000 then
		return 2.5 + (length - 5000) / 15000 * 1.5 -- Max 4x at 20000
	else
		return 4.0 -- Cap at 4x
	end
end

function Snake:initializeSegments()
	local maxVisible = mathMin(self.length, self.adaptiveMaxVisible)
	self.visibleSegmentCount = maxVisible
	
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.85 -- Slightly larger gap to reduce overlap calculations
	
	local startPos = self.rootPart.Position
	local direction = self.rootPart.CFrame.LookVector
	
	for i = 1, self.visibleSegmentCount do
		local segment = getSegmentFromPool()
		if segment then
			segment.Name = "Segment" .. i
			
			-- Position behind head
			local offset = direction * (i * spacing)
			local pos = startPos - offset
			
			-- Simple alternating colors (no complex patterns)
			segment.Color = i % 2 == 0 and self.config.BodyColors[1] or self.config.BodyColors[2]
			segment.Size = currentSize
			segment.CFrame = CFramenew(pos, pos - direction)
			segment.Parent = self.model
			
			-- Only tag first COLLISION_SEGMENTS for collision
			if i <= COLLISION_SEGMENTS then
				CollectionService:AddTag(segment, "SnakeSegment")
				segment:SetAttribute("SegmentIndex", i)
				segment:SetAttribute("OwnerName", self.player.Name)
			end
			
			self.segments[i] = segment
			self.segmentPositions[i] = pos
		end
	end
end

function Snake:setupUpdateLoop()
	-- Ensure network events exist
	ensureNetworkEvents()
	
	-- Main update loop with adaptive rate
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		-- Safety check
		if not self.model or not self.model.Parent or not self.rootPart or not self.rootPart.Parent then
			self:destroy()
			return
		end
		
		self.frameCount = self.frameCount + 1
		
		-- Always update position history
		local currentPos = self.rootPart.Position
		local currentLook = self.rootPart.CFrame.LookVector
		self:addToHistory(currentPos, currentLook)
		
		-- Update head every frame
		self:updateHead()
		
		-- Update segments with very adaptive rate
		local updateRate = 1
		if self.length > 5000 then
			updateRate = self.isBoosting and 2 or 3 -- Update every 2-3 frames
		elseif self.length > 2000 then
			updateRate = self.isBoosting and 1 or 2 -- Update every 1-2 frames
		end
		
		if self.frameCount % updateRate == 0 then
			self:updateSegments()
		end
		
		-- Check for gaps less frequently
		self.gapCheckFrame = self.gapCheckFrame + 1
		if self.gapCheckFrame >= GAP_CHECK_INTERVAL then
			self.gapCheckFrame = 0
			-- Only check gaps if not boosting (gaps are less noticeable when moving fast)
			if not self.isBoosting then
				self:checkAndHealGaps()
			end
		end
	end)
	
	-- Network updates (heavily throttled)
	if self.player == Players.LocalPlayer then
		self.networkConnection = RunService.Heartbeat:Connect(function()
			local now = tick()
			if now - (self.lastNetworkUpdate or 0) > 1/NETWORK_UPDATE_RATE then
				self.lastNetworkUpdate = now
				self:sendNetworkUpdate()
			end
		end)
		
		-- Connect boost state updates
		local boostEvent = remoteEvents.updatebooststate
		if boostEvent then
			self._boostConnection = boostEvent.OnClientEvent:Connect(function(boosting)
				self:setBoosting(boosting)
			end)
		end
	end
end

function Snake:updateHead()
	local growthFactor = self:calculateGrowthFactor()
	local headSize = (self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * growthFactor
	
	-- Only update size if it changed significantly
	if (self.head.Size - headSize).Magnitude > 0.1 then
		self.head.Size = headSize
	end
	
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	local headCF = CFramenew(currentPos, currentPos + currentLook)
	self.head.CFrame = headCF
	
	-- Update eyes (simplified)
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor * 0.8
		local eyeSeparation = 0.7 * growthFactor
		local eyeHeight = 0.7 * growthFactor
		local eyeForward = -1.5 * growthFactor
		
		self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)
	end
end

function Snake:updateSegments()
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.85
	
	-- Update adaptive settings if length changed significantly
	if mathAbs(self.length - (self.lastLengthCheck or 0)) > 500 then
		self:updateAdaptiveSettings()
		self.lastLengthCheck = self.length
	end
	
	-- Adjust visible segments based on current settings
	local targetVisible = mathMin(self.length, self.adaptiveMaxVisible)
	if self.isBoosting then
		targetVisible = mathFloor(targetVisible * 0.8) -- Show less when boosting
	end
	
	-- Batch update segments
	local historySteps = mathCeil(spacing / (self.config.BaseSpeed or 50) * 60)
	
	for i = 1, mathMin(#self.segments, targetVisible) do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Get position from history
			local historyData = self:getFromHistory(i * historySteps)
			
			if historyData then
				local newPos = historyData.position
				local newLook = historyData.lookVector
				
				-- Only update if position changed significantly
				local oldPos = self.segmentPositions[i]
				if not oldPos or (newPos - oldPos).Magnitude > 0.5 then
					self.segmentPositions[i] = newPos
					segment.CFrame = CFramenew(newPos, newPos + newLook)
				end
				
				-- Update size only if needed
				if (segment.Size - currentSize).Magnitude > 0.1 then
					segment.Size = currentSize
				end
			end
		end
	end
	
	-- Handle visibility changes efficiently
	if targetVisible < self.visibleSegmentCount then
		-- Hide extra segments
		for i = targetVisible + 1, self.visibleSegmentCount do
			if self.segments[i] then
				self.segments[i].Parent = nil
			end
		end
	elseif targetVisible > self.visibleSegmentCount then
		-- Show more segments (limited creation)
		local maxCreate = mathMin(targetVisible - self.visibleSegmentCount, 10) -- Max 10 per frame
		for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + maxCreate do
			if i <= targetVisible then
				if self.segments[i] then
					self.segments[i].Parent = self.model
				else
					-- Create new segment
					local segment = getSegmentFromPool()
					if segment then
						segment.Name = "Segment" .. i
						segment.Color = i % 2 == 0 and self.config.BodyColors[1] or self.config.BodyColors[2]
						segment.Size = currentSize
						segment.Parent = self.model
						self.segments[i] = segment
						
						-- Only tag first COLLISION_SEGMENTS
						if i <= COLLISION_SEGMENTS then
							CollectionService:AddTag(segment, "SnakeSegment")
							segment:SetAttribute("SegmentIndex", i)
						end
					end
				end
			end
		end
	end
	
	self.visibleSegmentCount = targetVisible
end

function Snake:checkAndHealGaps()
	-- Only check first 30 segments for gaps (most visible)
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local expectedDistance = (baseSize * growthFactor).X * 0.85
	
	for i = 2, mathMin(30, self.visibleSegmentCount) do
		local prevPos = self.segmentPositions[i-1]
		local currPos = self.segmentPositions[i]
		
		if prevPos and currPos then
			local distance = (currPos - prevPos).Magnitude
			
			-- If gap detected, quickly close it
			if distance > expectedDistance * 1.5 then
				local segment = self.segments[i]
				if segment and segment.Parent then
					-- Fast gap healing
					local targetPos = prevPos + (currPos - prevPos).Unit * expectedDistance
					self.segmentPositions[i] = targetPos
					local lookDir = (currPos - prevPos).Unit
					segment.CFrame = CFramenew(targetPos, targetPos + lookDir)
				end
			end
		end
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
	-- Update adaptive settings
	self:updateAdaptiveSettings()
end

function Snake:grow(amount)
	amount = amount or 1
	self:updateLength(self.length + amount)
	
	-- Update leaderstats
	if self.player then
		local leaderstats = self.player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = self.length
			end
		end
	end
end

function Snake:shrink(amount)
	amount = amount or 1
	self:updateLength(mathMax(10, self.length - amount))
	
	-- Update leaderstats
	if self.player then
		local leaderstats = self.player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = self.length
			end
		end
	end
end

function Snake:sendNetworkUpdate()
	if not remoteEvents.positionupdate then return end
	
	-- Only send minimal data
	local data = {
		p = self.rootPart.Position,
		l = self.rootPart.CFrame.LookVector,
		b = self.isBoosting and 1 or 0, -- Use number instead of boolean
		s = self.length
	}
	
	-- Compress position to 0.1 precision
	data.p = Vector3new(
		mathFloor(data.p.X * 10 + 0.5) / 10,
		mathFloor(data.p.Y * 10 + 0.5) / 10,
		mathFloor(data.p.Z * 10 + 0.5) / 10
	)
	
	remoteEvents.positionupdate:FireServer(data)
end

-- Expose segments property for compatibility
function Snake:GetSegments()
	-- Return only collision segments
	local collisionSegments = {}
	for i = 1, mathMin(COLLISION_SEGMENTS, #self.segments) do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(collisionSegments, self.segments[i])
		end
	end
	return collisionSegments
end

-- Add segments property
Snake.segments = function(self)
	return self:GetSegments()
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	-- Remove from global
	if _G.PlayerSnakes and _G.PlayerSnakes[self.player] then
		_G.PlayerSnakes[self.player] = nil
	end
	
	-- Disconnect updates first
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	if self.networkConnection then
		self.networkConnection:Disconnect()
		self.networkConnection = nil
	end
	
	if self._boostConnection then
		self._boostConnection:Disconnect()
		self._boostConnection = nil
	end
	
	-- Clear segments efficiently
	for _, segment in pairs(self.segments) do
		if segment then
			CollectionService:RemoveTag(segment, "SnakeSegment")
			returnSegmentToPool(segment)
		end
	end
	
	self.segments = {}
	self.segmentPositions = {}
	self.positionHistory = {}
	
	if self.model then
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
		self.model = nil
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.init()
	-- Lazy initialization - pool created on first snake
	ensureNetworkEvents()
	print("✅ Optimized Snake System V8 initialized - ULTRA PERFORMANCE!")
	print("📊 Adaptive LOD: Visible segments scale with length")
	print("🚀 Network rate: " .. NETWORK_UPDATE_RATE .. " Hz")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8