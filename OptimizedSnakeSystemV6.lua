-- Optimized Snake System V6 - ULTRA PERFORMANCE MODE
-- Fixes gapping when boosting and collision lag at high lengths

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- AGGRESSIVE PERFORMANCE CONSTANTS
local SEGMENT_POOL_SIZE = 2000  -- Smaller pool
local NETWORK_UPDATE_RATE = 15  -- Less network traffic
local MAX_VISIBLE_SEGMENTS = 200  -- Only render what matters!
local BOOST_VISIBLE_SEGMENTS = 150  -- Even less when boosting
local HISTORY_SIZE = 1000  -- Smaller history buffer
local COLLISION_CHECK_RATE = 4  -- Only check collision every 4th frame

-- Performance metrics
local frameCount = 0
local lastPerformanceCheck = tick()
local averageDeltaTime = 0.016

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil
local tick = tick

-- Segment Pool
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {}

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
		segment.CanQuery = false  -- Disable collision queries
		segment.CanTouch = false  -- Disable touch detection for segments
		segment.Anchored = true
		segment.Parent = nil

		-- Simple glow - no PointLight for performance
		SegmentPool[i] = segment
		ActiveSegments[segment] = false
	end
	print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
end

-- Get segment from pool
local function getSegmentFromPool()
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

	-- Hide character
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end

	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true

	-- Snake data
	self.length = config.InitialLength or 55
	self.segments = {}
	self.visibleSegmentCount = 0
	self.lastUpdateTime = tick()
	self.isBoosting = false

	-- Optimized position history
	self.positionHistory = {}
	self.historyIndex = 1
	self.historySize = HISTORY_SIZE
	
	-- Pre-fill history
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i = 1, self.historySize do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook
		}
	end

	-- Model
	self.model = Instance.new("Model")
	self.model.Name = "SnakeModel_" .. self.player.UserId
	self.model.Parent = workspace

	-- Initialize
	self:createHead()
	self:initializeSegments()
	self:setupUpdateLoop()

	-- Collision check state
	self.lastCollisionCheck = 0
	self.collisionCheckFrame = 0

	return self
end

function Snake:addToHistory(pos, look)
	self.historyIndex = (self.historyIndex % self.historySize) + 1
	self.positionHistory[self.historyIndex] = {
		position = pos,
		lookVector = look
	}
end

function Snake:getFromHistory(stepsBack)
	local index = self.historyIndex - stepsBack
	if index < 1 then
		index = index + self.historySize
	end
	return self.positionHistory[index]
end

function Snake:createHead()
	-- Simplified head - no glow for performance
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	head.Shape = Enum.PartType.Ball
	head.Material = self.config.HeadMaterial or Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanTouch = true  -- Keep for collision detection
	head.CanQuery = true
	head.Anchored = true
	head.Transparency = 0
	head.Parent = self.model

	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Simplified eyes - no pupils for performance
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Anchored = true
		eye.Parent = self.model
		return eye
	end

	self.leftEye = createEye("LeftEye", -0.7)
	self.rightEye = createEye("RightEye", 0.7)
	self.head = head
end

function Snake:calculateGrowthFactor()
	-- Simpler growth calculation
	local length = self.length
	if length <= 200 then
		return 1.0
	elseif length <= 5000 then
		return 1.0 + (length - 200) / 2400  -- Max 3x at 5000
	elseif length <= 20000 then
		return 3.0 + (length - 5000) / 7500  -- Max 5x at 20000
	else
		return 5.0 + mathMin((length - 20000) / 15000, 2.0)  -- Max 7x
	end
end

function Snake:initializeSegments()
	-- Calculate visible segments based on boost state
	local maxVisible = self.isBoosting and BOOST_VISIBLE_SEGMENTS or MAX_VISIBLE_SEGMENTS
	self.visibleSegmentCount = mathMin(self.length, maxVisible)
	
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.85  -- Tighter spacing to prevent gaps
	
	local startPos = self.rootPart.Position
	local direction = self.rootPart.CFrame.LookVector
	
	for i = 1, self.visibleSegmentCount do
		local segment = getSegmentFromPool()
		if segment then
			segment.Name = "Segment" .. i
			
			-- Position behind head
			local offset = direction * (i * spacing)
			local pos = startPos - offset
			
			-- Color
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
			segment.Size = currentSize
			segment.CFrame = CFramenew(pos, pos - direction)
			segment.Parent = self.model
			
			-- Only tag first 100 segments for collision
			if i <= 100 then
				CollectionService:AddTag(segment, "SnakeSegment")
				segment:SetAttribute("SegmentIndex", i)
				segment:SetAttribute("OwnerName", self.player.Name)
			end
			
			self.segments[i] = segment
		end
	end
end

function Snake:setupUpdateLoop()
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		-- Safety check
		if not self.model or not self.model.Parent or not self.rootPart or not self.rootPart.Parent then
			if self.updateConnection then
				self.updateConnection:Disconnect()
				self.updateConnection = nil
			end
			return
		end
		
		frameCount = frameCount + 1
		
		-- Track performance
		if frameCount % 60 == 0 then
			local now = tick()
			averageDeltaTime = (now - lastPerformanceCheck) / 60
			lastPerformanceCheck = now
		end
		
		-- Always update position history
		local currentPos = self.rootPart.Position
		local currentLook = self.rootPart.CFrame.LookVector
		self:addToHistory(currentPos, currentLook)
		
		-- Update head every frame
		self:updateHead()
		
		-- Smart segment updates based on performance
		local updateRate = self.isBoosting and 1 or 2  -- Update every frame when boosting
		if frameCount % updateRate == 0 then
			self:updateSegments()
		end
		
		-- Collision checks - reduced frequency
		self.collisionCheckFrame = self.collisionCheckFrame + 1
		if self.collisionCheckFrame >= COLLISION_CHECK_RATE then
			self.collisionCheckFrame = 0
			-- Collision system will handle this
		end
	end)
	
	-- Network updates (less frequent)
	if self.player == Players.LocalPlayer then
		self.networkConnection = RunService.Heartbeat:Connect(function()
			local now = tick()
			if now - (self.lastNetworkUpdate or 0) > 1/NETWORK_UPDATE_RATE then
				self.lastNetworkUpdate = now
				self:sendNetworkUpdate()
			end
		end)
	end
end

function Snake:updateHead()
	local growthFactor = self:calculateGrowthFactor()
	local headSize = (self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * growthFactor
	self.head.Size = headSize
	
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	local headCF = CFramenew(currentPos, currentPos + currentLook)
	self.head.CFrame = headCF
	
	-- Update eyes (simplified)
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor * 0.8
		self.leftEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		self.rightEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		
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
	local spacing = currentSize.X * 0.85  -- Tighter spacing
	
	-- Adjust visible segments based on boost state
	local targetVisible = self.isBoosting and BOOST_VISIBLE_SEGMENTS or MAX_VISIBLE_SEGMENTS
	targetVisible = mathMin(self.length, targetVisible)
	
	-- History calculation optimized for smooth following
	local historyStepsPerUnit = self.isBoosting and 1.5 or 2
	
	-- Update existing segments
	for i = 1, mathMin(#self.segments, targetVisible) do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate history position
			local distanceBehind = i * spacing
			local historySteps = mathCeil(distanceBehind * historyStepsPerUnit / 3.2)
			historySteps = mathMin(historySteps, self.historySize - 1)
			
			local historyData = self:getFromHistory(historySteps)
			if historyData then
				-- Smooth position update
				local targetPos = historyData.position
				local targetLook = historyData.lookVector
				
				-- Apply position
				segment.CFrame = CFramenew(targetPos, targetPos + targetLook)
				segment.Size = currentSize
			end
		end
	end
	
	-- Handle visibility changes
	if targetVisible < self.visibleSegmentCount then
		-- Hide extra segments
		for i = targetVisible + 1, self.visibleSegmentCount do
			if self.segments[i] then
				self.segments[i].Parent = nil
			end
		end
	elseif targetVisible > self.visibleSegmentCount then
		-- Show more segments
		for i = self.visibleSegmentCount + 1, targetVisible do
			if self.segments[i] then
				self.segments[i].Parent = self.model
			else
				-- Create new segment if needed
				local segment = getSegmentFromPool()
				if segment then
					segment.Name = "Segment" .. i
					local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
					segment.Color = self.config.BodyColors[colorIndex]
					segment.Size = currentSize
					segment.Parent = self.model
					self.segments[i] = segment
					
					-- Only tag first 100 for collision
					if i <= 100 then
						CollectionService:AddTag(segment, "SnakeSegment")
						segment:SetAttribute("SegmentIndex", i)
					end
				end
			end
		end
	end
	
	self.visibleSegmentCount = targetVisible
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
	
	-- Update visible segments on next frame
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

function Snake:sendNetworkUpdate()
	if remoteEvents.positionupdate then
		remoteEvents.positionupdate:FireServer({
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector,
			boosting = self.isBoosting
		})
	end
end

function Snake:GetSegments()
	-- Only return first 100 segments for collision checks
	local collisionSegments = {}
	for i = 1, mathMin(100, #self.segments) do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(collisionSegments, self.segments[i])
		end
	end
	return collisionSegments
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	-- Disconnect updates first
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	if self.networkConnection then
		self.networkConnection:Disconnect()
		self.networkConnection = nil
	end
	
	-- Clear segments
	local segmentsCopy = self.segments
	self.segments = {}
	
	for _, segment in pairs(segmentsCopy) do
		if segment and segment.Parent then
			CollectionService:RemoveTag(segment, "SnakeSegment")
			returnSegmentToPool(segment)
		end
	end
	
	if self.model then
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV6 = {}

function OptimizedSnakeSystemV6.init()
	initializeSegmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V6 initialized - ULTRA PERFORMANCE MODE!")
end

function OptimizedSnakeSystemV6.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV6