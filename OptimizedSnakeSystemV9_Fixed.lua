-- Optimized Snake System V9 ULTIMATE - FIXED FOR HIGH LENGTH (NO DISAPPEARING PARTS)
-- Perfect head-body integration with rendering optimizations for 50K+ snakes

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
local SEGMENT_SPACING = 0.5
local HISTORY_SIZE = 2000
local GROWTH_CHECK_INTERVAL = 10

-- Rendering optimization constants (NEW)
local RENDER_DISTANCE = 500 -- Force render within this distance
local SEGMENT_CULLING_START = 100 -- Start culling after this many segments
local MIN_RENDER_SEGMENTS = 150 -- Always render at least this many segments
local FORCE_RENDER_INTERVAL = 5 -- Force update rendering properties every N frames

-- Visual Constants
local BASE_SIZE = 3.5
local MAX_SIZE_MULTIPLIER = 3.5
local GLOW_INTENSITY = 3
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 25
local BEAM_WIDTH_BASE = 0.95
local BEAM_TAPER_STRENGTH = 0.15
local HEAD_SIZE_MULTIPLIER = 1.05
local HEAD_BLEND_SEGMENTS = 8
local GLOW_FALLOFF_START = 50
local VISUAL_SMOOTHING_FACTOR = 0.6

-- Growth Animation Constants
local GROWTH_SPEED = 0.15
local SEGMENT_GROWTH_DELAY = 0.05
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

	-- Rendering optimization state (NEW)
	self.renderFrameCount = 0
	self.lastRenderOptimization = 0
	self.isLocalPlayer = (self.player == Players.LocalPlayer)

	-- Movement history
	self.positionHistory = {}
	self.historyIndex = 0

	-- Visual components with models for organization
	self.snakeFolder = workspace:FindFirstChild("Snakes") or Instance.new("Folder", workspace)
	self.snakeFolder.Name = "Snakes"
	
	self.model = Instance.new("Model")
	self.model.Name = self.player.Name
	self.model.Parent = self.snakeFolder

	-- Create sub-models for better organization and rendering (NEW)
	self.headModel = Instance.new("Model")
	self.headModel.Name = "Head"
	self.headModel.Parent = self.model
	
	self.bodyModel = Instance.new("Model")
	self.bodyModel.Name = "Body"
	self.bodyModel.Parent = self.model

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

	print("✅ Snake created for", self.player.Name, "with rendering optimizations")
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

-- NEW: Force rendering properties on parts to prevent disappearing
function Snake:forceRenderingProperties(part)
	-- Set rendering properties to prevent culling
	part.Transparency = part.Transparency -- Force update
	
	-- Ensure part stays in StreamingEnabled radius
	if part:IsA("BasePart") then
		-- Force the part to be considered "important" for rendering
		part:SetAttribute("RenderFidelity", Enum.RenderFidelity.Precise)
		
		-- Make sure CanCollide and CanQuery are set properly
		if part.Name == "Segment0_Head" or tonumber(string.match(part.Name, "Segment(%d+)") or 0) <= 50 then
			part.CanQuery = true
		end
	end
end

function Snake:createUnifiedBody()
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)

	-- Create attachment holder part with rendering optimization
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Parent = self.bodyModel
	self:forceRenderingProperties(attachmentPart)

	-- HEAD
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
	head.Parent = self.headModel
	self:forceRenderingProperties(head)

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
		eye.Parent = self.headModel
		self:forceRenderingProperties(eye)

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.headModel
		self:forceRenderingProperties(pupil)

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye(-0.6)
	self.rightEye, self.rightPupil = createEye(0.6)

	-- Collision tagging
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Store references
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

	-- Create body segments with rendering optimizations
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		local segmentSize = self:getSegmentSize(i, BASE_SIZE)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

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

		segment.Parent = self.bodyModel
		self:forceRenderingProperties(segment)
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

	-- Create beams with rendering optimizations
	for i = 0, segmentCount - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

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

		-- Color handling
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

	-- Create selective overlap beams
	for i = 0, math.min(segmentCount - 2, HEAD_BLEND_SEGMENTS * 2) do
		if i % 2 == 0 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = self.attachments[i]
			overlapBeam.Attachment1 = self.attachments[i + 2]

			local overlapWidth = self:getBeamWidth(i, BASE_SIZE) * 1.15
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

-- NEW: Optimized rendering check
function Snake:shouldUpdateSegmentRendering(segmentIndex)
	-- Always update first MIN_RENDER_SEGMENTS
	if segmentIndex <= MIN_RENDER_SEGMENTS then
		return true
	end
	
	-- For local player, always render more segments
	if self.isLocalPlayer then
		return segmentIndex <= MIN_RENDER_SEGMENTS * 2
	end
	
	-- For other players, use distance-based culling
	local camera = workspace.CurrentCamera
	if camera and self.segments[segmentIndex] then
		local distance = (camera.CFrame.Position - self.segments[segmentIndex].Position).Magnitude
		return distance <= RENDER_DISTANCE
	end
	
	return false
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
		self.renderFrameCount = self.renderFrameCount + 1

		-- Update position history
		self:updatePositionHistory()

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

		-- Update visuals with rendering optimizations
		self:updateUnifiedBody()

		-- Force rendering properties periodically to prevent disappearing
		if self.renderFrameCount % FORCE_RENDER_INTERVAL == 0 then
			self:forceRenderOptimization()
		end

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

-- NEW: Force optimization to prevent disappearing parts
function Snake:forceRenderOptimization()
	-- Update model primary part to keep it relevant
	if self.model and self.head then
		self.model.PrimaryPart = self.head
	end
	
	-- For very long snakes, force update critical segments
	if self.actualLength > 5000 then
		-- Always ensure head and early segments are visible
		for i = 0, math.min(50, self.visibleSegmentCount) do
			local segment = self.segments[i]
			if segment and segment.Parent then
				self:forceRenderingProperties(segment)
				
				-- Force position update to refresh rendering
				local currentPos = segment.Position
				segment.Position = currentPos + Vector3.new(0, 0.001, 0)
				segment.Position = currentPos
			end
		end
		
		-- Ensure beams stay visible
		for _, beam in pairs(self.beams) do
			if beam and beam.Parent and beam.Enabled then
				-- Toggle enabled to force refresh
				beam.Enabled = false
				beam.Enabled = true
			end
		end
	end
end

function Snake:updateUnifiedBody()
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	if requiredSegments > self.visibleSegmentCount then
		local now = tick()
		if now - self.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			self:addSegments(1)
			self.lastSegmentAddTime = now
		end
	end

	local currentBaseSize = BASE_SIZE * self.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING

	-- Update segments with rendering optimization
	for i = 0, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Check if we should update this segment's rendering
			local shouldUpdate = self:shouldUpdateSegmentRendering(i) or (self.renderFrameCount % 3 == i % 3)
			
			if shouldUpdate then
				if i == 0 then
					-- Head positioning
					local cf = CFrame.lookAt(
						self.rootPart.Position,
						self.rootPart.Position + self.rootPart.CFrame.LookVector
					)
					segment.CFrame = cf

					local headSize = self:getSegmentSize(0, currentBaseSize)
					segment.Size = Vector3.new(headSize, headSize, headSize)

					-- Update eyes
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
					-- Body segment positioning
					local stepsBack = math.floor(i * spacing / 2)
					local histData = self:getHistoricalPosition(stepsBack)
					local nextHistData = self:getHistoricalPosition(stepsBack + 1)

					if histData and nextHistData then
						local alpha = (i * spacing / 2) % 1
						local targetPos = histData.position:Lerp(nextHistData.position, alpha)
						local currentPos = segment.Position

						local smoothingFactor = self.isGrowing and VISUAL_SMOOTHING_FACTOR * 1.2 or VISUAL_SMOOTHING_FACTOR
						segment.Position = currentPos:Lerp(targetPos, smoothingFactor)

						local segmentSize = self:getSegmentSize(i, currentBaseSize)
						segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

						if self.isBoosting then
							local pulse = math.sin(tick() * 10 + i * 0.1) * 0.03 + 1
							segment.Size = segment.Size * pulse
						end
					end
				end
			end

			-- Always update attachment positions for beams
			if self.attachments[i] then
				self.attachments[i].WorldPosition = segment.Position
			end
		end
	end

	-- Update beams with less frequent updates for distant ones
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				if i <= self.visibleSegmentCount then
					-- Update nearby beams more frequently
					local shouldUpdateBeam = i <= MIN_RENDER_SEGMENTS or (self.renderFrameCount % 2 == i % 2)
					
					if shouldUpdateBeam then
						local beamWidth = self:getBeamWidth(i, currentBaseSize)
						beam.Width0 = beamWidth
						beam.Width1 = beamWidth
					end
					
					beam.Enabled = true

					if self.isBoosting and i > HEAD_BLEND_SEGMENTS then
						local colorShift = math.floor(tick() * 3) % #self.config.BodyColors
						local colorIndex = ((i - 1 + colorShift) % #self.config.BodyColors) + 1
						beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlap") then
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 2 then
					if index <= MIN_RENDER_SEGMENTS then
						local overlapWidth = self:getBeamWidth(index, currentBaseSize) * 1.15
						beam.Width0 = overlapWidth
						beam.Width1 = overlapWidth
					end
					beam.Enabled = true
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

		if self.segments[i - 1] then
			segment.Position = self.segments[i - 1].Position
		end

		-- Add glow
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

		segment.Parent = self.bodyModel
		self:forceRenderingProperties(segment)
		self.segments[i] = segment

		-- Growth animation
		TweenService:Create(segment, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(targetSize, targetSize, targetSize),
			Transparency = 0
		}):Play()

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beam
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

			-- Animate beam
			TweenService:Create(beam, TweenInfo.new(0.3), {
				Width0 = beamWidth,
				Width1 = beamWidth
			}):Play()

			-- Transparency animation
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
local OptimizedSnakeSystemV9Fixed = {}

function OptimizedSnakeSystemV9Fixed.init()
	createNetworkEvents()
	print("✅ Snake System V9 ULTIMATE - FIXED FOR HIGH LENGTH")
	print("🐍 Features: No Disappearing Parts | Optimized Rendering | 50K+ Support")
end

function OptimizedSnakeSystemV9Fixed.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9Fixed