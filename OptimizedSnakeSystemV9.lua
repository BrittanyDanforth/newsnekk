-- Optimized Snake System V9 ULTIMATE - GAPLESS SMOOTH MOVEMENT
-- Zero gaps, perfect fluidity, dynamic segment chaining

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 75
local NETWORK_UPDATE_RATE = 25
local MAX_SEGMENTS = 500
local GROWTH_CHECK_INTERVAL = 10

-- Movement Constants - CRITICAL FOR GAPLESS MOVEMENT
local SEGMENT_DISTANCE = 2.8 -- Fixed distance between segments (slightly less than size for overlap)
local MOVEMENT_SMOOTHING = 0.25 -- How quickly segments follow (lower = smoother but more stretchy)
local POSITION_LERP_SPEED = 0.3 -- How fast segments catch up to their target
local MIN_MOVEMENT_THRESHOLD = 0.01 -- Minimum movement before updating
local CORNER_SMOOTHING_RADIUS = 5 -- Radius for corner smoothing
local MAX_SEGMENT_STRETCH = 1.2 -- Maximum stretch factor before forcing position update

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 3 -- Consistent glow throughout
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 25 -- High quality curves
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments
local VISUAL_SMOOTHING_FACTOR = 0.92 -- Higher = smoother transitions (increased for less gaps)

-- Growth Animation Constants
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions
local GROWTH_PULSE_STRENGTH = 0.1 -- How much segments pulse when growing
local GROWTH_WAVE_SPEED = 10 -- Speed of growth wave effect

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

-- Path Point for smooth movement tracking
local PathPoint = {}
PathPoint.__index = PathPoint

function PathPoint.new(position, direction, timestamp)
	return setmetatable({
		position = position,
		direction = direction,
		timestamp = timestamp or tick()
	}, PathPoint)
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

	-- Hide character model
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
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Core snake data
	self.length = config.InitialLength or 10
	self.actualLength = self.length
	self.targetLength = self.length
	self.isBoosting = false
	self.growthFactor = 1
	self.lastGrowthCheck = 0
	self.speed = 16 -- Base movement speed

	-- Growth animation state
	self.isGrowing = false
	self.growthStartTime = 0
	self.lastSegmentAddTime = 0
	self.pendingGrowth = 0
	self.growthWaveOffset = 0

	-- NEW: Path-based movement system
	self.pathPoints = {} -- Stores the actual path the head has traveled
	self.segmentPositions = {} -- Current positions of each segment
	self.segmentTargetPositions = {} -- Target positions for smooth movement
	self.lastHeadPosition = self.rootPart.Position
	self.totalPathDistance = 0

	-- Visual components
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace

	self.segments = {}
	self.beams = {}
	self.attachments = {}
	self.glows = {}
	self.visibleSegmentCount = 0

	-- Initialize path with starting position
	local startPos = self.rootPart.Position
	local startDir = self.rootPart.CFrame.LookVector
	
	-- Create initial path
	for i = 1, 100 do
		local point = PathPoint.new(
			startPos - startDir * (i * SEGMENT_DISTANCE / 10),
			startDir,
			tick()
		)
		table.insert(self.pathPoints, point)
	end

	-- Initialize snake
	self:createUnifiedBody()
	self:startUpdateLoop()

	print("✅ Snake created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	local length = self.actualLength

	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 0.5 -- Up to 1.5x
	elseif length <= 1000 then
		return 1.5 + (length - 200) / 800 * 1.0 -- Up to 2.5x
	elseif length <= 5000 then
		return 2.5 + (length - 1000) / 4000 * 0.5 -- Up to 3.0x
	else
		return 3.0 + math.min((length - 5000) / 10000 * 0.5, 0.5) -- Max 3.5x
	end
end

-- Smooth size transition function
function Snake:getSegmentSize(index, baseSize)
	local sizeMult = 1

	-- Add growth pulse effect when growing
	if self.isGrowing then
		local timeSinceGrowth = tick() - self.growthStartTime
		local growthWave = math.sin((timeSinceGrowth * GROWTH_WAVE_SPEED) - (index * 0.2)) * GROWTH_PULSE_STRENGTH
		sizeMult = 1 + math.max(0, growthWave * (1 - timeSinceGrowth))
	end

	if index == 0 then
		-- Head with subtle size increase
		return baseSize * HEAD_SIZE_MULTIPLIER * sizeMult
	elseif index <= HEAD_BLEND_SEGMENTS then
		-- Smooth transition from head to body
		local blendFactor = index / HEAD_BLEND_SEGMENTS
		local headSize = baseSize * HEAD_SIZE_MULTIPLIER
		local bodySize = baseSize * (1 - 0.05 * blendFactor) -- Subtle initial taper
		return (headSize + (bodySize - headSize) * (blendFactor ^ 0.5)) * sizeMult
	else
		-- Body with gradual taper
		local taperFactor = 1 - (index / self.visibleSegmentCount) * 0.2
		-- Apply exponential smoothing to taper
		taperFactor = 1 - (1 - taperFactor) ^ 1.5
		return baseSize * taperFactor * sizeMult
	end
end

-- Calculate beam width with proper transitions
function Snake:getBeamWidth(index, baseSize)
	local segmentSize1 = self:getSegmentSize(index, baseSize)
	local segmentSize2 = self:getSegmentSize(index + 1, baseSize)

	-- Average the two segment sizes for smooth transition
	local avgSize = (segmentSize1 + segmentSize2) / 2

	-- Apply beam-specific taper (less than segment taper for fuller appearance)
	local beamTaper = 1 - (index / self.visibleSegmentCount) * BEAM_TAPER_STRENGTH

	return avgSize * BEAM_WIDTH_BASE * beamTaper
end

function Snake:createUnifiedBody()
	-- Calculate initial segment count
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)

	-- Create attachment holder part
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Parent = self.model

	-- HEAD IS NOW SEGMENT 0 - Part of the unified body
	local head = Instance.new("Part")
	head.Name = "Segment0_Head"
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = self.config.HeadColor or self.config.BodyColors[1]
	head.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	head.Transparency = 0
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model

	-- Initialize head position
	self.segmentPositions[0] = self.rootPart.Position
	self.segmentTargetPositions[0] = self.rootPart.Position

	-- Head glow
	local headGlow = Instance.new("PointLight")
	headGlow.Name = "Glow"
	headGlow.Brightness = GLOW_INTENSITY
	headGlow.Range = GLOW_RANGE_BASE * 1.1
	headGlow.Color = head.Color
	headGlow.Shadows = false
	headGlow.Parent = head

	-- Boost particles on head
	local particle = Instance.new("ParticleEmitter")
	particle.Name = "BoostParticles"
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(head.Color)
	particle.Lifetime = NumberRange.new(0.5, 1)
	particle.Rate = 0
	particle.Speed = NumberRange.new(5, 10)
	particle.SpreadAngle = Vector2.new(180, 180)
	particle.VelocityInheritance = 0.5
	particle.Enabled = false
	particle.LightEmission = 1
	particle.LightInfluence = 0
	particle.Parent = head

	-- Eyes for character
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.5, 0.5, 0.5)
		eye.Transparency = 0
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye(-0.6)
	self.rightEye, self.rightPupil = createEye(0.6)

	-- Collision tagging for head
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Store head as segment 0
	self.segments[0] = head
	self.head = head
	self.headGlow = headGlow
	self.boostParticles = particle
	self.glows[0] = headGlow

	-- Create head attachment
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "Attachment0"
	headAttachment.Parent = attachmentPart
	self.attachments[0] = headAttachment

	-- Create body segments starting from 1
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		-- Use new size calculation
		local segmentSize = self:getSegmentSize(i, BASE_SIZE)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		-- Initialize segment position based on spacing
		local initialPos = self.rootPart.Position - self.rootPart.CFrame.LookVector * (i * SEGMENT_DISTANCE)
		self.segmentPositions[i] = initialPos
		self.segmentTargetPositions[i] = initialPos
		segment.Position = initialPos

		-- Color handling
		local colorIndex
		if i <= HEAD_BLEND_SEGMENTS then
			local blendFactor = (i / HEAD_BLEND_SEGMENTS) ^ 0.7
			local headColor = self.config.HeadColor or self.config.BodyColors[1]
			local bodyColor = self.config.BodyColors[1]
			segment.Color = headColor:Lerp(bodyColor, blendFactor)
		else
			colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
		end

		-- Strategic glow placement
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = true
		elseif i <= 100 then
			shouldHaveGlow = i % 2 == 0
		elseif i <= 200 then
			shouldHaveGlow = i % 3 == 0
		else
			shouldHaveGlow = i % 5 == 0
		end

		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / segmentCount) * 0.1)
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end

		segment.Parent = self.model
		self.segments[i] = segment

		-- Collision tagging
		if i <= 50 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.attachments[i] = attachment
	end

	-- Create seamless beams between all segments
	for i = 0, segmentCount - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

		-- Beam properties
		local beamWidth = self:getBeamWidth(i, BASE_SIZE)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 2
		beam.TextureSpeed = 0
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0)

		-- Color matching
		if i == 0 then
			local headColor = self.segments[0].Color
			local seg1Color = self.segments[1].Color
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, headColor),
				ColorSequenceKeypoint.new(0.3, headColor:Lerp(seg1Color, 0.3)),
				ColorSequenceKeypoint.new(0.7, headColor:Lerp(seg1Color, 0.7)),
				ColorSequenceKeypoint.new(1, seg1Color)
			})
		elseif i < HEAD_BLEND_SEGMENTS then
			beam.Color = ColorSequence.new(self.segments[i].Color)
		else
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		end

		beam.Parent = attachmentPart
		self.beams[i] = beam
	end

	-- Create strategic overlap beams for gap prevention
	for i = 0, math.min(segmentCount - 2, 20) do
		if i % 2 == 0 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = self.attachments[i]
			overlapBeam.Attachment1 = self.attachments[i + 2]

			local overlapWidth = self:getBeamWidth(i, BASE_SIZE) * 1.1
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			overlapBeam.TextureMode = Enum.TextureMode.Stretch
			overlapBeam.TextureLength = 3
			overlapBeam.LightEmission = 0.8
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.3)
			overlapBeam.ZOffset = -0.1

			local color = i == 0 and self.segments[0].Color or self.segments[i].Color
			overlapBeam.Color = ColorSequence.new(color)

			overlapBeam.Parent = attachmentPart
			self.beams["overlap" .. i] = overlapBeam
		end
	end

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

-- NEW: Update path points as the snake moves
function Snake:updatePath()
	local currentHeadPos = self.rootPart.Position
	local movement = (currentHeadPos - self.lastHeadPosition).Magnitude
	
	-- Only update if we've moved enough
	if movement > MIN_MOVEMENT_THRESHOLD then
		-- Add new path point
		local newPoint = PathPoint.new(
			currentHeadPos,
			self.rootPart.CFrame.LookVector,
			tick()
		)
		table.insert(self.pathPoints, 1, newPoint)
		
		-- Update total path distance
		self.totalPathDistance = self.totalPathDistance + movement
		
		-- Clean up old path points we don't need
		local maxPoints = self.visibleSegmentCount * 10 -- Keep extra for smooth movement
		while #self.pathPoints > maxPoints do
			table.remove(self.pathPoints)
		end
		
		self.lastHeadPosition = currentHeadPos
	end
end

-- NEW: Get position along the path for a specific segment
function Snake:getPositionAlongPath(distance)
	if #self.pathPoints < 2 then
		return self.rootPart.Position, self.rootPart.CFrame.LookVector
	end
	
	local accumulatedDistance = 0
	
	for i = 1, #self.pathPoints - 1 do
		local point1 = self.pathPoints[i]
		local point2 = self.pathPoints[i + 1]
		local segmentLength = (point1.position - point2.position).Magnitude
		
		if accumulatedDistance + segmentLength >= distance then
			-- Interpolate within this segment
			local remainingDistance = distance - accumulatedDistance
			local t = remainingDistance / segmentLength
			
			local position = point1.position:Lerp(point2.position, t)
			local direction = point1.direction:Lerp(point2.direction, t).Unit
			
			return position, direction
		end
		
		accumulatedDistance = accumulatedDistance + segmentLength
	end
	
	-- If we've gone beyond the path, return the last point
	local lastPoint = self.pathPoints[#self.pathPoints]
	return lastPoint.position, lastPoint.direction
end

function Snake:startUpdateLoop()
	local frameCount = 0
	local lastNetworkUpdate = 0

	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.character.Parent or not self.rootPart.Parent then
			self:destroy()
			return
		end

		frameCount = frameCount + 1

		-- Update path with head movement
		self:updatePath()

		-- Smooth length interpolation
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			local growthRate = GROWTH_SPEED

			if diff > 0.1 and not self.isGrowing then
				self.isGrowing = true
				self.growthStartTime = tick()
			end

			self.actualLength = self.actualLength + diff * growthRate

			if math.abs(diff) < 0.1 then
				self.actualLength = self.targetLength
				self.isGrowing = false
			end
		else
			self.isGrowing = false
		end

		-- Update growth factor
		if frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end

		-- Update speed based on boost
		self.speed = self.isBoosting and 24 or 16

		-- Update visuals with new movement system
		self:updateUnifiedBody()

		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 150
			for _, glow in pairs(self.glows) do
				if glow and glow.Parent then
					glow.Brightness = GLOW_INTENSITY * 1.5
				end
			end
		else
			self.boostParticles.Rate = 0
			for _, glow in pairs(self.glows) do
				if glow and glow.Parent then
					glow.Brightness = GLOW_INTENSITY
				end
			end
		end

		-- Network updates
		local now = tick()
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > 1/NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateUnifiedBody()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		local now = tick()
		if now - self.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			self:addSegments(1)
			self.lastSegmentAddTime = now
		end
	end

	-- Calculate sizes based on growth
	local currentBaseSize = BASE_SIZE * self.growthFactor
	
	-- Dynamic segment spacing based on speed and size
	local dynamicSpacing = SEGMENT_DISTANCE * (currentBaseSize / BASE_SIZE) * 0.9

	-- Update head (segment 0)
	local headCF = CFrame.lookAt(
		self.rootPart.Position,
		self.rootPart.Position + self.rootPart.CFrame.LookVector
	)
	
	self.segments[0].CFrame = headCF
	self.segmentPositions[0] = self.rootPart.Position
	
	-- Update head size
	local headSize = self:getSegmentSize(0, currentBaseSize)
	self.segments[0].Size = Vector3.new(headSize, headSize, headSize)
	
	-- Update eyes
	local eyeScale = headSize / BASE_SIZE * 0.5
	local eyeOffset = headSize * 0.3
	local eyeForward = -headSize * 0.35

	self.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	self.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

	self.leftEye.CFrame = headCF * CFrame.new(-eyeOffset, eyeOffset * 0.5, eyeForward)
	self.rightEye.CFrame = headCF * CFrame.new(eyeOffset, eyeOffset * 0.5, eyeForward)
	self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)

	-- Update body segments using chain following
	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Get the position of the previous segment
			local prevPos = self.segmentPositions[i - 1]
			local targetDistance = dynamicSpacing
			
			-- Calculate target position based on path
			local pathPosition, pathDirection = self:getPositionAlongPath(i * dynamicSpacing)
			
			-- For close segments, use direct following for tighter control
			if i <= 10 then
				-- Direct following of previous segment
				local toPrev = (prevPos - self.segmentPositions[i]).Unit
				self.segmentTargetPositions[i] = prevPos - toPrev * targetDistance
			else
				-- Blend between path following and chain following
				local chainPos = prevPos - (prevPos - self.segmentPositions[i]).Unit * targetDistance
				local blendFactor = math.min(i / 30, 1) -- Gradually transition to path following
				self.segmentTargetPositions[i] = chainPos:Lerp(pathPosition, blendFactor * 0.5)
			end
			
			-- Smooth movement to target position
			local currentPos = self.segmentPositions[i]
			local targetPos = self.segmentTargetPositions[i]
			
			-- Check if segment is stretching too much
			local stretchDistance = (prevPos - currentPos).Magnitude
			if stretchDistance > targetDistance * MAX_SEGMENT_STRETCH then
				-- Force position to maintain connection
				currentPos = prevPos - (prevPos - currentPos).Unit * targetDistance
			end
			
			-- Apply smoothing based on segment index (front segments follow more tightly)
			local smoothingFactor = POSITION_LERP_SPEED * (1 - i / self.visibleSegmentCount * 0.3)
			self.segmentPositions[i] = currentPos:Lerp(targetPos, smoothingFactor)
			
			-- Update segment position
			segment.Position = self.segmentPositions[i]
			
			-- Update segment size
			local segmentSize = self:getSegmentSize(i, currentBaseSize)
			segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)
			
			-- Pulse effect during boost
			if self.isBoosting then
				local pulse = math.sin(tick() * 10 + i * 0.1) * 0.02 + 1
				segment.Size = segment.Size * pulse
			end
		end
	end

	-- Update all attachments
	for i = 0, self.visibleSegmentCount do
		if self.attachments[i] and self.segments[i] then
			self.attachments[i].WorldPosition = self.segments[i].Position
		end
	end

	-- Update beams with dynamic sizing
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				if i <= self.visibleSegmentCount then
					-- Calculate beam curve for smoother appearance
					local pos1 = self.segmentPositions[i] or self.segments[i].Position
					local pos2 = self.segmentPositions[i + 1] or self.segments[i + 1].Position
					local distance = (pos1 - pos2).Magnitude
					
					-- Add slight curve to beams when turning
					local curveMagnitude = math.min(distance * 0.1, 2)
					beam.CurveSize0 = -curveMagnitude
					beam.CurveSize1 = curveMagnitude
					
					local beamWidth = self:getBeamWidth(i, currentBaseSize)
					beam.Width0 = beamWidth
					beam.Width1 = beamWidth
					beam.Enabled = true

					-- Dynamic color during boost
					if self.isBoosting and i > HEAD_BLEND_SEGMENTS then
						local colorShift = math.floor(tick() * 3) % #self.config.BodyColors
						local colorIndex = ((i - 1 + colorShift) % #self.config.BodyColors) + 1
						beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlap") then
				-- Overlap beams for gap prevention
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 2 then
					local overlapWidth = self:getBeamWidth(index, currentBaseSize) * 1.1
					beam.Width0 = overlapWidth
					beam.Width1 = overlapWidth
					beam.Enabled = true
					
					-- Adjust transparency based on segment stretch
					local pos1 = self.segmentPositions[index] or self.segments[index].Position
					local pos2 = self.segmentPositions[index + 2] or self.segments[index + 2].Position
					local stretchFactor = (pos1 - pos2).Magnitude / (dynamicSpacing * 2)
					local transparency = math.max(0.3, 1 - stretchFactor)
					beam.Transparency = NumberSequence.new(transparency)
				else
					beam.Enabled = false
				end
			end
		end
	end

	-- Update glow ranges
	for i, glow in pairs(self.glows) do
		if glow and glow.Parent then
			local glowScale = 1 - (i / self.visibleSegmentCount) * 0.3
			glow.Range = (GLOW_RANGE_BASE + (currentBaseSize - BASE_SIZE) * 2) * glowScale
		end
	end
end

function Snake:addSegments(count)
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		local targetSize = self:getSegmentSize(i, BASE_SIZE * self.growthFactor)
		segment.Size = Vector3.new(targetSize * 0.1, targetSize * 0.1, targetSize * 0.1)

		segment.Transparency = 0.8
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Initialize position at previous segment
		local prevPos = self.segmentPositions[i - 1] or self.segments[i - 1].Position
		segment.Position = prevPos
		self.segmentPositions[i] = prevPos
		self.segmentTargetPositions[i] = prevPos

		-- Add glow if needed
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = true
		elseif i <= 100 then
			shouldHaveGlow = i % 2 == 0
		elseif i <= 200 then
			shouldHaveGlow = i % 3 == 0
		else
			shouldHaveGlow = i % 5 == 0
		end

		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / MAX_SEGMENTS) * 0.2)
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end

		segment.Parent = self.model
		self.segments[i] = segment

		-- Animate growth
		TweenService:Create(segment, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(targetSize, targetSize, targetSize),
			Transparency = 0
		}):Play()

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beam from previous segment
		if self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. (i - 1)
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]

			local beamWidth = self:getBeamWidth(i - 1, BASE_SIZE * self.growthFactor)
			beam.Width0 = beamWidth * 0.1
			beam.Width1 = beamWidth * 0.1
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureLength = 2
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(0.8)

			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])

			beam.Parent = self.attachmentPart
			self.beams[i - 1] = beam

			-- Animate beam growth
			TweenService:Create(beam, TweenInfo.new(0.3), {
				Width0 = beamWidth,
				Width1 = beamWidth
			}):Play()

			-- Animate transparency
			local startTime = tick()
			local transparencyConnection
			transparencyConnection = RunService.Heartbeat:Connect(function()
				local elapsed = tick() - startTime
				local progress = math.min(elapsed / 0.3, 1)
				local transparency = 0.8 * (1 - progress)
				beam.Transparency = NumberSequence.new(transparency)
				if progress >= 1 then
					transparencyConnection:Disconnect()
				end
			end)
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

function Snake:grow(amount)
	self.pendingGrowth = self.pendingGrowth + (amount or 1)
	self.targetLength = math.min(self.targetLength + (amount or 1), 50000)

	-- Visual feedback
	if self.head and self.headGlow then
		local originalBrightness = self.headGlow.Brightness
		self.headGlow.Brightness = GLOW_INTENSITY * 2
		TweenService:Create(self.headGlow, TweenInfo.new(0.2), {
			Brightness = originalBrightness
		}):Play()
	end

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

	if boosting then
		self.boostParticles.Enabled = true

		-- Create speed effect
		for i = 1, 5 do
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.3, 0.3, 10)
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.head.Color
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.head.CFrame * CFrame.new(
				math.random(-3, 3),
				math.random(-3, 3),
				5
			)
			speedLine.Parent = self.model

			local tween = TweenService:Create(speedLine,
				TweenInfo.new(0.3, Enum.EasingStyle.Linear),
				{
					Transparency = 1,
					Size = Vector3.new(0.1, 0.1, 20),
					CFrame = speedLine.CFrame * CFrame.new(0, 0, -15)
				}
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
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	createNetworkEvents()
	print("✅ Snake System V9 ULTIMATE - GAPLESS SMOOTH MOVEMENT")
	print("🐍 Features: Zero Gaps | Chain Physics | Dynamic Spacing | Path Tracking")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9