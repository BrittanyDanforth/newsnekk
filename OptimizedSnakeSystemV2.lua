-- Optimized Snake System V8.0 - PERFORMANCE FIXED
-- Handles 50K+ length without lag using LOD, batching, and frame skipping

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Performance Constants
local SEGMENT_POOL_SIZE = 5000  -- Reduced - we'll use LOD instead
local NETWORK_UPDATE_RATE = 20  -- Reduced network updates
local MAX_VISIBLE_SEGMENTS = 300  -- Much lower - use LOD for rest
local UPDATE_BATCH_SIZE = 50  -- Update segments in batches
local FRAME_SKIP = 3  -- Only update every 3rd frame
local LOD_DISTANCES = {
	{ distance = 100, segments = 300, quality = 1.0 },    -- Full quality nearby
	{ distance = 300, segments = 150, quality = 0.7 },    -- Medium quality
	{ distance = 500, segments = 75, quality = 0.5 },     -- Low quality
	{ distance = 1000, segments = 25, quality = 0.3 },    -- Very low quality
	{ distance = math.huge, segments = 0, quality = 0 }   -- Hide beyond 1000 studs
}

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil
local tableInsert = table.insert
local tableRemove = table.remove

-- Segment Pool
local SegmentPool = {}
local SegmentPoolIndex = 0

-- LOD Groups for batch updates
local LODGroups = {
	high = {},
	medium = {},
	low = {},
	hidden = {}
}

-- Initialize smaller segment pool
local function initializeSegmentPool()
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = Instance.new("Part")
		segment.Name = "PooledSegment"
		segment.Size = Vector3.new(4, 4, 4)
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Anchored = true
		segment.Parent = nil
		
		-- Simple glow - will be adjusted by LOD
		local glow = Instance.new("PointLight")
		glow.Name = "glow"
		glow.Brightness = 0.8
		glow.Range = 5
		glow.Parent = segment
		
		SegmentPool[i] = segment
	end
	print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
end

-- Get segment from pool
local function getSegmentFromPool()
	SegmentPoolIndex = SegmentPoolIndex + 1
	if SegmentPoolIndex > SEGMENT_POOL_SIZE then
		SegmentPoolIndex = 1
	end
	return SegmentPool[SegmentPoolIndex]
end

-- Return segment to pool
local function returnSegmentToPool(segment)
	if segment then
		segment.Parent = nil
		segment.CFrame = CFramenew(0, -10000, 0)
		segment.Transparency = 0
		local glow = segment:FindFirstChild("glow")
		if glow then
			glow.Enabled = true
		end
	end
end

-- Create network events
local remoteEvents = {}
local function createNetworkEvents()
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end
	
	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate"}
	for _, eventName in ipairs(events) do
		local event = folder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = folder
		end
		remoteEvents[eventName:lower()] = event
	end
	
	print("✅ Network events created")
end

-- Optimized Snake Class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	-- Core properties
	self.character = character
	self.player = Players:GetPlayerFromCharacter(character)
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.rootPart = character:FindFirstChild("HumanoidRootPart")
	self.config = config or {}
	
	-- Snake properties
	self.length = config.InitialLength or 55
	self.segments = {}
	self.visibleSegments = {}
	self.segmentPool = {}
	
	-- Performance tracking
	self.frameCounter = 0
	self.lastUpdateFrame = 0
	self.updateBatchIndex = 1
	self.lodLevel = 1
	
	-- Position history with circular buffer
	self.historySize = mathMin(10000, config.MaxSegments * 2)
	self.positionHistory = {}
	self.historyHead = 1
	self.historyCount = 0
	
	-- Initialize history
	for i = 1, self.historySize do
		self.positionHistory[i] = {
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector
		}
	end
	
	-- Create model
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. (self.player and self.player.Name or "Unknown")
	self.model.Parent = workspace
	
	-- Create head
	self:createHead()
	
	-- Setup networking
	self:setupNetworking()
	
	-- Initialize segments
	self:initializeSegments()
	
	return self
end

function Snake:createHead()
	-- Head is always visible and high quality
	self.head = Instance.new("Part")
	self.head.Name = "SnakeHead"
	self.head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	self.head.Shape = Enum.PartType.Ball
	self.head.Material = self.config.HeadMaterial or Enum.Material.Neon
	self.head.Color = self.config.HeadColor or Color3.new(1, 1, 0)
	self.head.Transparency = 1  -- Invisible like original
	self.head.CanCollide = false
	self.head.CanTouch = true
	self.head.CanQuery = true
	self.head.Anchored = true
	self.head.Parent = self.model
	
	-- Head glow
	local headGlow = Instance.new("PointLight")
	headGlow.Color = self.config.HeadColor or Color3.new(1, 1, 0)
	headGlow.Brightness = self.config.GlowIntensity or 2
	headGlow.Range = self.config.GlowRange or 6
	headGlow.Parent = self.head
	
	-- Create eyes (simplified)
	self:createEyes()
	
	-- Tag for collision
	CollectionService:AddTag(self.head, "SnakeHead")
	self.head:SetAttribute("Player", self.player and self.player.Name or "")
end

function Snake:createEyes()
	-- Simplified eye creation
	local eyeModel = Instance.new("Model")
	eyeModel.Name = "Eyes"
	eyeModel.Parent = self.model
	
	-- Left eye
	self.leftEye = Instance.new("Part")
	self.leftEye.Name = "LeftEye"
	self.leftEye.Size = Vector3.new(0.8, 0.8, 0.8)
	self.leftEye.Shape = Enum.PartType.Ball
	self.leftEye.Material = Enum.Material.Neon
	self.leftEye.Color = Color3.new(1, 1, 1)
	self.leftEye.CanCollide = false
	self.leftEye.Anchored = true
	self.leftEye.Parent = eyeModel
	
	-- Right eye
	self.rightEye = self.leftEye:Clone()
	self.rightEye.Name = "RightEye"
	self.rightEye.Parent = eyeModel
	
	-- Pupils
	self.leftPupil = Instance.new("Part")
	self.leftPupil.Name = "LeftPupil"
	self.leftPupil.Size = Vector3.new(0.4, 0.4, 0.4)
	self.leftPupil.Shape = Enum.PartType.Ball
	self.leftPupil.Material = Enum.Material.Neon
	self.leftPupil.Color = Color3.new(0, 0, 0)
	self.leftPupil.CanCollide = false
	self.leftPupil.Anchored = true
	self.leftPupil.Parent = self.leftEye
	
	self.rightPupil = self.leftPupil:Clone()
	self.rightPupil.Name = "RightPupil"
	self.rightPupil.Parent = self.rightEye
end

function Snake:calculateGrowthFactor()
	-- Progressive growth scaling
	if self.length <= 200 then
		return 1.0
	elseif self.length <= 1000 then
		return 1.0 + (self.length - 200) / 2000
	elseif self.length <= 5000 then
		return 1.4 + (self.length - 1000) / 8000
	else
		return 1.9 + (self.length - 5000) / 20000
	end
end

function Snake:addToHistory(data)
	self.positionHistory[self.historyHead] = data
	self.historyHead = (self.historyHead % self.historySize) + 1
	self.historyCount = mathMin(self.historyCount + 1, self.historySize)
end

function Snake:getFromHistory(stepsBack)
	if stepsBack >= self.historyCount then
		return self.positionHistory[1]
	end
	
	local index = self.historyHead - stepsBack - 1
	if index < 1 then
		index = index + self.historySize
	end
	return self.positionHistory[index]
end

function Snake:initializeSegments()
	-- Only create initial visible segments based on LOD
	local camera = workspace.CurrentCamera
	local viewerPos = camera and camera.CFrame.Position or self.rootPart.Position
	local distance = (self.rootPart.Position - viewerPos).Magnitude
	
	-- Determine LOD level
	local lodInfo = LOD_DISTANCES[1]
	for _, lod in ipairs(LOD_DISTANCES) do
		if distance <= lod.distance then
			lodInfo = lod
			break
		end
	end
	
	local visibleCount = mathMin(self.length, lodInfo.segments)
	
	-- Create initial segments
	for i = 1, visibleCount do
		local segment = getSegmentFromPool()
		if segment then
			self:setupSegment(segment, i)
			self.visibleSegments[i] = segment
		end
	end
end

function Snake:setupSegment(segment, index)
	segment.Name = "Segment" .. index
	
	-- Color
	local colorIndex = ((index - 1) % #self.config.BodyColors) + 1
	segment.Color = self.config.BodyColors[colorIndex]
	
	-- Size based on growth
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	segment.Size = baseSize * growthFactor
	
	-- Position will be set in update
	segment.CFrame = CFramenew(self.rootPart.Position)
	segment.Parent = self.model
	
	-- Tag for collision
	CollectionService:AddTag(segment, "SnakeSegment")
	segment:SetAttribute("SegmentIndex", index)
	segment:SetAttribute("OwnerName", self.player and self.player.Name or "")
	
	-- Glow
	local glow = segment:FindFirstChild("glow")
	if glow then
		glow.Color = segment.Color
		glow.Range = 5 * growthFactor
	end
	
	return segment
end

function Snake:updateLOD()
	-- Get viewer position
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local viewerPos = camera.CFrame.Position
	local distance = (self.rootPart.Position - viewerPos).Magnitude
	
	-- Determine LOD level
	local lodInfo = LOD_DISTANCES[1]
	local lodIndex = 1
	for i, lod in ipairs(LOD_DISTANCES) do
		if distance <= lod.distance then
			lodInfo = lod
			lodIndex = i
			break
		end
	end
	
	-- Skip if LOD hasn't changed significantly
	if math.abs(lodIndex - (self.lodLevel or 1)) < 1 then
		return
	end
	
	self.lodLevel = lodIndex
	local targetSegments = mathMin(self.length, lodInfo.segments)
	local currentVisible = #self.visibleSegments
	
	-- Add segments if needed
	if targetSegments > currentVisible then
		for i = currentVisible + 1, targetSegments do
			local segment = getSegmentFromPool()
			if segment then
				self:setupSegment(segment, i)
				self.visibleSegments[i] = segment
			end
		end
	elseif targetSegments < currentVisible then
		-- Remove excess segments
		for i = currentVisible, targetSegments + 1, -1 do
			local segment = self.visibleSegments[i]
			if segment then
				returnSegmentToPool(segment)
				self.visibleSegments[i] = nil
			end
		end
	end
	
	-- Adjust quality for visible segments
	for i, segment in pairs(self.visibleSegments) do
		if segment then
			local glow = segment:FindFirstChild("glow")
			if glow then
				glow.Enabled = lodInfo.quality > 0.5
				glow.Brightness = 0.8 * lodInfo.quality
			end
			
			-- Reduce material quality for distant segments
			if lodInfo.quality < 0.5 then
				segment.Material = Enum.Material.SmoothPlastic
			else
				segment.Material = self.config.BodyMaterial or Enum.Material.Neon
			end
		end
	end
end

function Snake:update(dt)
	-- Frame skip for performance
	self.frameCounter = self.frameCounter + 1
	if self.frameCounter % FRAME_SKIP ~= 0 then
		return
	end
	
	-- Update position history
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	
	self:addToHistory({
		position = currentPos,
		lookVector = currentLook
	})
	
	-- Update LOD every 30 frames
	if self.frameCounter % 30 == 0 then
		self:updateLOD()
	end
	
	-- Update head (always high priority)
	self:updateHead()
	
	-- Batch update segments
	self:updateSegmentsBatched()
end

function Snake:updateHead()
	local growthFactor = self:calculateGrowthFactor()
	local headSize = (self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * growthFactor
	self.head.Size = headSize
	
	local headCF = CFramenew(self.rootPart.Position, self.rootPart.Position + self.rootPart.CFrame.LookVector)
	self.head.CFrame = headCF
	
	-- Update eyes
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor * 0.8
		self.leftEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		self.rightEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		
		local eyeHeight = 0.7 * growthFactor
		local eyeForward = -1.5 * growthFactor
		local eyeSeparation = 0.7 * growthFactor
		
		self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)
		
		if self.leftPupil and self.rightPupil then
			self.leftPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale
			self.rightPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale
			self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
			self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
		end
	end
end

function Snake:updateSegmentsBatched()
	local visibleCount = #self.visibleSegments
	if visibleCount == 0 then return end
	
	-- Calculate batch range
	local batchStart = ((self.updateBatchIndex - 1) * UPDATE_BATCH_SIZE) + 1
	local batchEnd = mathMin(batchStart + UPDATE_BATCH_SIZE - 1, visibleCount)
	
	-- Update only this batch
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local segmentDiameter = currentSize.X
	local spacing = segmentDiameter * 0.85  -- Tighter spacing to prevent gaps
	
	for i = batchStart, batchEnd do
		local segment = self.visibleSegments[i]
		if segment then
			-- Calculate position from history
			local distanceBehind = i * spacing
			local historySteps = mathFloor(distanceBehind * 0.5)  -- Adjust for movement speed
			historySteps = mathMin(historySteps, self.historyCount - 1)
			
			local historyData = self:getFromHistory(historySteps)
			if historyData then
				-- Smooth interpolation for close segments
				if i <= 50 and historySteps > 0 then
					local prevData = self:getFromHistory(historySteps - 1)
					if prevData then
						local alpha = (distanceBehind * 0.5) % 1
						local lerpedPos = prevData.position:Lerp(historyData.position, alpha)
						segment.CFrame = CFramenew(lerpedPos, lerpedPos + historyData.lookVector)
					else
						segment.CFrame = CFramenew(historyData.position, historyData.position + historyData.lookVector)
					end
				else
					segment.CFrame = CFramenew(historyData.position, historyData.position + historyData.lookVector)
				end
				
				segment.Size = currentSize
			end
		end
	end
	
	-- Move to next batch
	self.updateBatchIndex = self.updateBatchIndex + 1
	if batchStart >= visibleCount then
		self.updateBatchIndex = 1
	end
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
	
	-- Let LOD system handle segment visibility
	-- Don't create all segments immediately
end

function Snake:grow(amount)
	self.length = mathMin(self.length + amount, self.config.MaxSegments or 50000)
	
	-- Update leaderstats if exists
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

function Snake:setupNetworking()
	-- Minimal networking - only send important updates
	if self.player == Players.LocalPlayer then
		self.networkTimer = 0
		
		self.networkConnection = RunService.Heartbeat:Connect(function(dt)
			self.networkTimer = self.networkTimer + dt
			if self.networkTimer >= 1/NETWORK_UPDATE_RATE then
				self.networkTimer = 0
				if remoteEvents.positionupdate then
					-- Send compressed position data
					remoteEvents.positionupdate:FireServer({
						p = self.rootPart.Position,
						l = self.rootPart.CFrame.LookVector
					})
				end
			end
		end)
	end
end

function Snake:destroy()
	-- Cleanup
	if self.networkConnection then
		self.networkConnection:Disconnect()
	end
	
	-- Return all segments to pool
	for _, segment in pairs(self.visibleSegments) do
		returnSegmentToPool(segment)
	end
	
	-- Destroy model
	if self.model then
		self.model:Destroy()
	end
	
	-- Clear from collision system
	if self.player and _G.PlayerSnakes then
		_G.PlayerSnakes[self.player] = nil
	end
end

-- Module
local OptimizedSnakeSystemV2 = {}

function OptimizedSnakeSystemV2.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV2.init()
	initializeSegmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V8.0 initialized - Performance mode!")
end

return OptimizedSnakeSystemV2