-- Optimized Snake System V8 Enhanced - ULTRA SOLID BEAM RENDERING
-- No transparency, no gaps, maximum visual impact with overlapping beams

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
local SEGMENT_SPACING = 0.6 -- TIGHTER spacing for no gaps
local HISTORY_SIZE = 2000 -- Large history for smooth trailing
local GROWTH_CHECK_INTERVAL = 10 -- Check growth every 10 frames

-- Visual Constants - ENHANCED FOR SOLID RENDERING
local MIN_HEAD_SIZE = 3
local MAX_HEAD_SIZE = 12
local MIN_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 10
local GLOW_INTENSITY_MIN = 2 -- Increased base glow
local GLOW_INTENSITY_MAX = 5 -- Stronger boost glow
local BEAM_SEGMENTS = 20 -- MORE segments for smoother curves
local BEAM_MIN_WIDTH = 4 -- WIDER minimum for no gaps
local BEAM_MAX_WIDTH = 16 -- Bigger max for massive snakes
local BEAM_OVERLAP_FACTOR = 1.3 -- Overlap beams to prevent gaps
local SEGMENT_BLEND_FACTOR = 0.5 -- How much segments blend together

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

	-- Make sure character is hidden but head will be visible
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

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
	head.Material = Enum.Material.ForceField -- ULTRA GLOW MATERIAL
	head.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
	head.Size = Vector3.new(MIN_HEAD_SIZE, MIN_HEAD_SIZE, MIN_HEAD_SIZE)
	head.Transparency = 0 -- COMPLETELY SOLID
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model

	-- Epic glow effect - DOUBLED
	local glow = Instance.new("PointLight")
	glow.Name = "HeadGlow"
	glow.Brightness = GLOW_INTENSITY_MIN
	glow.Range = 20 -- Increased range
	glow.Color = head.Color
	glow.Shadows = true -- Enable shadows for depth
	glow.Parent = head

	-- Secondary glow for extra brightness
	local glow2 = Instance.new("PointLight")
	glow2.Name = "HeadGlow2"
	glow2.Brightness = GLOW_INTENSITY_MIN * 0.5
	glow2.Range = 30
	glow2.Color = head.Color
	glow2.Shadows = false
	glow2.Parent = head

	-- Surface light for head
	local surfaceLight = Instance.new("SurfaceLight")
	surfaceLight.Brightness = 2
	surfaceLight.Color = head.Color
	surfaceLight.Face = Enum.NormalId.Front
	surfaceLight.Parent = head

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
	particle.LightEmission = 1
	particle.Parent = head

	-- Eyes for personality - GLOWING EYES
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.6, 0.6, 0.6)
		eye.Transparency = 0 -- SOLID EYES
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		-- Eye glow
		local eyeGlow = Instance.new("PointLight")
		eyeGlow.Brightness = 1
		eyeGlow.Range = 5
		eyeGlow.Color = Color3.fromRGB(255, 255, 255)
		eyeGlow.Parent = eye

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.3, 0.3, 0.3)
		pupil.Transparency = 0 -- SOLID PUPILS
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

	-- Create head attachment for beam connection
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "HeadAttachment"
	headAttachment.Parent = head
	self.headAttachment = headAttachment

	self.head = head
	self.headGlow = glow
	self.headGlow2 = glow2
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

	-- Create physical segments for collision and visuals
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.ForceField -- ULTRA GLOW SEGMENTS
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0 -- SOLID SEGMENTS
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Only first 50 segments for collision
		segment.CanQuery = false
		segment.Anchored = true

		-- Color pattern
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Glow for ALL segments (performance optimized)
		if i <= 100 or i % 5 == 0 then -- Every segment up to 100, then every 5th
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Brightness = 1
			segmentGlow.Range = 10
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

	-- CREATE HEAD-TO-BODY BEAM FIRST - CRITICAL CONNECTION
	local headBeam = Instance.new("Beam")
	headBeam.Name = "HeadBeam"
	headBeam.Attachment0 = self.headAttachment
	headBeam.Attachment1 = self.attachments[1]

	-- Head beam properties - ULTRA SOLID
	headBeam.Width0 = BEAM_MIN_WIDTH * 1.2 -- Slightly wider at head
	headBeam.Width1 = BEAM_MIN_WIDTH
	headBeam.CurveSize0 = 0
	headBeam.CurveSize1 = 0
	headBeam.FaceCamera = true
	headBeam.Segments = BEAM_SEGMENTS
	headBeam.Texture = "" -- NO TEXTURE for pure color
	headBeam.TextureMode = Enum.TextureMode.Static
	headBeam.TextureLength = 1
	headBeam.TextureSpeed = 0
	headBeam.LightEmission = 1 -- FULL EMISSION
	headBeam.LightInfluence = 0
	headBeam.Transparency = NumberSequence.new(0) -- COMPLETELY SOLID
	headBeam.ZOffset = -0.1 -- Render slightly behind to prevent z-fighting

	-- Use first body color for head beam
	headBeam.Color = ColorSequence.new(self.config.BodyColors[1])
	headBeam.Parent = attachmentPart
	self.headBeam = headBeam

	-- Create OVERLAPPING beams between segments for NO GAPS
	for i = 1, math.min(segmentCount * 2, 200) do -- Double beams for coverage
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		
		-- Alternate between normal and overlap beams
		if i <= segmentCount then
			-- Normal beam
			beam.Attachment0 = self.attachments[i]
			beam.Attachment1 = self.attachments[i + 1]
		else
			-- Overlap beam (connects i to i+2 for gap coverage)
			local baseIndex = i - segmentCount
			if self.attachments[baseIndex] and self.attachments[baseIndex + 2] then
				beam.Attachment0 = self.attachments[baseIndex]
				beam.Attachment1 = self.attachments[baseIndex + 2]
			else
				beam:Destroy()
				continue
			end
		end

		-- Enhanced beam visuals - MAXIMUM SOLIDITY
		local isOverlap = i > segmentCount
		beam.Width0 = BEAM_MIN_WIDTH * (isOverlap and 0.8 or 1) -- Overlap beams slightly thinner
		beam.Width1 = BEAM_MIN_WIDTH * (isOverlap and 0.8 or 1)
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = "" -- NO TEXTURE for pure solid color
		beam.TextureMode = Enum.TextureMode.Static
		beam.TextureLength = 1
		beam.TextureSpeed = 0
		beam.LightEmission = 1 -- MAXIMUM BRIGHTNESS
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0) -- ZERO TRANSPARENCY
		beam.ZOffset = isOverlap and 0.1 or 0 -- Layer overlap beams

		-- Color
		local colorIndex = ((math.floor((i - 1) / 2)) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])

		beam.Parent = attachmentPart
		self.beams[i] = beam
	end

	-- Add extra fill beams for critical gaps
	self:createFillBeams(segmentCount)

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

function Snake:createFillBeams(segmentCount)
	-- Create additional beams that span 3-4 segments to fill any potential gaps
	local fillBeams = {}
	for i = 1, math.min(segmentCount - 3, 20) do
		local fillBeam = Instance.new("Beam")
		fillBeam.Name = "FillBeam" .. i
		fillBeam.Attachment0 = self.attachments[i]
		fillBeam.Attachment1 = self.attachments[i + 3]
		
		-- Fill beam properties
		fillBeam.Width0 = BEAM_MIN_WIDTH * 1.5
		fillBeam.Width1 = BEAM_MIN_WIDTH * 1.5
		fillBeam.CurveSize0 = 0
		fillBeam.CurveSize1 = 0
		fillBeam.FaceCamera = true
		fillBeam.Segments = BEAM_SEGMENTS * 2 -- Extra smooth
		fillBeam.Texture = ""
		fillBeam.LightEmission = 0.8 -- Slightly less bright
		fillBeam.LightInfluence = 0
		fillBeam.Transparency = NumberSequence.new(0.2) -- Slight transparency for blending
		fillBeam.ZOffset = 0.2 -- Render on top
		
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		fillBeam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		
		fillBeam.Parent = self.attachmentPart
		table.insert(fillBeams, fillBeam)
	end
	self.fillBeams = fillBeams
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
			self.boostParticles.Rate = 100 -- More particles
			self.headGlow.Brightness = GLOW_INTENSITY_MAX
			self.headGlow2.Brightness = GLOW_INTENSITY_MAX * 0.5
			self.head.Material = Enum.Material.Neon -- Switch to neon when boosting
		else
			self.boostParticles.Rate = 0
			self.headGlow.Brightness = GLOW_INTENSITY_MIN
			self.headGlow2.Brightness = GLOW_INTENSITY_MIN * 0.5
			self.head.Material = Enum.Material.ForceField -- Back to forcefield
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
	self.headGlow.Range = 15 + headSize * 3
	self.headGlow2.Range = 20 + headSize * 4
end

function Snake:updateBody()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end

	-- Update each segment with smooth interpolation
	local segmentSize = MIN_SEGMENT_SIZE + (MAX_SEGMENT_SIZE - MIN_SEGMENT_SIZE) * (self.growthFactor - 1) / 9
	local spacing = segmentSize * SEGMENT_SPACING

	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate position from history with interpolation
			local stepsBack = math.floor(i * spacing / 2)
			local histData = self:getHistoricalPosition(stepsBack)
			
			-- Get next historical position for interpolation
			local nextHistData = self:getHistoricalPosition(stepsBack + 1)

			if histData and nextHistData then
				-- Interpolate between positions for ultra smooth movement
				local alpha = (i * spacing / 2) % 1
				local targetPos = histData.position:Lerp(nextHistData.position, alpha)
				local currentPos = segment.Position
				segment.Position = currentPos:Lerp(targetPos, 0.4) -- Smoother lerp

				-- Update size with taper
				local taper = 1 - (i / self.visibleSegmentCount) * 0.3 -- 30% taper at tail
				segment.Size = Vector3.new(segmentSize * taper, segmentSize * taper, segmentSize * taper)

				-- Update attachment positions for beams
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end
				
				-- Pulse effect for living feel
				if self.isBoosting then
					local pulse = math.sin(tick() * 10 + i * 0.2) * 0.1 + 1
					segment.Size = segment.Size * pulse
				end
			end
		end
	end

	-- Update final attachment
	if self.attachments[self.visibleSegmentCount + 1] and self.segments[self.visibleSegmentCount] then
		self.attachments[self.visibleSegmentCount + 1].WorldPosition = self.segments[self.visibleSegmentCount].Position
	end

	-- Update head beam width and appearance
	if self.headBeam then
		local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
		self.headBeam.Width0 = width * 1.2 -- Wider at head
		self.headBeam.Width1 = width
		self.headBeam.LightEmission = 1 -- Always full emission
		self.headBeam.Transparency = NumberSequence.new(0) -- ALWAYS FULLY SOLID
	end

	-- Update all beams with enhanced visuals
	for i, beam in ipairs(self.beams) do
		if beam and beam.Parent then
			local isOverlap = i > self.visibleSegmentCount
			local baseIndex = isOverlap and (i - self.visibleSegmentCount) or i
			
			if baseIndex <= self.visibleSegmentCount then
				local progress = baseIndex / self.visibleSegmentCount
				local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
				width = width * (1 - progress * 0.3) * (isOverlap and BEAM_OVERLAP_FACTOR or 1)

				beam.Width0 = width
				beam.Width1 = width
				beam.LightEmission = 1 -- Maximum emission always

				-- Dynamic color shifting when boosting
				if self.isBoosting then
					local colorIndex = ((baseIndex - 1 + math.floor(tick() * 5)) % #self.config.BodyColors) + 1
					beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
				end

				-- Always solid, no transparency
				beam.Transparency = NumberSequence.new(0)
			else
				beam.Enabled = false
			end
		end
	end
	
	-- Update fill beams
	if self.fillBeams then
		for i, fillBeam in ipairs(self.fillBeams) do
			if fillBeam and fillBeam.Parent and i <= self.visibleSegmentCount - 3 then
				local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
				fillBeam.Width0 = width * 1.5
				fillBeam.Width1 = width * 1.5
				fillBeam.Enabled = true
			elseif fillBeam then
				fillBeam.Enabled = false
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
		segment.Material = Enum.Material.ForceField -- Consistent glow material
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0 -- SOLID NEW SEGMENTS
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		
		-- Add glow to new segments
		if i <= 100 or i % 5 == 0 then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Brightness = 1
			segmentGlow.Range = 10
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
		end
		
		segment.Parent = self.model

		self.segments[i] = segment

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beams if within limit
		if i <= 200 then
			-- Normal beam
			if self.attachments[i - 1] then
				local beam = Instance.new("Beam")
				beam.Name = "Beam" .. i
				beam.Attachment0 = self.attachments[i - 1]
				beam.Attachment1 = self.attachments[i]

				-- Enhanced beam properties
				beam.Width0 = BEAM_MIN_WIDTH
				beam.Width1 = BEAM_MIN_WIDTH
				beam.CurveSize0 = 0
				beam.CurveSize1 = 0
				beam.FaceCamera = true
				beam.Segments = BEAM_SEGMENTS
				beam.Texture = ""
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Transparency = NumberSequence.new(0)

				local colorIdx = ((i - 1) % #self.config.BodyColors) + 1
				beam.Color = ColorSequence.new(self.config.BodyColors[colorIdx])

				beam.Parent = self.attachmentPart
				self.beams[i] = beam
			end
			
			-- Overlap beam
			if i > 2 and self.attachments[i - 2] then
				local overlapIndex = i + self.visibleSegmentCount
				local overlapBeam = Instance.new("Beam")
				overlapBeam.Name = "Beam" .. overlapIndex
				overlapBeam.Attachment0 = self.attachments[i - 2]
				overlapBeam.Attachment1 = self.attachments[i]
				
				overlapBeam.Width0 = BEAM_MIN_WIDTH * 0.8
				overlapBeam.Width1 = BEAM_MIN_WIDTH * 0.8
				overlapBeam.CurveSize0 = 0
				overlapBeam.CurveSize1 = 0
				overlapBeam.FaceCamera = true
				overlapBeam.Segments = BEAM_SEGMENTS
				overlapBeam.Texture = ""
				overlapBeam.LightEmission = 1
				overlapBeam.LightInfluence = 0
				overlapBeam.Transparency = NumberSequence.new(0)
				overlapBeam.ZOffset = 0.1
				
				local colorIdx = ((i - 2) % #self.config.BodyColors) + 1
				overlapBeam.Color = ColorSequence.new(self.config.BodyColors[colorIdx])
				
				overlapBeam.Parent = self.attachmentPart
				self.beams[overlapIndex] = overlapBeam
			end
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
	
	-- Recreate fill beams for new segments
	if self.fillBeams then
		for _, beam in ipairs(self.fillBeams) do
			beam:Destroy()
		end
	end
	self:createFillBeams(self.visibleSegmentCount)
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
		-- Speed lines effect with glow
		for i = 1, 8 do -- More speed lines
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.5, 0.5, 15)
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.head.Color
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.head.CFrame * CFrame.new(
				math.random(-5, 5), 
				math.random(-5, 5), 
				5
			)
			speedLine.Parent = self.model

			-- Add glow to speed lines
			local speedGlow = Instance.new("PointLight")
			speedGlow.Brightness = 2
			speedGlow.Range = 10
			speedGlow.Color = speedLine.Color
			speedGlow.Parent = speedLine

			-- Fade out with scaling
			local tween = TweenService:Create(speedLine, 
				TweenInfo.new(0.4, Enum.EasingStyle.Linear), 
				{
					Transparency = 1, 
					Size = Vector3.new(0.1, 0.1, 30),
					CFrame = speedLine.CFrame * CFrame.new(0, 0, -20)
				}
			)
			tween:Play()
			Debris:AddItem(speedLine, 0.4)
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
	print("✅ Snake System V8 ENHANCED - ULTRA SOLID BEAM RENDERING")
	print("🐍 Features: Zero Gaps | Maximum Glow | Overlapping Beams | ForceField Material")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8