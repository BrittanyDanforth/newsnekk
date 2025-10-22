-- Optimized Snake System V8 ULTIMATE - EXTREME VISUAL BEAST
-- ZERO LAG | BUTTERY SMOOTH | DYNAMIC GROWTH | PERFECT BEAMS

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- EXTREME Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS LOCKED
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_SEGMENTS = 1000 -- DOUBLED for massive snakes
local SEGMENT_SPACING = 0.6 -- TIGHTER for ultra smooth
local HISTORY_SIZE = 3000 -- MASSIVE history for perfect trailing
local GROWTH_CHECK_INTERVAL = 5 -- Check growth more often

-- EXTREME Visual Constants
local MIN_HEAD_SIZE = 3
local MAX_HEAD_SIZE = 20 -- BIGGER max head
local MIN_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 15 -- BIGGER segments
local GLOW_INTENSITY_MIN = 2 -- BRIGHTER minimum
local GLOW_INTENSITY_MAX = 5 -- SUPER bright max
local BEAM_SEGMENTS = 20 -- ULTRA smooth beams
local BEAM_MIN_WIDTH = 3 -- Thicker minimum
local BEAM_MAX_WIDTH = 20 -- MASSIVE beams
local MAX_BEAMS = 500 -- TONS of beams

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

-- ULTIMATE Snake Class
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

	-- COMPLETELY hide character
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

	-- Core snake data with EXTREME values
	self.length = config.InitialLength or 10
	self.actualLength = self.length
	self.targetLength = self.length
	self.isBoosting = false
	self.growthFactor = 1
	self.lastGrowthCheck = 0
	
	-- EXTREME visual effects
	self.pulsePhase = 0
	self.glowPulse = 0
	self.rainbowPhase = 0

	-- Movement history for PERFECT trailing
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
	
	-- For EXTREME orb eating animations
	self.eatingOrbs = {}
	self.orbTrails = {}

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

	-- Initialize the ULTIMATE snake
	self:createHead()
	self:createBody()
	self:startUpdateLoop()

	print("✅ ULTIMATE Snake created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	-- EXTREME growth scaling
	local length = self.actualLength

	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 2.5 -- Up to 3.5x at 200
	elseif length <= 1000 then
		return 3.5 + (length - 200) / 800 * 3.5 -- Up to 7x at 1000
	elseif length <= 5000 then
		return 7.0 + (length - 1000) / 4000 * 5.0 -- Up to 12x at 5000
	elseif length <= 20000 then
		return 12.0 + (length - 5000) / 15000 * 8.0 -- Up to 20x at 20000
	else
		return 20.0 -- MAX 20x scaling
	end
end

function Snake:createHead()
	-- EXTREME head part
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
	head.Size = Vector3.new(MIN_HEAD_SIZE, MIN_HEAD_SIZE, MIN_HEAD_SIZE)
	head.Transparency = 0 -- PERFECT SOLID
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model

	-- EXTREME glow effect
	local glow = Instance.new("PointLight")
	glow.Name = "HeadGlow"
	glow.Brightness = GLOW_INTENSITY_MIN
	glow.Range = 20
	glow.Color = head.Color
	glow.Shadows = true -- Enable shadows for depth
	glow.Parent = head
	
	-- Secondary glow for EXTREME brightness
	local glow2 = Instance.new("PointLight")
	glow2.Name = "HeadGlow2"
	glow2.Brightness = GLOW_INTENSITY_MIN * 0.5
	glow2.Range = 30
	glow2.Color = head.Color
	glow2.Shadows = false
	glow2.Parent = head

	-- EXTREME particle effects
	local particle = Instance.new("ParticleEmitter")
	particle.Name = "BoostParticles"
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(head.Color)
	particle.Lifetime = NumberRange.new(0.5, 1.5)
	particle.Rate = 0
	particle.Speed = NumberRange.new(10, 20)
	particle.SpreadAngle = Vector2.new(360, 360)
	particle.VelocityInheritance = 0.5
	particle.EmissionDirection = Enum.NormalId.Back
	particle.Enabled = false
	particle.Parent = head
	
	-- AURA particle effect
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "AuraParticles"
	aura.Texture = "rbxasset://textures/particles/smoke_main.dds"
	aura.Color = ColorSequence.new(head.Color)
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Rate = 20
	aura.Speed = NumberRange.new(1, 3)
	aura.SpreadAngle = Vector2.new(360, 360)
	aura.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 1)
	})
	aura.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 5)
	})
	aura.RotSpeed = NumberRange.new(-100, 100)
	aura.Parent = head

	-- EXTREME eyes with depth
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Transparency = 0
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
		pupil.Size = Vector3.new(0.4, 0.4, 0.4)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model

		return eye, pupil, eyeGlow
	end

	self.leftEye, self.leftPupil, self.leftEyeGlow = createEye(-0.8)
	self.rightEye, self.rightPupil, self.rightEyeGlow = createEye(0.8)

	-- Collision tagging
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Create head attachment for PERFECT beam connection
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "HeadAttachment"
	headAttachment.Parent = head
	self.headAttachment = headAttachment

	self.head = head
	self.headGlow = glow
	self.headGlow2 = glow2
	self.boostParticles = particle
	self.auraParticles = aura
end

function Snake:createBody()
	-- Calculate initial segment count
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

	-- Create EXTREME segments
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0 -- PERFECT SOLID
		segment.CanCollide = false
		segment.CanTouch = i <= 100 -- More collision segments
		segment.CanQuery = false
		segment.Anchored = true

		-- RAINBOW color pattern option
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Glow for MORE segments
		if i <= 50 then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Brightness = 1
			segmentGlow.Range = 10
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
		end

		segment.Parent = self.model
		self.segments[i] = segment

		-- Collision tagging for more segments
		if i <= 100 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end

		-- Create attachments
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

	-- CREATE PERFECT HEAD-TO-BODY BEAM
	local headBeam = Instance.new("Beam")
	headBeam.Name = "HeadBeam"
	headBeam.Attachment0 = self.headAttachment
	headBeam.Attachment1 = self.attachments[1]

	-- EXTREME beam properties
	headBeam.Width0 = BEAM_MIN_WIDTH
	headBeam.Width1 = BEAM_MIN_WIDTH
	headBeam.CurveSize0 = 0
	headBeam.CurveSize1 = 0
	headBeam.FaceCamera = true
	headBeam.Segments = BEAM_SEGMENTS
	headBeam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
	headBeam.TextureMode = Enum.TextureMode.Stretch
	headBeam.TextureLength = 1
	headBeam.TextureSpeed = 2 -- Animated texture!
	headBeam.LightEmission = 1 -- MAX emission
	headBeam.LightInfluence = 0
	headBeam.Transparency = NumberSequence.new(0) -- PERFECT SOLID
	headBeam.ZOffset = -0.1 -- Slight offset to prevent z-fighting

	headBeam.Color = ColorSequence.new(self.config.BodyColors[1])
	headBeam.Parent = attachmentPart
	self.headBeam = headBeam

	-- Create EXTREME beams between segments
	for i = 1, math.min(segmentCount, MAX_BEAMS) do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

		-- ULTIMATE beam visuals
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
		beam.LightEmission = 1 -- MAX brightness
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0) -- PERFECT SOLID
		beam.ZOffset = -0.1

		-- Color with potential for effects
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

-- EXTREME orb eating animation
function Snake:eatOrb(orbPosition, orbColor, orbSize)
	-- Create MULTIPLE visual orbs for effect
	for i = 1, 3 do
		task.wait(0.05 * i)
		local eatingOrb = Instance.new("Part")
		eatingOrb.Name = "EatingOrb"
		eatingOrb.Shape = Enum.PartType.Ball
		eatingOrb.Material = Enum.Material.Neon
		eatingOrb.Color = orbColor or Color3.fromRGB(255, 255, 0)
		eatingOrb.Size = Vector3.new(orbSize or 2, orbSize or 2, orbSize or 2) * (1 - i * 0.2)
		eatingOrb.CanCollide = false
		eatingOrb.Anchored = true
		eatingOrb.Parent = self.model
		
		-- EXTREME glow
		local orbGlow = Instance.new("PointLight")
		orbGlow.Brightness = 3
		orbGlow.Range = 15
		orbGlow.Color = eatingOrb.Color
		orbGlow.Parent = eatingOrb
		
		-- Store orb data
		table.insert(self.eatingOrbs, {
			part = eatingOrb,
			startTime = tick(),
			duration = 1.5, -- Faster travel
			startPos = orbPosition,
			glow = orbGlow,
			trail = self:createOrbTrail(eatingOrb)
		})
	end
	
	-- EXTREME eat effect
	local eatEffect = Instance.new("Part")
	eatEffect.Name = "EatEffect"
	eatEffect.Shape = Enum.PartType.Ball
	eatEffect.Material = Enum.Material.ForceField
	eatEffect.Color = orbColor or Color3.fromRGB(255, 255, 0)
	eatEffect.Size = Vector3.new(orbSize * 3, orbSize * 3, orbSize * 3)
	eatEffect.Transparency = 0.3
	eatEffect.CanCollide = false
	eatEffect.Anchored = true
	eatEffect.Position = orbPosition
	eatEffect.Parent = self.model
	
	-- Shockwave effect
	local shockwave = Instance.new("Part")
	shockwave.Name = "Shockwave"
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Material = Enum.Material.ForceField
	shockwave.Color = orbColor or Color3.fromRGB(255, 255, 0)
	shockwave.Size = Vector3.new(0.5, orbSize * 2, orbSize * 2)
	shockwave.Transparency = 0.5
	shockwave.CanCollide = false
	shockwave.Anchored = true
	shockwave.CFrame = CFrame.new(orbPosition) * CFrame.Angles(0, 0, math.rad(90))
	shockwave.Parent = self.model
	
	-- Tween both effects
	local eatTween = TweenService:Create(eatEffect,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1,
			Position = self.head.Position
		}
	)
	
	local shockTween = TweenService:Create(shockwave,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.1, orbSize * 10, orbSize * 10),
			Transparency = 1
		}
	)
	
	eatTween:Play()
	shockTween:Play()
	Debris:AddItem(eatEffect, 0.3)
	Debris:AddItem(shockwave, 0.5)
end

function Snake:createOrbTrail(orb)
	local trail = Instance.new("Trail")
	trail.Texture = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.TextureLength = 1
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Color = ColorSequence.new(orb.Color)
	trail.Lifetime = 0.5
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.Width0 = orb.Size.X
	trail.Width1 = 0
	
	local att0 = Instance.new("Attachment", orb)
	local att1 = Instance.new("Attachment", orb)
	att0.Position = Vector3.new(0, orb.Size.Y/2, 0)
	att1.Position = Vector3.new(0, -orb.Size.Y/2, 0)
	
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Parent = orb
	
	return trail
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
		
		-- Update visual phases
		self.pulsePhase = self.pulsePhase + deltaTime * 2
		self.glowPulse = math.sin(self.pulsePhase) * 0.5 + 0.5
		self.rainbowPhase = self.rainbowPhase + deltaTime * 0.5

		-- Update position history
		self:updatePositionHistory()

		-- ULTRA smooth length interpolation
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			self.actualLength = self.actualLength + diff * 0.15 -- Smoother
		end

		-- Update growth factor
		if frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end

		-- Update ALL visuals
		self:updateHead()
		self:updateBody()
		self:updateEatingOrbs()
		self:updateVisualEffects() -- NEW!

		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 100 -- MORE particles
			self.headGlow.Brightness = GLOW_INTENSITY_MAX
			self.headGlow2.Brightness = GLOW_INTENSITY_MAX * 0.7
			self.auraParticles.Rate = 50
		else
			self.boostParticles.Rate = 0
			self.headGlow.Brightness = GLOW_INTENSITY_MIN + self.glowPulse
			self.headGlow2.Brightness = (GLOW_INTENSITY_MIN + self.glowPulse) * 0.5
			self.auraParticles.Rate = 20
		end

		-- Network updates
		local now = tick()
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > 1/NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateVisualEffects()
	-- Pulsing effects
	local pulseScale = 1 + self.glowPulse * 0.1
	
	-- Update head glow range
	self.headGlow.Range = (10 + self.head.Size.X * 2) * pulseScale
	self.headGlow2.Range = (15 + self.head.Size.X * 3) * pulseScale
	
	-- Update eye glow
	self.leftEyeGlow.Brightness = 0.5 + self.glowPulse * 0.5
	self.rightEyeGlow.Brightness = 0.5 + self.glowPulse * 0.5
	
	-- Rainbow mode for special snakes
	if self.actualLength > 1000 then
		local rainbow = Color3.fromHSV(self.rainbowPhase % 1, 1, 1)
		self.auraParticles.Color = ColorSequence.new(rainbow)
	end
end

function Snake:updateEatingOrbs()
	local currentTime = tick()
	
	for i = #self.eatingOrbs, 1, -1 do
		local orbData = self.eatingOrbs[i]
		local elapsed = currentTime - orbData.startTime
		local progress = elapsed / orbData.duration
		
		if progress >= 1 then
			-- Orb reached end
			if orbData.part and orbData.part.Parent then
				-- Create burst effect
				local burst = Instance.new("Part")
				burst.Name = "OrbBurst"
				burst.Shape = Enum.PartType.Ball
				burst.Material = Enum.Material.ForceField
				burst.Color = orbData.part.Color
				burst.Size = Vector3.new(3, 3, 3)
				burst.Transparency = 0.5
				burst.CanCollide = false
				burst.Anchored = true
				burst.Position = orbData.part.Position
				burst.Parent = self.model
				
				TweenService:Create(burst,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1}
				):Play()
				
				Debris:AddItem(burst, 0.3)
				orbData.part:Destroy()
			end
			table.remove(self.eatingOrbs, i)
		else
			-- Update orb position with SPIRAL movement
			local segmentIndex = math.floor(progress * self.visibleSegmentCount) + 1
			segmentIndex = math.min(segmentIndex, self.visibleSegmentCount)
			
			if self.segments[segmentIndex] then
				local targetPos = self.segments[segmentIndex].Position
				
				-- Spiral motion
				local spiral = elapsed * 10
				local spiralOffset = Vector3.new(
					math.sin(spiral) * 2,
					math.cos(spiral) * 2,
					0
				) * (1 - progress)
				
				orbData.part.Position = targetPos + spiralOffset
				orbData.part.CFrame = orbData.part.CFrame * CFrame.Angles(0.1, 0.1, 0.1)
				
				-- Fade and scale
				if progress > 0.7 then
					local fadeProgress = (progress - 0.7) / 0.3
					orbData.part.Transparency = fadeProgress * 0.8
					orbData.glow.Brightness = 3 * (1 - fadeProgress)
				end
				
				local scaleFactor = 1 - progress * 0.7
				orbData.part.Size = Vector3.new(2, 2, 2) * scaleFactor
			end
		end
	end
end

function Snake:updateHead()
	-- EXTREME dynamic head sizing
	local headSize = MIN_HEAD_SIZE + (MAX_HEAD_SIZE - MIN_HEAD_SIZE) * (self.growthFactor - 1) / 19
	headSize = headSize * (1 + self.glowPulse * 0.05) -- Pulsing!
	self.head.Size = Vector3.new(headSize, headSize, headSize)

	-- Perfect positioning
	local cf = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + self.rootPart.CFrame.LookVector)
	self.head.CFrame = cf

	-- EXTREME eye updates
	local eyeScale = headSize / MIN_HEAD_SIZE * 0.8
	local eyeOffset = headSize * 0.35
	local eyeForward = -headSize * 0.35

	self.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
	self.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	self.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

	-- Dynamic eye movement
	local lookOffset = self.rootPart.CFrame.LookVector * 0.1
	self.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.7, eyeForward)
	self.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.7, eyeForward)
	self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(lookOffset.X, lookOffset.Y, -eyeScale * 0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(lookOffset.X, lookOffset.Y, -eyeScale * 0.3)
end

function Snake:updateBody()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end

	-- EXTREME segment updates
	local segmentSize = MIN_SEGMENT_SIZE + (MAX_SEGMENT_SIZE - MIN_SEGMENT_SIZE) * (self.growthFactor - 1) / 19
	local spacing = segmentSize * SEGMENT_SPACING

	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate position from history
			local stepsBack = math.floor(i * spacing / 2)
			local histData = self:getHistoricalPosition(stepsBack)

			if histData then
				-- ULTRA smooth position
				local targetPos = histData.position
				local currentPos = segment.Position
				segment.Position = currentPos:Lerp(targetPos, 0.4) -- Smoother lerp

				-- Dynamic size with pulse
				local taper = 1 - (i / self.visibleSegmentCount) * 0.25 -- Less taper
				local pulse = 1 + math.sin(self.pulsePhase + i * 0.1) * 0.05
				segment.Size = Vector3.new(segmentSize * taper * pulse, segmentSize * taper * pulse, segmentSize * taper * pulse)

				-- Update attachment positions
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end
				
				-- Update glow for segments
				local glow = segment:FindFirstChild("PointLight")
				if glow then
					glow.Brightness = 0.5 + self.glowPulse * 0.3
				end
			end
		end
	end

	-- Update final attachment
	if self.attachments[self.visibleSegmentCount + 1] and self.segments[self.visibleSegmentCount] then
		self.attachments[self.visibleSegmentCount + 1].WorldPosition = self.segments[self.visibleSegmentCount].Position
	end

	-- EXTREME head beam updates
	if self.headBeam then
		local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 19
		width = width * (1 + self.glowPulse * 0.1)
		self.headBeam.Width0 = width
		self.headBeam.Width1 = width
		self.headBeam.LightEmission = 1
		self.headBeam.Transparency = NumberSequence.new(0)
		self.headBeam.TextureSpeed = self.isBoosting and 5 or 2
	end

	-- EXTREME beam updates with perfect coverage
	local beamCount = math.min(#self.beams, self.visibleSegmentCount, MAX_BEAMS)
	for i = 1, beamCount do
		local beam = self.beams[i]
		if beam and beam.Parent then
			local progress = i / self.visibleSegmentCount
			local width = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 19
			
			-- Minimal tapering for perfect tail
			width = width * (1 - progress * 0.15) * (1 + self.glowPulse * 0.1)

			beam.Width0 = width
			beam.Width1 = width
			beam.LightEmission = 1
			beam.Transparency = NumberSequence.new(0)
			beam.TextureSpeed = self.isBoosting and 5 or 2
			beam.Enabled = true
			
			-- Rainbow effect for long snakes
			if self.actualLength > 2000 then
				local hue = (self.rainbowPhase + i * 0.02) % 1
				beam.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
			end
		end
	end
end

function Snake:addSegments(count)
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		-- Create EXTREME segment
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 100
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		
		-- Add glow to more segments
		if i <= 100 then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Brightness = 0.5
			segmentGlow.Range = 8
			segmentGlow.Color = segment.Color
			segmentGlow.Parent = segment
		end
		
		segment.Parent = self.model
		self.segments[i] = segment

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create EXTREME beam
		if i <= MAX_BEAMS and self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. i
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]

			-- ULTIMATE beam properties
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
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(0)
			beam.ZOffset = -0.1
			beam.Enabled = true

			local colorIdx = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIdx])

			beam.Parent = self.attachmentPart
			self.beams[i] = beam
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
	
	-- Update final attachment
	if not self.attachments[self.visibleSegmentCount + 1] then
		local finalAttachment = Instance.new("Attachment")
		finalAttachment.Name = "AttachmentFinal"
		finalAttachment.Parent = self.attachmentPart
		self.attachments[self.visibleSegmentCount + 1] = finalAttachment
	end
end

function Snake:grow(amount)
	self.targetLength = math.min(self.targetLength + (amount or 1), 100000) -- Higher max!

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
	
	-- Growth effect
	if amount > 5 then
		self:createGrowthEffect()
	end
end

function Snake:createGrowthEffect()
	-- Pulse effect through entire snake
	spawn(function()
		for i = 1, math.min(self.visibleSegmentCount, 50) do
			local segment = self.segments[i]
			if segment then
				local originalSize = segment.Size
				TweenService:Create(segment,
					TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
					{Size = originalSize * 1.3}
				):Play()
				
				wait(0.02)
				
				TweenService:Create(segment,
					TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.In),
					{Size = originalSize}
				):Play()
			end
		end
	end)
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting

	-- EXTREME boost effects
	if boosting then
		self.boostParticles.Enabled = true
		
		-- Create boost aura
		local boostAura = Instance.new("Part")
		boostAura.Name = "BoostAura"
		boostAura.Shape = Enum.PartType.Ball
		boostAura.Material = Enum.Material.ForceField
		boostAura.Color = self.head.Color
		boostAura.Size = self.head.Size * 2
		boostAura.Transparency = 0.7
		boostAura.CanCollide = false
		boostAura.Anchored = true
		boostAura.CFrame = self.head.CFrame
		boostAura.Parent = self.model
		
		TweenService:Create(boostAura,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = self.head.Size * 5, Transparency = 1}
		):Play()
		
		Debris:AddItem(boostAura, 0.5)
		
		-- EXTREME speed lines
		for i = 1, 10 do
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.5, 0.5, 20)
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.head.Color
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.head.CFrame * CFrame.new(
				math.random(-10, 10), 
				math.random(-10, 10), 
				10
			)
			speedLine.Parent = self.model

			local tween = TweenService:Create(speedLine, 
				TweenInfo.new(0.3, Enum.EasingStyle.Linear), 
				{
					Transparency = 1, 
					Size = Vector3.new(0.1, 0.1, 40),
					Position = speedLine.Position + speedLine.CFrame.LookVector * -20
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
	self.targetLength = math.min(newLength, 100000)
end

function Snake:GetSegments()
	-- Return collision segments
	local collisionSegments = {}
	for i = 1, math.min(100, self.visibleSegmentCount) do
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
local OptimizedSnakeSystemV8_ULTIMATE = {}

function OptimizedSnakeSystemV8_ULTIMATE.init()
	createNetworkEvents()
	print("✅ Snake System V8 ULTIMATE - EXTREME VISUAL BEAST INITIALIZED")
	print("🐍 Features: EXTREME Growth | PERFECT Movement | ZERO Lag | ULTIMATE Beams | INSANE Effects")
	print("⚡ Performance: 60 FPS LOCKED | 1000+ Segments | 500+ Beams")
end

function OptimizedSnakeSystemV8_ULTIMATE.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8_ULTIMATE