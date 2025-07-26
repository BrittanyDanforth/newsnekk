-- Optimized Snake System V8 Enhanced - SEAMLESS BEAM SNAKE
-- Pure beam-based rendering with no separate head orb

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_SEGMENTS = 500 -- Maximum visible segments
local SEGMENT_SPACING = 0.5 -- Very tight for seamless look
local HISTORY_SIZE = 2000 -- Large history for smooth trailing
local GROWTH_CHECK_INTERVAL = 10 -- Check growth every 10 frames

-- Visual Constants - UNIFIED BEAM LOOK
local MIN_SEGMENT_SIZE = 0.1 -- Tiny segments (just for position tracking)
local MAX_SEGMENT_SIZE = 0.1 -- Keep small since beams do the visuals
local GLOW_INTENSITY = 3 -- Consistent glow
local BEAM_SEGMENTS = 10 -- Balanced for performance
local BEAM_MIN_WIDTH = 3 -- Base width
local BEAM_MAX_WIDTH = 12 -- Max width for huge snakes
local HEAD_WIDTH_MULTIPLIER = 1.3 -- Head slightly bigger
local BEAM_TEXTURE = "rbxasset://textures/white.png" -- Solid texture

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

	-- Hide the character model
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

	-- Initialize
	self:createSnake()
	self:startUpdateLoop()

	print("✅ Seamless beam snake created for", self.player.Name)
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

function Snake:createSnake()
	-- Calculate initial segment count
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)

	-- Create attachment holder (invisible)
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(0.1, 0.1, 0.1)
	attachmentPart.Parent = self.model

	-- Create invisible segments for position tracking and collision
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Transparency = 1 -- INVISIBLE - beams do all the visuals
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.CanCollide = false
		segment.CanTouch = i <= 10 -- Only first 10 for head collision
		segment.CanQuery = false
		segment.Anchored = true
		segment.Parent = self.model

		self.segments[i] = segment

		-- Collision tagging for head area
		if i <= 10 then
			CollectionService:AddTag(segment, i == 1 and "SnakeHead" or "SnakeSegment")
			segment:SetAttribute("PlayerId", self.player.UserId)
			segment:SetAttribute("OwnerName", self.player.Name)
			segment:SetAttribute("SegmentIndex", i)
		end

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.attachments[i] = attachment
	end

	-- Add final attachment for tail
	local finalAttachment = Instance.new("Attachment")
	finalAttachment.Name = "AttachmentFinal"
	finalAttachment.Parent = attachmentPart
	self.attachments[segmentCount + 1] = finalAttachment

	-- Create unified beam snake
	self:createBeamBody(segmentCount)

	-- Add glow effect attachments
	self:createGlowEffects()

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

function Snake:createBeamBody(segmentCount)
	-- Calculate beam count (we'll create overlapping beams)
	local beamCount = math.min(segmentCount * 3, 300) -- Triple beams for coverage
	
	-- Create beams with different connection patterns
	for i = 1, beamCount do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		
		-- Determine connection pattern
		local startIdx, endIdx
		if i <= segmentCount then
			-- Primary beams: connect adjacent segments
			startIdx = i
			endIdx = i + 1
		elseif i <= segmentCount * 2 then
			-- Secondary beams: skip one segment
			local baseIdx = i - segmentCount
			startIdx = baseIdx
			endIdx = math.min(baseIdx + 2, segmentCount + 1)
		else
			-- Tertiary beams: skip two segments
			local baseIdx = i - segmentCount * 2
			startIdx = baseIdx
			endIdx = math.min(baseIdx + 3, segmentCount + 1)
		end
		
		-- Skip invalid connections
		if not self.attachments[startIdx] or not self.attachments[endIdx] then
			beam:Destroy()
			continue
		end
		
		beam.Attachment0 = self.attachments[startIdx]
		beam.Attachment1 = self.attachments[endIdx]
		
		-- Beam properties for seamless look
		local isHead = startIdx <= 3
		local isTail = endIdx >= segmentCount - 5
		local isPrimary = i <= segmentCount
		
		-- Width calculation
		local baseWidth = BEAM_MIN_WIDTH
		if isHead then
			baseWidth = baseWidth * HEAD_WIDTH_MULTIPLIER
		elseif isTail then
			baseWidth = baseWidth * 0.7 -- Taper at tail
		end
		
		beam.Width0 = baseWidth
		beam.Width1 = baseWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = BEAM_TEXTURE
		beam.TextureMode = Enum.TextureMode.Static
		beam.TextureLength = 1
		beam.TextureSpeed = 0
		beam.LightEmission = isPrimary and 0.8 or 0.6 -- Primary beams brighter
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(isPrimary and 0 or 0.3) -- Secondary/tertiary slightly transparent
		beam.ZOffset = isPrimary and 0 or (i <= segmentCount * 2 and -0.1 or -0.2)
		
		-- Color based on position
		local colorProgress = startIdx / segmentCount
		local colorIndex = math.floor(colorProgress * #self.config.BodyColors) + 1
		colorIndex = math.min(colorIndex, #self.config.BodyColors)
		
		-- Head uses head color, body uses body colors
		local beamColor = isHead and self.config.HeadColor or self.config.BodyColors[colorIndex]
		beam.Color = ColorSequence.new(beamColor)
		
		beam.Parent = self.attachmentPart
		self.beams[i] = beam
	end
end

function Snake:createGlowEffects()
	-- Create subtle glow points along the snake
	local glowInterval = math.max(10, self.visibleSegmentCount / 20) -- Glow every N segments
	
	for i = 1, self.visibleSegmentCount, glowInterval do
		if self.segments[i] then
			local glowPart = Instance.new("Part")
			glowPart.Name = "GlowPoint" .. i
			glowPart.Size = Vector3.new(0.1, 0.1, 0.1)
			glowPart.Transparency = 1
			glowPart.CanCollide = false
			glowPart.CanQuery = false
			glowPart.Anchored = true
			glowPart.Parent = self.model
			
			local light = Instance.new("PointLight")
			light.Brightness = i == 1 and GLOW_INTENSITY or GLOW_INTENSITY * 0.5
			light.Range = i == 1 and 15 or 10
			light.Color = i == 1 and self.config.HeadColor or self.config.BodyColors[1]
			light.Shadows = false
			light.Parent = glowPart
			
			-- Store reference
			if not self.glowParts then self.glowParts = {} end
			self.glowParts[i] = glowPart
		end
	end
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
			self.actualLength = self.actualLength + diff * 0.1
		end

		-- Update growth factor
		if frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end

		-- Update snake
		self:updateSnake()

		-- Network updates
		local now = tick()
		if self.player == Players.LocalPlayer and now - lastNetworkUpdate > 1/NETWORK_UPDATE_RATE then
			lastNetworkUpdate = now
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateSnake()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end

	-- Update segment positions (invisible, just for tracking)
	local segmentSpacing = SEGMENT_SPACING * self.growthFactor
	
	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate position from history
			local stepsBack = math.floor(i * segmentSpacing)
			local histData = self:getHistoricalPosition(stepsBack)
			
			if histData then
				-- Smooth position update
				local targetPos = histData.position
				local currentPos = segment.Position
				segment.Position = currentPos:Lerp(targetPos, 0.4)
				
				-- Update attachment position
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end
			end
		end
	end

	-- Update final attachment
	if self.attachments[self.visibleSegmentCount + 1] and self.segments[self.visibleSegmentCount] then
		self.attachments[self.visibleSegmentCount + 1].WorldPosition = self.segments[self.visibleSegmentCount].Position
	end

	-- Update glow positions
	if self.glowParts then
		for i, glowPart in pairs(self.glowParts) do
			if self.segments[i] then
				glowPart.Position = self.segments[i].Position
			end
		end
	end

	-- Update all beam widths based on growth
	local baseWidth = BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9
	
	for i, beam in ipairs(self.beams) do
		if beam and beam.Parent then
			-- Determine beam position
			local isPrimary = i <= self.visibleSegmentCount
			local startIdx = isPrimary and i or ((i - self.visibleSegmentCount - 1) % self.visibleSegmentCount + 1)
			
			-- Check if beam should be visible
			if startIdx <= self.visibleSegmentCount then
				beam.Enabled = true
				
				-- Calculate width with position-based scaling
				local isHead = startIdx <= 3
				local progress = startIdx / self.visibleSegmentCount
				local taper = 1 - progress * 0.3 -- 30% taper to tail
				
				local width = baseWidth * taper
				if isHead then
					width = width * HEAD_WIDTH_MULTIPLIER
				end
				
				beam.Width0 = width
				beam.Width1 = width
				
				-- Boost effects
				if self.isBoosting then
					beam.LightEmission = isPrimary and 1 or 0.8
					-- Pulse effect
					local pulse = math.sin(tick() * 10 + startIdx * 0.1) * 0.1 + 1
					beam.Width0 = beam.Width0 * pulse
					beam.Width1 = beam.Width1 * pulse
				else
					beam.LightEmission = isPrimary and 0.8 or 0.6
				end
			else
				beam.Enabled = false
			end
		end
	end
end

function Snake:addSegments(count)
	local startIdx = self.visibleSegmentCount + 1
	
	for i = startIdx, startIdx + count - 1 do
		if i > MAX_SEGMENTS then break end

		-- Create invisible segment
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Transparency = 1
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.CanCollide = false
		segment.CanTouch = false
		segment.CanQuery = false
		segment.Anchored = true
		segment.Parent = self.model

		self.segments[i] = segment

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beams for new segment
		local beamIdx = #self.beams + 1
		
		-- Primary beam
		if self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. beamIdx
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]
			
			beam.Width0 = BEAM_MIN_WIDTH
			beam.Width1 = BEAM_MIN_WIDTH
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = BEAM_TEXTURE
			beam.TextureMode = Enum.TextureMode.Static
			beam.LightEmission = 0.8
			beam.LightInfluence = 0
			beam.Transparency = NumberSequence.new(0)
			
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
			
			beam.Parent = self.attachmentPart
			self.beams[beamIdx] = beam
		end
		
		-- Secondary beams for coverage
		if i > 2 and self.attachments[i - 2] then
			beamIdx = beamIdx + 1
			local beam2 = Instance.new("Beam")
			beam2.Name = "Beam" .. beamIdx
			beam2.Attachment0 = self.attachments[i - 2]
			beam2.Attachment1 = self.attachments[i]
			
			beam2.Width0 = BEAM_MIN_WIDTH * 0.8
			beam2.Width1 = BEAM_MIN_WIDTH * 0.8
			beam2.CurveSize0 = 0
			beam2.CurveSize1 = 0
			beam2.FaceCamera = true
			beam2.Segments = BEAM_SEGMENTS
			beam2.Texture = BEAM_TEXTURE
			beam2.LightEmission = 0.6
			beam2.LightInfluence = 0
			beam2.Transparency = NumberSequence.new(0.3)
			beam2.ZOffset = -0.1
			
			local colorIndex = ((i - 2) % #self.config.BodyColors) + 1
			beam2.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
			
			beam2.Parent = self.attachmentPart
			self.beams[beamIdx] = beam2
		end
		
		-- Add glow point every N segments
		if i % 20 == 0 then
			local glowPart = Instance.new("Part")
			glowPart.Name = "GlowPoint" .. i
			glowPart.Size = Vector3.new(0.1, 0.1, 0.1)
			glowPart.Transparency = 1
			glowPart.CanCollide = false
			glowPart.CanQuery = false
			glowPart.Anchored = true
			glowPart.Parent = self.model
			
			local light = Instance.new("PointLight")
			light.Brightness = GLOW_INTENSITY * 0.5
			light.Range = 10
			light.Color = self.config.BodyColors[1]
			light.Shadows = false
			light.Parent = glowPart
			
			if not self.glowParts then self.glowParts = {} end
			self.glowParts[i] = glowPart
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

	-- Visual boost effects
	if boosting then
		-- Create boost particles at head
		if self.segments[1] then
			for i = 1, 5 do
				local particle = Instance.new("Part")
				particle.Name = "BoostParticle"
				particle.Size = Vector3.new(0.5, 0.5, 2)
				particle.Material = Enum.Material.Neon
				particle.Color = self.config.HeadColor
				particle.CanCollide = false
				particle.Anchored = true
				particle.CFrame = CFrame.lookAt(
					self.segments[1].Position + Vector3.new(math.random(-2, 2), math.random(-2, 2), 0),
					self.segments[1].Position
				)
				particle.Parent = self.model

				-- Fade and fly
				local tween = TweenService:Create(particle, 
					TweenInfo.new(0.5, Enum.EasingStyle.Linear), 
					{
						Transparency = 1, 
						Size = Vector3.new(0.1, 0.1, 5),
						Position = particle.Position - particle.CFrame.LookVector * 10
					}
				)
				tween:Play()
				Debris:AddItem(particle, 0.5)
			end
		end
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
	-- Return first 10 segments for collision (head area)
	local collisionSegments = {}
	for i = 1, math.min(10, self.visibleSegmentCount) do
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
	print("✅ Snake System V8 SEAMLESS - Pure Beam Rendering")
	print("🐍 Features: No Head Orb | Unified Look | Triple-Layer Beams")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8