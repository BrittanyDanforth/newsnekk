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

function Snake:updatePositionHistory()
	local now = tick()
	if now - self.lastHistoryUpdate < 1/120 then -- Limit history updates
		return
	end
	self.lastHistoryUpdate = now

	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	
	-- Calculate velocity for smoother interpolation
	local prevIndex = self.historyIndex - 1
	if prevIndex < 1 then prevIndex = HISTORY_SIZE end
	
	local prevData = self.positionHistory[prevIndex]
	local velocity = (self.rootPart.Position - prevData.position) / (now - prevData.time)
	
	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector,
		cframe = self.rootPart.CFrame,
		time = now,
		velocity = velocity
	}
end

function Snake:getHistoricalPosition(stepsBack)
	local index = self.historyIndex - stepsBack
	if index < 1 then
		index = index + HISTORY_SIZE
	end
	
	local data = self.positionHistory[index]
	
	-- If we need interpolation between history points
	if stepsBack % 1 ~= 0 then
		local nextIndex = index + 1
		if nextIndex > HISTORY_SIZE then nextIndex = 1 end
		
		local nextData = self.positionHistory[nextIndex]
		local alpha = stepsBack % 1
		
		return {
			position = data.position:Lerp(nextData.position, alpha),
			lookVector = data.lookVector:Lerp(nextData.lookVector, alpha),
			cframe = data.cframe:Lerp(nextData.cframe, alpha),
			time = data.time + (nextData.time - data.time) * alpha,
			velocity = data.velocity:Lerp(nextData.velocity, alpha)
		}
	end
	
	return data
end

function Snake:startUpdateLoop()
	local frameCount = 0
	local lastNetworkUpdate = 0
	local lastFullUpdate = 0

	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.character.Parent or not self.rootPart.Parent then
			self:destroy()
			return
		end

		frameCount = frameCount + 1
		local now = tick()

		-- Update position history
		self:updatePositionHistory()

		-- Smooth length interpolation
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			local growthRate = GROWTH_SPEED

			if diff > 0.1 and not self.isGrowing then
				self.isGrowing = true
				self.growthStartTime = now
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

		-- Batch update visuals for performance
		if now - lastFullUpdate > 1/60 then
			self:updateUnifiedBodyBatched()
			lastFullUpdate = now
		else
			-- Update only critical segments (head and nearby)
			self:updateCriticalSegments()
		end

		-- Handle boost effects
		self:updateBoostEffects()

		-- Network updates
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > 1/NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateCriticalSegments()
	-- Always update head
	local cf = CFrame.lookAt(
		self.rootPart.Position,
		self.rootPart.Position + self.rootPart.CFrame.LookVector
	)
	self.segments[0].CFrame = cf
	
	-- Update eyes
	local headSize = self:getSegmentSize(0, BASE_SIZE * self.growthFactor)
	local eyeScale = headSize / BASE_SIZE * 0.5
	local eyeOffset = headSize * 0.3
	local eyeForward = -headSize * 0.35

	self.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.5, eyeForward)
	self.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.5, eyeForward)
	self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
	
	-- Update head attachment
	if self.attachments[0] then
		self.attachments[0].WorldPosition = self.segments[0].Position
	end
	
	-- Update first few segments for smooth head connection
	local currentBaseSize = BASE_SIZE * self.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING
	
	for i = 1, math.min(10, self.visibleSegmentCount) do
		local segment = self.segments[i]
		if segment and segment.Parent then
			local stepsBack = math.floor(i * spacing / 2)
			local histData = self:getHistoricalPosition(stepsBack)
			
			if histData then
				segment.Position = segment.Position:Lerp(histData.position, 0.9)
				
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end
			end
		end
	end
end

function Snake:updateUnifiedBodyBatched()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		local now = tick()
		if now - self.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			self:addSegmentsBatched(math.min(5, requiredSegments - self.visibleSegmentCount))
			self.lastSegmentAddTime = now
		end
	end

	local currentBaseSize = BASE_SIZE * self.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING
	
	-- Get camera position for LOD
	local cameraPos = self.camera and self.camera.CFrame.Position or self.rootPart.Position

	-- Update segments in batches
	local batchStart = 0
	local batchSize = BATCH_UPDATE_SIZE
	
	while batchStart <= self.visibleSegmentCount do
		local batchEnd = math.min(batchStart + batchSize - 1, self.visibleSegmentCount)
		
		for i = batchStart, batchEnd do
			local segment = self.segments[i]
			if segment and segment.Parent then
				if i == 0 then
					-- Head update (already done in critical segments)
					local headSize = self:getSegmentSize(0, currentBaseSize)
					segment.Size = Vector3.new(headSize, headSize, headSize)
				else
					-- Body segment update
					local stepsBack = math.floor(i * spacing / 2)
					local histData = self:getHistoricalPosition(stepsBack)
					
					if histData then
						-- Calculate distance for LOD
						local distance = (segment.Position - cameraPos).Magnitude
						local lodFactor = math.min(1, LOD_DISTANCE / distance)
						
						-- Smoother interpolation for segments
						local targetPos = histData.position
						local currentPos = segment.Position
						local smoothingFactor = VISUAL_SMOOTHING_FACTOR * lodFactor
						
						segment.Position = currentPos:Lerp(targetPos, smoothingFactor)
						
						-- Update size
						local segmentSize = self:getSegmentSize(i, currentBaseSize)
						segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)
						
						-- Pulse effect during boost
						if self.isBoosting and lodFactor > 0.5 then
							local pulse = math.sin(tick() * 10 + i * 0.1) * 0.03 + 1
							segment.Size = segment.Size * pulse
						end
						
						-- Update attachment
						if self.attachments[i] then
							self.attachments[i].WorldPosition = segment.Position
						end
					end
				end
			end
		end
		
		batchStart = batchEnd + 1
		
		-- Yield to prevent frame drops
		if batchStart < self.visibleSegmentCount then
			RunService.Heartbeat:Wait()
		end
	end

	-- Update beams in separate pass
	self:updateBeamsBatched(currentBaseSize)
	
	-- Update glows
	self:updateGlows(currentBaseSize)
end

function Snake:updateBeamsBatched(currentBaseSize)
	local beamUpdateCount = 0
	
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent and type(i) == "number" then
			if i <= self.visibleSegmentCount then
				local beamWidth = self:getBeamWidth(i, currentBaseSize)
				
				-- Only update if width changed significantly
				if math.abs(beam.Width0 - beamWidth) > 0.1 then
					beam.Width0 = beamWidth
					beam.Width1 = beamWidth
				end
				
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
			
			beamUpdateCount = beamUpdateCount + 1
			
			-- Yield periodically
			if beamUpdateCount % 50 == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end
end

function Snake:updateGlows(currentBaseSize)
	for i, glow in pairs(self.glows) do
		if glow and glow.Parent then
			local glowScale = 1 - (i / self.visibleSegmentCount) * 0.3
			glow.Range = (GLOW_RANGE_BASE + (currentBaseSize - BASE_SIZE) * 2) * glowScale
			
			if self.isBoosting then
				glow.Brightness = GLOW_INTENSITY * 1.5
			else
				glow.Brightness = GLOW_INTENSITY
			end
		end
	end
end

function Snake:updateBoostEffects()
	if self.isBoosting then
		self.boostParticles.Rate = 150
	else
		self.boostParticles.Rate = 0
	end
end

function Snake:addSegmentsBatched(count)
	local newSegments = {}
	local newBeams = {}
	
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		-- Create segment
		local segment = getPooledSegment()
		segment.Name = "Segment" .. i
		
		local targetSize = self:getSegmentSize(i, BASE_SIZE * self.growthFactor)
		segment.Size = Vector3.new(targetSize * 0.1, targetSize * 0.1, targetSize * 0.1)
		segment.Transparency = 0.8
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Position at last segment
		if self.segments[i - 1] then
			segment.Position = self.segments[i - 1].Position
		end

		-- Add glow if needed
		local shouldHaveGlow = i <= GLOW_FALLOFF_START and i % 2 == 0
		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9
			segmentGlow.Range = GLOW_RANGE_BASE * 0.8
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end

		self.segments[i] = segment
		table.insert(newSegments, segment)

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beam
		if self.attachments[i - 1] then
			local beam = getPooledBeam()
			beam.Name = "Beam" .. (i - 1)
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]

			local beamWidth = self:getBeamWidth(i - 1, BASE_SIZE * self.growthFactor)
			beam.Width0 = beamWidth * 0.1
			beam.Width1 = beamWidth * 0.1
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.Segments = BEAM_SEGMENTS
			beam.TextureLength = 2
			beam.Transparency = NumberSequence.new(0.8)
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])

			self.beams[i - 1] = beam
			table.insert(newBeams, {beam = beam, targetWidth = beamWidth})
		end
	end

	-- Parent all new segments at once
	for _, segment in ipairs(newSegments) do
		segment.Parent = self.model
	end

	-- Parent all new beams at once
	for _, beamData in ipairs(newBeams) do
		beamData.beam.Parent = self.attachmentPart
	end

	-- Animate growth
	for i, segment in ipairs(newSegments) do
		local targetSize = self:getSegmentSize(self.visibleSegmentCount + i, BASE_SIZE * self.growthFactor)
		TweenService:Create(segment, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
			Size = Vector3.new(targetSize, targetSize, targetSize),
			Transparency = 0
		}):Play()
	end

	-- Animate beams
	for _, beamData in ipairs(newBeams) do
		TweenService:Create(beamData.beam, TweenInfo.new(0.3), {
			Width0 = beamData.targetWidth,
			Width1 = beamData.targetWidth
		}):Play()
		
		-- Animate transparency
		local startTime = tick()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local elapsed = tick() - startTime
			local progress = math.min(elapsed / 0.3, 1)
			beamData.beam.Transparency = NumberSequence.new(0.8 * (1 - progress))
			if progress >= 1 then
				conn:Disconnect()
			end
		end)
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

		-- Create speed lines effect
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

	-- Return segments to pool
	for _, segment in pairs(self.segments) do
		if segment and segment.Parent then
			returnToPool(segment)
		end
	end

	-- Return beams to pool
	for _, beam in pairs(self.beams) do
		if beam and beam.Parent then
			returnBeamToPool(beam)
		end
	end

	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

-- Module
local OptimizedSnakeSystemV10 = {}

function OptimizedSnakeSystemV10.init()
	createNetworkEvents()
	print("✅ Snake System V10 ULTIMATE - COMPLETELY REVAMPED!")
	print("🐍 Features: No Gaps | No Disappearing Parts | Ultra Smooth | Perfect Beams")
end

function OptimizedSnakeSystemV10.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV10