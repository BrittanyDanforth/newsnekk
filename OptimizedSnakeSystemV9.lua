--[[
	OPTIMIZED SNAKE SYSTEM V9.0 - ULTIMATE
	SEAMLESS UNIFIED RENDERING (FIXED GROWTH)
	
	Professional visual effects with fixed gaps, improved LOD, and stability at extreme lengths
--]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local OptimizedSnakeSystemV9 = {}
OptimizedSnakeSystemV9.__index = OptimizedSnakeSystemV9

-- Constants
local MIN_SEGMENT_DISTANCE = 0.1
local BEAM_ATTACHMENT_OFFSET = 0.5
local POSITION_HISTORY_SIZE = 5000 -- Increased for massive snakes!
local LOD_DISTANCE_THRESHOLDS = {150, 300, 500}
local LOD_SEGMENT_SKIP = {1, 2, 4}

-- Initialize system
function OptimizedSnakeSystemV9.init()
	print("Snake System V9.0 - ULTIMATE SEAMLESS UNIFIED RENDERING initialized")
end

-- Snake class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	-- Basics
	self.character = character
	self.humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	self.humanoid = character:FindFirstChild("Humanoid")
	
	if not self.humanoidRootPart or not self.humanoid then
		warn("Missing required components")
		return nil
	end
	
	-- Configuration
	self.config = config or {}
	self.length = self.config.InitialLength or 500
	self.segmentSpacing = self.config.SegmentSpacing or 3.2
	self.segmentSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	self.headSize = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	self.maxSegments = self.config.MaxSegments or 50000
	self.growthRate = self.config.GrowthRate or 15
	
	-- Visuals
	self.headColor = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.bodyColors = self.config.BodyColors or {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	}
	self.material = self.config.BodyMaterial or Enum.Material.Neon
	self.headMaterial = self.config.HeadMaterial or Enum.Material.Neon
	
	-- Performance
	self.lastLODUpdate = 0
	self.LODUpdateInterval = 0.5
	self.currentLOD = 0
	
	-- State
	self.segments = {}
	self.positionHistory = {}
	self.lastPosition = self.humanoidRootPart.Position
	self.speed = 16
	self.turnSpeed = 5
	self.destroyed = false
	self.targetLength = self.length
	self.actualSegmentCount = 0
	self.growing = false
	self.isBoosting = false
	self.rainbowMode = false
	
	-- Growth animation
	self.growthStartTime = 0
	self.growthDuration = 0.5
	self.startLength = self.length
	
	-- Model
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. character.Name
	self.model.Parent = workspace
	
	-- Create unified rendering
	self:createUnifiedBody()
	
	-- Setup updates
	self:setupUpdates()
	
	return self
end

function Snake:createUnifiedBody()
	-- Create head
	self.head = Instance.new("Part")
	self.head.Name = "Head"
	self.head.Size = self.headSize
	self.head.Material = self.headMaterial
	self.head.Color = self.headColor
	self.head.TopSurface = Enum.SurfaceType.Smooth
	self.head.BottomSurface = Enum.SurfaceType.Smooth
	self.head.CanCollide = false
	self.head.CFrame = self.humanoidRootPart.CFrame
	self.head.Parent = self.model
	
	-- Head mesh
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Sphere
	headMesh.Parent = self.head
	
	-- Head glow
	if self.config.GlowIntensity then
		local headGlow = Instance.new("PointLight")
		headGlow.Brightness = self.config.GlowIntensity
		headGlow.Range = self.config.GlowRange or 6
		headGlow.Color = self.headColor
		headGlow.Parent = self.head
	end
	
	-- Create segment pool
	self.segmentPool = {}
	self.beamPool = {}
	
	-- Pre-create segments and beams
	local preCreateCount = math.min(100, math.ceil(self.length / self.segmentSpacing))
	for i = 1, preCreateCount do
		self:createSegmentPair(i)
	end
	
	-- Initialize with full body
	self:updateUnifiedBody()
end

function Snake:createSegmentPair(index)
	-- Create segment
	local segment = Instance.new("Part")
	segment.Name = "Segment" .. index
	segment.Size = self.segmentSize
	segment.Material = self.material
	segment.TopSurface = Enum.SurfaceType.Smooth
	segment.BottomSurface = Enum.SurfaceType.Smooth
	segment.CanCollide = false
	segment.CFrame = self.humanoidRootPart.CFrame
	segment.Parent = self.model
	
	-- Mesh for smoother appearance
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = segment
	
	-- Create attachments for beam
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "BeamAttachment0"
	attachment0.Position = Vector3.new(0, 0, BEAM_ATTACHMENT_OFFSET)
	attachment0.Parent = segment
	
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "BeamAttachment1"
	attachment1.Position = Vector3.new(0, 0, -BEAM_ATTACHMENT_OFFSET)
	attachment1.Parent = segment
	
	-- Create beam to next segment
	local beam = Instance.new("Beam")
	beam.Name = "Connector" .. index
	beam.FaceCamera = true
	beam.Width0 = self.segmentSize.X
	beam.Width1 = self.segmentSize.X
	beam.Segments = 1
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = 0.5
	beam.LightInfluence = 0
	beam.Parent = segment
	
	-- Store references
	self.segmentPool[index] = segment
	self.beamPool[index] = beam
	
	-- Set initial properties
	local colorIndex = ((index - 1) % #self.bodyColors) + 1
	segment.Color = self.bodyColors[colorIndex]
	beam.Color = ColorSequence.new(self.bodyColors[colorIndex])
	
	return segment, beam
end

function Snake:updateUnifiedBody()
	if self.destroyed then return end
	
	-- Calculate required segments
	local requiredSegments = math.min(
		math.ceil(self.length / self.segmentSpacing),
		self.maxSegments
	)
	
	-- Create more segments if needed
	while #self.segmentPool < requiredSegments do
		local index = #self.segmentPool + 1
		self:createSegmentPair(index)
	end
	
	-- Update segment positions and visibility
	local currentTime = tick()
	local visibleCount = 0
	
	for i = 1, requiredSegments do
		local segment = self.segmentPool[i]
		local beam = self.beamPool[i]
		
		if segment and beam then
			-- Position from history
			local historyIndex = i * 2
			if self.positionHistory[historyIndex] then
				segment.CFrame = CFrame.new(self.positionHistory[historyIndex])
				
				-- Connect beam to next segment
				if i < requiredSegments and self.segmentPool[i + 1] then
					local nextSegment = self.segmentPool[i + 1]
					beam.Attachment0 = segment:FindFirstChild("BeamAttachment1")
					beam.Attachment1 = nextSegment:FindFirstChild("BeamAttachment0")
					beam.Enabled = true
					
					-- Smooth beam width transition
					local t = i / requiredSegments
					local widthMultiplier = 1 - (t * 0.3) -- Taper towards tail
					beam.Width0 = self.segmentSize.X * widthMultiplier
					beam.Width1 = self.segmentSize.X * widthMultiplier
				else
					beam.Enabled = false
				end
				
				segment.Parent = self.model
				visibleCount = visibleCount + 1
				
				-- Update color (rainbow mode or normal)
				if self.rainbowMode then
					local hue = ((currentTime * 0.5) + (i * 0.02)) % 1
					local color = Color3.fromHSV(hue, 1, 1)
					segment.Color = color
					beam.Color = ColorSequence.new(color)
				else
					-- Apply LOD-based rendering
					if self.currentLOD > 0 and i % (self.currentLOD + 1) ~= 0 then
						segment.Transparency = 0.5
						beam.Transparency = NumberSequence.new(0.5)
					else
						segment.Transparency = 0
						beam.Transparency = NumberSequence.new(0)
					end
				end
			else
				segment.Parent = nil
			end
		end
	end
	
	-- Hide unused segments
	for i = requiredSegments + 1, #self.segmentPool do
		if self.segmentPool[i] then
			self.segmentPool[i].Parent = nil
		end
		if self.beamPool[i] then
			self.beamPool[i].Enabled = false
		end
	end
	
	self.actualSegmentCount = visibleCount
end

function Snake:setupUpdates()
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		if self.destroyed or not self.humanoidRootPart.Parent then
			self:destroy()
			return
		end
		
		-- Update position history
		local currentPos = self.humanoidRootPart.Position
		if (currentPos - self.lastPosition).Magnitude > MIN_SEGMENT_DISTANCE then
			table.insert(self.positionHistory, 1, currentPos)
			self.lastPosition = currentPos
			
			-- Trim history
			while #self.positionHistory > POSITION_HISTORY_SIZE do
				table.remove(self.positionHistory)
			end
		end
		
		-- Update head position
		if self.head then
			self.head.CFrame = self.humanoidRootPart.CFrame
		end
		
		-- Smooth growth animation
		if self.growing then
			local elapsed = tick() - self.growthStartTime
			local t = math.min(elapsed / self.growthDuration, 1)
			
			-- Easing function for smooth growth
			local easedT = 1 - (1 - t) * (1 - t) -- Quadratic ease out
			self.length = self.startLength + (self.targetLength - self.startLength) * easedT
			
			if t >= 1 then
				self.growing = false
				self.length = self.targetLength
			end
		end
		
		-- Update LOD
		if tick() - self.lastLODUpdate > self.LODUpdateInterval then
			self:updateLOD()
			self.lastLODUpdate = tick()
		end
		
		-- Update body
		self:updateUnifiedBody()
		
		-- Update boost effects
		if self.isBoosting then
			self:updateBoostEffects()
		end
	end)
end

function Snake:updateLOD()
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local distance = (camera.CFrame.Position - self.humanoidRootPart.Position).Magnitude
	
	-- Determine LOD level
	self.currentLOD = 0
	for i, threshold in ipairs(LOD_DISTANCE_THRESHOLDS) do
		if distance > threshold then
			self.currentLOD = i
		end
	end
end

function Snake:grow(amount)
	if self.destroyed then return end
	
	amount = amount or self.growthRate
	self.startLength = self.length
	self.targetLength = math.min(self.targetLength + amount, self.maxSegments * self.segmentSpacing)
	self.growthStartTime = tick()
	self.growing = true
end

function Snake:setSkin(skinData)
	if self.destroyed then return end
	
	-- Update colors
	self.headColor = skinData.HeadColor or self.headColor
	self.bodyColors = skinData.BodyColors or self.bodyColors
	
	-- Apply to head
	if self.head then
		self.head.Color = self.headColor
		local headLight = self.head:FindFirstChild("PointLight")
		if headLight then
			headLight.Color = self.headColor
		end
	end
	
	-- Check for rainbow mode
	self.rainbowMode = skinData.IsRainbow or false
	
	-- Update all segments
	for i, segment in ipairs(self.segmentPool) do
		if segment and segment.Parent then
			local colorIndex = ((i - 1) % #self.bodyColors) + 1
			segment.Color = self.bodyColors[colorIndex]
			
			local beam = self.beamPool[i]
			if beam then
				beam.Color = ColorSequence.new(self.bodyColors[colorIndex])
			end
		end
	end
end

function Snake:setBoosting(boosting)
	if self.destroyed then return end
	
	self.isBoosting = boosting
	
	if boosting then
		-- Create boost particles
		if not self.boostEffect then
			self.boostEffect = Instance.new("ParticleEmitter")
			self.boostEffect.Name = "BoostEffect"
			self.boostEffect.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			self.boostEffect.Rate = 50
			self.boostEffect.Lifetime = NumberRange.new(0.5, 1)
			self.boostEffect.Speed = NumberRange.new(5, 10)
			self.boostEffect.SpreadAngle = Vector2.new(30, 30)
			self.boostEffect.Color = ColorSequence.new(self.headColor)
			self.boostEffect.LightEmission = 1
			self.boostEffect.Parent = self.head
		end
		
		-- Enhance glow
		local headLight = self.head:FindFirstChild("PointLight")
		if headLight then
			TweenService:Create(headLight, TweenInfo.new(0.3), {
				Brightness = (self.config.GlowIntensity or 2) * 2,
				Range = (self.config.GlowRange or 6) * 1.5
			}):Play()
		end
	else
		-- Remove boost effects
		if self.boostEffect then
			self.boostEffect:Destroy()
			self.boostEffect = nil
		end
		
		-- Reset glow
		local headLight = self.head:FindFirstChild("PointLight")
		if headLight then
			TweenService:Create(headLight, TweenInfo.new(0.3), {
				Brightness = self.config.GlowIntensity or 2,
				Range = self.config.GlowRange or 6
			}):Play()
		end
	end
end

function Snake:updateBoostEffects()
	if self.boostEffect then
		-- Update particle color to match current head color
		self.boostEffect.Color = ColorSequence.new(self.head.Color)
	end
end

function Snake:getLength()
	return self.targetLength
end

function Snake:getSegments()
	local activeSegments = {}
	for i, segment in ipairs(self.segmentPool) do
		if segment.Parent then
			table.insert(activeSegments, segment)
		end
	end
	return activeSegments
end

function Snake:destroy()
	if self.destroyed then return end
	self.destroyed = true
	
	-- Disconnect updates
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	-- Clean up model
	if self.model then
		self.model:Destroy()
	end
	
	-- Clear references
	self.segments = nil
	self.segmentPool = nil
	self.beamPool = nil
	self.positionHistory = nil
end

-- Module functions
function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV9