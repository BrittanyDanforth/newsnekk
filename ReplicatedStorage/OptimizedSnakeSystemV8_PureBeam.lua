-- Optimized Snake System V8 - PURE BEAM SYSTEM (True Slither.io Style)
-- This is COMPLETELY different - uses ONLY beams, no individual segments
-- Includes proper death orb spawning

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

-- Detect environment
local IS_CLIENT = RunService:IsClient()
local IS_SERVER = RunService:IsServer()

-- Beam configuration
local BEAM_SEGMENT_LENGTH = 3  -- Shorter segments for smoother curves
local BEAM_CURVE_SIZE = 2  -- More pronounced curves
local BEAM_WIDTH_MULTIPLIER = 5  -- MUCH thicker for visibility
local MAX_BEAM_SEGMENTS = 300  -- More segments for longer snakes
local BEAM_TEXTURE = ""  -- No texture for cleaner look

-- Death orb configuration
local DEATH_ORB_SIZE = 8  -- Size of death orbs
local DEATH_ORB_SPACING = 12  -- Space between death orbs
local DEATH_ORB_VALUE = 5  -- Length value per orb

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathRandom = math.random
local mathClamp = math.clamp or function(v, min, max) return mathMin(mathMax(v, min), max) end
local tick = tick

-- Snake Class
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
		warn("Failed to get player from character")
		return nil
	end
	
	-- Hide character
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end
	
	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true
	self.rootPart.CanTouch = true
	
	-- Snake data
	self.length = config.InitialLength or 55
	self.isDead = false
	self.skinName = config.SkinName or "Default"
	self.headColor = config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.bodyColors = config.BodyColors or {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	}
	
	-- Path tracking
	self.pathPoints = {}
	self.totalPathLength = 0
	
	-- Create model
	self.model = Instance.new("Model")
	self.model.Name = self.player.Name .. "_Snake"
	self.model.Parent = workspace
	
	-- Initialize path points BEFORE creating visuals
	self:initializePath()
	
	-- Initialize based on environment
	if IS_CLIENT then
		self:initializeClient()
	else
		self:initializeServer()
	end
	
	-- Start updates
	self:startUpdateLoop()
	
	-- Handle death
	self.humanoid.Died:Connect(function()
		self:onDeath()
	end)
	
	return self
end

function Snake:initializeServer()
	-- Server only needs collision detection and death handling
	self:createServerCollision()
	
	-- Set attributes for client sync
	self.player:SetAttribute("SnakeLength", self.length)
	self.player:SetAttribute("HeadColor", self.headColor)
	self.player:SetAttribute("EquippedSkin", self.skinName)
end

function Snake:initializeClient()
	-- Client creates the PURE BEAM visual system
	self:createPureBeamSystem()
	self:createClientHead()
end

function Snake:createServerCollision()
	-- Create invisible collision boxes along the snake
	self.collisionParts = {}
	
	local numCollisionParts = mathMin(mathFloor(self.length / 10), 30)
	
	for i = 1, numCollisionParts do
		local part = Instance.new("Part")
		part.Name = "Collision" .. i
		part.Size = Vector3new(8, 8, 8)
		part.Shape = Enum.PartType.Ball
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = true
		part.Anchored = true
		part.Parent = self.model
		
		part:SetAttribute("SnakeOwner", self.player.Name)
		part:SetAttribute("SegmentIndex", i)
		CollectionService:AddTag(part, "SnakeSegment")
		
		table.insert(self.collisionParts, part)
	end
end

function Snake:createPureBeamSystem()
	-- This is the MAGIC - pure beam rendering
	print("🌟 Creating PURE BEAM snake for", self.player.Name)
	print("   - Model exists:", self.model ~= nil)
	print("   - Model parent:", self.model.Parent)
	print("   - Initial length:", self.length)
	print("   - Path points count:", #self.pathPoints)
	print("   - RootPart position:", self.rootPart.Position)
	
	-- TEST: Create a simple visible beam to verify beams work at all
	local testPart1 = Instance.new("Part")
	testPart1.Name = "TestBeamPart1"
	testPart1.Size = Vector3new(5, 5, 5)
	testPart1.Material = Enum.Material.Neon
	testPart1.Color = Color3.new(1, 1, 0)
	testPart1.Position = self.rootPart.Position + Vector3new(0, 10, 0)
	testPart1.Anchored = true
	testPart1.Parent = workspace
	
	local testPart2 = Instance.new("Part")
	testPart2.Name = "TestBeamPart2"
	testPart2.Size = Vector3new(5, 5, 5)
	testPart2.Material = Enum.Material.Neon
	testPart2.Color = Color3.new(1, 1, 0)
	testPart2.Position = self.rootPart.Position + Vector3new(0, 10, 20)
	testPart2.Anchored = true
	testPart2.Parent = workspace
	
	local testAtt1 = Instance.new("Attachment")
	testAtt1.Parent = testPart1
	local testAtt2 = Instance.new("Attachment")
	testAtt2.Parent = testPart2
	
	local testBeam = Instance.new("Beam")
	testBeam.Name = "TestBeam"
	testBeam.Attachment0 = testAtt1
	testBeam.Attachment1 = testAtt2
	testBeam.Width0 = 20
	testBeam.Width1 = 20
	testBeam.Color = ColorSequence.new(Color3.new(1, 0, 1))  -- Magenta
	testBeam.LightEmission = 1
	testBeam.Transparency = NumberSequence.new(0)
	testBeam.FaceCamera = true
	testBeam.Enabled = true
	testBeam.Parent = workspace
	
	print("🟣 Created TEST BEAM - you should see a thick magenta beam above you!")
	game:GetService("Debris"):AddItem(testPart1, 15)
	game:GetService("Debris"):AddItem(testPart2, 15)
	game:GetService("Debris"):AddItem(testBeam, 15)
	
	-- Container for all attachments - using Folder instead of Part
	self.beamContainer = Instance.new("Folder")
	self.beamContainer.Name = "BeamContainer"
	self.beamContainer.Parent = self.model
	
	-- Create anchor part for attachments
	self.anchorPart = Instance.new("Part")
	self.anchorPart.Name = "BeamAnchor"
	self.anchorPart.Size = Vector3new(1, 1, 1)
	self.anchorPart.Transparency = 1
	self.anchorPart.CanCollide = false
	self.anchorPart.Anchored = true
	self.anchorPart.CFrame = self.rootPart.CFrame
	self.anchorPart.Parent = self.model
	
	print("   - Anchor part created at:", self.anchorPart.Position)
	
	-- Create attachment chain
	self.attachments = {}
	self.beams = {}
	
	-- Calculate how many segments we need
	local totalLength = self.length * 4  -- Scale to visual length
	local numSegments = mathMin(mathFloor(totalLength / BEAM_SEGMENT_LENGTH), MAX_BEAM_SEGMENTS)
	
	-- Create individual parts with attachments for beam system
	self.attachmentParts = {}
	for i = 0, numSegments do
		-- Create a small invisible part for each attachment
		local part = Instance.new("Part")
		part.Name = "BeamAnchor" .. i
		part.Size = Vector3new(0.1, 0.1, 0.1)
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Anchored = true
		part.Parent = self.model
		
		-- Position the part along the path
		local distance = i * BEAM_SEGMENT_LENGTH
		local position = self:getPositionAlongPath(distance)
		part.Position = position
		
		-- Create attachment inside the part
		local attachment = Instance.new("Attachment")
		attachment.Name = "BeamPoint" .. i
		attachment.Parent = part
		
		table.insert(self.attachmentParts, part)
		table.insert(self.attachments, attachment)
	end
	
	-- Create ONE CONTINUOUS BEAM through all attachments
	-- This is the key difference - we use multiple beams but they connect seamlessly
	for i = 1, #self.attachments - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "SnakeBeam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]
		
		-- Calculate width based on position (taper to tail)
		local growthFactor = self:calculateGrowthFactor()
		local baseWidth = 12 * BEAM_WIDTH_MULTIPLIER * growthFactor  -- Much thicker!
		local tailFactor = 1 - (i / #self.attachments) * 0.2  -- Even less taper (0.8 minimum)
		
		beam.Width0 = baseWidth * tailFactor
		beam.Width1 = baseWidth * tailFactor * 0.98  -- Very slight taper between segments
		
		-- CURVED beams for smooth look
		beam.CurveSize0 = BEAM_CURVE_SIZE * 1.5
		beam.CurveSize1 = -BEAM_CURVE_SIZE * 1.5
		
		-- High segment count for smooth curves
		beam.Segments = 30
		
		-- Make beam fully visible
		beam.Transparency = NumberSequence.new(0)  -- Fully opaque
		beam.Enabled = true  -- Force enable
		
		-- Color pattern - make it bright and visible
		local colorIndex = ((i - 1) % #self.bodyColors) + 1
		local color = self.bodyColors[colorIndex] or Color3.new(0, 1, 0)  -- Fallback to green
		
		-- Single color for simplicity
		beam.Color = ColorSequence.new(color)
		
		-- No texture for cleaner look
		beam.Texture = ""
		beam.TextureSpeed = 0
		beam.TextureLength = 1
		beam.TextureMode = Enum.TextureMode.Stretch
		
		-- Lighting - make it glow MORE!
		beam.LightEmission = 1  -- Maximum glow
		beam.LightInfluence = 0  -- Not affected by world lighting
		
		-- Always face camera for best look
		beam.FaceCamera = true
		beam.ZOffset = 2  -- Render on top
		
		-- IMPORTANT: Parent to model, not beamContainer
		beam.Parent = self.model
		table.insert(self.beams, beam)
	end
	
	print("✅ Created", #self.beams, "beam segments for continuous snake")
	
	-- Debug: Check if beams are actually visible
	if #self.beams > 0 then
		local firstBeam = self.beams[1]
		print("🔍 First beam check:")
		print("   - Width0:", firstBeam.Width0)
		print("   - Width1:", firstBeam.Width1)
		print("   - Transparency:", tostring(firstBeam.Transparency))
		print("   - Parent:", firstBeam.Parent and firstBeam.Parent.Name or "nil")
		print("   - Attachment0 pos:", firstBeam.Attachment0.WorldPosition)
		print("   - Attachment1 pos:", firstBeam.Attachment1.WorldPosition)
		print("   - LightEmission:", firstBeam.LightEmission)
		print("   - Color:", tostring(firstBeam.Color))
		
		-- Create debug parts at attachment positions to verify they're correct
		if true then  -- Set to false to disable debug
			for i = 1, math.min(10, #self.attachments) do  -- Show more debug parts
				local debugPart = Instance.new("Part")
				debugPart.Name = "DebugAttachment" .. i
				debugPart.Size = Vector3new(5, 5, 5)  -- Bigger
				debugPart.Shape = Enum.PartType.Ball
				debugPart.Material = Enum.Material.Neon
				debugPart.Color = Color3.new(1, i/10, 0)  -- Gradient from red to orange
				debugPart.Anchored = true
				debugPart.CanCollide = false
				debugPart.CanQuery = false
				debugPart.Position = self.attachments[i].WorldPosition
				debugPart.Parent = workspace
				
				-- Add PointLight for visibility
				local light = Instance.new("PointLight")
				light.Brightness = 2
				light.Range = 20
				light.Color = debugPart.Color
				light.Parent = debugPart
				
				-- Remove after 10 seconds
				game:GetService("Debris"):AddItem(debugPart, 10)
			end
			print("🔴 Created debug parts at first 10 attachment positions")
			
			-- Also create a debug part at the anchor position
			local anchorDebug = Instance.new("Part")
			anchorDebug.Name = "DebugAnchor"
			anchorDebug.Size = Vector3new(10, 10, 10)
			anchorDebug.Shape = Enum.PartType.Ball
			anchorDebug.Material = Enum.Material.ForceField
			anchorDebug.Color = Color3.new(0, 0, 1)  -- Blue
			anchorDebug.Anchored = true
			anchorDebug.CanCollide = false
			anchorDebug.CanQuery = false
			anchorDebug.Transparency = 0.5
			anchorDebug.Position = self.anchorPart.Position
			anchorDebug.Parent = workspace
			game:GetService("Debris"):AddItem(anchorDebug, 10)
			print("🔵 Created debug anchor at:", anchorDebug.Position)
		end
	end
end

function Snake:createClientHead()
	-- Create glowing head
	self.headPart = Instance.new("Part")
	self.headPart.Name = "SnakeHead"
	self.headPart.Size = Vector3new(7, 7, 7) * self:calculateGrowthFactor()
	self.headPart.Shape = Enum.PartType.Ball
	self.headPart.Material = Enum.Material.Neon
	self.headPart.Color = self.headColor
	self.headPart.Transparency = 0.2
	self.headPart.CanCollide = false
	self.headPart.Anchored = true
	self.headPart.Parent = self.model
	
	-- Head glow
	local headLight = Instance.new("PointLight")
	headLight.Brightness = 2
	headLight.Range = 15
	headLight.Color = self.headColor
	headLight.Parent = self.headPart
	
	-- Eyes
	self:createEyes()
end

function Snake:createEyes()
	local eyeSize = Vector3new(1.5, 1.5, 1.5) * self:calculateGrowthFactor()
	
	self.leftEye = Instance.new("Part")
	self.leftEye.Name = "LeftEye"
	self.leftEye.Size = eyeSize
	self.leftEye.Shape = Enum.PartType.Ball
	self.leftEye.Material = Enum.Material.Neon
	self.leftEye.Color = Color3.new(1, 1, 1)
	self.leftEye.CanCollide = false
	self.leftEye.Anchored = true
	self.leftEye.Parent = self.model
	
	self.rightEye = self.leftEye:Clone()
	self.rightEye.Name = "RightEye"
	self.rightEye.Parent = self.model
	
	-- Glow effect on eyes
	local eyeGlow = Instance.new("PointLight")
	eyeGlow.Brightness = 1
	eyeGlow.Range = 5
	eyeGlow.Color = Color3.new(1, 1, 1)
	eyeGlow.Parent = self.leftEye
	
	eyeGlow:Clone().Parent = self.rightEye
end

function Snake:calculateGrowthFactor()
	if self.length <= 200 then
		return 1
	elseif self.length <= 2000 then
		return 1 + ((self.length - 200) / 1800) * 1.0
	elseif self.length <= 5000 then
		return 2 + ((self.length - 2000) / 3000) * 0.5
	else
		return 2.5 + ((self.length - 5000) / 5000) * 0.5
	end
end

function Snake:initializePath()
	-- Create initial path points so beams have something to render
	print("🛤️ Initializing path for snake length:", self.length)
	
	local startPos = self.rootPart.Position
	local startDir = self.rootPart.CFrame.LookVector
	
	-- Create enough path points for the full snake length
	local totalLength = self.length * 4  -- Visual length multiplier
	local pointSpacing = 2  -- Distance between path points
	local numPoints = mathFloor(totalLength / pointSpacing)
	
	-- Create path points in a straight line behind the snake
	for i = 0, numPoints do
		local distance = i * pointSpacing
		local position = startPos - startDir * distance  -- Behind the snake
		
		table.insert(self.pathPoints, {
			position = position,
			direction = -startDir  -- Pointing backwards initially
		})
	end
	
	-- Calculate initial total path length
	self.totalPathLength = totalLength
	
	print("✅ Created", #self.pathPoints, "initial path points")
end

function Snake:updatePath()
	-- Track the snake's path
	local currentPos = self.rootPart.Position
	
	-- Add new point if moved enough
	if #self.pathPoints == 0 or (currentPos - self.pathPoints[1].position).Magnitude > 2 then
		table.insert(self.pathPoints, 1, {
			position = currentPos,
			direction = self.rootPart.CFrame.LookVector
		})
		
		-- Calculate total path length
		self.totalPathLength = 0
		for i = 2, #self.pathPoints do
			self.totalPathLength = self.totalPathLength + 
				(self.pathPoints[i].position - self.pathPoints[i-1].position).Magnitude
		end
		
		-- Trim path to snake length
		local targetLength = self.length * 4
		while self.totalPathLength > targetLength and #self.pathPoints > 2 do
			local lastSegment = (self.pathPoints[#self.pathPoints].position - 
				self.pathPoints[#self.pathPoints - 1].position).Magnitude
			self.totalPathLength = self.totalPathLength - lastSegment
			table.remove(self.pathPoints)
		end
	end
end

function Snake:updateBeamPositions()
	if not self.attachments or #self.pathPoints < 2 then return end
	
	-- Distribute attachments along the path
	local targetLength = self.length * 4
	local segmentSpacing = targetLength / #self.attachments
	
	for i, attachment in ipairs(self.attachments) do
		local targetDistance = (i - 1) * segmentSpacing
		local pos = self:getPositionAlongPath(targetDistance)
		if pos and self.attachmentParts and self.attachmentParts[i] then
			-- Move the part, not just the attachment
			self.attachmentParts[i].Position = pos
		end
	end
	
	-- Update beam properties based on length
	local growthFactor = self:calculateGrowthFactor()
	for i, beam in ipairs(self.beams) do
		local baseWidth = 12 * BEAM_WIDTH_MULTIPLIER * growthFactor  -- Match creation width
		local tailFactor = 1 - (i / #self.beams) * 0.2  -- Match creation taper
		beam.Width0 = baseWidth * tailFactor
		beam.Width1 = baseWidth * tailFactor * 0.98
		
		-- Ensure beam is visible and glowing
		beam.Transparency = NumberSequence.new(0)
		beam.Enabled = true
		beam.LightEmission = 1
		beam.ZOffset = 2
	end
end

function Snake:getPositionAlongPath(distance)
	-- Handle edge cases
	if #self.pathPoints == 0 then
		print("⚠️ No path points! Using root position")
		return self.rootPart.Position
	elseif #self.pathPoints == 1 then
		return self.pathPoints[1].position
	end
	
	-- If distance is 0, return first point
	if distance <= 0 then
		return self.pathPoints[1].position
	end
	
	local currentDist = 0
	for i = 2, #self.pathPoints do
		local segmentLength = (self.pathPoints[i].position - self.pathPoints[i-1].position).Magnitude
		
		if currentDist + segmentLength >= distance then
			-- Interpolate within this segment
			local t = (distance - currentDist) / segmentLength
			t = mathClamp(t, 0, 1)  -- Ensure t is between 0 and 1
			return self.pathPoints[i-1].position:Lerp(self.pathPoints[i].position, t)
		end
		
		currentDist = currentDist + segmentLength
	end
	
	-- Return last point if beyond path
	return self.pathPoints[#self.pathPoints].position
end

function Snake:updateServerCollision()
	if not self.collisionParts then return end
	
	-- Update collision box positions
	local spacing = self.length * 4 / #self.collisionParts
	
	for i, part in ipairs(self.collisionParts) do
		local distance = (i - 1) * spacing
		local pos = self:getPositionAlongPath(distance)
		if pos then
			part.Position = pos
		end
	end
end

function Snake:updateHead()
	if not self.headPart then return end
	
	local growthFactor = self:calculateGrowthFactor()
	self.headPart.CFrame = self.rootPart.CFrame
	self.headPart.Size = Vector3new(7, 7, 7) * growthFactor
	
	-- Update eyes
	if self.leftEye and self.rightEye then
		local eyeOffset = 2 * growthFactor
		local eyeForward = -3 * growthFactor
		local headCF = self.rootPart.CFrame
		
		self.leftEye.CFrame = headCF * CFramenew(-eyeOffset, 0, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeOffset, 0, eyeForward)
		
		self.leftEye.Size = Vector3new(1.5, 1.5, 1.5) * growthFactor
		self.rightEye.Size = Vector3new(1.5, 1.5, 1.5) * growthFactor
	end
end

function Snake:onDeath()
	if self.isDead then return end
	self.isDead = true
	
	print("💀 Snake died! Spawning death orbs...")
	
	-- Only spawn orbs on server
	if IS_SERVER then
		self:spawnDeathOrbs()
	end
	
	-- Clean up snake after delay
	wait(0.5)
	self:destroy()
end

function Snake:spawnDeathOrbs()
	-- Calculate orb count based on length
	local orbCount = mathFloor(self.length / DEATH_ORB_VALUE)
	orbCount = mathMin(orbCount, 50)  -- Cap at 50 orbs
	
	print("🔮 Spawning", orbCount, "death orbs")
	
	-- Get orb spawner
	local orbSpawner = workspace:FindFirstChild("OrbSpawner") or ReplicatedStorage:FindFirstChild("OrbSpawner")
	
	-- Spawn orbs along the snake's path
	for i = 1, orbCount do
		local distance = (i - 1) * DEATH_ORB_SPACING
		local position = self:getPositionAlongPath(distance)
		
		if position then
			-- Add random offset
			local offset = Vector3new(
				mathRandom(-5, 5),
				mathRandom(0, 3),
				mathRandom(-5, 5)
			)
			
			local orbPos = position + offset
			
			-- Create death orb
			local orb = Instance.new("Part")
			orb.Name = "DeathOrb"
			orb.Shape = Enum.PartType.Ball
			orb.Material = Enum.Material.Neon
			orb.Size = Vector3new(DEATH_ORB_SIZE, DEATH_ORB_SIZE, DEATH_ORB_SIZE)
			orb.Color = self.bodyColors[mathRandom(1, #self.bodyColors)]
			orb.TopSurface = Enum.SurfaceType.Smooth
			orb.BottomSurface = Enum.SurfaceType.Smooth
			orb.CanCollide = false
			orb.Position = orbPos
			
			-- Add glow
			local glow = Instance.new("PointLight")
			glow.Brightness = 2
			glow.Range = 10
			glow.Color = orb.Color
			glow.Parent = orb
			
			-- Make it float
			local bodyPos = Instance.new("BodyPosition")
			bodyPos.MaxForce = Vector3new(4000, 4000, 4000)
			bodyPos.Position = orbPos
			bodyPos.Parent = orb
			
			local bodyVel = Instance.new("BodyVelocity")
			bodyVel.MaxForce = Vector3new(4000, 0, 4000)
			bodyVel.Velocity = Vector3new(mathRandom(-10, 10), 0, mathRandom(-10, 10))
			bodyVel.Parent = orb
			
			-- Tag as death orb with value
			orb:SetAttribute("OrbValue", DEATH_ORB_VALUE)
			orb:SetAttribute("IsDeathOrb", true)
			orb:SetAttribute("SourcePlayer", self.player.Name)
			CollectionService:AddTag(orb, "Orb")
			
			orb.Parent = workspace
			
			-- Slow down over time
			Debris:AddItem(bodyVel, 1)
			
			-- Make orb permanent until collected
			spawn(function()
				wait(1)
				if orb.Parent then
					bodyPos.Position = orb.Position  -- Stop at current position
				end
			end)
		end
	end
end

function Snake:startUpdateLoop()
	local updateCounter = 0
	
	self.updateConnection = RunService.Heartbeat:Connect(function()
		if not self.character.Parent or self.isDead then
			return
		end
		
		updateCounter = updateCounter + 1
		
		-- Update path tracking
		self:updatePath()
		
		-- Client updates
		if IS_CLIENT then
			-- Update anchor part position to follow player
			if self.anchorPart then
				self.anchorPart.CFrame = self.rootPart.CFrame
			end
			
			self:updateBeamPositions()
			self:updateHead()
			
			-- Less frequent updates for beam recreation
			if updateCounter % 60 == 0 then
				self:checkBeamIntegrity()
			end
		end
		
		-- Server updates
		if IS_SERVER then
			if updateCounter % 3 == 0 then
				self:updateServerCollision()
			end
		end
	end)
end

function Snake:checkBeamIntegrity()
	-- Recreate beams if length changed significantly
	local desiredSegments = mathMin(mathFloor(self.length * 4 / BEAM_SEGMENT_LENGTH), MAX_BEAM_SEGMENTS)
	
	if math.abs(desiredSegments - #self.attachments) > 10 then
		print("🔄 Recreating beam system due to length change")
		
		-- Clear old
		for _, beam in ipairs(self.beams) do
			beam:Destroy()
		end
		for _, attachment in ipairs(self.attachments) do
			attachment:Destroy()
		end
		
		self.beams = {}
		self.attachments = {}
		
		-- Recreate
		self:createPureBeamSystem()
	end
end

function Snake:setLength(newLength)
	self.length = mathMax(10, newLength)
	
	if IS_SERVER then
		self.player:SetAttribute("SnakeLength", self.length)
	end
end

function Snake:destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	if self.model then
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV8.init()
	if IS_SERVER then
		print("✅ OptimizedSnakeSystemV8 PURE BEAM - Server initialized")
	else
		print("✅ OptimizedSnakeSystemV8 PURE BEAM - Client initialized")
		-- Client initialization is handled by SnakeMovement calling createSnake
	end
end

return OptimizedSnakeSystemV8