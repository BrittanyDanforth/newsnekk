-- Optimized Snake System V8 - ULTRA SMOOTH VISUAL BEAST
-- Dynamic growth, buttery smooth movement, no lag, no invisible bullshit

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS baby
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_SEGMENTS = 500 -- Maximum visible segments
local SEGMENT_SPACING = 0.8 -- Tighter spacing for smoother look
local HISTORY_SIZE = 2000 -- Large history for smooth trailing
local GROWTH_CHECK_INTERVAL = 10 -- Check growth every 10 frames

-- Visual Constants
local MIN_HEAD_SIZE = 3
local MAX_HEAD_SIZE = 12
local MIN_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 10
local GLOW_INTENSITY_MIN = 1
local GLOW_INTENSITY_MAX = 3
local BEAM_SEGMENTS = 10 -- Smooth curves
local BEAM_MIN_WIDTH = 2
local BEAM_MAX_WIDTH = 8

-- Create network events
local remoteEvents = {}
local function createNetworkEvents()
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end

	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate", "BoostUpdate"}
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

-- Optimized Snake Class
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
		warn("⚠️ Failed to get player from character")
		return nil
	end

	-- Hide the ugly character model
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		elseif part:IsA("Accessory") then
			part:Destroy()
		end
	end

	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true
	self.rootPart.CanQuery = false

	-- Core snake data
	self.length = config.InitialLength or 10
	self.actualLength = self.length -- For smooth growth interpolation
	self.targetLength = self.length
	self.isBoosting = false
	self.growthFactor = 1
	self.lastGrowthCheck = 0
	
	-- Movement history for smooth trailing
	self.positionHistory = {}
	self.historyIndex = 0
	
	-- Visual components
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace
	
	self.segments = {}
	self.beams = {}
	self.attachments = {}
	self.visibleSegmentCount = 0
	
	-- Pre-fill history with starting position
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i = 1, HISTORY_SIZE do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook,
			time = tick()
		}
	end
	
	-- Initialize the snake
	self:createHead()
	self:createBody()
	self:startUpdateLoop()
	
	print("✅ Snake created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	-- Smooth growth from tiny to massive
	local length = self.actualLength
	
	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 1.5 -- Up to 2.5x at 200
	elseif length <= 1000 then
		return 2.5 + (length - 200) / 800 * 2.5 -- Up to 5x at 1000
	elseif length <= 5000 then
		return 5.0 + (length - 1000) / 4000 * 3.0 -- Up to 8x at 5000
	else
		return 8.0 + math.min((length - 5000) / 10000 * 2.0, 2.0) -- Max 10x
	end
end

function Snake:createHead()
	-- Main head part
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.ForceField
	head.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
	head.Size = Vector3.new(MIN_HEAD_SIZE, MIN_HEAD_SIZE, MIN_HEAD_SIZE)
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model
	
	-- Epic glow effect
	local glow = Instance.new("PointLight")
	glow.Name = "HeadGlow"
	glow.Brightness = GLOW_INTENSITY_MIN
	glow.Range = 15
	glow.Color = head.Color
	glow.Shadows = false
	glow.Parent = head
	
	-- Particle effect for boost
	local particle = Instance.new("ParticleEmitter")
	particle.Name = "BoostParticles"
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(head.Color)
	particle.Lifetime = NumberRange.new(0.5, 1)
	particle.Rate = 0
	particle.Speed = NumberRange.new(5)
	particle.SpreadAngle = Vector2.new(360, 360)
	particle.Enabled = false
	particle.Parent = head
	
	-- Eyes for personality
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.6, 0.6, 0.6)
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model
		
		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.3, 0.3, 0.3)
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model
		
		return eye, pupil
	end
	
	self.leftEye, self.leftPupil = createEye(-0.8)
	self.rightEye, self.rightPupil = createEye(0.8)
	
	-- Collision tagging
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)
	
	self.head = head
	self.headGlow = glow
	self.boostParticles = particle
end

function Snake:createBody()
	-- Calculate initial segment count based on length
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)
	
	-- Create attachment holder
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Parent = self.model
	
	-- Create physical segments for collision
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Only first 50 segments for collision
		segment.CanQuery = false
		segment.Anchored = true
		
		-- Color pattern
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		
		-- Glow for nearby segments
		if i <= 20 then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Brightness = 0.5
			segmentGlow.Range = 8
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
		end
		
		segment.Parent = self.model
		self.segments[i] = segment
		
		-- Collision tagging for first segments
		if i <= 50 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end
		
		-- Create attachments for beams
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "Attachment" .. i
		attachment0.Parent = attachmentPart
		self.attachments[i] = attachment0
	end
	
	-- Add final attachment
	local finalAttachment = Instance.new("Attachment")
	finalAttachment.Name = "AttachmentFinal"
	finalAttachment.Parent = attachmentPart
	self.attachments[segmentCount + 1] = finalAttachment
	
	-- Create smooth beams between segments
	for i = 1, math.min(segmentCount, 100) do -- Limit beams for performance
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]
		
		-- Beam visuals
		beam.Width0 = BEAM_MIN_WIDTH
		beam.Width1 = BEAM_MIN_WIDTH
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.TextureSpeed = 2
		beam.LightEmission = 0.5
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0)
		
		-- Color
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		
		beam.Parent = attachmentPart
		self.beams[i] = beam
	end
	
	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

function Snake:updatePositionHistory()
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector,
		time = tick()
	}
end

function Snake:getHistoricalPosition(stepsBack)
	local index = self.historyIndex - stepsBack
	if index < 1 then
		index = index + HISTORY_SIZE
	end
	return self.positionHistory[index]
end

function Snake:startUpdateLoop()
	local frameCount = 0
	local lastNetworkUpdate = 0
	
	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Safety check
		if not self.character.Parent or not self.rootPart.Parent then
			self:destroy()
			return
		end
		
		frameCount = frameCount + 1
		
		-- Update position history
		self:updatePositionHistory()
		
		-- Smooth length interpolation
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			self.actualLength = self.actualLength + diff * 0.1 -- Smooth transition
		end
		
		-- Update growth factor
		if frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end
		
		-- Update visuals every frame for smoothness
		self:updateHead()
		self:updateBody()
		
		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 50
			self.headGlow.Brightness = GLOW_INTENSITY_MAX
		else
			self.boostParticles.Rate = 0
			self.headGlow.Brightness = GLOW_INTENSITY_MIN
		end
		
		-- Network updates
		local now = tick()
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > 1/NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateHead()
	-- Dynamic head size based on growth
	local headSize = MIN_HEAD_SIZE + (MAX_HEAD_SIZE - MIN_HEAD_SIZE) * (self.growthFactor - 1) / 9
	self.head.Size = Vector3.new(headSize, headSize, headSize)
	
	-- Position and rotation
	local cf = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + self.rootPart.CFrame.LookVector)
	self.head.CFrame = cf
	
	-- Update eyes
	local eyeScale = headSize / MIN_HEAD_SIZE * 0.6
	local eyeOffset = headSize * 0.3
	local eyeForward = -headSize * 0.3
	
	self.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	self.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	
	self.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.7, eyeForward)
	self.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.7, eyeForward)
	self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
	
	-- Update glow
	self.headGlow.Range = 10 + headSize * 2
end

function Snake:updateBody()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)
	
	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end
	
	-- Update each segment
	local segmentSize = MIN_SEGMENT_SIZE + (MAX_SEGMENT_SIZE - MIN_SEGMENT_SIZE) * (self.growthFactor - 1) / 9
	local spacing = segmentSize * SEGMENT_SPACING
	
	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate position from history
			local stepsBack = math.floor(i * spacing / 2)
			local histData = self:getHistoricalPosition(stepsBack)
			
			if histData then
				-- Smooth position update
				local targetPos = histData.position
				local currentPos = segment.Position
				segment.Position = currentPos:Lerp(targetPos, 0.3)
				
				-- Update size with taper
				local taper = 1 - (i / self.visibleSegmentCount) * 0.3 -- 30% taper at tail
				segment.Size = Vector3.new(segmentSize * taper, segmentSize * taper, segmentSize * taper)
				
				-- Update attachment positions for beams
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end
			end
		end
	end
	
	-- Update final attachment
	if self.attachments[self.visibleSegmentCount + 1] and self.segments[self.visibleSegmentCount] then
		self.attachments[self.visibleSegmentCount + 1].WorldPosition = self.segments[self.visibleSegmentCount].Position
	end
	
	-- Update beam widths
	for i, beam in ipairs(self.beams) do
		if beam and beam.Parent and i <= self.visibleSegmentCount then
			local progress = i / self.visibleSegmentCount
			local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
			width = width * (1 - progress * 0.3) -- Taper
			
			beam.Width0 = width
			beam.Width1 = width
			beam.LightEmission = self.isBoosting and 1 or 0.5
			
			-- Boost glow effect
			if self.isBoosting then
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0.2),
					NumberSequenceKeypoint.new(1, 0)
				})
			else
				beam.Transparency = NumberSequence.new(0)
			end
		end
	end
end

function Snake:addSegments(count)
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end
		
		-- Create new segment
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true
		
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		segment.Parent = self.model
		
		self.segments[i] = segment
		
		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment
		
		-- Create beam if within limit
		if i <= 100 and self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. i
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]
			
			beam.Width0 = BEAM_MIN_WIDTH
			beam.Width1 = BEAM_MIN_WIDTH
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureSpeed = 2
			beam.LightEmission = 0.5
			beam.LightInfluence = 0
			
			local colorIdx = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIdx])
			
			beam.Parent = self.attachmentPart
			self.beams[i] = beam
		end
	end
	
	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

function Snake:grow(amount)
	self.targetLength = math.min(self.targetLength + (amount or 1), 50000)
	
	-- Update leaderstats
	if self.player then
		local leaderstats = self.player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = math.floor(self.targetLength)
			end
		end
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
	
	-- Visual feedback
	if boosting then
		self.boostParticles.Enabled = true
		-- Speed lines effect
		for i = 1, 5 do
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.5, 0.5, 10)
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.head.Color
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.head.CFrame * CFrame.new(math.random(-5, 5), math.random(-5, 5), 5)
			speedLine.Parent = self.model
			
			-- Fade out
			local tween = TweenService:Create(speedLine, 
				TweenInfo.new(0.3, Enum.EasingStyle.Linear), 
				{Transparency = 1, Size = Vector3.new(0.1, 0.1, 20)}
			)
			tween:Play()
			Debris:AddItem(speedLine, 0.3)
		end
	else
		self.boostParticles.Enabled = false
	end
end

function Snake:sendNetworkUpdate()
	if remoteEvents.positionupdate then
		remoteEvents.positionupdate:FireServer({
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector,
			length = self.targetLength,
			boosting = self.isBoosting
		})
	end
end

function Snake:updateLength(newLength)
	self.targetLength = math.min(newLength, 50000)
end

function Snake:GetSegments()
	-- Return first 50 segments for collision
	local collisionSegments = {}
	for i = 1, math.min(50, self.visibleSegmentCount) do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(collisionSegments, self.segments[i])
		end
	end
	return collisionSegments
end

function Snake:GetLength()
	return math.floor(self.targetLength)
end

function Snake:destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.init()
	createNetworkEvents()
	print("✅ Snake System V8 - ULTRA SMOOTH INITIALIZED")
	print("🐍 Features: Dynamic Growth | Smooth Movement | Zero Lag")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8