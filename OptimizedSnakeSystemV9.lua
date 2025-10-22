-- Optimized Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING (FIXED GROWTH + LOD)
-- Perfect head-body integration with smooth growth transitions and LOD system

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
local HISTORY_SIZE = 2000
local GROWTH_CHECK_INTERVAL = 10

-- LOD Constants (NEW)
local LOD_UPDATE_INTERVAL = 10 -- Update LOD every 10 frames
local LOD_VISIBLE_SEGMENTS = 100 -- Maximum visible segments at any time
local LOD_FADE_START = 60 -- Start fading at this segment
local LOD_FADE_END = 100 -- Fully transparent at this segment
local LOD_BEAM_QUALITY_DROPOFF = 50 -- Reduce beam quality after this segment
local LOD_GLOW_CUTOFF = 40 -- No glows after this segment
local LOD_DISTANCE_MULTIPLIER = 1.5 -- Distance multiplier for LOD calculations

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 3 -- Consistent glow throughout
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 25 -- High quality curves
local BEAM_SEGMENTS_LOW = 10 -- Low quality for distant segments
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper (reduced from part taper)
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments
local VISUAL_SMOOTHING_FACTOR = 0.6 -- Higher = smoother transitions

-- Growth Animation Constants
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length (increased for smoother growth)
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions for smooth appearance
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

	-- LOD state (NEW)
	self.lodFrameCount = 0
	self.isLocalPlayer = (self.player == Players.LocalPlayer)
	self.camera = workspace.CurrentCamera
	self.visibleRange = {start = 0, finish = LOD_VISIBLE_SEGMENTS}
	self.lastLODUpdate = 0

	-- Growth animation state
	self.isGrowing = false
	self.growthStartTime = 0
	self.lastSegmentAddTime = 0
	self.pendingGrowth = 0
	self.growthWaveOffset = 0

	-- Movement history
	self.positionHistory = {}
	self.historyIndex = 0

	-- Visual components
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace

	self.segments = {}
	self.beams = {}
	self.attachments = {}
	self.glows = {}
	self.visibleSegmentCount = 0

	-- Pre-fill history
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i = 1, HISTORY_SIZE do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook,
			time = tick()
		}
	end

	-- Initialize snake
	self:createUnifiedBody()
	self:startUpdateLoop()

	print("✅ Snake created for", self.player.Name, "with LOD system")
	return self
end

-- LOD visibility calculation (NEW)
function Snake:calculateLODVisibility(segmentIndex, segmentPosition)
	-- Always show head and early segments
	if segmentIndex <= 10 then
		return 1.0, true -- Full visibility, high quality
	end
	
	-- For local player, use distance-based LOD
	if self.isLocalPlayer then
		local cameraPos = self.camera.CFrame.Position
		local distance = (segmentPosition - cameraPos).Magnitude
		
		-- Calculate visibility based on distance and segment index
		local baseVisibility = math.max(0, 1 - (segmentIndex - LOD_FADE_START) / (LOD_FADE_END - LOD_FADE_START))
		local distanceFactor = math.max(0, 1 - (distance / (100 * LOD_DISTANCE_MULTIPLIER)))
		
		local visibility = baseVisibility * distanceFactor
		local highQuality = segmentIndex < LOD_BEAM_QUALITY_DROPOFF and distance < 150
		
		return visibility, highQuality
	else
		-- For other players, use more aggressive LOD
		local cameraPos = self.camera.CFrame.Position
		local distance = (segmentPosition - cameraPos).Magnitude
		
		-- Hide distant snake segments of other players more aggressively
		if distance > 200 then
			return 0, false
		end
		
		local visibility = math.max(0, 1 - (distance / 200))
		local highQuality = distance < 100 and segmentIndex < 30
		
		return visibility, highQuality
	end
end

-- Update visible range based on camera position (NEW)
function Snake:updateVisibleRange()
	if not self.isLocalPlayer then
		-- For other players, always limit visible segments
		self.visibleRange = {start = 0, finish = math.min(50, self.visibleSegmentCount)}
		return
	end
	
	-- For local player, show more segments but still apply LOD
	local maxVisible = math.min(LOD_VISIBLE_SEGMENTS, self.visibleSegmentCount)
	self.visibleRange = {start = 0, finish = maxVisible}
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
	head.Material = Enum.Material.Neon -- Neon for consistent look
	head.Color = self.config.HeadColor or self.config.BodyColors[1]
	head.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	head.Transparency = 0
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model

	-- Head glow - matches body glow intensity
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

	-- Eyes for character (smaller, integrated)
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
		segment.Material = Enum.Material.Neon -- Consistent material

		-- Use new size calculation
		local segmentSize = self:getSegmentSize(i, BASE_SIZE)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Collision for first 50
		segment.CanQuery = false
		segment.Anchored = true

		-- Smooth color transition from head to body
		local colorIndex
		if i <= HEAD_BLEND_SEGMENTS then
			-- Blend head color into body colors
			local blendFactor = (i / HEAD_BLEND_SEGMENTS) ^ 0.7 -- Non-linear blend
			local headColor = self.config.HeadColor or self.config.BodyColors[1]
			local bodyColor = self.config.BodyColors[1]
			segment.Color = headColor:Lerp(bodyColor, blendFactor)
		else
			-- Regular body pattern
			colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
		end

		-- Strategic glow placement for performance with LOD in mind
		local shouldHaveGlow = false
		if i <= LOD_GLOW_CUTOFF then -- LOD cutoff for glows
			if i <= 20 then
				shouldHaveGlow = true -- All early segments
			elseif i <= 40 then
				shouldHaveGlow = i % 2 == 0 -- Every other segment
			end
		end

		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9 -- Slightly dimmer than head
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / segmentCount) * 0.1) -- Gradual range decrease
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

		-- Beam properties with calculated width
		local beamWidth = self:getBeamWidth(i, BASE_SIZE)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png" -- Smooth gradient texture
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 2
		beam.TextureSpeed = 0
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0)

		-- Color matching with smooth transitions
		if i == 0 then
			-- Head to first segment - smooth color transition
			local headColor = self.segments[0].Color
			local seg1Color = self.segments[1].Color
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, headColor),
				ColorSequenceKeypoint.new(0.3, headColor:Lerp(seg1Color, 0.3)),
				ColorSequenceKeypoint.new(0.7, headColor:Lerp(seg1Color, 0.7)),
				ColorSequenceKeypoint.new(1, seg1Color)
			})
		elseif i < HEAD_BLEND_SEGMENTS then
			-- Blending region - use segment colors
			beam.Color = ColorSequence.new(self.segments[i].Color)
		else
			-- Regular body colors
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		end

		beam.Parent = attachmentPart
		self.beams[i] = beam
	end

	-- Create selective overlap beams for critical areas only
	-- Focus on head blend area and early segments
	for i = 0, math.min(segmentCount - 2, HEAD_BLEND_SEGMENTS * 2) do
		if i % 2 == 0 then -- Every other segment
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = self.attachments[i]
			overlapBeam.Attachment1 = self.attachments[i + 2]

			-- Calculate overlap beam width
			local overlapWidth = self:getBeamWidth(i, BASE_SIZE) * 1.15 -- Only 15% wider
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			overlapBeam.TextureMode = Enum.TextureMode.Stretch
			overlapBeam.TextureLength = 3
			overlapBeam.LightEmission = 0.7
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.5) -- More transparent
			overlapBeam.ZOffset = -0.1 -- Behind main beams

			-- Color
			local color = i == 0 and self.segments[0].Color or self.segments[i].Color
			overlapBeam.Color = ColorSequence.new(color)

			overlapBeam.Parent = attachmentPart
			self.beams["overlap" .. i] = overlapBeam
		end
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
		if not self.character.Parent or not self.rootPart.Parent then
			self:destroy()
			return
		end

		frameCount = frameCount + 1
		self.lodFrameCount = self.lodFrameCount + 1

		-- Update position history
		self:updatePositionHistory()

		-- Smooth length interpolation with growth animation tracking
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			local growthRate = GROWTH_SPEED

			-- Start growth animation if we're growing
			if diff > 0.1 and not self.isGrowing then
				self.isGrowing = true
				self.growthStartTime = tick()
			end

			-- Use smoother interpolation for growth
			self.actualLength = self.actualLength + diff * growthRate

			-- Stop growth animation when we reach target
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

		-- Update LOD visible range
		if self.lodFrameCount % LOD_UPDATE_INTERVAL == 0 then
			self:updateVisibleRange()
		end

		-- Update visuals with LOD
		self:updateUnifiedBody()

		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 150
			-- Enhance visible glows during boost
			for i, glow in pairs(self.glows) do
				if glow and glow.Parent and i <= self.visibleRange.finish then
					glow.Brightness = GLOW_INTENSITY * 1.5
				end
			end
		else
			self.boostParticles.Rate = 0
			-- Normal glow
			for i, glow in pairs(self.glows) do
				if glow and glow.Parent and i <= self.visibleRange.finish then
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

	-- Add new segments if grown with smooth animation
	if requiredSegments > self.visibleSegmentCount then
		local now = tick()
		if now - self.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			self:addSegments(1) -- Add one at a time for smooth growth
			self.lastSegmentAddTime = now
		end
	end

	-- Calculate sizes based on growth
	local currentBaseSize = BASE_SIZE * self.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING

	-- Update all segments including head (segment 0) with LOD
	for i = 0, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			if i == 0 then
				-- Head positioning (always visible)
				local cf = CFrame.lookAt(
					self.rootPart.Position,
					self.rootPart.Position + self.rootPart.CFrame.LookVector
				)
				segment.CFrame = cf
				segment.Transparency = 0

				-- Use calculated head size
				local headSize = self:getSegmentSize(0, currentBaseSize)
				segment.Size = Vector3.new(headSize, headSize, headSize)

				-- Update eyes with proper scaling
				local eyeScale = headSize / BASE_SIZE * 0.5
				local eyeOffset = headSize * 0.3
				local eyeForward = -headSize * 0.35

				self.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				self.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				self.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
				self.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

				self.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.5, eyeForward)
				self.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.5, eyeForward)
				self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
				self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
			else
				-- Body segment positioning with LOD
				local stepsBack = math.floor(i * spacing / 2)
				local histData = self:getHistoricalPosition(stepsBack)
				local nextHistData = self:getHistoricalPosition(stepsBack + 1)

				if histData and nextHistData then
					-- Smooth interpolation
					local alpha = (i * spacing / 2) % 1
					local targetPos = histData.position:Lerp(nextHistData.position, alpha)
					local currentPos = segment.Position

					-- Use higher smoothing during growth for smoother transitions
					local smoothingFactor = self.isGrowing and VISUAL_SMOOTHING_FACTOR * 1.2 or VISUAL_SMOOTHING_FACTOR
					segment.Position = currentPos:Lerp(targetPos, smoothingFactor)

					-- Calculate LOD visibility
					local visibility, highQuality = self:calculateLODVisibility(i, segment.Position)
					
					-- Apply LOD transparency
					if i <= self.visibleRange.finish then
						segment.Transparency = math.max(0, 1 - visibility)
						
						-- Hide segments that are too far or transparent
						if visibility < 0.1 then
							segment.Transparency = 1
						end
					else
						segment.Transparency = 1
					end

					-- Use calculated segment size
					local segmentSize = self:getSegmentSize(i, currentBaseSize)
					segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

					-- Pulse effect during boost (only for visible segments)
					if self.isBoosting and visibility > 0.5 then
						local pulse = math.sin(tick() * 10 + i * 0.1) * 0.03 + 1 -- Reduced pulse
						segment.Size = segment.Size * pulse
					end

					-- Update glow visibility based on LOD
					if self.glows[i] then
						self.glows[i].Enabled = visibility > 0.5 and i <= LOD_GLOW_CUTOFF
					end
				end
			end

			-- Update attachment position
			if self.attachments[i] then
				self.attachments[i].WorldPosition = segment.Position
			end
		end
	end

	-- Update all beams with calculated widths and LOD
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				-- Regular beams
				if i <= self.visibleSegmentCount then
					-- Check if both segments are visible
					local seg1 = self.segments[i]
					local seg2 = self.segments[i + 1]
					
					if seg1 and seg2 then
						local visibility1, highQuality1 = self:calculateLODVisibility(i, seg1.Position)
						local visibility2, highQuality2 = self:calculateLODVisibility(i + 1, seg2.Position)
						
						local avgVisibility = (visibility1 + visibility2) / 2
						local useHighQuality = highQuality1 and highQuality2
						
						if avgVisibility > 0.1 and i <= self.visibleRange.finish then
							beam.Enabled = true
							beam.Transparency = NumberSequence.new(math.max(0, 1 - avgVisibility))
							
							-- Adjust beam quality based on LOD
							beam.Segments = useHighQuality and BEAM_SEGMENTS or BEAM_SEGMENTS_LOW
							
							local beamWidth = self:getBeamWidth(i, currentBaseSize)
							beam.Width0 = beamWidth
							beam.Width1 = beamWidth
							
							-- Dynamic color during boost
							if self.isBoosting and i > HEAD_BLEND_SEGMENTS then
								local colorShift = math.floor(tick() * 3) % #self.config.BodyColors
								local colorIndex = ((i - 1 + colorShift) % #self.config.BodyColors) + 1
								beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
							end
						else
							beam.Enabled = false
						end
					else
						beam.Enabled = false
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlap") then
				-- Overlap beams with LOD
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 2 and index <= 30 then -- Limit overlap beams
					local seg = self.segments[index]
					if seg then
						local visibility, _ = self:calculateLODVisibility(index, seg.Position)
						if visibility > 0.5 then
							beam.Enabled = true
							beam.Transparency = NumberSequence.new(0.5 + (1 - visibility) * 0.5)
							local overlapWidth = self:getBeamWidth(index, currentBaseSize) * 1.15
							beam.Width0 = overlapWidth
							beam.Width1 = overlapWidth
						else
							beam.Enabled = false
						end
					else
						beam.Enabled = false
					end
				else
					beam.Enabled = false
				end
			end
		end
	end

	-- Update glow ranges based on size and LOD
	for i, glow in pairs(self.glows) do
		if glow and glow.Parent and i <= LOD_GLOW_CUTOFF then
			local seg = self.segments[i]
			if seg then
				local visibility, _ = self:calculateLODVisibility(i, seg.Position)
				if visibility > 0.3 then
					glow.Enabled = true
					local glowScale = visibility * (1 - (i / self.visibleSegmentCount) * 0.3)
					glow.Range = (GLOW_RANGE_BASE + (currentBaseSize - BASE_SIZE) * 2) * glowScale
					glow.Brightness = GLOW_INTENSITY * visibility
				else
					glow.Enabled = false
				end
			end
		elseif glow then
			glow.Enabled = false
		end
	end
end

function Snake:addSegments(count)
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		-- Create new segment with fade-in effect
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		-- Start small for growth animation
		local targetSize = self:getSegmentSize(i, BASE_SIZE * self.growthFactor)
		segment.Size = Vector3.new(targetSize * 0.1, targetSize * 0.1, targetSize * 0.1)

		segment.Transparency = 0.8 -- Start more transparent
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Position at last segment initially
		if self.segments[i - 1] then
			segment.Position = self.segments[i - 1].Position
		end

		-- Add glow based on falloff rules with LOD
		local shouldHaveGlow = false
		if i <= LOD_GLOW_CUTOFF then
			if i <= 20 then
				shouldHaveGlow = true
			elseif i <= 40 then
				shouldHaveGlow = i % 2 == 0
			end
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

			-- Calculate beam width for new segment
			local beamWidth = self:getBeamWidth(i - 1, BASE_SIZE * self.growthFactor)
			beam.Width0 = beamWidth * 0.1 -- Start thin
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
			beam.Transparency = NumberSequence.new(0.8) -- Start more transparent

			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])

			beam.Parent = self.attachmentPart
			self.beams[i - 1] = beam

			-- Animate beam growth (width only - transparency needs custom animation)
			TweenService:Create(beam, TweenInfo.new(0.3), {
				Width0 = beamWidth,
				Width1 = beamWidth
			}):Play()

			-- Custom transparency animation for NumberSequence
			local startTime = tick()
			local transparencyConnection
			transparencyConnection = RunService.Heartbeat:Connect(function()
				local elapsed = tick() - startTime
				local progress = math.min(elapsed / 0.3, 1) -- 0.3 second duration

				-- Interpolate from 0.8 to 0
				local transparency = 0.8 * (1 - progress)
				beam.Transparency = NumberSequence.new(transparency)

				if progress >= 1 then
					transparencyConnection:Disconnect()
				end
			end)
		end

		-- Add strategic overlap beams for new segments in critical areas
		if i <= HEAD_BLEND_SEGMENTS * 2 and i > 2 and i % 2 == 0 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. (i - 2)
			overlapBeam.Attachment0 = self.attachments[i - 2]
			overlapBeam.Attachment1 = self.attachments[i]

			local overlapWidth = self:getBeamWidth(i - 2, BASE_SIZE * self.growthFactor) * 1.15
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			overlapBeam.TextureMode = Enum.TextureMode.Stretch
			overlapBeam.TextureLength = 3
			overlapBeam.LightEmission = 0.7
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.5)
			overlapBeam.ZOffset = -0.1

			local overlapColorIndex = ((i - 3) % #self.config.BodyColors) + 1
			overlapBeam.Color = ColorSequence.new(self.config.BodyColors[overlapColorIndex])

			overlapBeam.Parent = self.attachmentPart
			self.beams["overlap" .. (i - 2)] = overlapBeam
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

function Snake:grow(amount)
	-- Store pending growth for smooth animation
	self.pendingGrowth = self.pendingGrowth + (amount or 1)
	self.targetLength = math.min(self.targetLength + (amount or 1), 50000)

	-- Visual feedback for growth
	if self.head and self.headGlow then
		-- Flash effect
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

		-- Create speed effect (only for visible segments)
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
	-- Only return visible segments for collision
	for i = 1, math.min(50, self.visibleSegmentCount) do
		if self.segments[i] and self.segments[i].Parent then
			local visibility, _ = self:calculateLODVisibility(i, self.segments[i].Position)
			if visibility > 0.3 then -- Only include visible segments
				table.insert(collisionSegments, self.segments[i])
			end
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
	print("✅ Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING with LOD")
	print("🐍 Features: Smooth Growth | Perfect Blending | No Teleporting | LOD System")
	print("📊 LOD: Auto-hides distant segments, reduces quality for performance")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9