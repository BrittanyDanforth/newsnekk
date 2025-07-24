-- Optimized Snake System V8 - CONTINUOUS BEAM SYSTEM (Slither.io Style)
-- Works like other versions but uses beams for visuals on client
-- NO GAPS POSSIBLE - Uses beam technology on client, collision parts on server

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Detect environment
local IS_CLIENT = RunService:IsClient()
local IS_SERVER = RunService:IsServer()

-- Performance constants
local SEGMENT_POOL_SIZE = 500  -- For server collision parts
local NETWORK_UPDATE_RATE = 15
local HISTORY_SIZE = 2000
local MAX_VISIBLE_SEGMENTS = 300

-- Beam settings (client only)
local BEAM_WIDTH_BASE = 4
local BEAM_SEGMENTS = 10
local ATTACHMENT_SPACING = 3.2

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local tick = tick

-- Pools
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {}

-- Initialize segment pool (server only)
local function initializeSegmentPool()
	if IS_CLIENT then return end
	
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = Instance.new("Part")
		segment.Name = "PooledSegment"
		segment.Size = Vector3new(4, 4, 4)
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Anchored = true
		segment.Parent = nil
		
		-- Add glow
		local glow = Instance.new("PointLight")
		glow.Name = "glow"
		glow.Brightness = 0.5
		glow.Range = 4
		glow.Parent = segment
		
		SegmentPool[i] = segment
		ActiveSegments[segment] = false
	end
	
	print("✅ V8 Server: Segment pool initialized")
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
	self.rootPart.CanTouch = true
	
	-- Snake data
	self.length = config.InitialLength or 55
	self.segments = {}  -- Server: collision parts, Client: visual parts
	self.visibleSegmentCount = 0
	self.isBoosting = false
	
	-- Movement history
	self.positionHistory = {}
	self.historyHead = 1
	self.historyCount = 0
	local maxHistorySize = mathMin(mathFloor(config.MaxSegments * 0.3), 1500)
	
	-- Initialize history
	local initialPoint = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector
	}
	for i = 1, 100 do
		self.positionHistory[i] = initialPoint
		self.historyCount = i
	end
	
	-- Skin data
	self.skinName = config.SkinName or "Default"
	self.headColor = config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.bodyColors = config.BodyColors or {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	}
	
	-- Create model
	self.model = Instance.new("Model")
	self.model.Name = self.player.Name .. "_Snake"
	self.model.Parent = workspace
	
	-- Initialize based on environment
	if IS_CLIENT then
		self:initializeClient()
	else
		self:initializeServer()
	end
	
	-- Start updates
	self:startUpdateLoop()
	
	return self
end

function Snake:initializeServer()
	-- Server only creates collision parts and head
	self:createServerHead()
	self:createInitialSegments()
	
	-- Set attributes for client sync
	self.player:SetAttribute("SnakeLength", self.length)
	self.player:SetAttribute("HeadColor", self.headColor)
	self.player:SetAttribute("EquippedSkin", self.skinName)
end

function Snake:initializeClient()
	-- Client creates visual beam system
	if self.player == Players.LocalPlayer then
		-- For local player, also create collision detection
		self:createClientHead()
	end
	
	-- Create beam visuals
	self:createBeamSystem()
end

function Snake:createServerHead()
	-- Create invisible head
	self.head = Instance.new("Part")
	self.head.Name = "Head"
	self.head.Size = self.config.HeadSize or Vector3new(4.5, 4.5, 4.5)
	self.head.Shape = Enum.PartType.Ball
	self.head.Material = Enum.Material.Neon
	self.head.Color = self.headColor
	self.head.Transparency = 1
	self.head.CanCollide = false
	self.head.CanQuery = false
	self.head.CanTouch = false
	self.head.Anchored = true
	self.head.Parent = self.model
	
	-- Create eyes (visible)
	self:createEyes()
end

function Snake:createClientHead()
	-- Client version - similar but for local collision
	self.head = Instance.new("Part")
	self.head.Name = "ClientHead"
	self.head.Size = self.config.HeadSize or Vector3new(4.5, 4.5, 4.5)
	self.head.Transparency = 1
	self.head.CanCollide = false
	self.head.Anchored = true
	self.head.Parent = self.model
	
	-- Eyes
	self:createEyes()
end

function Snake:createEyes()
	local eyeSize = Vector3new(0.8, 0.8, 0.8)
	
	self.leftEye = Instance.new("Part")
	self.leftEye.Name = "LeftEye"
	self.leftEye.Size = eyeSize
	self.leftEye.Shape = Enum.PartType.Ball
	self.leftEye.Material = Enum.Material.Neon
	self.leftEye.Color = Color3.new(1, 1, 1)
	self.leftEye.CanCollide = false
	self.leftEye.Anchored = true
	self.leftEye.Parent = self.model
	
	self.rightEye = self.leftEye:Clone()
	self.rightEye.Name = "RightEye"
	self.rightEye.Parent = self.model
	
	-- Pupils
	local pupilSize = Vector3new(0.4, 0.4, 0.4)
	self.leftPupil = Instance.new("Part")
	self.leftPupil.Name = "LeftPupil"
	self.leftPupil.Size = pupilSize
	self.leftPupil.Shape = Enum.PartType.Ball
	self.leftPupil.Material = Enum.Material.Neon
	self.leftPupil.Color = Color3.new(0, 0, 0)
	self.leftPupil.CanCollide = false
	self.leftPupil.Anchored = true
	self.leftPupil.Parent = self.model
	
	self.rightPupil = self.leftPupil:Clone()
	self.rightPupil.Name = "RightPupil"
	self.rightPupil.Parent = self.model
end

function Snake:createInitialSegments()
	-- Server creates collision segments
	local visibleLength = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	
	for i = 1, visibleLength do
		local segment = getSegmentFromPool()
		if segment then
			segment.Name = "Segment" .. i
			local colorIndex = ((i - 1) % #self.bodyColors) + 1
			segment.Color = self.bodyColors[colorIndex]
			
			-- Position behind head
			local spacing = self.config.SegmentSpacing or 3.2
			segment.Position = self.rootPart.Position - self.rootPart.CFrame.LookVector * (i * spacing)
			segment.Parent = self.model
			
			self.segments[i] = segment
			CollectionService:AddTag(segment, "SnakeSegment")
		end
	end
	
	self.visibleSegmentCount = visibleLength
end

function Snake:createBeamSystem()
	-- Client-only beam system
	self.beamContainer = Instance.new("Part")
	self.beamContainer.Name = "BeamContainer"
	self.beamContainer.Size = Vector3new(1, 1, 1)
	self.beamContainer.Transparency = 1
	self.beamContainer.CanCollide = false
	self.beamContainer.Anchored = true
	self.beamContainer.Parent = self.model
	
	self.attachments = {}
	self.beams = {}
	
	-- Create attachments along the snake
	local numAttachments = mathMin(self.length, 100)  -- Limit for performance
	
	for i = 0, numAttachments do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.beamContainer
		attachment.WorldPosition = self.rootPart.Position - self.rootPart.CFrame.LookVector * (i * ATTACHMENT_SPACING)
		table.insert(self.attachments, attachment)
	end
	
	-- Create beams between attachments
	for i = 1, #self.attachments - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]
		
		-- Visual properties
		local growthFactor = self:calculateGrowthFactor()
		beam.Width0 = BEAM_WIDTH_BASE * growthFactor
		beam.Width1 = BEAM_WIDTH_BASE * growthFactor * 0.8
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Segments = BEAM_SEGMENTS
		beam.Transparency = NumberSequence.new(0)
		
		-- Color
		local colorIndex = ((i - 1) % #self.bodyColors) + 1
		beam.Color = ColorSequence.new(self.bodyColors[colorIndex])
		
		-- Texture
		beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-check.png"
		beam.TextureSpeed = 2
		beam.TextureLength = 2
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.FaceCamera = true
		
		beam.Parent = self.beamContainer
		table.insert(self.beams, beam)
	end
end

function Snake:addToHistory(data)
	if self.historyCount < #self.positionHistory then
		self.historyCount = self.historyCount + 1
		self.positionHistory[self.historyCount] = data
		self.historyHead = self.historyCount
	else
		self.historyHead = (self.historyHead % #self.positionHistory) + 1
		self.positionHistory[self.historyHead] = data
	end
end

function Snake:getFromHistory(stepsBack)
	if stepsBack > self.historyCount then
		return self.positionHistory[1]
	end
	
	local index = self.historyHead - stepsBack
	if index < 1 then
		index = index + #self.positionHistory
	end
	return self.positionHistory[index] or self.positionHistory[1]
end

function Snake:calculateGrowthFactor()
	if self.length <= 200 then
		return 1
	elseif self.length <= 2000 then
		return 1 + ((self.length - 200) / 1800) * 1.0
	elseif self.length <= 5000 then
		return 2 + ((self.length - 2000) / 3000) * 0.5
	else
		return 2.5 + ((self.length - 5000) / 5000) * 0.5
	end
end

function Snake:updateHead()
	local growthFactor = self:calculateGrowthFactor()
	local headSize = (self.config.HeadSize or Vector3new(4.5, 4.5, 4.5)) * growthFactor
	
	if self.head then
		self.head.Size = headSize
		self.head.CFrame = self.rootPart.CFrame
	end
	
	-- Update eyes
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor * 0.8
		self.leftEye.Size = Vector3new(0.8, 0.8, 0.8) * eyeScale
		self.rightEye.Size = Vector3new(0.8, 0.8, 0.8) * eyeScale
		self.leftPupil.Size = Vector3new(0.4, 0.4, 0.4) * eyeScale
		self.rightPupil.Size = Vector3new(0.4, 0.4, 0.4) * eyeScale
		
		local eyeSeparation = 0.7 * growthFactor
		local eyeHeight = 0.7 * growthFactor
		local eyeForward = -1.5 * growthFactor
		
		local headCF = self.rootPart.CFrame
		self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)
		
		self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
		self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
	end
end

function Snake:updateSegments()
	if IS_SERVER then
		self:updateServerSegments()
	else
		self:updateClientBeams()
	end
end

function Snake:updateServerSegments()
	-- Server updates collision segments like other versions
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.8
	
	local targetVisible = mathMin(self.length, MAX_VISIBLE_SEGMENTS)
	
	-- Update existing segments
	for i = 1, mathMin(#self.segments, targetVisible) do
		local segment = self.segments[i]
		if segment and segment.Parent then
			local delay = i * 0.8
			local targetData = self:getFromHistory(mathFloor(delay))
			
			if targetData then
				segment.CFrame = CFramenew(targetData.position, targetData.position + targetData.lookVector)
				segment.Size = currentSize
				
				local glow = segment:FindFirstChild("glow")
				if glow then
					glow.Range = 4 * growthFactor
				end
			end
		end
	end
	
	-- Handle visibility changes
	if targetVisible < self.visibleSegmentCount then
		for i = targetVisible + 1, self.visibleSegmentCount do
			if self.segments[i] then
				self.segments[i].Parent = nil
			end
		end
	elseif targetVisible > self.visibleSegmentCount then
		for i = self.visibleSegmentCount + 1, targetVisible do
			if self.segments[i] then
				self.segments[i].Parent = self.model
			else
				local segment = getSegmentFromPool()
				if segment then
					segment.Name = "Segment" .. i
					local colorIndex = ((i - 1) % #self.bodyColors) + 1
					segment.Color = self.bodyColors[colorIndex]
					segment.Parent = self.model
					self.segments[i] = segment
					CollectionService:AddTag(segment, "SnakeSegment")
				end
			end
		end
	end
	
	self.visibleSegmentCount = targetVisible
end

function Snake:updateClientBeams()
	-- Client updates beam positions
	if not self.attachments then return end
	
	local growthFactor = self:calculateGrowthFactor()
	
	-- Update attachment positions based on history
	for i, attachment in ipairs(self.attachments) do
		local delay = (i - 1) * 2  -- Spread out more
		local historyData = self:getFromHistory(mathFloor(delay))
		
		if historyData then
			attachment.WorldPosition = historyData.position
		end
	end
	
	-- Update beam widths
	for i, beam in ipairs(self.beams) do
		beam.Width0 = BEAM_WIDTH_BASE * growthFactor * (1 - (i / #self.beams) * 0.3)
		beam.Width1 = beam.Width0 * 0.9
	end
	
	-- Recreate if length changed significantly
	local desiredAttachments = mathMin(self.length, 100)
	if math.abs(desiredAttachments - #self.attachments) > 10 then
		-- Clear old
		for _, beam in ipairs(self.beams) do
			beam:Destroy()
		end
		for _, attachment in ipairs(self.attachments) do
			attachment:Destroy()
		end
		self.beams = {}
		self.attachments = {}
		
		-- Recreate
		self:createBeamSystem()
	end
end

function Snake:startUpdateLoop()
	local updateCounter = 0
	
	self.updateConnection = RunService.Heartbeat:Connect(function()
		if not self.character.Parent then
			self:destroy()
			return
		end
		
		updateCounter = updateCounter + 1
		
		-- Update history
		local currentPos = self.rootPart.Position
		local lookVector = self.rootPart.CFrame.LookVector
		
		local lastHistory = self:getFromHistory(1)
		local dist = (currentPos - lastHistory.position).Magnitude
		
		if dist > 0.1 then
			self:addToHistory({
				position = currentPos,
				lookVector = lookVector
			})
		end
		
		-- Update visuals
		self:updateHead()
		self:updateSegments()
		
		-- Network sync (client to server)
		if IS_CLIENT and self.player == Players.LocalPlayer and updateCounter % 30 == 0 then
			if remoteEvents.positionupdate then
				remoteEvents.positionupdate:FireServer({
					position = currentPos,
					lookVector = lookVector,
					length = self.length
				})
			end
		end
	end)
end

function Snake:setLength(newLength)
	self.length = mathMax(10, newLength)
	
	-- Update on server
	if IS_SERVER then
		self.player:SetAttribute("SnakeLength", self.length)
	end
end

function Snake:destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	-- Clean up segments
	for _, segment in pairs(self.segments) do
		if IS_SERVER then
			returnSegmentToPool(segment)
		else
			segment:Destroy()
		end
	end
	
	-- Clean up beams
	if self.beams then
		for _, beam in ipairs(self.beams) do
			beam:Destroy()
		end
	end
	
	if self.attachments then
		for _, attachment in ipairs(self.attachments) do
			attachment:Destroy()
		end
	end
	
	if self.model then
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV8.init()
	-- Initialize based on environment
	if IS_SERVER then
		initializeSegmentPool()
		createNetworkEvents()
		print("✅ OptimizedSnakeSystemV8 - Server initialized")
	else
		print("✅ OptimizedSnakeSystemV8 - Client initialized")
		
		-- Auto-create beam visuals for all snakes on client
		local function handleCharacter(character)
			wait(0.5)  -- Wait for server setup
			
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				local config = {
					InitialLength = player:GetAttribute("SnakeLength") or 55,
					HeadColor = player:GetAttribute("HeadColor"),
					SkinName = player:GetAttribute("EquippedSkin")
				}
				
				Snake.new(character, config)
			end
		end
		
		-- Handle existing players
		for _, player in pairs(Players:GetPlayers()) do
			if player.Character then
				handleCharacter(player.Character)
			end
			player.CharacterAdded:Connect(handleCharacter)
		end
		
		-- Handle new players
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(handleCharacter)
		end)
	end
end

return OptimizedSnakeSystemV8