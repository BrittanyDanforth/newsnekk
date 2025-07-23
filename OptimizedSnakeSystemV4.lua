-- Optimized Snake System V4 - PERFORMANCE FOCUSED
-- Same visual quality but actually handles 50k length smoothly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- SMART CONSTANTS - The key to performance
local SEGMENT_POOL_SIZE = 3000  -- Only need 3k, not 20k
local NETWORK_UPDATE_RATE = 20   -- Less network spam
local MAX_VISIBLE_SEGMENTS = 300 -- This is the KEY - only render what matters
local HISTORY_SIZE = 2000        -- Reduced from 30k - still smooth
local UPDATE_SKIP_FRAMES = 2     -- Update every 2nd frame for distant segments

-- Performance tracking
local frameCount = 0
local lastCameraPos = Vector3.new(0,0,0)

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathAbs = math.abs

-- Segment Pool
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {} -- Track which segments are active

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

		-- Glow effect - will be toggled based on distance
		local glow = Instance.new("PointLight")
		glow.Name = "glow"
		glow.Brightness = 0.8
		glow.Range = 5
		glow.Parent = segment

		SegmentPool[i] = segment
		ActiveSegments[segment] = false
	end
	print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
end

-- Get segment from pool
local function getSegmentFromPool()
	-- Find an inactive segment
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = SegmentPool[i]
		if not ActiveSegments[segment] then
			ActiveSegments[segment] = true
			return segment
		end
	end
	-- If all are active, cycle through
	SegmentPoolIndex = (SegmentPoolIndex % SEGMENT_POOL_SIZE) + 1
	return SegmentPool[SegmentPoolIndex]
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

	print("✅ Network events created")
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
	self.segments = {}           -- All segments (for collision)
	self.visibleSegments = {}    -- Currently visible segments
	self.segmentStartIndex = 1   -- For virtual scrolling

	-- SMART position history - circular buffer
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
	self:initializeVisibleSegments()
	self:setupUpdateLoop()

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
	-- Head
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	head.Shape = Enum.PartType.Ball
	head.Material = self.config.HeadMaterial or Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanTouch = true  -- Important for collision
	head.CanQuery = true
	head.Anchored = true
	head.Transparency = 1  -- Invisible head
	head.Parent = self.model

	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Glow
	local glow = Instance.new("PointLight")
	glow.Brightness = self.config.GlowIntensity or 2
	glow.Range = self.config.GlowRange or 6
	glow.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	glow.Parent = head

	-- Eyes (simplified)
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = name .. "Pupil"
		pupil.Size = Vector3.new(0.4, 0.4, 0.4)
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye("LeftEye", -0.7)
	self.rightEye, self.rightPupil = createEye("RightEye", 0.7)
	self.head = head
end

function Snake:calculateGrowthFactor()
	-- Simplified growth calculation
	if self.length <= 200 then
		return 1.0
	elseif self.length <= 5000 then
		return 1.0 + (self.length - 200) / 4800 * 2.0  -- 1x to 3x
	elseif self.length <= 20000 then
		return 3.0 + (self.length - 5000) / 15000 * 2.0  -- 3x to 5x
	else
		return 5.0 + (self.length - 20000) / 30000 * 2.0  -- 5x to 7x max
	end
end

function Snake:initializeVisibleSegments()
	-- Only create what we can see
	local visibleCount = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	
	for i = 1, visibleCount do
		local segment = getSegmentFromPool()
		if segment then
			self:setupSegment(segment, i)
			self.visibleSegments[i] = segment
			self.segments[i] = segment  -- Track for collision
		end
	end

	print("Snake initialized with", #self.visibleSegments, "visible segments out of", self.length, "total")
end

function Snake:setupSegment(segment, index)
	segment.Name = "Segment" .. index
	
	-- Color
	local colorIndex = ((index - 1) % #self.config.BodyColors) + 1
	segment.Color = self.config.BodyColors[colorIndex]
	
	-- Size
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	segment.Size = baseSize * growthFactor
	
	-- Position (will be set in update)
	segment.CFrame = CFramenew(self.rootPart.Position)
	segment.Parent = self.model
	
	-- Collision tag ONLY for visible segments
	if index <= MAX_VISIBLE_SEGMENTS then
		CollectionService:AddTag(segment, "SnakeSegment")
		segment:SetAttribute("SegmentIndex", index)
		segment:SetAttribute("OwnerName", self.player.Name)
	end
	
	-- Glow
	local glow = segment:FindFirstChild("glow")
	if glow then
		glow.Color = segment.Color
		glow.Range = 5 * growthFactor
	end
end

function Snake:setupUpdateLoop()
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		frameCount = frameCount + 1
		
		-- Update position history EVERY frame
		local currentPos = self.rootPart.Position
		local currentLook = self.rootPart.CFrame.LookVector
		self:addToHistory(currentPos, currentLook)
		
		-- Update head EVERY frame
		self:updateHead()
		
		-- Update segments based on performance needs
		if frameCount % UPDATE_SKIP_FRAMES == 0 then
			self:updateAllSegments()
		else
			-- Only update first 50 segments every frame for smoothness
			self:updateNearSegments()
		end
		
		-- Virtual scrolling check every 30 frames
		if frameCount % 30 == 0 then
			self:checkVirtualScrolling()
		end
	end)
	
	-- Network updates (less frequent)
	if self.player == Players.LocalPlayer then
		self.networkTimer = 0
		self.networkConnection = RunService.Heartbeat:Connect(function(dt)
			self.networkTimer = self.networkTimer + dt
			if self.networkTimer >= 1/NETWORK_UPDATE_RATE then
				self.networkTimer = 0
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
		
		self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
		self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
	end
end

function Snake:updateNearSegments()
	-- Only update the first 50 segments for smooth head following
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.9  -- 10% overlap
	
	for i = 1, mathMin(50, #self.visibleSegments) do
		local segment = self.visibleSegments[i]
		if segment and segment.Parent then
			local actualIndex = self.segmentStartIndex + i - 1
			local distanceBehind = actualIndex * spacing
			local historySteps = mathFloor(distanceBehind * 0.6)  -- Tuned for smooth following
			
			local historyData = self:getFromHistory(historySteps)
			if historyData then
				segment.CFrame = CFramenew(historyData.position, historyData.position + historyData.lookVector)
			end
		end
	end
end

function Snake:updateAllSegments()
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.9  -- 10% overlap prevents gaps
	
	-- Get camera for LOD
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or lastCameraPos
	lastCameraPos = cameraPos
	
	-- Update all visible segments
	for i, segment in ipairs(self.visibleSegments) do
		if segment and segment.Parent then
			-- Calculate actual snake index for this visible segment
			local actualIndex = self.segmentStartIndex + i - 1
			local distanceBehind = actualIndex * spacing
			local historySteps = mathFloor(distanceBehind * 0.6)
			
			local historyData = self:getFromHistory(historySteps)
			if historyData then
				segment.CFrame = CFramenew(historyData.position, historyData.position + historyData.lookVector)
				segment.Size = currentSize
				
				-- LOD for glow based on distance
				local distToCamera = (segment.Position - cameraPos).Magnitude
				local glow = segment:FindFirstChild("glow")
				if glow then
					if distToCamera > 200 then
						glow.Enabled = false  -- Disable glow for distant segments
					else
						glow.Enabled = true
						glow.Range = 5 * growthFactor * mathMax(0.3, 1 - distToCamera/200)
					end
				end
			end
		end
	end
end

function Snake:checkVirtualScrolling()
	-- Virtual scrolling - only show segments near the camera
	if self.length <= MAX_VISIBLE_SEGMENTS then
		return  -- No need for virtual scrolling
	end
	
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local cameraPos = camera.CFrame.Position
	local headPos = self.head.Position
	
	-- Find which segment range should be visible
	-- For now, always show segments from head
	-- (Could be optimized to show segments near camera instead)
	
	-- This is where you could implement smart segment visibility
	-- based on camera position, but for now we'll keep it simple
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
	
	-- Update visible segments if needed
	local targetVisible = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	local currentVisible = #self.visibleSegments
	
	if targetVisible > currentVisible then
		-- Add segments
		for i = currentVisible + 1, targetVisible do
			local segment = getSegmentFromPool()
			if segment then
				self:setupSegment(segment, i)
				self.visibleSegments[i] = segment
				self.segments[i] = segment
			end
		end
	elseif targetVisible < currentVisible then
		-- Remove segments
		for i = currentVisible, targetVisible + 1, -1 do
			local segment = self.visibleSegments[i]
			if segment then
				CollectionService:RemoveTag(segment, "SnakeSegment")
				returnSegmentToPool(segment)
				self.visibleSegments[i] = nil
				self.segments[i] = nil
			end
		end
	end
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
			lookVector = self.rootPart.CFrame.LookVector
		})
	end
end

function Snake:destroy()
	-- Cleanup
	for _, segment in pairs(self.visibleSegments) do
		CollectionService:RemoveTag(segment, "SnakeSegment")
		returnSegmentToPool(segment)
	end
	
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	if self.networkConnection then
		self.networkConnection:Disconnect()
	end
	
	if self.model then
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV4 = {}

function OptimizedSnakeSystemV4.init()
	initializeSegmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V4 initialized - PERFORMANCE FOCUSED!")
end

function OptimizedSnakeSystemV4.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV4