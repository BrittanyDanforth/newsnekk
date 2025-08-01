-- AISnakeBodySetup Module
-- Adapted from OptimizedSnakeSystemV9 for AI Snakes
-- Provides the same visual quality as player snakes with optimized performance

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

-- Performance Constants from V9
local SEGMENT_UPDATE_RATE = 75
local MAX_SEGMENTS = 500
local SEGMENT_SPACING = 0.5
local GROWTH_CHECK_INTERVAL = 10

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5
local MAX_SIZE_MULTIPLIER = 3.5
local GLOW_INTENSITY = 2
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 10
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

-- Professional Visual Enhancement Constants
local BEAM_TEXTURE_SPEED = 2
local RAINBOW_SPEED = 2
local RAINBOW_SEGMENT_OFFSET = 0.1

-- Professional Texture Library
local BEAM_TEXTURES = {
	gradient = "rbxasset://textures/ui/LuaChat/9-slice/kit-modal-highlight.png",
	flow = "rbxasset://textures/ui/GuiImagePlaceholder.png",
	energy = "rbxasset://textures/particles/sparkles_main.dds",
	smooth = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
}

-- Enhanced Visibility Constants
local VISIBILITY_CHECK_INTERVAL = 5
local RENDER_DISTANCE = 500
local LOD_DISTANCE_NEAR = 100
local LOD_DISTANCE_MID = 250
local LOD_DISTANCE_FAR = 500
local BEAM_SYNC_INTERVAL = 3
local FORCE_RENDER_SEGMENTS = 150
local VISIBILITY_BUFFER_ZONE = 50

local AISnakeBodySetup = {}

-- Professional Color Utilities
local function HSVToRGB(h, s, v)
	h = h % 1
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)

	i = i % 6

	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	elseif i == 5 then return v, p, q
	end
end

-- Calculate growth factor for size scaling
function AISnakeBodySetup.calculateGrowthFactor(length)
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

-- Get segment size with smooth transitions
function AISnakeBodySetup.getSegmentSize(index, baseSize, visibleSegmentCount, isGrowing, growthStartTime)
	local sizeMult = 1

	-- Add growth pulse effect when growing
	if isGrowing then
		local timeSinceGrowth = tick() - growthStartTime
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
		local bodySize = baseSize * (1 - 0.05 * blendFactor)
		return (headSize + (bodySize - headSize) * (blendFactor ^ 0.5)) * sizeMult
	else
		-- Body with gradual taper
		local taperFactor = 1 - (index / visibleSegmentCount) * 0.2
		taperFactor = 1 - (1 - taperFactor) ^ 1.5
		return baseSize * taperFactor * sizeMult
	end
end

-- Calculate beam width with proper transitions
function AISnakeBodySetup.getBeamWidth(index, baseSize, visibleSegmentCount, isGrowing, growthStartTime)
	local segmentSize1 = AISnakeBodySetup.getSegmentSize(index, baseSize, visibleSegmentCount, isGrowing, growthStartTime)
	local segmentSize2 = AISnakeBodySetup.getSegmentSize(index + 1, baseSize, visibleSegmentCount, isGrowing, growthStartTime)

	local avgSize = (segmentSize1 + segmentSize2) / 2
	local beamTaper = 1 - (index / visibleSegmentCount) * BEAM_TAPER_STRENGTH

	return avgSize * BEAM_WIDTH_BASE * beamTaper
end

-- Get segment color with rainbow mode support
function AISnakeBodySetup.getSegmentColor(index, config, rainbowMode, currentHue)
	if rainbowMode then
		local hue = (currentHue + (index * RAINBOW_SEGMENT_OFFSET)) % 1
		local r, g, b = HSVToRGB(hue, 1, 1)
		return Color3.new(r, g, b)
	else
		if index == 0 then
			return config.HeadColor or config.BodyColors[1]
		elseif index <= HEAD_BLEND_SEGMENTS then
			local blendFactor = (index / HEAD_BLEND_SEGMENTS) ^ 0.7
			local headColor = config.HeadColor or config.BodyColors[1]
			local bodyColor = config.BodyColors[1]
			return headColor:Lerp(bodyColor, blendFactor)
		else
			local colorIndex = ((index - 1) % #config.BodyColors) + 1
			return config.BodyColors[colorIndex]
		end
	end
end

-- Create the unified body system for AI snakes
function AISnakeBodySetup.createUnifiedBody(snake)
	-- Calculate initial segment count
	local segmentCount = math.min(math.ceil(snake.Length / 2), MAX_SEGMENTS)

	-- Create model if it doesn't exist
	if not snake.Model then
		snake.Model = Instance.new("Model")
		snake.Model.Name = "AISnake_" .. tostring(snake)
		snake.Model.Parent = workspace
	end

	-- Clear existing visual components
	if snake.segments then
		for _, segment in pairs(snake.segments) do
			if segment then segment:Destroy() end
		end
	end
	if snake.attachmentPart then
		snake.attachmentPart:Destroy()
	end

	-- Initialize visual component tables
	snake.segments = {}
	snake.beams = {}
	snake.attachments = {}
	snake.glows = {}
	snake.visibleSegmentCount = 0
	snake.segmentVisibility = {}
	snake.lodStates = {}
	snake.forcedRenderSegments = {}

	-- Visual state
	snake.rainbowMode = false
	snake.currentHue = 0
	snake.glowPulsePhase = 0
	snake.beamAnimationOffset = 0
	snake.isBoosting = false

	-- Growth animation state
	snake.isGrowing = false
	snake.growthStartTime = 0
	snake.lastSegmentAddTime = 0
	snake.pendingGrowth = 0
	snake.growthWaveOffset = 0
	snake.actualLength = snake.Length
	snake.targetLength = snake.Length
	snake.growthFactor = 1

	-- Create attachment holder part
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Parent = snake.Model
	attachmentPart:SetAttribute("AlwaysRender", true)
	snake.attachmentPart = attachmentPart

	-- HEAD IS NOW SEGMENT 0
	local head = Instance.new("Part")
	head.Name = "Segment0_Head"
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = AISnakeBodySetup.getSegmentColor(0, snake.Config, false, 0)
	head.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	head.Transparency = 0
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = snake.Model

	-- Force head to always render
	head:SetAttribute("RenderFidelity", Enum.RenderFidelity.Precise)
	head:SetAttribute("AlwaysRender", true)

	-- Professional head glow
	local headGlow = Instance.new("PointLight")
	headGlow.Name = "Glow"
	headGlow.Brightness = GLOW_INTENSITY
	headGlow.Range = GLOW_RANGE_BASE * 1.1
	headGlow.Color = head.Color
	headGlow.Shadows = false
	headGlow.Parent = head

	-- Eyes for character
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
		eye.Parent = snake.Model
		eye:SetAttribute("AlwaysRender", true)

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = snake.Model
		pupil:SetAttribute("AlwaysRender", true)

		return eye, pupil
	end

	snake.leftEye, snake.leftPupil = createEye(-0.6)
	snake.rightEye, snake.rightPupil = createEye(0.6)

	-- Collision tagging for head
	CollectionService:AddTag(head, "AISnakeHead")
	head:SetAttribute("SnakeId", tostring(snake))
	head:SetAttribute("SnakeName", snake.Name)

	-- Store head as segment 0
	snake.segments[0] = head
	snake.head = head
	snake.headGlow = headGlow
	snake.glows[0] = headGlow
	snake.segmentVisibility[0] = true

	-- Create head attachment
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "Attachment0"
	headAttachment.Parent = attachmentPart
	snake.attachments[0] = headAttachment

	-- Create body segments starting from 1
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		-- Use new size calculation
		local segmentSize = AISnakeBodySetup.getSegmentSize(i, BASE_SIZE, segmentCount, false, 0)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		-- Set render fidelity for important segments
		if i <= FORCE_RENDER_SEGMENTS then
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Precise)
			segment:SetAttribute("AlwaysRender", true)
			snake.forcedRenderSegments[i] = true
		else
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Automatic)
		end

		-- Use new color system
		segment.Color = AISnakeBodySetup.getSegmentColor(i, snake.Config, false, 0)

		-- Strategic glow placement for performance
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
			snake.glows[i] = segmentGlow
		end

		segment.Parent = snake.Model
		snake.segments[i] = segment
		snake.segmentVisibility[i] = true

		-- Collision tagging
		if i <= 50 then
			CollectionService:AddTag(segment, "AISnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", snake.Name)
		end

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		snake.attachments[i] = attachment
	end

	-- Create seamless beams between all segments
	for i = 0, segmentCount - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = snake.attachments[i]
		beam.Attachment1 = snake.attachments[i + 1]

		-- Professional beam properties
		local beamWidth = AISnakeBodySetup.getBeamWidth(i, BASE_SIZE, segmentCount, false, 0)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = BEAM_TEXTURES.gradient
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.TextureSpeed = BEAM_TEXTURE_SPEED
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.Transparency = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1)
		}

		-- Color matching with smooth transitions
		if i == 0 then
			local headColor = snake.segments[0].Color
			local seg1Color = snake.segments[1].Color
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, headColor),
				ColorSequenceKeypoint.new(0.3, headColor:Lerp(seg1Color, 0.3)),
				ColorSequenceKeypoint.new(0.7, headColor:Lerp(seg1Color, 0.7)),
				ColorSequenceKeypoint.new(1, seg1Color)
			})
		else
			beam.Color = ColorSequence.new(AISnakeBodySetup.getSegmentColor(i, snake.Config, false, 0))
		end

		beam.Parent = attachmentPart
		snake.beams[i] = beam
	end

	-- Create selective overlap beams for critical areas
	for i = 0, math.min(segmentCount - 2, HEAD_BLEND_SEGMENTS * 2) do
		if i % 2 == 0 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = snake.attachments[i]
			overlapBeam.Attachment1 = snake.attachments[i + 2]

			local overlapWidth = AISnakeBodySetup.getBeamWidth(i, BASE_SIZE, segmentCount, false, 0) * 1.15
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = BEAM_TEXTURES.gradient
			overlapBeam.TextureMode = Enum.TextureMode.Wrap
			overlapBeam.TextureLength = 3
			overlapBeam.TextureSpeed = BEAM_TEXTURE_SPEED * 0.7
			overlapBeam.LightEmission = 0.7
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.5)
			overlapBeam.ZOffset = -0.1

			overlapBeam.Color = ColorSequence.new(AISnakeBodySetup.getSegmentColor(i, snake.Config, false, 0))

			overlapBeam.Parent = attachmentPart
			snake.beams["overlap" .. i] = overlapBeam
		end
	end

	snake.visibleSegmentCount = segmentCount

	-- Store references to key components
	if snake.HeadParts then
		snake.HeadParts.head = head
	else
		snake.HeadParts = { head = head }
	end

	-- Update RootPart reference if needed
	if not snake.RootPart then
		snake.RootPart = head
	end

	print("✅ AI Snake unified body created with", segmentCount, "segments")
end

-- Update the unified body (called every frame)
function AISnakeBodySetup.updateUnifiedBody(snake)
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(snake.actualLength / 2), MAX_SEGMENTS)

	-- Add new segments if grown
	if requiredSegments > snake.visibleSegmentCount then
		local now = tick()
		if now - snake.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			AISnakeBodySetup.addSegments(snake, 1)
			snake.lastSegmentAddTime = now
		end
	end

	-- Calculate sizes based on growth
	snake.growthFactor = AISnakeBodySetup.calculateGrowthFactor(snake.actualLength)
	local currentBaseSize = BASE_SIZE * snake.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING

	-- Update all segments including head (segment 0)
	for i = 0, snake.visibleSegmentCount do
		local segment = snake.segments[i]
		if segment and segment.Parent then
			-- Update colors for rainbow mode
			if snake.rainbowMode and i % 3 == 0 then
				segment.Color = AISnakeBodySetup.getSegmentColor(i, snake.Config, true, snake.currentHue)
				if snake.glows[i] then
					snake.glows[i].Color = segment.Color
				end
			end

			if i == 0 then
				-- Head positioning
				local cf = CFrame.lookAt(
					snake.Position,
					snake.Position + snake.Direction
				)
				segment.CFrame = cf

				-- Use calculated head size
				local headSize = AISnakeBodySetup.getSegmentSize(0, currentBaseSize, snake.visibleSegmentCount, snake.isGrowing, snake.growthStartTime)
				segment.Size = Vector3.new(headSize, headSize, headSize)

				-- Update eyes
				local eyeScale = headSize / BASE_SIZE * 0.5
				local eyeOffset = headSize * 0.3
				local eyeForward = -headSize * 0.35

				snake.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				snake.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				snake.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
				snake.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

				snake.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.5, eyeForward)
				snake.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.5, eyeForward)
				snake.leftPupil.CFrame = snake.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
				snake.rightPupil.CFrame = snake.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
			else
				-- Body segment positioning
				local historyIndex = math.min(i * 2, #snake.positionHistory)
				local histData = snake.positionHistory[#snake.positionHistory - historyIndex + 1]
				
				if histData then
					local targetPos = histData.position
					local currentPos = segment.Position

					-- Smooth interpolation
					local smoothingFactor = snake.isGrowing and VISUAL_SMOOTHING_FACTOR * 1.2 or VISUAL_SMOOTHING_FACTOR
					segment.Position = currentPos:Lerp(targetPos, smoothingFactor)

					-- Use calculated segment size
					local segmentSize = AISnakeBodySetup.getSegmentSize(i, currentBaseSize, snake.visibleSegmentCount, snake.isGrowing, snake.growthStartTime)
					segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

					-- Pulse effect during boost
					if snake.isBoosting then
						local pulse = math.sin(tick() * 10 + i * 0.1) * 0.03 + 1
						segment.Size = segment.Size * pulse
					end
				end
			end

			-- Update attachment position
			if snake.attachments[i] then
				snake.attachments[i].WorldPosition = segment.Position
			end
		end
	end

	-- Update all beams with calculated widths
	for i, beam in pairs(snake.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				if i <= snake.visibleSegmentCount then
					local beamWidth = AISnakeBodySetup.getBeamWidth(i, currentBaseSize, snake.visibleSegmentCount, snake.isGrowing, snake.growthStartTime)
					beam.Width0 = beamWidth
					beam.Width1 = beamWidth

					-- Update beam colors for rainbow mode
					if snake.rainbowMode and i % 5 == 0 then
						beam.Color = ColorSequence.new(AISnakeBodySetup.getSegmentColor(i, snake.Config, true, snake.currentHue))
					end

					-- Dynamic color during boost
					if snake.isBoosting and i > HEAD_BLEND_SEGMENTS and not snake.rainbowMode then
						local colorShift = math.floor(tick() * 3) % #snake.Config.BodyColors
						local colorIndex = ((i - 1 + colorShift) % #snake.Config.BodyColors) + 1
						beam.Color = ColorSequence.new(snake.Config.BodyColors[colorIndex])
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlap") then
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= snake.visibleSegmentCount - 2 then
					local overlapWidth = AISnakeBodySetup.getBeamWidth(index, currentBaseSize, snake.visibleSegmentCount, snake.isGrowing, snake.growthStartTime) * 1.15
					beam.Width0 = overlapWidth
					beam.Width1 = overlapWidth

					if snake.rainbowMode and index % 5 == 0 then
						beam.Color = ColorSequence.new(AISnakeBodySetup.getSegmentColor(index, snake.Config, true, snake.currentHue))
					end
				else
					beam.Enabled = false
				end
			end
		end
	end

	-- Update glow ranges
	for i, glow in pairs(snake.glows) do
		if glow and glow.Parent then
			local glowScale = 1 - (i / snake.visibleSegmentCount) * 0.3
			glow.Range = (GLOW_RANGE_BASE + (currentBaseSize - BASE_SIZE) * 2) * glowScale

			-- Pulse effect
			local pulseMult = 1 + math.sin(snake.glowPulsePhase) * (snake.isBoosting and 0.2 or 0.05)
			glow.Brightness = GLOW_INTENSITY * (snake.isBoosting and 1.5 or 1) * pulseMult
		end
	end
end

-- Add new segments for growth
function AISnakeBodySetup.addSegments(snake, count)
	for i = snake.visibleSegmentCount + 1, snake.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		-- Create new segment with fade-in effect
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		-- Start small for growth animation
		local targetSize = AISnakeBodySetup.getSegmentSize(i, BASE_SIZE * snake.growthFactor, i, snake.isGrowing, snake.growthStartTime)
		segment.Size = Vector3.new(targetSize * 0.1, targetSize * 0.1, targetSize * 0.1)

		segment.Transparency = 0.8
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		if i <= FORCE_RENDER_SEGMENTS then
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Precise)
			segment:SetAttribute("AlwaysRender", true)
			snake.forcedRenderSegments[i] = true
		else
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Automatic)
		end

		segment.Color = AISnakeBodySetup.getSegmentColor(i, snake.Config, snake.rainbowMode, snake.currentHue)

		-- Position at last segment initially
		if snake.segments[i - 1] then
			segment.Position = snake.segments[i - 1].Position
		end

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
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / MAX_SEGMENTS) * 0.2)
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			snake.glows[i] = segmentGlow
		end

		segment.Parent = snake.Model
		snake.segments[i] = segment
		snake.segmentVisibility[i] = true
		snake.lodStates[i] = "near"

		-- Animate growth
		TweenService:Create(segment, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(targetSize, targetSize, targetSize),
			Transparency = 0
		}):Play()

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = snake.attachmentPart
		snake.attachments[i] = attachment

		-- Create beam from previous segment
		if snake.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. (i - 1)
			beam.Attachment0 = snake.attachments[i - 1]
			beam.Attachment1 = snake.attachments[i]

			local beamWidth = AISnakeBodySetup.getBeamWidth(i - 1, BASE_SIZE * snake.growthFactor, i, snake.isGrowing, snake.growthStartTime)
			beam.Width0 = beamWidth * 0.1
			beam.Width1 = beamWidth * 0.1
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = BEAM_TEXTURES.gradient
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 2
			beam.TextureSpeed = BEAM_TEXTURE_SPEED
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 2
			beam.Transparency = NumberSequence.new(0.8)

			beam.Color = ColorSequence.new(AISnakeBodySetup.getSegmentColor(i, snake.Config, snake.rainbowMode, snake.currentHue))

			beam.Parent = snake.attachmentPart
			snake.beams[i - 1] = beam

			-- Animate beam growth
			TweenService:Create(beam, TweenInfo.new(0.3), {
				Width0 = beamWidth,
				Width1 = beamWidth
			}):Play()

			-- Custom transparency animation
			local startTime = tick()
			local transparencyConnection
			transparencyConnection = RunService.Heartbeat:Connect(function()
				local elapsed = tick() - startTime
				local progress = math.min(elapsed / 0.3, 1)

				local transparency = 0.8 * (1 - progress)
				beam.Transparency = NumberSequence.new{
					NumberSequenceKeypoint.new(0, transparency),
					NumberSequenceKeypoint.new(0.5, transparency),
					NumberSequenceKeypoint.new(1, transparency + 0.1)
				}

				if progress >= 1 then
					transparencyConnection:Disconnect()
				end
			end)
		end
	end

	snake.visibleSegmentCount = math.min(snake.visibleSegmentCount + count, MAX_SEGMENTS)
end

-- Clean up visual components
function AISnakeBodySetup.cleanup(snake)
	if snake.segments then
		for _, segment in pairs(snake.segments) do
			if segment then segment:Destroy() end
		end
		snake.segments = nil
	end

	if snake.beams then
		for _, beam in pairs(snake.beams) do
			if beam then beam:Destroy() end
		end
		snake.beams = nil
	end

	if snake.attachments then
		for _, attachment in pairs(snake.attachments) do
			if attachment then attachment:Destroy() end
		end
		snake.attachments = nil
	end

	if snake.attachmentPart then
		snake.attachmentPart:Destroy()
		snake.attachmentPart = nil
	end

	if snake.leftEye then snake.leftEye:Destroy() end
	if snake.rightEye then snake.rightEye:Destroy() end
	if snake.leftPupil then snake.leftPupil:Destroy() end
	if snake.rightPupil then snake.rightPupil:Destroy() end
end

return AISnakeBodySetup