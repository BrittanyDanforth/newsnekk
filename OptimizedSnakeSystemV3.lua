-- Optimized Snake System V3 - SMOOTH & NO GAPS
-- Fixed the gappy movement by removing frame skipping and batch updates for visible segments

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Constants
local SEGMENT_POOL_SIZE = 5000
local NETWORK_UPDATE_RATE = 30
local MAX_VISIBLE_SEGMENTS = 500  -- Increased for smoother look
local HISTORY_UPDATE_RATE = 60   -- History updates per second

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil

-- Segment Pool
local SegmentPool = {}
local SegmentPoolIndex = 0

-- Initialize segment pool
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
		
		-- Simple glow
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
	
	-- Movement properties
	self.speed = config.BaseSpeed or 16
	self.boostSpeed = config.BoostSpeed or 32
	self.currentSpeed = self.speed
	
	-- Position history with high resolution
	self.maxHistorySize = 5000  -- Much larger for smooth following
	self.positionHistory = {}
	self.historyIndex = 1
	
	-- Initialize with current position
	local startPos = self.rootPart.Position
	for i = 1, self.maxHistorySize do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = self.rootPart.CFrame.LookVector,
			time = tick()
		}
	end
	
	-- Create model
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. (self.player and self.player.Name or "Unknown")
	self.model.Parent = workspace
	
	-- Create head
	self:createHead()
	
	-- Initialize segments
	self:initializeSegments()
	
	-- Setup update connection
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)
	
	-- Setup networking
	self:setupNetworking()
	
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
	
	-- Create eyes
	self:createEyes()
	
	-- Tag for collision
	CollectionService:AddTag(self.head, "SnakeHead")
	self.head:SetAttribute("Player", self.player and self.player.Name or "")
end

function Snake:createEyes()
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

function Snake:initializeSegments()
	local initialVisible = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	
	-- Create all visible segments at start
	for i = 1, initialVisible do
		local segment = getSegmentFromPool()
		if segment then
			self:setupSegment(segment, i)
			self.visibleSegments[i] = segment
			self.segments[i] = segment
		end
	end
	
	print("Snake initialized with", #self.visibleSegments, "visible segments")
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

function Snake:update(dt)
	-- Update position history ALWAYS
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	
	-- Add new position to history
	self.historyIndex = (self.historyIndex % self.maxHistorySize) + 1
	self.positionHistory[self.historyIndex] = {
		position = currentPos,
		lookVector = currentLook,
		time = tick()
	}
	
	-- Update head
	self:updateHead()
	
	-- Update ALL visible segments EVERY frame
	self:updateAllSegments()
	
	-- Handle length changes
	self:updateVisibleSegments()
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
	
	-- Update head glow
	local headGlow = self.head:FindFirstChild("PointLight")
	if headGlow then
		headGlow.Range = (self.config.GlowRange or 6) * growthFactor
	end
end

function Snake:updateAllSegments()
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	
	-- Calculate segment spacing based on size for NO GAPS
	local segmentRadius = currentSize.X / 2
	local segmentSpacing = segmentRadius * 1.8  -- Slight overlap to prevent ANY gaps
	
	-- Get current speed for proper following distance
	local speed = self.currentSpeed or self.speed
	local distancePerSegment = segmentSpacing
	
	-- Update each segment to follow the path
	for i, segment in ipairs(self.visibleSegments) do
		if segment and segment.Parent then
			-- Calculate how far back in history this segment should be
			local distanceBehind = i * distancePerSegment
			
			-- Find the appropriate history position
			local targetPos, targetLook = self:getHistoryPosition(distanceBehind)
			
			if targetPos then
				-- Update segment position smoothly
				segment.CFrame = CFramenew(targetPos, targetPos + targetLook)
				segment.Size = currentSize
				
				-- Update glow
				local glow = segment:FindFirstChild("glow")
				if glow then
					glow.Range = 5 * growthFactor
				end
			end
		end
	end
end

function Snake:getHistoryPosition(distanceBehind)
	-- Convert distance to approximate history steps
	local stepsPerStud = 2  -- Adjust based on movement speed
	local targetSteps = mathFloor(distanceBehind * stepsPerStud)
	
	-- Clamp to available history
	targetSteps = mathMin(targetSteps, self.maxHistorySize - 1)
	
	-- Calculate history index
	local historyIdx = self.historyIndex - targetSteps
	if historyIdx < 1 then
		historyIdx = historyIdx + self.maxHistorySize
	end
	
	local historyData = self.positionHistory[historyIdx]
	if historyData then
		return historyData.position, historyData.lookVector
	end
	
	-- Fallback to current position
	return self.rootPart.Position, self.rootPart.CFrame.LookVector
end

function Snake:updateVisibleSegments()
	local targetVisible = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	local currentVisible = #self.visibleSegments
	
	-- Add segments if needed
	if targetVisible > currentVisible then
		for i = currentVisible + 1, targetVisible do
			local segment = getSegmentFromPool()
			if segment then
				self:setupSegment(segment, i)
				self.visibleSegments[i] = segment
				self.segments[i] = segment
			end
		end
	elseif targetVisible < currentVisible then
		-- Remove excess segments
		for i = currentVisible, targetVisible + 1, -1 do
			local segment = self.visibleSegments[i]
			if segment then
				returnSegmentToPool(segment)
				self.visibleSegments[i] = nil
				self.segments[i] = nil
			end
		end
	end
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
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

function Snake:setBoosting(isBoosting)
	if isBoosting then
		self.currentSpeed = self.boostSpeed
	else
		self.currentSpeed = self.speed
	end
end

function Snake:setupNetworking()
	-- Only network essential data
	if self.player == Players.LocalPlayer then
		self.networkTimer = 0
		
		self.networkConnection = RunService.Heartbeat:Connect(function(dt)
			self.networkTimer = self.networkTimer + dt
			if self.networkTimer >= 1/NETWORK_UPDATE_RATE then
				self.networkTimer = 0
				if remoteEvents.positionupdate then
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
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
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
local OptimizedSnakeSystemV3 = {}

function OptimizedSnakeSystemV3.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV3.init()
	initializeSegmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V3 initialized - SMOOTH movement!")
end

return OptimizedSnakeSystemV3