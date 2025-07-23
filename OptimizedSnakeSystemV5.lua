-- Optimized Snake System V5 - FIXED BODY SPAWNING
-- Based on V7.0 with proper body rendering at spawn

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Constants
local SEGMENT_POOL_SIZE = 5000  -- Reduced for performance
local NETWORK_UPDATE_RATE = 30
local MAX_VISIBLE_SEGMENTS = 500  -- Balance between quality and performance
local VISIBLE_DISTANCE = 300  -- Only show segments within this distance
local UPDATE_BATCH_SIZE = 50  -- Update segments in batches

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathAbs = math.abs
local tableInsert = table.insert
local tableRemove = table.remove

-- Segment Pool for efficient memory management
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {} -- Track active segments

-- Initialize segment pool
local function initializeSegmentPool()
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = Instance.new("Part")
		segment.Name = "PooledSegment"
		segment.Size = Vector3.new(4, 4, 4)  -- Default size
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Anchored = true
		segment.Parent = nil -- Keep in memory but not in workspace

		-- Add glow effect
		local glow = Instance.new("PointLight")
		glow.Name = "glow"
		glow.Brightness = 0.8  -- Subtle glow
		glow.Range = 5
		glow.Parent = segment

		SegmentPool[i] = segment
		ActiveSegments[segment] = false
	end
	print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
end

-- Get segment from pool
local function getSegmentFromPool()
	-- Find inactive segment first
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = SegmentPool[i]
		if not ActiveSegments[segment] then
			ActiveSegments[segment] = true
			return segment
		end
	end
	
	-- If all active, reuse oldest
	SegmentPoolIndex = SegmentPoolIndex + 1
	if SegmentPoolIndex > SEGMENT_POOL_SIZE then
		SegmentPoolIndex = 1
	end
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

-- Create RemoteEvents for networking
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

	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config

	-- Ensure we have a valid player
	if not self.player then
		warn("Failed to get player from character")
		return nil
	end

	-- Make character invisible (like original system)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end

	-- Root part settings
	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true

	-- Snake data
	self.length = config.InitialLength or 55
	self.segments = {}  -- Array of segment parts for collision detection
	self.visibleSegments = {}
	self.spawnTime = tick()  -- Track spawn time for LOD delay

	print("Creating snake with initial length:", self.length)

	-- Position history buffer (optimized size)
	local maxHistorySize = mathMin(mathFloor(config.MaxSegments * 0.1), 5000)  -- Much smaller!
	self.positionHistory = {}
	self.historyHead = 1
	self.historyCount = 0

	-- Initialize history with enough points for the full snake
	local initialPoint = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector
	}
	-- Need enough history for visible segments
	local historyNeeded = mathMin(MAX_VISIBLE_SEGMENTS * 2, maxHistorySize)
	for i = 1, historyNeeded do
		self.positionHistory[i] = initialPoint
		self.historyCount = i
	end
	self.maxHistorySize = maxHistorySize

	-- Performance optimization
	self.updateCounter = 0
	self.lastCameraPos = nil
	self.isLocalPlayer = (self.player == Players.LocalPlayer)

	-- Create snake model with proper naming for collision detection
	self.model = Instance.new("Model")
	self.model.Name = "SnakeModel_" .. self.player.UserId
	self.model:SetAttribute("IsSnakeModel", true)
	self.model:SetAttribute("OwnerUserId", self.player.UserId)
	self.model.Parent = workspace

	-- Store reference to snake instance for collision handler
	local snakeRef = Instance.new("ObjectValue")
	snakeRef.Name = "SnakeInstance"
	snakeRef.Parent = self.model

	-- Initialize
	self:createHead()
	self:createInitialSegments()
	self:setupNetworking()

	return self
end

function Snake:addToHistory(data)
	if self.historyCount < self.maxHistorySize then
		self.historyCount = self.historyCount + 1
		self.positionHistory[self.historyCount] = data
		self.historyHead = self.historyCount
	else
		self.historyHead = (self.historyHead % self.maxHistorySize) + 1
		self.positionHistory[self.historyHead] = data
	end
end

function Snake:getFromHistory(stepsBack)
	if stepsBack > self.historyCount then
		return self.positionHistory[1]
	end

	local index = self.historyHead - stepsBack
	if index < 1 then
		if self.historyCount >= self.maxHistorySize then
			index = index + self.maxHistorySize
		else
			index = 1
		end
	end
	return self.positionHistory[index] or self.positionHistory[1]
end

function Snake:createHead()
	-- Create visual head
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	head.Shape = Enum.PartType.Ball
	head.Material = self.config.HeadMaterial or Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.Anchored = true
	head.Transparency = 0  -- Make head visible!
	head.Parent = self.model

	-- Tag for collision detection
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Add glow
	local glow = Instance.new("PointLight")
	glow.Brightness = self.config.GlowIntensity or 2
	glow.Range = self.config.GlowRange or 6
	glow.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	glow.Parent = head

	-- Create eyes
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Anchored = true
		eye.Transparency = 0  -- Visible!
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = "Pupil"
		pupil.Size = Vector3.new(0.4, 0.4, 0.4)
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.CanCollide = false
		pupil.CanQuery = false
		pupil.CanTouch = false
		pupil.Anchored = true
		pupil.Transparency = 0  -- Visible!
		pupil.Parent = self.model

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye(-0.7)
	self.rightEye, self.rightPupil = createEye(0.7)

	self.head = head
end

function Snake:calculateGrowthFactor()
	local growthFactor = 1
	if self.length > 200 then
		if self.length <= 2000 then
			-- 200-2000: grow from 1x to 2x
			growthFactor = 1 + ((self.length - 200) / 1800) * 1.0
		elseif self.length <= 5000 then
			-- 2000-5000: grow from 2x to 3x
			growthFactor = 2 + ((self.length - 2000) / 3000) * 1.0
		elseif self.length <= 10000 then
			-- 5000-10000: grow from 3x to 4x
			growthFactor = 3 + ((self.length - 5000) / 5000) * 1.0
		elseif self.length <= 20000 then
			-- 10000-20000: grow from 4x to 5x
			growthFactor = 4 + ((self.length - 10000) / 10000) * 1.0
		elseif self.length <= 35000 then
			-- 20000-35000: grow from 5x to 6x
			growthFactor = 5 + ((self.length - 20000) / 15000) * 1.0
		else
			-- 35000-50000: grow from 6x to 7x (MASSIVE!)
			growthFactor = 6 + ((self.length - 35000) / 15000) * 1.0
		end
	end
	return mathMin(growthFactor, 7.0)  -- Cap at 7x size
end

function Snake:createInitialSegments()
	local visibleSegments = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	local startPos = self.rootPart.Position

	-- Calculate growth factor
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor

	-- Calculate proper spacing to eliminate gaps
	-- Segments should overlap slightly (0.9 = 10% overlap)
	local segmentDiameter = currentSize.X
	local spacing = segmentDiameter * 0.9

	-- Create all visible segments with no gaps
	local currentPos = startPos
	for i = 1, visibleSegments do
		local segment = getSegmentFromPool()
		if segment then
			segment.Name = "Segment" .. i

			-- Position segments tightly behind each other
			local direction = self.rootPart.CFrame.LookVector
			local offset = direction * (i * spacing)

			-- Add slight curve for natural look
			local curve = math.sin(i * 0.02) * 2
			local rightVector = self.rootPart.CFrame.RightVector
			local pos = startPos - offset + rightVector * curve

			-- Apply color
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
			segment.Size = currentSize
			segment.CFrame = CFramenew(pos, pos - direction)
			segment.Parent = self.model  -- IMPORTANT: Parent immediately!

			-- Tag for collision detection
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)

			-- Update glow
			local glow = segment:FindFirstChild("glow")
			if glow then
				glow.Color = segment.Color
				glow.Range = 5 * growthFactor
			end

			self.segments[i] = segment
		end
	end

	print("Snake spawned: Length", self.length, "Growth", growthFactor, "Size", currentSize.X, "Visible segments", #self.segments)
end

function Snake:setupNetworking()
	if not self.player then return end

	-- Setup update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)

	-- Only setup networking for local player
	if self.player == Players.LocalPlayer then
		self.networkConnection = RunService.Heartbeat:Connect(function()
			local now = tick()
			if now - (self.lastNetworkUpdate or 0) > 1/NETWORK_UPDATE_RATE then
				self:sendNetworkUpdate()
				self.lastNetworkUpdate = now
			end
		end)
	end
end

function Snake:update(dt)
	-- Update position history EVERY FRAME
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector

	-- Add to history
	self:addToHistory({
		position = currentPos,
		lookVector = currentLook
	})

	-- Update head position and size based on growth
	if self.head then
		local growthFactor = self:calculateGrowthFactor()
		local headSize = (self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * growthFactor
		self.head.Size = headSize

		local headCF = CFramenew(currentPos, currentPos + currentLook)
		self.head.CFrame = headCF

		-- Update head glow
		local headGlow = self.head:FindFirstChild("PointLight")
		if headGlow then
			headGlow.Range = (self.config.GlowRange or 6) * growthFactor
		end

		-- Update eyes
		if self.leftEye and self.rightEye then
			local eyeScale = growthFactor * 0.8
			self.leftEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
			self.rightEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
			self.leftPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale
			self.rightPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale

			local eyeHeight = 0.7 * growthFactor
			local eyeForward = -1.5 * growthFactor
			local eyeSeparation = 0.7 * growthFactor

			self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
			self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)

			if self.leftPupil and self.rightPupil then
				self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
				self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
			end
		end
	end

	-- Performance optimization: Update segments smartly
	self.updateCounter = self.updateCounter + 1
	
	-- Get camera position for distance culling
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or currentPos

	-- Update segments to follow history with no gaps
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local segmentDiameter = currentSize.X
	local spacing = segmentDiameter * 0.9  -- 10% overlap to eliminate gaps

	-- Calculate history steps per unit distance
	local historyStepsPerUnit = 2  -- How many history steps per stud

	-- Update strategy based on performance needs
	local timeSinceSpawn = tick() - self.spawnTime
	local skipFrames = 1  -- Default: update every frame
	
	if self.length > 10000 and not self.isLocalPlayer then
		skipFrames = 3  -- Update every 3rd frame for non-local long snakes
	elseif self.length > 5000 and not self.isLocalPlayer then
		skipFrames = 2  -- Update every 2nd frame
	end
	
	-- Update segments
	if self.updateCounter % skipFrames == 0 or timeSinceSpawn < 1 then
		for i, segment in pairs(self.segments) do
			-- Each segment follows at a fixed distance
			local distanceBehind = i * spacing
			local historySteps = mathFloor(distanceBehind * historyStepsPerUnit / 3.2)  -- Normalize by original spacing
			historySteps = mathMin(historySteps, self.historyCount - 1)

			local historyData = self:getFromHistory(historySteps)

			if historyData then
				segment.CFrame = CFramenew(historyData.position, historyData.position + historyData.lookVector)

				-- Update segment size
				segment.Size = currentSize

				-- ALWAYS parent the segment to model - never hide it!
				segment.Parent = self.model
				
				-- LOD for glow only (not visibility)
				if timeSinceSpawn > 3 then
					local distanceFromCamera = (segment.Position - cameraPos).Magnitude
					
					-- Update glow based on distance
					local glow = segment:FindFirstChild("glow")
					if glow then
						if distanceFromCamera > 200 then
							glow.Enabled = false
						else
							glow.Enabled = true
							glow.Range = 5 * growthFactor * mathMax(0.3, 1 - distanceFromCamera/200)
						end
					end
				else
					-- During spawn grace period, full glow
					local glow = segment:FindFirstChild("glow")
					if glow then
						glow.Enabled = true
						glow.Range = 5 * growthFactor
					end
				end
			end
		end
	end
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments)

	-- Calculate growth factor
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor

	-- Add new segments if growing
	local currentVisibleSegments = #self.segments
	local targetVisibleSegments = mathMin(self.length, MAX_VISIBLE_SEGMENTS)

	if targetVisibleSegments > currentVisibleSegments then
		-- Batch segment creation to reduce lag
		local segmentsToAdd = {}

		for i = currentVisibleSegments + 1, targetVisibleSegments do
			local segment = getSegmentFromPool()
			if segment then
				segment.Name = "Segment" .. i

				-- Start at last segment position
				local lastSegment = self.segments[i-1]
				local pos = lastSegment and lastSegment.Position or self.rootPart.Position

				-- Apply color
				local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
				segment.Color = self.config.BodyColors[colorIndex]
				segment.Size = currentSize
				segment.CFrame = CFramenew(pos)

				-- Tag for collision detection
				CollectionService:AddTag(segment, "SnakeSegment")
				segment:SetAttribute("SegmentIndex", i)

				-- Update glow
				local glow = segment:FindFirstChild("glow")
				if glow then
					glow.Color = segment.Color
					glow.Range = 5 * growthFactor
				end

				self.segments[i] = segment
				segmentsToAdd[#segmentsToAdd + 1] = segment
			end
		end

		-- Parent all segments at once to reduce lag
		for _, segment in ipairs(segmentsToAdd) do
			segment.Parent = self.model
		end
	end

	-- Network update
	if self.player == Players.LocalPlayer and remoteEvents.lengthupdate then
		remoteEvents.lengthupdate:FireServer(self.length)
	end
end

function Snake:grow(amount)
	-- Increase length by amount (default 1)
	amount = amount or 1
	local newLength = self.length + amount

	-- Update length (will create new segments if needed)
	self:updateLength(newLength)

	-- Update leaderstats
	local player = self.player
	if player then
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = self.length
			end
		end
	end
end

function Snake:sendNetworkUpdate()
	-- Send position updates to server
	if remoteEvents.positionupdate then
		remoteEvents.positionupdate:FireServer({
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector
		})
	end
end

function Snake:GetSegments()
	-- Return all segments in order for collision detection
	local allSegments = {}
	for i = 1, #self.segments do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(allSegments, self.segments[i])
		end
	end
	return allSegments
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	-- Return all segments to pool and remove tags
	for _, segment in pairs(self.segments) do
		CollectionService:RemoveTag(segment, "SnakeSegment")
		returnSegmentToPool(segment)
	end

	if self.networkConnection then
		self.networkConnection:Disconnect()
	end

	if self.updateConnection then
		self.updateConnection:Disconnect()
	end

	if self.model then
		-- Remove head tag
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV5 = {}

function OptimizedSnakeSystemV5.init()
	-- Initialize pools and networking
	initializeSegmentPool()
	createNetworkEvents()

	print("✅ Optimized Snake System V5 initialized - FIXED BODY SPAWNING!")
end

function OptimizedSnakeSystemV5.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV5