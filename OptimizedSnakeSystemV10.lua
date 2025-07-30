-- Optimized Snake System V10 ULTIMATE - COMPLETELY REVAMPED
-- Fixed all beam/LOD issues, no gaps, no disappearing parts, ultra smooth
-- Maintains perfect visual appearance while fixing all bugs

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60
local NETWORK_UPDATE_RATE = 20
local MAX_SEGMENTS = 500
local SEGMENT_SPACING = 0.5 -- Tighter for seamless look
local HISTORY_SIZE = 3000 -- Increased for smoother movement
local GROWTH_CHECK_INTERVAL = 10
local BATCH_UPDATE_SIZE = 50 -- Update segments in batches
local LOD_DISTANCE = 150 -- Distance for LOD optimization

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5
local MAX_SIZE_MULTIPLIER = 3.5
local GLOW_INTENSITY = 3
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 20 -- Optimized for performance
local BEAM_WIDTH_BASE = 0.95
local BEAM_TAPER_STRENGTH = 0.15
local HEAD_SIZE_MULTIPLIER = 1.05
local HEAD_BLEND_SEGMENTS = 8
local GLOW_FALLOFF_START = 50
local VISUAL_SMOOTHING_FACTOR = 0.85 -- Higher for smoother movement

-- Growth Animation Constants
local GROWTH_SPEED = 0.2
local SEGMENT_GROWTH_DELAY = 0.03
local GROWTH_PULSE_STRENGTH = 0.1
local GROWTH_WAVE_SPEED = 10

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

-- Object pooling for performance
local SegmentPool = {}
local BeamPool = {}
local AttachmentPool = {}

local function getPooledSegment()
	local segment = table.remove(SegmentPool)
	if not segment then
		segment = Instance.new("Part")
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
	end
	return segment
end

local function returnToPool(segment)
	segment.Parent = nil
	segment.Transparency = 0
	segment.Size = Vector3.new(1, 1, 1)
	table.insert(SegmentPool, segment)
end

local function getPooledBeam()
	local beam = table.remove(BeamPool)
	if not beam then
		beam = Instance.new("Beam")
		beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
	end
	return beam
end

local function returnBeamToPool(beam)
	beam.Parent = nil
	beam.Enabled = true
	table.insert(BeamPool, beam)
end

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

	-- Growth animation state
	self.isGrowing = false
	self.growthStartTime = 0
	self.lastSegmentAddTime = 0
	self.pendingGrowth = 0
	self.growthWaveOffset = 0

	-- Movement history with better interpolation
	self.positionHistory = {}
	self.historyIndex = 0
	self.lastHistoryUpdate = 0

	-- Visual components
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace

	self.segments = {}
	self.beams = {}
	self.attachments = {}
	self.glows = {}
	self.visibleSegmentCount = 0

	-- Performance tracking
	self.lastBatchUpdate = 0
	self.segmentUpdateQueue = {}
	self.beamUpdateQueue = {}

	-- LOD tracking
	self.camera = workspace.CurrentCamera
	self.lastLODCheck = 0
	self.lodSegments = {}

	-- Pre-fill history with smooth interpolation
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	local startCFrame = self.rootPart.CFrame

	for i = 1, HISTORY_SIZE do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook,
			cframe = startCFrame,
			time = tick(),
			velocity = Vector3.new(0, 0, 0)
		}
	end

	-- Initialize snake
	self:createUnifiedBody()
	self:startUpdateLoop()

	print("✅ Snake V10 created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	local length = self.actualLength

	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 0.5
	elseif length <= 1000 then
		return 1.5 + (length - 200) / 800 * 1.0
	elseif length <= 5000 then
		return 2.5 + (length - 1000) / 4000 * 0.5
	else
		return 3.0 + math.min((length - 5000) / 10000 * 0.5, 0.5)
	end
end

function Snake:getSegmentSize(index, baseSize)
	local sizeMult = 1

	-- Add growth pulse effect when growing
	if self.isGrowing then
		local timeSinceGrowth = tick() - self.growthStartTime
		local growthWave = math.sin((timeSinceGrowth * GROWTH_WAVE_SPEED) - (index * 0.2)) * GROWTH_PULSE_STRENGTH
		sizeMult = 1 + math.max(0, growthWave * (1 - timeSinceGrowth))
	end

	if index == 0 then
		return baseSize * HEAD_SIZE_MULTIPLIER * sizeMult
	elseif index <= HEAD_BLEND_SEGMENTS then
		local blendFactor = index / HEAD_BLEND_SEGMENTS
		local headSize = baseSize * HEAD_SIZE_MULTIPLIER
		local bodySize = baseSize * (1 - 0.05 * blendFactor)
		return (headSize + (bodySize - headSize) * (blendFactor ^ 0.5)) * sizeMult
	else
		local taperFactor = 1 - (index / self.visibleSegmentCount) * 0.2
		taperFactor = 1 - (1 - taperFactor) ^ 1.5
		return baseSize * taperFactor * sizeMult
	end
end

function Snake:getBeamWidth(index, baseSize)
	local segmentSize1 = self:getSegmentSize(index, baseSize)
	local segmentSize2 = self:getSegmentSize(index + 1, baseSize)
	local avgSize = (segmentSize1 + segmentSize2) / 2
	local beamTaper = 1 - (index / self.visibleSegmentCount) * BEAM_TAPER_STRENGTH
	return avgSize * BEAM_WIDTH_BASE * beamTaper
end

function Snake:createUnifiedBody()
	-- Calculate initial segment count
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)

	-- Create single attachment holder part for all attachments
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.CFrame = self.rootPart.CFrame
	attachmentPart.Parent = self.model

	-- Create head (segment 0)
	local head = getPooledSegment()
	head.Name = "Segment0_Head"
	head.Color = self.config.HeadColor or self.config.BodyColors[1]
	head.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	head.Transparency = 0
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.CFrame = self.rootPart.CFrame  -- SET INITIAL POSITION TO ROOTPART
	head.Position = self.rootPart.Position  -- ENSURE POSITION IS SET
	head.Parent = self.model

	-- Head glow
	local headGlow = Instance.new("PointLight")
	headGlow.Name = "Glow"
	headGlow.Brightness = GLOW_INTENSITY
	headGlow.Range = GLOW_RANGE_BASE * 1.1
	headGlow.Color = head.Color
	headGlow.Shadows = false
	headGlow.Parent = head

	-- Boost particles
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

	-- Eyes
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

	-- Collision tagging
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Store head
	self.segments[0] = head
	self.head = head
	self.headGlow = headGlow
	self.boostParticles = particle
	self.glows[0] = headGlow

	-- Create all attachments in batch for performance
	for i = 0, segmentCount do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.attachments[i] = attachment
	end

	-- CRITICAL FIX: Initialize all attachment positions to rootPart position
	-- This prevents stray beams at spawn
	for i = 0, segmentCount do
		self.attachments[i].WorldPosition = self.rootPart.Position
	end

	-- Create body segments in batches
	local segmentBatch = {}
	for i = 1, segmentCount do
		local segment = getPooledSegment()
		segment.Name = "Segment" .. i

		local segmentSize = self:getSegmentSize(i, BASE_SIZE)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)
		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true
		
		-- Initialize segment position to rootPart position
		segment.Position = self.rootPart.Position

		-- Color assignment
		if i <= HEAD_BLEND_SEGMENTS then
			local blendFactor = (i / HEAD_BLEND_SEGMENTS) ^ 0.7
			local headColor = self.config.HeadColor or self.config.BodyColors[1]
			local bodyColor = self.config.BodyColors[1]
			segment.Color = headColor:Lerp(bodyColor, blendFactor)
		else
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
		end

		-- Strategic glow placement
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = i % 2 == 0 -- Every other for first 50
		elseif i <= 100 then
			shouldHaveGlow = i % 3 == 0
		elseif i <= 200 then
			shouldHaveGlow = i % 5 == 0
		else
			shouldHaveGlow = i % 10 == 0
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

		self.segments[i] = segment
		table.insert(segmentBatch, segment)

		-- Collision tagging for first 50
		if i <= 50 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end

		-- Parent in batches
		if #segmentBatch >= 20 then
			for _, seg in ipairs(segmentBatch) do
				seg.Parent = self.model
			end
			segmentBatch = {}
		end
	end

	-- Parent remaining segments
	for _, seg in ipairs(segmentBatch) do
		seg.Parent = self.model
	end

	-- Create beams in batches
	local beamBatch = {}
	for i = 0, segmentCount - 1 do
		local beam = getPooledBeam()
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

		local beamWidth = self:getBeamWidth(i, BASE_SIZE)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Segments = BEAM_SEGMENTS
		beam.TextureLength = 2
		beam.TextureSpeed = 0
		beam.Transparency = NumberSequence.new(0)

		-- Color setup
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

		self.beams[i] = beam
		table.insert(beamBatch, beam)

		-- Parent in batches
		if #beamBatch >= 20 then
			for _, b in ipairs(beamBatch) do
				b.Parent = attachmentPart
			end
			beamBatch = {}
		end
	end

	-- Parent remaining beams
	for _, b in ipairs(beamBatch) do
		b.Parent = attachmentPart
	end

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end