-- Optimized Snake System V8 - PURE BEAM RENDERING (SIMPLIFIED & WORKING)
-- Clean, smooth, beam-based snake system

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Constants
local BEAM_SEGMENTS = 30 -- Smooth curves
local ATTACHMENT_SPACING = 2 -- Distance between points
local MAX_VISIBLE_LENGTH = 300 -- Max visible length of snake
local NETWORK_UPDATE_RATE = 1/15 -- 15 FPS network updates

-- Create network events
local remoteEvents = {}
local function createNetworkEvents()
	wait() -- Ensure ReplicatedStorage is ready
	
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
	self.config = config or {}

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

	-- Snake properties
	self.length = config.InitialLength or 10
	self.isBoosting = false
	
	-- Position tracking
	self.positions = {}
	self.positionIndex = 1
	self.maxPositions = 500
	
	-- Visual elements
	self.attachments = {}
	self.beams = {}
	self.model = Instance.new("Model")
	self.model.Name = "SnakeModel_" .. self.player.UserId
	self.model.Parent = workspace
	
	-- Initialize position history
	local startPos = self.rootPart.Position
	for i = 1, self.maxPositions do
		self.positions[i] = startPos
	end
	
	-- Create the snake
	self:createHead()
	self:createBody()
	self:startUpdateLoop()

	return self
end

function Snake:createHead()
	-- Simple glowing head
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = Vector3.new(5, 5, 5)
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 0)
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model
	
	-- Head glow
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 10
	light.Color = head.Color
	light.Parent = head
	
	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)
	
	self.head = head
end

function Snake:createBody()
	-- Create attachments holder
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "AttachmentHolder"
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Parent = self.model
	
	-- Calculate how many segments we need
	local segmentCount = math.min(math.floor(self.length * 2), 100) -- Cap at 100 for performance
	
	-- Create attachments
	for i = 1, segmentCount + 1 do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.attachments[i] = attachment
		
		-- Position them initially
		attachment.WorldPosition = self.rootPart.Position - Vector3.new(0, 0, i * ATTACHMENT_SPACING)
	end
	
	-- Create beams between attachments
	for i = 1, segmentCount do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]
		
		-- Beam appearance
		beam.Width0 = 4
		beam.Width1 = 4
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = ""
		beam.TextureSpeed = 0
		beam.LightEmission = 1
		beam.LightInfluence = 0
		
		-- Color based on body colors
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		
		beam.Parent = attachmentPart
		self.beams[i] = beam
		
		-- Add collision part every 5 segments
		if i % 5 == 0 and i <= 30 then
			local collisionPart = Instance.new("Part")
			collisionPart.Name = "Collision" .. i
			collisionPart.Size = Vector3.new(4, 4, 4)
			collisionPart.Shape = Enum.PartType.Ball
			collisionPart.Transparency = 1
			collisionPart.CanCollide = false
			collisionPart.CanTouch = true
			collisionPart.Anchored = true
			collisionPart.Parent = self.model
			
			CollectionService:AddTag(collisionPart, "SnakeSegment")
			collisionPart:SetAttribute("SegmentIndex", i)
			collisionPart:SetAttribute("OwnerName", self.player.Name)
		end
	end
	
	self.attachmentPart = attachmentPart
end

function Snake:startUpdateLoop()
	local lastNetworkUpdate = 0
	
	self.updateConnection = RunService.Heartbeat:Connect(function()
		if not self.character.Parent then
			self:destroy()
			return
		end
		
		-- Update position history
		local currentPos = self.rootPart.Position
		self.positionIndex = (self.positionIndex % self.maxPositions) + 1
		self.positions[self.positionIndex] = currentPos
		
		-- Update head position
		self.head.CFrame = CFrame.lookAt(currentPos, currentPos + self.rootPart.CFrame.LookVector)
		
		-- Update body segments
		self:updateBody()
		
		-- Network updates
		local now = tick()
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateBody()
	-- Calculate visible length
	local visibleLength = math.min(self.length * ATTACHMENT_SPACING * 2, MAX_VISIBLE_LENGTH)
	local segmentCount = #self.attachments - 1
	
	-- Update attachment positions based on history
	for i = 1, #self.attachments do
		local distanceBehind = (i - 1) * ATTACHMENT_SPACING
		local stepsBack = math.floor(distanceBehind / 2) -- How far back in history
		
		-- Get position from history
		local historyIndex = self.positionIndex - stepsBack
		if historyIndex < 1 then
			historyIndex = historyIndex + self.maxPositions
		end
		
		local targetPos = self.positions[historyIndex]
		if targetPos then
			-- Smooth movement
			local currentPos = self.attachments[i].WorldPosition
			self.attachments[i].WorldPosition = currentPos:Lerp(targetPos, 0.5)
			
			-- Update collision parts
			if i % 5 == 0 and i <= 30 then
				local collisionPart = self.model:FindFirstChild("Collision" .. i)
				if collisionPart then
					collisionPart.Position = self.attachments[i].WorldPosition
				end
			end
		end
	end
	
	-- Update beam widths for tapering effect
	for i, beam in ipairs(self.beams) do
		local progress = i / segmentCount
		local width = 4 * (1 - progress * 0.3) -- Taper to 70% at tail
		beam.Width0 = width
		beam.Width1 = width
		
		-- Boost effect
		if self.isBoosting then
			beam.LightEmission = 1.5
		else
			beam.LightEmission = 1
		end
	end
end

function Snake:grow(amount)
	self.length = math.min(self.length + (amount or 1), self.config.MaxSegments or 10000)
	
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
	
	-- Recreate body if grown significantly
	if self.length > (#self.attachments - 1) / 2 + 10 then
		-- Clean up old body
		for _, attachment in ipairs(self.attachments) do
			attachment:Destroy()
		end
		for _, beam in ipairs(self.beams) do
			beam:Destroy()
		end
		self.attachments = {}
		self.beams = {}
		
		-- Create new body
		self:createBody()
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
end

function Snake:updateLength(newLength)
	self.length = math.min(newLength, self.config.MaxSegments or 10000)
	self:grow(0) -- Trigger body update
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
	local segments = {}
	for i = 5, 30, 5 do
		local part = self.model:FindFirstChild("Collision" .. i)
		if part then
			table.insert(segments, part)
		end
	end
	return segments
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	if self.model then
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.init()
	createNetworkEvents()
	print("✅ Snake System V8 - Simplified & Working!")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8