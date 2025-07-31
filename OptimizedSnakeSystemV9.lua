--[[
	OPTIMIZED SNAKE SYSTEM V9
	ULTIMATE - SEAMLESS UNIFIED RENDERING (FIXED GROWTH)
	
	Features:
	- Professional visual effects
	- Fixed gap issues  
	- Improved LOD handling
	- Stable at extreme lengths
--]]

local module = {}

-- Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

-- Constants
local POSITION_HISTORY_SIZE = 300 -- Increased for smoother trails
local UPDATE_RATE = 1/60
local SMOOTH_FACTOR = 0.92
local MAX_RENDER_DISTANCE = 500
local MOBILE_MAX_RENDER_DISTANCE = 350
local PERFORMANCE_CHECK_INTERVAL = 2

-- Performance detection
local IS_MOBILE = game:GetService("UserInputService").TouchEnabled
local LOW_PERFORMANCE_MODE = false

-- Cached references
local workspace = game.Workspace
local Vector3new = Vector3.new
local CFramenew = CFrame.new
local CFramelookAt = CFrame.lookAt
local mathmin = math.min
local mathmax = math.max
local mathabs = math.abs
local mathsin = math.sin
local mathcos = math.cos
local mathrad = math.rad
local tabinsert = table.insert
local tabremove = table.remove

-- Snake class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	-- Core properties
	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.player = game.Players:GetPlayerFromCharacter(character)
	
	-- Configuration
	self.config = config or {}
	self.length = config.InitialLength or 500
	self.segmentSpacing = config.SegmentSpacing or 3.2
	self.segmentSize = config.SegmentSize or Vector3new(4, 4, 4)
	self.headSize = config.HeadSize or Vector3new(4.5, 4.5, 4.5)
	self.maxSegments = config.MaxSegments or 50000
	self.growthMultiplier = config.GrowthMultiplier or 1
	
	-- Visual configuration
	self.headColor = config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.bodyColors = config.BodyColors or {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	}
	self.headMaterial = config.HeadMaterial or Enum.Material.Neon
	self.bodyMaterial = config.BodyMaterial or Enum.Material.Neon
	self.glowIntensity = config.GlowIntensity or 2
	self.glowRange = config.GlowRange or 6
	self.isRainbow = config.IsRainbow or false
	
	-- Movement and physics
	self.positionHistory = {}
	self.lastPosition = self.rootPart.Position
	self.velocity = Vector3new(0, 0, 0)
	self.smoothedVelocity = Vector3new(0, 0, 0)
	self.targetBend = 0
	self.currentBend = 0
	
	-- Unified rendering
	self.unifiedBody = nil
	self.beams = {}
	self.segmentCount = 0
	self.lastLODCheck = 0
	self.currentLOD = 1
	
	-- State
	self.isDestroyed = false
	self.isBoosting = false
	self.isGhostMode = false
	self.connections = {}
	self.lastUpdateTime = tick()
	self.frameCount = 0
	self.lastPerformanceCheck = 0
	
	-- Create snake
	self:setup()
	
	return self
end

function Snake:setup()
	-- Hide character parts
	for _, part in ipairs(self.character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		elseif part:IsA("Accessory") then
			part:Destroy()
		end
	end
	
	-- Initialize head
	self.head = Instance.new("Part")
	self.head.Name = "SnakeHead"
	self.head.Shape = Enum.PartType.Ball
	self.head.Material = self.headMaterial
	self.head.Size = self.headSize
	self.head.Color = self.headColor
	self.head.TopSurface = Enum.SurfaceType.Smooth
	self.head.BottomSurface = Enum.SurfaceType.Smooth
	self.head.CanCollide = false
	self.head.Massless = true
	self.head.Parent = self.character
	
	-- Add glow
	local headGlow = Instance.new("PointLight")
	headGlow.Brightness = self.glowIntensity
	headGlow.Range = self.glowRange
	headGlow.Color = self.headColor
	headGlow.Parent = self.head
	
	-- Create unified body
	self:createUnifiedBody()
	
	-- Start update loop
	self:startUpdateLoop()
	
	-- Performance monitoring
	self:startPerformanceMonitoring()
end

function Snake:createUnifiedBody()
	-- Calculate initial segment count
	self.segmentCount = math.floor(self.length / self.segmentSpacing)
	self.segmentCount = mathmin(self.segmentCount, self.maxSegments)
	
	-- Create unified body model
	self.unifiedBody = Instance.new("Model")
	self.unifiedBody.Name = "SnakeBody"
	self.unifiedBody.Parent = self.character
	
	-- Create segments with LOD in mind
	local segmentsToCreate = mathmin(self.segmentCount, 100) -- Start with limited segments
	
	for i = 1, segmentsToCreate do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = self.bodyMaterial
		segment.Size = self.segmentSize
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.CanCollide = false
		segment.Massless = true
		segment.Anchored = true
		
		-- Color pattern
		local colorIndex = ((i - 1) % #self.bodyColors) + 1
		segment.Color = self.bodyColors[colorIndex]
		
		-- Add glow for nearby segments
		if i <= 20 then
			local glow = Instance.new("PointLight")
			glow.Brightness = self.glowIntensity * 0.5
			glow.Range = self.glowRange * 0.5
			glow.Color = segment.Color
			glow.Parent = segment
		end
		
		segment.Parent = self.unifiedBody
		
		-- Create beam for segment
		if i > 1 then
			local prevSegment = self.unifiedBody:FindFirstChild("Segment" .. (i - 1))
			if prevSegment then
				self:createBeam(prevSegment, segment, i)
			end
		end
	end
	
	-- Connect head to first segment
	local firstSegment = self.unifiedBody:FindFirstChild("Segment1")
	if firstSegment then
		self:createBeam(self.head, firstSegment, 0)
	end
end

function Snake:createBeam(part1, part2, index)
	local attachment1 = Instance.new("Attachment")
	attachment1.Parent = part1
	
	local attachment2 = Instance.new("Attachment")
	attachment2.Parent = part2
	
	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment1
	beam.Attachment1 = attachment2
	beam.Width0 = self.segmentSize.X
	beam.Width1 = self.segmentSize.X
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Transparency = NumberSequence.new(0)
	
	-- Color based on segment
	local colorIndex = (index % #self.bodyColors) + 1
	beam.Color = ColorSequence.new(self.bodyColors[colorIndex])
	
	beam.Parent = part1
	
	table.insert(self.beams, {
		beam = beam,
		attachment1 = attachment1,
		attachment2 = attachment2,
		index = index
	})
end

function Snake:startUpdateLoop()
	self.connections.update = RunService.Heartbeat:Connect(function(deltaTime)
		if self.isDestroyed then return end
		
		self.frameCount = self.frameCount + 1
		
		-- Update position history
		self:updatePositionHistory()
		
		-- Update unified body
		self:updateUnifiedBody()
		
		-- Handle rainbow effect
		if self.isRainbow then
			self:updateRainbowEffect()
		end
		
		-- Check LOD every few frames
		if self.frameCount % 30 == 0 then
			self:updateLOD()
		end
		
		self.lastUpdateTime = tick()
	end)
end

function Snake:updatePositionHistory()
	local currentPos = self.rootPart.Position
	local currentVel = self.rootPart.AssemblyLinearVelocity
	
	-- Smooth velocity
	self.smoothedVelocity = self.smoothedVelocity:Lerp(currentVel, 0.15)
	
	-- Add position to history
	tabinsert(self.positionHistory, 1, {
		position = currentPos,
		velocity = self.smoothedVelocity,
		time = tick()
	})
	
	-- Maintain history size
	while #self.positionHistory > POSITION_HISTORY_SIZE do
		tabremove(self.positionHistory)
	end
	
	-- Update head position
	if self.head then
		self.head.CFrame = CFramenew(currentPos)
	end
end

function Snake:updateUnifiedBody()
	if not self.unifiedBody or #self.positionHistory < 2 then return end
	
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or self.rootPart.Position
	
	-- Update visible segments based on actual snake length
	local visibleSegments = math.floor(self.length / self.segmentSpacing)
	visibleSegments = mathmin(visibleSegments, self.segmentCount)
	
	-- LOD calculations
	local maxRenderDist = IS_MOBILE and MOBILE_MAX_RENDER_DISTANCE or MAX_RENDER_DISTANCE
	if LOW_PERFORMANCE_MODE then
		maxRenderDist = maxRenderDist * 0.7
	end
	
	-- Update segments
	for i = 1, visibleSegments do
		local segment = self.unifiedBody:FindFirstChild("Segment" .. i)
		if not segment and i <= 100 then -- Create segments on demand up to 100
			self:createSegmentOnDemand(i)
			segment = self.unifiedBody:FindFirstChild("Segment" .. i)
		end
		
		if segment then
			-- Calculate position along the snake
			local targetIndex = math.floor(i * self.segmentSpacing / self.segmentSize.X) + 1
			if targetIndex <= #self.positionHistory then
				local historyPoint = self.positionHistory[targetIndex]
				local targetPos = historyPoint.position
				
				-- Apply distance-based LOD
				local distToCam = (targetPos - cameraPos).Magnitude
				local shouldRender = distToCam < maxRenderDist
				
				if shouldRender then
					-- Smooth position
					segment.CFrame = segment.CFrame:Lerp(CFramenew(targetPos), SMOOTH_FACTOR)
					segment.Transparency = 0
					
					-- Update beam
					local beamData = self.beams[i]
					if beamData and beamData.beam then
						beamData.beam.Enabled = true
						
						-- Smooth beam width based on position
						local widthMultiplier = 1 - (i / visibleSegments) * 0.2
						beamData.beam.Width0 = self.segmentSize.X * widthMultiplier
						beamData.beam.Width1 = self.segmentSize.X * widthMultiplier
					end
				else
					segment.Transparency = 1
					local beamData = self.beams[i]
					if beamData and beamData.beam then
						beamData.beam.Enabled = false
					end
				end
			end
		end
	end
	
	-- Hide excess segments
	for i = visibleSegments + 1, self.segmentCount do
		local segment = self.unifiedBody:FindFirstChild("Segment" .. i)
		if segment then
			segment.Transparency = 1
			local beamData = self.beams[i]
			if beamData and beamData.beam then
				beamData.beam.Enabled = false
			end
		end
	end
end

function Snake:createSegmentOnDemand(index)
	local segment = Instance.new("Part")
	segment.Name = "Segment" .. index
	segment.Shape = Enum.PartType.Ball
	segment.Material = self.bodyMaterial
	segment.Size = self.segmentSize
	segment.TopSurface = Enum.SurfaceType.Smooth
	segment.BottomSurface = Enum.SurfaceType.Smooth
	segment.CanCollide = false
	segment.Massless = true
	segment.Anchored = true
	
	-- Color pattern
	local colorIndex = ((index - 1) % #self.bodyColors) + 1
	segment.Color = self.bodyColors[colorIndex]
	
	segment.Parent = self.unifiedBody
	
	-- Create beam connection
	if index > 1 then
		local prevSegment = self.unifiedBody:FindFirstChild("Segment" .. (index - 1))
		if prevSegment then
			self:createBeam(prevSegment, segment, index)
		end
	end
end

function Snake:updateLOD()
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local playerPos = self.rootPart.Position
	local cameraPos = camera.CFrame.Position
	local distanceToPlayer = (cameraPos - playerPos).Magnitude
	
	-- Adjust LOD based on distance and performance
	if LOW_PERFORMANCE_MODE then
		self.currentLOD = distanceToPlayer < 50 and 1 or 2
	else
		if distanceToPlayer < 100 then
			self.currentLOD = 1 -- Full quality
		elseif distanceToPlayer < 300 then
			self.currentLOD = 2 -- Medium quality
		else
			self.currentLOD = 3 -- Low quality
		end
	end
end

function Snake:startPerformanceMonitoring()
	self.connections.performance = RunService.Heartbeat:Connect(function()
		if self.isDestroyed then return end
		
		local now = tick()
		if now - self.lastPerformanceCheck > PERFORMANCE_CHECK_INTERVAL then
			self.lastPerformanceCheck = now
			
			-- Check FPS
			local fps = math.floor(1 / game:GetService("Stats").FrameRateManager.RenderAverage:GetValue())
			if fps < 30 then
				LOW_PERFORMANCE_MODE = true
			elseif fps > 50 then
				LOW_PERFORMANCE_MODE = false
			end
		end
	end)
end

function Snake:updateRainbowEffect()
	local time = tick()
	local hue = (time * 0.5) % 1
	
	-- Update head color
	self.head.Color = Color3.fromHSV(hue, 1, 1)
	local headGlow = self.head:FindFirstChildOfClass("PointLight")
	if headGlow then
		headGlow.Color = self.head.Color
	end
	
	-- Update body segments
	for i, beamData in ipairs(self.beams) do
		if beamData.beam then
			local segmentHue = (hue + i * 0.02) % 1
			local color = Color3.fromHSV(segmentHue, 1, 1)
			beamData.beam.Color = ColorSequence.new(color)
		end
	end
end

function Snake:grow(amount)
	amount = amount * self.growthMultiplier
	self.length = mathmin(self.length + amount, self.maxSegments * self.segmentSpacing)
	
	-- Update segment count
	local newSegmentCount = math.floor(self.length / self.segmentSpacing)
	newSegmentCount = mathmin(newSegmentCount, self.maxSegments)
	
	if newSegmentCount > self.segmentCount then
		self.segmentCount = newSegmentCount
		-- Segments will be created on demand in updateUnifiedBody
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
	
	if boosting then
		-- Create boost effects
		if not self.boostParticle then
			self.boostParticle = Instance.new("ParticleEmitter")
			self.boostParticle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			self.boostParticle.Rate = 100
			self.boostParticle.Lifetime = NumberRange.new(0.5, 1)
			self.boostParticle.Speed = NumberRange.new(5, 10)
			self.boostParticle.SpreadAngle = Vector2.new(30, 30)
			self.boostParticle.Color = ColorSequence.new(self.headColor)
			self.boostParticle.Parent = self.head
		end
		
		-- Enhanced glow
		local headGlow = self.head:FindFirstChildOfClass("PointLight")
		if headGlow then
			TweenService:Create(headGlow, TweenInfo.new(0.3), {
				Brightness = self.glowIntensity * 2,
				Range = self.glowRange * 1.5
			}):Play()
		end
	else
		-- Remove boost effects
		if self.boostParticle then
			self.boostParticle:Destroy()
			self.boostParticle = nil
		end
		
		-- Normal glow
		local headGlow = self.head:FindFirstChildOfClass("PointLight")
		if headGlow then
			TweenService:Create(headGlow, TweenInfo.new(0.3), {
				Brightness = self.glowIntensity,
				Range = self.glowRange
			}):Play()
		end
	end
end

function Snake:setGhostMode(enabled)
	self.isGhostMode = enabled
	
	if enabled then
		-- Make snake semi-transparent
		self.head.Transparency = 0.5
		for i = 1, self.segmentCount do
			local segment = self.unifiedBody:FindFirstChild("Segment" .. i)
			if segment then
				segment.Transparency = 0.5
			end
		end
		
		-- Update beams
		for _, beamData in ipairs(self.beams) do
			if beamData.beam then
				beamData.beam.Transparency = NumberSequence.new(0.5)
			end
		end
	else
		-- Restore normal transparency
		self.head.Transparency = 0
		self:updateUnifiedBody() -- This will restore proper transparency
	end
end

function Snake:updateVisuals(config)
	-- Update colors
	self.headColor = config.HeadColor or self.headColor
	self.bodyColors = config.BodyColors or self.bodyColors
	self.isRainbow = config.IsRainbow or false
	
	-- Update head
	if not self.isRainbow then
		self.head.Color = self.headColor
		local headGlow = self.head:FindFirstChildOfClass("PointLight")
		if headGlow then
			headGlow.Color = self.headColor
		end
	end
	
	-- Update beams
	for i, beamData in ipairs(self.beams) do
		if beamData.beam and not self.isRainbow then
			local colorIndex = (i % #self.bodyColors) + 1
			beamData.beam.Color = ColorSequence.new(self.bodyColors[colorIndex])
		end
	end
end

function Snake:getLength()
	return self.length
end

function Snake:destroy()
	self.isDestroyed = true
	
	-- Disconnect all connections
	for _, connection in pairs(self.connections) do
		if connection then
			connection:Disconnect()
		end
	end
	
	-- Clean up objects
	if self.head then
		self.head:Destroy()
	end
	
	if self.unifiedBody then
		self.unifiedBody:Destroy()
	end
	
	if self.boostParticle then
		self.boostParticle:Destroy()
	end
	
	-- Clear references
	self.beams = {}
	self.positionHistory = {}
	self.connections = {}
end

-- Module functions
function module.new(character, config)
	return Snake.new(character, config)
end

function module.createSnake(character, config)
	return Snake.new(character, config)
end

function module.init()
	-- Any global initialization
	print("OptimizedSnakeSystemV9 initialized")
end

return module