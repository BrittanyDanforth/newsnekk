-- Optimized Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING
-- Perfect head-body integration with consistent glow and zero visual artifacts

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

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 3 -- Consistent glow throughout
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 25 -- High quality curves
local BEAM_WIDTH_RATIO = 1.1 -- Beam slightly wider than parts
local HEAD_BLEND_SEGMENTS = 5 -- Segments to blend head into body
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments

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
	head.Size = Vector3.new(BASE_SIZE, BASE_SIZE, BASE_SIZE)
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
	headGlow.Range = GLOW_RANGE_BASE
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
		segment.Size = Vector3.new(BASE_SIZE, BASE_SIZE, BASE_SIZE)
		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Collision for first 50
		segment.CanQuery = false
		segment.Anchored = true
		
		-- Smooth color transition from head to body
		local colorIndex
		if i <= HEAD_BLEND_SEGMENTS then
			-- Blend head color into body colors
			local blendFactor = i / HEAD_BLEND_SEGMENTS
			local headColor = self.config.HeadColor or self.config.BodyColors[1]
			local bodyColor = self.config.BodyColors[1]
			segment.Color = headColor:Lerp(bodyColor, blendFactor)
		else
			-- Regular body pattern
			colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
		end
		
		-- Strategic glow placement for performance
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = true -- All segments up to falloff
		elseif i <= 100 then
			shouldHaveGlow = i % 2 == 0 -- Every other segment
		elseif i <= 200 then
			shouldHaveGlow = i % 3 == 0 -- Every third
		else
			shouldHaveGlow = i % 5 == 0 -- Every fifth
		end
		
		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.8 -- Slightly dimmer than head
			segmentGlow.Range = GLOW_RANGE_BASE * 0.8
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
		
		-- Beam properties for seamless connection
		beam.Width0 = BASE_SIZE * BEAM_WIDTH_RATIO
		beam.Width1 = BASE_SIZE * BEAM_WIDTH_RATIO
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
		
		-- Color matching
		if i == 0 then
			-- Head to first segment
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, self.segments[0].Color),
				ColorSequenceKeypoint.new(1, self.segments[1].Color)
			})
		elseif i < HEAD_BLEND_SEGMENTS then
			-- Blending region
			beam.Color = ColorSequence.new(self.segments[i].Color)
		else
			-- Regular body colors
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		end
		
		beam.Parent = attachmentPart
		self.beams[i] = beam
	end
	
	-- Create overlap beams for gap prevention
	for i = 0, math.min(segmentCount - 2, 100) do
		if i % 2 == 0 then -- Every other segment for performance
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = self.attachments[i]
			overlapBeam.Attachment1 = self.attachments[i + 2]
			
			overlapBeam.Width0 = BASE_SIZE * BEAM_WIDTH_RATIO * 1.2
			overlapBeam.Width1 = BASE_SIZE * BEAM_WIDTH_RATIO * 1.2
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			overlapBeam.TextureMode = Enum.TextureMode.Stretch
			overlapBeam.TextureLength = 3
			overlapBeam.LightEmission = 0.8
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.3) -- Semi-transparent for blending
			overlapBeam.ZOffset = 0.1
			
			-- Color
			local color = i == 0 and self.segments[0].Color or self.config.BodyColors[((i - 1) % #self.config.BodyColors) + 1]
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
		
		-- Update position history
		self:updatePositionHistory()
		
		-- Smooth length interpolation
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			self.actualLength = self.actualLength + diff * 0.1
		end
		
		-- Update growth factor
		if frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end
		
		-- Update visuals
		self:updateUnifiedBody()
		
		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 150
			-- Enhance all glows during boost
			for _, glow in pairs(self.glows) do
				if glow and glow.Parent then
					glow.Brightness = GLOW_INTENSITY * 1.5
				end
			end
		else
			self.boostParticles.Rate = 0
			-- Normal glow
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
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end
	
	-- Calculate sizes based on growth
	local currentSize = BASE_SIZE * self.growthFactor
	local spacing = currentSize * SEGMENT_SPACING
	
	-- Update all segments including head (segment 0)
	for i = 0, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			if i == 0 then
				-- Head positioning
				local cf = CFrame.lookAt(
					self.rootPart.Position,
					self.rootPart.Position + self.rootPart.CFrame.LookVector
				)
				segment.CFrame = cf
				segment.Size = Vector3.new(currentSize * 1.1, currentSize * 1.1, currentSize * 1.1) -- Slightly larger head
				
				-- Update eyes
				local eyeScale = currentSize / BASE_SIZE * 0.5
				local eyeOffset = currentSize * 0.3
				local eyeForward = -currentSize * 0.35
				
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
					-- Smooth interpolation
					local alpha = (i * spacing / 2) % 1
					local targetPos = histData.position:Lerp(nextHistData.position, alpha)
					local currentPos = segment.Position
					segment.Position = currentPos:Lerp(targetPos, 0.5)
					
					-- Size with subtle taper
					local taper = 1 - (i / self.visibleSegmentCount) * 0.2 -- Only 20% taper
					segment.Size = Vector3.new(
						currentSize * taper,
						currentSize * taper,
						currentSize * taper
					)
					
					-- Pulse effect during boost
					if self.isBoosting then
						local pulse = math.sin(tick() * 10 + i * 0.1) * 0.05 + 1
						segment.Size = segment.Size * pulse
					end
				end
			end
			
			-- Update attachment position
			if self.attachments[i] then
				self.attachments[i].WorldPosition = segment.Position
			end
		end
	end
	
	-- Update all beams
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				-- Regular beams
				if i <= self.visibleSegmentCount then
					local width = currentSize * BEAM_WIDTH_RATIO
					local taper = 1 - (i / self.visibleSegmentCount) * 0.2
					
					beam.Width0 = width * taper
					beam.Width1 = width * taper
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
			else
				-- Overlap beams
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 2 then
					local width = currentSize * BEAM_WIDTH_RATIO * 1.2
					beam.Width0 = width
					beam.Width1 = width
					beam.Enabled = true
				else
					beam.Enabled = false
				end
			end
		end
	end
	
	-- Update glow ranges based on size
	for i, glow in pairs(self.glows) do
		if glow and glow.Parent then
			glow.Range = GLOW_RANGE_BASE + (currentSize - BASE_SIZE) * 2
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
		segment.Size = Vector3.new(BASE_SIZE, BASE_SIZE, BASE_SIZE)
		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true
		
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		
		-- Add glow based on falloff rules
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
			segmentGlow.Brightness = GLOW_INTENSITY * 0.8
			segmentGlow.Range = GLOW_RANGE_BASE * 0.8
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end
		
		segment.Parent = self.model
		self.segments[i] = segment
		
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
			
			beam.Width0 = BASE_SIZE * BEAM_WIDTH_RATIO
			beam.Width1 = BASE_SIZE * BEAM_WIDTH_RATIO
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureLength = 2
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(0)
			
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
			
			beam.Parent = self.attachmentPart
			self.beams[i - 1] = beam
		end
		
		-- Create overlap beam if needed
		if i > 2 and i % 2 == 0 and i <= 100 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. (i - 2)
			overlapBeam.Attachment0 = self.attachments[i - 2]
			overlapBeam.Attachment1 = self.attachments[i]
			
			overlapBeam.Width0 = BASE_SIZE * BEAM_WIDTH_RATIO * 1.2
			overlapBeam.Width1 = BASE_SIZE * BEAM_WIDTH_RATIO * 1.2
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
			overlapBeam.ZOffset = 0.1
			
			local overlapColorIndex = ((i - 3) % #self.config.BodyColors) + 1
			overlapBeam.Color = ColorSequence.new(self.config.BodyColors[overlapColorIndex])
			
			overlapBeam.Parent = self.attachmentPart
			self.beams["overlap" .. (i - 2)] = overlapBeam
		end
	end
	
	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

function Snake:grow(amount)
	self.targetLength = math.min(self.targetLength + (amount or 1), 50000)
	
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
	print("✅ Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING")
	print("🐍 Features: Unified Head-Body | Consistent Glow | Perfect Blending | Zero Artifacts")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9