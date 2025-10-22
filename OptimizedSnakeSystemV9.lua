-- Optimized Snake System V9 - ANGULAR BEAST EDITION
-- Complete revamp with square/rectangular design using pure beam-based rendering
-- No more round parts - everything is angular and sharp!

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_PHYSICAL_SEGMENTS = 50 -- Invisible collision boxes
local MAX_VISUAL_BEAMS = 300 -- More beams for smoother look
local SEGMENT_SPACING = 0.5 -- Tighter for continuous look
local HISTORY_SIZE = 5000 -- Massive history
local GROWTH_CHECK_INTERVAL = 10
local BEAM_SEGMENT_LENGTH = 15 -- Shorter segments for more detail

-- Smoothing Constants
local POSITION_SMOOTHING = 0.35
local CURVE_SMOOTHING_FACTOR = 0.25
local TURNING_SMOOTHNESS = 0.92

-- Visual Constants - ANGULAR DESIGN
local MIN_HEAD_SIZE = 4
local MAX_HEAD_SIZE = 14
local MIN_SEGMENT_WIDTH = 3
local MAX_SEGMENT_WIDTH = 12
local GLOW_INTENSITY_MIN = 2
local GLOW_INTENSITY_MAX = 5
local BEAM_SEGMENTS = 1 -- Low segments for sharp edges!
local HEAD_BEAM_LENGTH = 8 -- Length of head "square"

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

-- ANGULAR Snake Class
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

	-- Hide character completely
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
	self.model.Name = "AngularSnake_" .. self.player.Name
	self.model.Parent = workspace

	-- Component arrays
	self.physicalSegments = {} -- Invisible collision boxes
	self.visualBeams = {} -- Main body beams
	self.beamAttachments = {} -- Attachment points
	self.edgeBeams = {} -- For creating square edges

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

	-- Initialize
	self:createAngularHead()
	self:createAngularBody()
	self:startUpdateLoop()

	print("✅ ANGULAR Snake created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	local length = self.actualLength

	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 1.5
	elseif length <= 1000 then
		return 2.5 + (length - 200) / 800 * 2.5
	elseif length <= 5000 then
		return 5.0 + (length - 1000) / 4000 * 3.0
	else
		return 8.0 + math.min((length - 5000) / 10000 * 2.0, 2.0)
	end
end

function Snake:createAngularHead()
	-- Create invisible head part for collision and attachment
	local headPart = Instance.new("Part")
	headPart.Name = "SnakeHeadCollider"
	headPart.Transparency = 1
	headPart.Size = Vector3.new(MIN_HEAD_SIZE, MIN_HEAD_SIZE, MIN_HEAD_SIZE)
	headPart.CanCollide = false
	headPart.CanTouch = true
	headPart.CanQuery = true
	headPart.Anchored = true
	headPart.Parent = self.model

	-- Collision tagging
	CollectionService:AddTag(headPart, "SnakeHead")
	headPart:SetAttribute("PlayerId", self.player.UserId)

	-- Create attachment holder for head
	local headAttachmentPart = Instance.new("Part")
	headAttachmentPart.Name = "HeadAttachmentHolder"
	headAttachmentPart.Transparency = 1
	headAttachmentPart.CanCollide = false
	headAttachmentPart.CanQuery = false
	headAttachmentPart.Anchored = true
	headAttachmentPart.Size = Vector3.new(1, 1, 1)
	headAttachmentPart.Parent = self.model

	-- Create square head using 4 beams forming edges
	local headColor = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
	
	-- Create 8 attachments for cube corners
	local corners = {
		Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1),
		Vector3.new(1, 1, -1), Vector3.new(-1, 1, -1),
		Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1),
		Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1)
	}
	
	self.headCorners = {}
	for i, offset in ipairs(corners) do
		local attachment = Instance.new("Attachment")
		attachment.Name = "HeadCorner" .. i
		attachment.Parent = headAttachmentPart
		attachment.Position = offset * 2 -- Scale up
		self.headCorners[i] = attachment
	end

	-- Create main head attachment for body connection
	local mainHeadAttachment = Instance.new("Attachment")
	mainHeadAttachment.Name = "MainHeadAttachment"
	mainHeadAttachment.Parent = headAttachmentPart
	mainHeadAttachment.Position = Vector3.new(0, 0, 2) -- Back of head
	self.headAttachment = mainHeadAttachment

	-- Create 12 edge beams to form cube
	local edges = {
		{1, 2}, {2, 3}, {3, 4}, {4, 1}, -- Front face
		{5, 6}, {6, 7}, {7, 8}, {8, 5}, -- Back face
		{1, 5}, {2, 6}, {3, 7}, {4, 8}  -- Connecting edges
	}

	self.headBeams = {}
	for i, edge in ipairs(edges) do
		local beam = Instance.new("Beam")
		beam.Name = "HeadEdge" .. i
		beam.Attachment0 = self.headCorners[edge[1]]
		beam.Attachment1 = self.headCorners[edge[2]]
		
		-- Configure for sharp angular look
		beam.Color = ColorSequence.new(headColor)
		beam.Transparency = NumberSequence.new(0)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = MIN_HEAD_SIZE * 0.3
		beam.Width1 = MIN_HEAD_SIZE * 0.3
		beam.FaceCamera = true
		beam.Segments = 1 -- Sharp edges!
		
		beam.Parent = headAttachmentPart
		self.headBeams[i] = beam
	end

	-- Add face beams for filled look
	local faces = {
		{1, 2, 3, 4}, -- Front
		{5, 6, 7, 8}, -- Back
		{1, 2, 6, 5}, -- Bottom
		{3, 4, 8, 7}, -- Top
		{1, 4, 8, 5}, -- Left
		{2, 3, 7, 6}  -- Right
	}

	self.headFaceBeams = {}
	for i, face in ipairs(faces) do
		-- Create diagonal beams for each face
		local beam1 = Instance.new("Beam")
		beam1.Name = "HeadFace" .. i .. "A"
		beam1.Attachment0 = self.headCorners[face[1]]
		beam1.Attachment1 = self.headCorners[face[3]]
		
		beam1.Color = ColorSequence.new(headColor)
		beam1.Transparency = NumberSequence.new(0.7) -- Semi-transparent for layered look
		beam1.LightEmission = 0.5
		beam1.LightInfluence = 0
		beam1.Width0 = MIN_HEAD_SIZE * 2
		beam1.Width1 = MIN_HEAD_SIZE * 2
		beam1.FaceCamera = true
		beam1.Segments = 1
		
		beam1.Parent = headAttachmentPart
		table.insert(self.headFaceBeams, beam1)
	end

	-- Epic glow effect
	local glow = Instance.new("PointLight")
	glow.Name = "HeadGlow"
	glow.Brightness = GLOW_INTENSITY_MIN
	glow.Range = 20
	glow.Color = headColor
	glow.Shadows = false
	glow.Parent = headPart

	-- Angular particle effect for boost
	local particle = Instance.new("ParticleEmitter")
	particle.Name = "BoostParticles"
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(headColor)
	particle.Lifetime = NumberRange.new(0.5, 1)
	particle.Rate = 0
	particle.Speed = NumberRange.new(10)
	particle.SpreadAngle = Vector2.new(45, 45) -- Angular spread
	particle.VelocityInheritance = 0.5
	particle.EmissionDirection = Enum.NormalId.Back
	particle.Enabled = false
	particle.Parent = headPart

	-- Store references
	self.headPart = headPart
	self.headAttachmentPart = headAttachmentPart
	self.headGlow = glow
	self.boostParticles = particle
end

function Snake:createAngularBody()
	-- Create main attachment holder
	local attachmentHolder = Instance.new("Part")
	attachmentHolder.Name = "BodyAttachmentHolder"
	attachmentHolder.Transparency = 1
	attachmentHolder.CanCollide = false
	attachmentHolder.CanQuery = false
	attachmentHolder.Anchored = true
	attachmentHolder.Size = Vector3.new(1, 1, 1)
	attachmentHolder.Parent = self.model
	self.attachmentHolder = attachmentHolder

	-- Create invisible collision segments
	for i = 1, MAX_PHYSICAL_SEGMENTS do
		local segment = Instance.new("Part")
		segment.Name = "CollisionSegment" .. i
		segment.Transparency = 1
		segment.Size = Vector3.new(MIN_SEGMENT_WIDTH, MIN_SEGMENT_WIDTH, MIN_SEGMENT_WIDTH)
		segment.CanCollide = false
		segment.CanTouch = true
		segment.CanQuery = false
		segment.Anchored = true
		segment.Parent = self.model
		
		self.physicalSegments[i] = segment

		-- Collision tagging
		CollectionService:AddTag(segment, "SnakeSegment")
		segment:SetAttribute("SegmentIndex", i)
		segment:SetAttribute("OwnerName", self.player.Name)
	end

	-- Setup angular beam system
	self:setupAngularBeamSystem()
end

function Snake:setupAngularBeamSystem()
	local beamCount = math.min(math.ceil(self.actualLength / BEAM_SEGMENT_LENGTH), MAX_VISUAL_BEAMS)

	-- Create attachment pairs for rectangular segments
	for i = 1, beamCount + 1 do
		-- Each segment needs 4 attachments for rectangular shape
		local attachments = {}
		for j = 1, 4 do
			local attachment = Instance.new("Attachment")
			attachment.Name = "BeamAttachment" .. i .. "_Corner" .. j
			attachment.Parent = self.attachmentHolder
			attachments[j] = attachment
		end
		self.beamAttachments[i] = attachments
	end

	-- Create connection from head to first segment
	local headConnector = Instance.new("Beam")
	headConnector.Name = "HeadConnector"
	headConnector.Attachment0 = self.headAttachment
	headConnector.Attachment1 = self.beamAttachments[1][1] -- Connect to first corner
	
	self:configureAngularBeam(headConnector, 0, true)
	headConnector.Parent = self.attachmentHolder
	self.headConnector = headConnector

	-- Create rectangular segments using beams
	for i = 1, beamCount do
		local segmentBeams = {}
		
		-- Create 4 edge beams for each segment
		for j = 1, 4 do
			local beam = Instance.new("Beam")
			beam.Name = "Segment" .. i .. "_Edge" .. j
			
			local nextJ = j % 4 + 1
			beam.Attachment0 = self.beamAttachments[i][j]
			beam.Attachment1 = self.beamAttachments[i][nextJ]
			
			self:configureAngularBeam(beam, i, false)
			beam.Parent = self.attachmentHolder
			segmentBeams[j] = beam
		end
		
		-- Create connecting beams to next segment
		if i < beamCount then
			for j = 1, 4 do
				local connectBeam = Instance.new("Beam")
				connectBeam.Name = "Connect" .. i .. "_" .. j
				connectBeam.Attachment0 = self.beamAttachments[i][j]
				connectBeam.Attachment1 = self.beamAttachments[i + 1][j]
				
				self:configureAngularBeam(connectBeam, i, false)
				connectBeam.Parent = self.attachmentHolder
				segmentBeams[4 + j] = connectBeam
			end
		end
		
		self.visualBeams[i] = segmentBeams
	end
end

function Snake:configureAngularBeam(beam, index, isHeadBeam)
	local colorIndex = ((index - 1) % #self.config.BodyColors) + 1
	local color = isHeadBeam and self.config.HeadColor or self.config.BodyColors[colorIndex]

	-- Sharp angular beam properties
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Texture = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 2
	beam.TextureSpeed = self.isBoosting and 3 or 0
	beam.Width0 = MIN_SEGMENT_WIDTH
	beam.Width1 = MIN_SEGMENT_WIDTH
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.FaceCamera = true
	beam.Segments = 1 -- CRITICAL: Keep segments at 1 for sharp edges!
	beam.ZOffset = -0.1
end

function Snake:updatePositionHistory()
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector

	local lastEntry = self.positionHistory[self.historyIndex] or {position = currentPos, lookVector = currentLook}
	local distance = (currentPos - lastEntry.position).Magnitude

	if distance > 0.1 then
		-- Less interpolation for sharper movement
		local steps = math.min(math.floor(distance / 0.8), 2)

		for i = 1, steps do
			local t = i / (steps + 1)
			local interpPos = lastEntry.position:Lerp(currentPos, t)
			local interpLook = lastEntry.lookVector:Lerp(currentLook, t).Unit

			self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
			self.positionHistory[self.historyIndex] = {
				position = interpPos,
				lookVector = interpLook,
				time = tick()
			}
		end
	end

	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = {
		position = currentPos,
		lookVector = currentLook,
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

function Snake:getSmoothPosition(stepsBack)
	-- Less aggressive smoothing for more angular movement
	local p2 = self:getHistoricalPosition(math.max(0, stepsBack - 1))
	local p3 = self:getHistoricalPosition(stepsBack)
	local p4 = self:getHistoricalPosition(stepsBack + 1)

	if not p2 or not p3 or not p4 then
		return p3 or self.positionHistory[self.historyIndex]
	end

	-- Simple linear interpolation for sharper turns
	local blend = 0.3
	local smoothedPos = p3.position:Lerp(p2.position, blend * 0.5):Lerp(p4.position, blend * 0.5)
	
	return {
		position = smoothedPos,
		lookVector = p3.lookVector,
		time = p3.time
	}
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
		self:updateAngularHead()
		self:updateAngularBody()

		-- Handle boost effects
		if self.isBoosting then
			self.boostParticles.Rate = 100
			self.headGlow.Brightness = GLOW_INTENSITY_MAX
			-- Update all beam speeds
			for _, beamSet in pairs(self.visualBeams) do
				for _, beam in pairs(beamSet) do
					if beam and beam.Parent then
						beam.TextureSpeed = 3
					end
				end
			end
		else
			self.boostParticles.Rate = 0
			self.headGlow.Brightness = GLOW_INTENSITY_MIN
			-- Reset beam speeds
			for _, beamSet in pairs(self.visualBeams) do
				for _, beam in pairs(beamSet) do
					if beam and beam.Parent then
						beam.TextureSpeed = 0
					end
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

function Snake:updateAngularHead()
	-- Update head size
	local headSize = MIN_HEAD_SIZE + (MAX_HEAD_SIZE - MIN_HEAD_SIZE) * (self.growthFactor - 1) / 9
	
	-- Update collision part
	self.headPart.Size = Vector3.new(headSize, headSize, headSize)
	self.headPart.CFrame = self.rootPart.CFrame

	-- Update attachment holder
	self.headAttachmentPart.CFrame = self.rootPart.CFrame

	-- Scale corner positions
	local scale = headSize / MIN_HEAD_SIZE
	for i, corner in ipairs(self.headCorners) do
		local basePos = (i <= 4) and 
			Vector3.new(((i-1)%2)*2-1, math.floor((i-1)/2)%2*2-1, -1) or
			Vector3.new(((i-5)%2)*2-1, math.floor((i-5)/2)%2*2-1, 1)
		corner.Position = basePos * scale
	end

	-- Update beam widths
	local beamWidth = headSize * 0.3
	for _, beam in ipairs(self.headBeams) do
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
	end

	-- Update face beams
	for _, beam in ipairs(self.headFaceBeams) do
		beam.Width0 = headSize * 2
		beam.Width1 = headSize * 2
	end

	-- Update glow
	self.headGlow.Range = 15 + headSize * 2
end

function Snake:updateAngularBody()
	-- Update collision segments
	local segmentSize = MIN_SEGMENT_WIDTH + (MAX_SEGMENT_WIDTH - MIN_SEGMENT_WIDTH) * (self.growthFactor - 1) / 9
	local spacing = segmentSize * SEGMENT_SPACING * 1.2 -- Slightly more spacing for angular look

	for i = 1, MAX_PHYSICAL_SEGMENTS do
		local segment = self.physicalSegments[i]
		if segment and segment.Parent then
			local distanceFromHead = i * spacing * 2
			local stepsBack = math.floor(distanceFromHead / 2)
			local histData = self:getSmoothPosition(stepsBack)

			if histData then
				segment.Position = histData.position
				segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)
			end
		end
	end

	-- Update beam system
	local requiredBeams = math.min(math.ceil(self.actualLength / BEAM_SEGMENT_LENGTH), MAX_VISUAL_BEAMS)
	
	-- Add more beams if needed
	if requiredBeams > #self.visualBeams then
		self:addAngularBeams(requiredBeams - #self.visualBeams)
	end

	-- Update beam positions and sizes
	local beamWidth = MIN_SEGMENT_WIDTH + (MAX_SEGMENT_WIDTH - MIN_SEGMENT_WIDTH) * (self.growthFactor - 1) / 9

	for i = 1, requiredBeams do
		if self.beamAttachments[i] then
			-- Calculate segment position
			local distanceFromHead = (i - 1) * BEAM_SEGMENT_LENGTH
			local stepsBack = math.floor(distanceFromHead / 2)
			local histData = self:getSmoothPosition(stepsBack)

			if histData then
				-- Calculate rotation from look vector
				local cf = CFrame.lookAt(histData.position, histData.position + histData.lookVector)
				
				-- Position rectangular corners
				local halfWidth = segmentSize * 0.5
				local offsets = {
					Vector3.new(-halfWidth, -halfWidth, 0),
					Vector3.new(halfWidth, -halfWidth, 0),
					Vector3.new(halfWidth, halfWidth, 0),
					Vector3.new(-halfWidth, halfWidth, 0)
				}

				for j = 1, 4 do
					local attachment = self.beamAttachments[i][j]
					if attachment then
						attachment.WorldPosition = cf:PointToWorldSpace(offsets[j])
					end
				end
			end
		end

		-- Update beam widths with taper
		local beamSet = self.visualBeams[i]
		if beamSet then
			local progress = i / requiredBeams
			local taperFactor = 1 - progress * 0.3 -- 30% taper

			for _, beam in pairs(beamSet) do
				if beam and beam.Parent then
					beam.Width0 = beamWidth * taperFactor
					beam.Width1 = beamWidth * taperFactor
					beam.Enabled = true
				end
			end
		end
	end

	-- Hide unused beams
	for i = requiredBeams + 1, #self.visualBeams do
		local beamSet = self.visualBeams[i]
		if beamSet then
			for _, beam in pairs(beamSet) do
				if beam then
					beam.Enabled = false
				end
			end
		end
	end
end

function Snake:addAngularBeams(count)
	local startIndex = #self.visualBeams + 1

	-- Add new attachment sets
	for i = startIndex, startIndex + count do
		if #self.beamAttachments < i + 1 then
			local attachments = {}
			for j = 1, 4 do
				local attachment = Instance.new("Attachment")
				attachment.Name = "BeamAttachment" .. (i + 1) .. "_Corner" .. j
				attachment.Parent = self.attachmentHolder
				attachments[j] = attachment
			end
			self.beamAttachments[i + 1] = attachments
		end
	end

	-- Add new beam sets
	for i = startIndex, startIndex + count - 1 do
		if i <= MAX_VISUAL_BEAMS then
			local segmentBeams = {}
			
			-- Create edge beams
			for j = 1, 4 do
				local beam = Instance.new("Beam")
				beam.Name = "Segment" .. i .. "_Edge" .. j
				
				local nextJ = j % 4 + 1
				beam.Attachment0 = self.beamAttachments[i][j]
				beam.Attachment1 = self.beamAttachments[i][nextJ]
				
				self:configureAngularBeam(beam, i, false)
				beam.Parent = self.attachmentHolder
				segmentBeams[j] = beam
			end
			
			-- Create connecting beams
			if i < startIndex + count - 1 then
				for j = 1, 4 do
					local connectBeam = Instance.new("Beam")
					connectBeam.Name = "Connect" .. i .. "_" .. j
					connectBeam.Attachment0 = self.beamAttachments[i][j]
					connectBeam.Attachment1 = self.beamAttachments[i + 1][j]
					
					self:configureAngularBeam(connectBeam, i, false)
					connectBeam.Parent = self.attachmentHolder
					segmentBeams[4 + j] = connectBeam
				end
			end
			
			self.visualBeams[i] = segmentBeams
		end
	end
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
		-- Angular speed lines
		for i = 1, 8 do
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.3, 0.3, 15)
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.config.HeadColor or Color3.fromRGB(0, 255, 100)
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.headPart.CFrame * 
				CFrame.Angles(0, math.rad(i * 45), 0) * 
				CFrame.new(0, 0, -8)
			speedLine.Parent = self.model

			local tween = TweenService:Create(speedLine, 
				TweenInfo.new(0.4, Enum.EasingStyle.Linear), 
				{Transparency = 1, Size = Vector3.new(0.1, 0.1, 25)}
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
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	createNetworkEvents()
	print("✅ Snake System V9 - ANGULAR BEAST EDITION INITIALIZED")
	print("🔲 Features: Pure Angular Design | Square Head | Rectangular Body | Sharp Edges")
	print("⚡ Performance: 50k+ Length | Zero Lag | Beam-Based Rendering")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9