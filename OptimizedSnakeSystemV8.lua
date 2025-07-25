-- Optimized Snake System V8 - ULTRA SMOOTH VISUAL BEAST
-- Dynamic growth, buttery smooth movement, no lag, no invisible bullshit

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60 -- 60 FPS baby
local NETWORK_UPDATE_RATE = 20 -- Network at 20 FPS
local MAX_SEGMENTS = 500 -- Maximum visible segments
local SEGMENT_SPACING = 0.8 -- Tighter spacing for smoother look
local HISTORY_SIZE = 2000 -- Large history for smooth trailing
local GROWTH_CHECK_INTERVAL = 10 -- Check growth every 10 frames

-- Visual Constants
local MIN_HEAD_SIZE = 3
local MAX_HEAD_SIZE = 12
local MIN_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 10
local GLOW_INTENSITY_MIN = 2  -- Increased from 1
local GLOW_INTENSITY_MAX = 5  -- Increased from 3
local BEAM_SEGMENTS = 20  -- Increased from 10 for smoother curves
local BEAM_MIN_WIDTH = 4  -- Increased from 2.5
local BEAM_MAX_WIDTH = 15  -- Increased from 10
local BEAM_LIGHT_EMISSION = 1  -- FULL GLOW
local BEAM_BRIGHTNESS = 2  -- Extra brightness

-- ... existing code ...

function Snake:createBody()
	-- Calculate initial segment count based on length
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

	-- Create physical segments for collision
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0 -- SOLID SEGMENTS
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Only first 50 segments for collision
		segment.CanQuery = false
		segment.Anchored = true

		-- Color pattern
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]

		-- Enhanced glow for ALL segments
		local segmentGlow = Instance.new("PointLight")
		segmentGlow.Brightness = i <= 20 and 1.5 or 0.8  -- Brighter glow
		segmentGlow.Range = i <= 20 and 12 or 8  -- Larger range
		segmentGlow.Color = segment.Color
		segmentGlow.Shadows = false
		segmentGlow.Parent = segment

		segment.Parent = self.model
		self.segments[i] = segment

		-- Collision tagging for first segments
		if i <= 50 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end

		-- Create attachments for beams
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

	-- Create SUPER VISIBLE beams between segments
	for i = 1, math.min(segmentCount, 100) do -- Limit beams for performance
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

		-- ULTRA ENHANCED beam visuals
		beam.Width0 = BEAM_MIN_WIDTH * 1.5  -- Wider beams
		beam.Width1 = BEAM_MIN_WIDTH * 1.5
		beam.CurveSize0 = -1  -- Slight curve for organic look
		beam.CurveSize1 = 1
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = ""  -- Remove texture for cleaner look
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.TextureSpeed = 0
		beam.LightEmission = BEAM_LIGHT_EMISSION  -- MAXIMUM GLOW
		beam.LightInfluence = 0
		beam.Brightness = BEAM_BRIGHTNESS  -- Extra brightness
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),     -- COMPLETELY SOLID at edges
			NumberSequenceKeypoint.new(0.2, 0),   -- SOLID
			NumberSequenceKeypoint.new(0.5, 0),   -- SOLID in middle
			NumberSequenceKeypoint.new(0.8, 0),   -- SOLID
			NumberSequenceKeypoint.new(1, 0)      -- COMPLETELY SOLID at edges
		})

		-- Vibrant color with gradient
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		local mainColor = self.config.BodyColors[colorIndex]
		local nextColorIndex = (colorIndex % #self.config.BodyColors) + 1
		local nextColor = self.config.BodyColors[nextColorIndex]
		
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, mainColor),
			ColorSequenceKeypoint.new(0.5, mainColor),
			ColorSequenceKeypoint.new(1, nextColor)
		})

		beam.Parent = attachmentPart
		self.beams[i] = beam
	end

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

-- ... existing code ...

function Snake:updateBody()
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > self.visibleSegmentCount then
		self:addSegments(requiredSegments - self.visibleSegmentCount)
	end

	-- Update each segment
	local segmentSize = MIN_SEGMENT_SIZE + (MAX_SEGMENT_SIZE - MIN_SEGMENT_SIZE) * (self.growthFactor - 1) / 9
	local spacing = segmentSize * SEGMENT_SPACING

	for i = 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate position from history
			local stepsBack = math.floor(i * spacing / 2)
			local histData = self:getHistoricalPosition(stepsBack)

			if histData then
				-- Smooth position update
				local targetPos = histData.position
				local currentPos = segment.Position
				segment.Position = currentPos:Lerp(targetPos, 0.3)

				-- Update size with less taper for fuller look
				local taper = 1 - (i / self.visibleSegmentCount) * 0.15 -- Only 15% taper
				segment.Size = Vector3.new(segmentSize * taper, segmentSize * taper, segmentSize * taper)

				-- Update attachment positions for beams
				if self.attachments[i] then
					self.attachments[i].WorldPosition = segment.Position
				end

				-- Update glow dynamically
				local glow = segment:FindFirstChild("PointLight")
				if glow then
					glow.Range = 8 + segmentSize * 1.5
					glow.Brightness = self.isBoosting and 2 or 1
				end
			end
		end
	end

	-- Update final attachment
	if self.attachments[self.visibleSegmentCount + 1] and self.segments[self.visibleSegmentCount] then
		self.attachments[self.visibleSegmentCount + 1].WorldPosition = self.segments[self.visibleSegmentCount].Position
	end

	-- Update beam widths and appearance - MAKE THEM THICC AND VISIBLE
	for i, beam in ipairs(self.beams) do
		if beam and beam.Parent and i <= self.visibleSegmentCount then
			local progress = i / self.visibleSegmentCount
			local width = (BEAM_MIN_WIDTH + (BEAM_MAX_WIDTH - BEAM_MIN_WIDTH) * (self.growthFactor - 1) / 9) * 1.5
			width = width * (1 - progress * 0.15) -- Less taper for fuller snake

			beam.Width0 = width
			beam.Width1 = width * 0.9  -- Slight taper between segments
			beam.LightEmission = BEAM_LIGHT_EMISSION
			beam.Brightness = self.isBoosting and 3 or BEAM_BRIGHTNESS

			-- ULTRA VISIBLE transparency
			if self.isBoosting then
				beam.Transparency = NumberSequence.new(0) -- FULLY SOLID
				beam.CurveSize0 = -2  -- More curve when boosting
				beam.CurveSize1 = 2
			else
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),    -- SOLID
					NumberSequenceKeypoint.new(0.5, 0),  -- SOLID
					NumberSequenceKeypoint.new(1, 0)     -- SOLID
				})
				beam.CurveSize0 = -1
				beam.CurveSize1 = 1
			end

			-- Pulsing effect for extra visibility
			if self.isBoosting then
				local pulse = math.sin(tick() * 10) * 0.2 + 1
				beam.Width0 = width * pulse
				beam.Width1 = width * 0.9 * pulse
			end
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
		segment.Size = Vector3.new(MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE, MIN_SEGMENT_SIZE)
		segment.Transparency = 0 -- SOLID NEW SEGMENTS
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		segment.Color = self.config.BodyColors[colorIndex]
		
		-- Add glow to new segments
		local segmentGlow = Instance.new("PointLight")
		segmentGlow.Brightness = 0.8
		segmentGlow.Range = 8
		segmentGlow.Color = segment.Color
		segmentGlow.Shadows = false
		segmentGlow.Parent = segment
		
		segment.Parent = self.model

		self.segments[i] = segment

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beam if within limit
		if i <= 100 and self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. i
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]

			-- SUPER VISIBLE beam properties
			beam.Width0 = BEAM_MIN_WIDTH * 1.5
			beam.Width1 = BEAM_MIN_WIDTH * 1.5
			beam.CurveSize0 = -1
			beam.CurveSize1 = 1
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = ""  -- Clean look
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureLength = 1
			beam.TextureSpeed = 0
			beam.LightEmission = BEAM_LIGHT_EMISSION
			beam.LightInfluence = 0
			beam.Brightness = BEAM_BRIGHTNESS
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),    -- SOLID
				NumberSequenceKeypoint.new(0.5, 0),  -- SOLID
				NumberSequenceKeypoint.new(1, 0)     -- SOLID
			})

			local colorIdx = ((i - 1) % #self.config.BodyColors) + 1
			local mainColor = self.config.BodyColors[colorIdx]
			local nextColorIdx = (colorIdx % #self.config.BodyColors) + 1
			local nextColor = self.config.BodyColors[nextColorIdx]
			
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, mainColor),
				ColorSequenceKeypoint.new(0.5, mainColor),
				ColorSequenceKeypoint.new(1, nextColor)
			})

			beam.Parent = self.attachmentPart
			self.beams[i] = beam
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

-- ... existing code ...