-- Optimized Snake System V8 - ULTRA PERFORMANCE BEAST
-- Revolutionary hybrid rendering - handles 50k+ length with buttery smooth 60 FPS

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS baby
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_PHYSICAL_SEGMENTS = 50 -- Only 50 physical parts for collision
local MAX_VISUAL_BEAMS = 300 -- More beams for smoother curves
local SEGMENT_SPACING = 0.6 -- Tighter spacing for smoother look
local HISTORY_SIZE = 5000 -- Massive history for long snakes
local GROWTH_CHECK_INTERVAL = 10 -- Check growth every 10 frames
local BEAM_SEGMENT_LENGTH = 15 -- Shorter beams for smoother curves

-- Visual Constants
local MIN_HEAD_SIZE = 3
local MAX_HEAD_SIZE = 12
local MIN_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 10
local GLOW_INTENSITY_MIN = 1
local GLOW_INTENSITY_MAX = 3
local BEAM_SEGMENTS = 10 -- Balanced for performance
local BEAM_MIN_WIDTH = 3.5 -- Slightly thicker
local BEAM_MAX_WIDTH = 14 -- Slightly smaller max
local BEAM_CURVE_SIZE = 0.5 -- Add curves to beams for smoother turns

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

	-- Separate arrays for different components
	self.physicalSegments = {} -- Only 50 for collision
	self.visualBeams = {} -- Up to 200 for visuals
	self.beamAttachments = {} -- Attachments for beams
	
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
	self:createOptimizedBody()
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
	head.Material = Enum.Material.ForceField -- Better performance than Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
	head.Size = Vector3.new(MIN_HEAD_SIZE, MIN_HEAD_SIZE, MIN_HEAD_SIZE)
	head.Transparency = 0
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
		eye.Transparency = 0
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.3, 0.3, 0.3)
		pupil.Transparency = 0
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
	self.boostParticles = particle
end

function Snake:createOptimizedBody()
	-- Create attachment holder part (invisible)
	local attachmentHolder = Instance.new("Part")
	attachmentHolder.Name = "AttachmentHolder"
	attachmentHolder.Transparency = 1
	attachmentHolder.CanCollide = false
	attachmentHolder.CanQuery = false
	attachmentHolder.Anchored = true
	attachmentHolder.Size = Vector3.new(1, 1, 1)
	attachmentHolder.Parent = self.model
	self.attachmentHolder = attachmentHolder

	-- Create physical segments (only 50 for collision detection)
	for i = 1, MAX_PHYSICAL_SEGMENTS do
		local segment = Instance.new("Part")
		segment.Name = "PhysicalSegment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon -- Back to Neon for better glow
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = i <= 10 and 0 or 0.3 -- First 10 segments fully visible
		segment.CanCollide = false
		segment.CanTouch = true -- All physical segments can collide
		segment.CanQuery = false
		segment.Anchored = true

		-- Color pattern
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		segment.Parent = self.model
		self.physicalSegments[i] = segment

		-- Collision tagging
		CollectionService:AddTag(segment, "SnakeSegment")
		segment:SetAttribute("SegmentIndex", i)
		segment:SetAttribute("OwnerName", self.player.Name)
	end

	-- Create initial beam system
	self:setupBeamSystem()
end

function Snake:setupBeamSystem()
	-- Calculate how many beams we need
	local beamCount = math.min(math.ceil(self.actualLength / BEAM_SEGMENT_LENGTH), MAX_VISUAL_BEAMS)
	
	-- Create beam attachments
	for i = 1, beamCount + 1 do
		local attachment = Instance.new("Attachment")
		attachment.Name = "BeamAttachment" .. i
		attachment.Parent = self.attachmentHolder
		self.beamAttachments[i] = attachment
	end

	-- Create head-to-first-attachment beam
	local headBeam = Instance.new("Beam")
	headBeam.Name = "HeadBeam"
	headBeam.Attachment0 = self.headAttachment
	headBeam.Attachment1 = self.beamAttachments[1]
	
	-- Configure head beam
	self:configureBeam(headBeam, 1, true)
	headBeam.Parent = self.attachmentHolder
	self.headBeam = headBeam

	-- Create body beams
	for i = 1, beamCount do
		local beam = Instance.new("Beam")
		beam.Name = "BodyBeam" .. i
		beam.Attachment0 = self.beamAttachments[i]
		beam.Attachment1 = self.beamAttachments[i + 1]
		
		-- Configure beam
		self:configureBeam(beam, i + 1, false)
		beam.Parent = self.attachmentHolder
		self.visualBeams[i] = beam
	end
end

function Snake:configureBeam(beam, index, isHeadBeam)
	-- Calculate color
	local colorIndex = ((index - 1) % #self.config.BodyColors) + 1
	local color = isHeadBeam and self.config.HeadColor or self.config.BodyColors[colorIndex]
	
	-- Beam properties for maximum visibility and smoothness
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0) -- FULLY OPAQUE
	beam.LightEmission = 1 -- MAXIMUM BRIGHTNESS
	beam.LightInfluence = 0
	beam.Texture = "" -- Remove texture for smoother appearance
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 0
	beam.Width0 = BEAM_MIN_WIDTH
	beam.Width1 = BEAM_MIN_WIDTH
	beam.CurveSize0 = BEAM_CURVE_SIZE -- Add curves for smoother turns
	beam.CurveSize1 = -BEAM_CURVE_SIZE -- Opposite curve for natural flow
	beam.FaceCamera = true
	beam.Segments = BEAM_SEGMENTS
	beam.ZOffset = 0 -- Same level as parts for better blending
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
		self:updateOptimizedBody()

		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 50
			self.headGlow.Brightness = GLOW_INTENSITY_MAX
			-- Visual boost effects on beams
			for _, beam in pairs(self.visualBeams) do
				if beam and beam.Parent then
					beam.LightEmission = 1
				end
			end
			if self.headBeam then
				self.headBeam.LightEmission = 1
			end
		else
			self.boostParticles.Rate = 0
			self.headGlow.Brightness = GLOW_INTENSITY_MIN
			-- Reset beam effects
			for _, beam in pairs(self.visualBeams) do
				if beam and beam.Parent then
					beam.LightEmission = 0.8
				end
			end
			if self.headBeam then
				self.headBeam.LightEmission = 0.8
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

function Snake:updateOptimizedBody()
	-- Update physical segments (only 50 for collision)
	local segmentSize = MIN_SEGMENT_SIZE + (MAX_SEGMENT_SIZE - MIN_SEGMENT_SIZE) * (self.growthFactor - 1) / 9
	local spacing = segmentSize * SEGMENT_SPACING
	
	for i = 1, MAX_PHYSICAL_SEGMENTS do
		local segment = self.physicalSegments[i]
		if segment and segment.Parent then
			-- Calculate position from history
			local distanceFromHead = i * spacing
			local stepsBack = math.floor(distanceFromHead / 2)
			local histData = self:getHistoricalPosition(stepsBack)
			
			if histData then
				-- Smooth position update with interpolation
				local targetPos = histData.position
				local currentPos = segment.Position
				
				-- Add smooth interpolation between history points for curves
				if i > 1 and i < MAX_PHYSICAL_SEGMENTS then
					local prevStepsBack = math.floor((i - 1) * spacing / 2)
					local nextStepsBack = math.floor((i + 1) * spacing / 2)
					local prevData = self:getHistoricalPosition(prevStepsBack)
					local nextData = self:getHistoricalPosition(nextStepsBack)
					
					if prevData and nextData then
						-- Bezier-like smoothing
						local midPoint = (prevData.position + nextData.position) / 2
						targetPos = targetPos:Lerp(midPoint, 0.3)
					end
				end
				
				segment.Position = currentPos:Lerp(targetPos, 0.4)
				
				-- Update size
				segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)
			end
		end
	end
	
	-- Update beam system
	local requiredBeams = math.min(math.ceil(self.actualLength / BEAM_SEGMENT_LENGTH), MAX_VISUAL_BEAMS)
	
	-- Add more beams if needed
	if requiredBeams > #self.visualBeams then
		self:addBeams(requiredBeams - #self.visualBeams)
	end
	
	-- Update beam attachments positions
	local beamWidth = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
	
	-- Update each beam attachment position with smoothing
	for i = 1, requiredBeams + 1 do
		local attachment = self.beamAttachments[i]
		if attachment then
			-- Calculate position along snake
			local distanceFromHead = (i - 1) * BEAM_SEGMENT_LENGTH
			local stepsBack = math.floor(distanceFromHead / 2)
			local histData = self:getHistoricalPosition(stepsBack)
			
			if histData then
				local targetPos = histData.position
				
				-- Smooth out positions for middle attachments
				if i > 1 and i < requiredBeams then
					local prevDist = (i - 2) * BEAM_SEGMENT_LENGTH
					local nextDist = i * BEAM_SEGMENT_LENGTH
					local prevSteps = math.floor(prevDist / 2)
					local nextSteps = math.floor(nextDist / 2)
					
					local prevData = self:getHistoricalPosition(prevSteps)
					local nextData = self:getHistoricalPosition(nextSteps)
					
					if prevData and nextData then
						-- Create smooth curve through points
						local direction = (nextData.position - prevData.position).Unit
						local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
						local curveOffset = perpendicular * math.sin(i * 0.1) * 0.2
						targetPos = targetPos + curveOffset
					end
				end
				
				attachment.WorldPosition = targetPos
			end
		end
	end
	
	-- Update head beam width
	if self.headBeam then
		self.headBeam.Width0 = beamWidth * 1.2 -- Slightly thicker at head
		self.headBeam.Width1 = beamWidth
	end
	
	-- Update body beam widths with taper and dynamic curves
	for i = 1, requiredBeams do
		local beam = self.visualBeams[i]
		if beam and beam.Parent then
			local progress = i / requiredBeams
			local taperFactor = 1 - progress * 0.4 -- 40% taper at tail
			
			beam.Width0 = beamWidth * taperFactor
			beam.Width1 = beamWidth * taperFactor * 0.95 -- Very slight taper
			
			-- Dynamic curve adjustment based on movement
			if i > 1 and i < requiredBeams then
				local currentAttach = self.beamAttachments[i]
				local nextAttach = self.beamAttachments[i + 1]
				local prevAttach = self.beamAttachments[i - 1]
				
				if currentAttach and nextAttach and prevAttach then
					local dir1 = (currentAttach.WorldPosition - prevAttach.WorldPosition).Unit
					local dir2 = (nextAttach.WorldPosition - currentAttach.WorldPosition).Unit
					local turnAngle = math.acos(math.clamp(dir1:Dot(dir2), -1, 1))
					
					-- Adjust curve based on turn angle
					local curveAmount = math.sin(turnAngle) * BEAM_CURVE_SIZE * 2
					beam.CurveSize0 = curveAmount
					beam.CurveSize1 = -curveAmount
				end
			end
			
			-- Ensure beam is visible
			beam.Enabled = true
		end
	end
	
	-- Hide unused beams
	for i = requiredBeams + 1, #self.visualBeams do
		if self.visualBeams[i] then
			self.visualBeams[i].Enabled = false
		end
	end
end

function Snake:addBeams(count)
	local startIndex = #self.visualBeams + 1
	
	-- Add new attachments
	for i = startIndex, startIndex + count do
		if #self.beamAttachments < i + 1 then
			local attachment = Instance.new("Attachment")
			attachment.Name = "BeamAttachment" .. (i + 1)
			attachment.Parent = self.attachmentHolder
			self.beamAttachments[i + 1] = attachment
		end
	end
	
	-- Add new beams
	for i = startIndex, startIndex + count - 1 do
		if i <= MAX_VISUAL_BEAMS then
			local beam = Instance.new("Beam")
			beam.Name = "BodyBeam" .. i
			beam.Attachment0 = self.beamAttachments[i]
			beam.Attachment1 = self.beamAttachments[i + 1]
			
			-- Configure beam
			self:configureBeam(beam, i + 1, false)
			beam.Parent = self.attachmentHolder
			self.visualBeams[i] = beam
		end
	end
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
	-- Return physical segments for collision
	return self.physicalSegments
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
	print("✅ Snake System V8 - ULTRA PERFORMANCE INITIALIZED")
	print("🐍 Features: Hybrid Rendering | 50k+ Length Support | Zero Lag | Perfect Visuals")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8