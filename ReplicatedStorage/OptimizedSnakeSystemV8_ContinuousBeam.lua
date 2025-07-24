-- Optimized Snake System V8 - CONTINUOUS BEAM SYSTEM (Like Real Slither.io)
-- Revolutionary approach: Uses beams for visuals (no gaps possible) with invisible parts for collision

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance constants
local ATTACHMENT_POOL_SIZE = 500  -- Attachments along the snake
local COLLISION_PART_POOL_SIZE = 100  -- Invisible parts for collision
local PATH_RESOLUTION = 2  -- Distance between path points
local NETWORK_UPDATE_RATE = 20  -- Hz
local BEAM_SEGMENTS = 10  -- Curve segments per beam section

-- Visual settings
local BEAM_WIDTH_BASE = 4  -- Base width of the snake
local BEAM_TEXTURE = "rbxasset://textures/ui/LuaChat/icons/ic-check.png"  -- Simple texture
local BEAM_TEXTURE_SPEED = 2  -- Texture scroll speed
local BEAM_TRANSPARENCY = NumberSequence.new(0)  -- Fully opaque

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathSin = math.sin
local mathCos = math.cos
local tick = tick

-- Object pools
local AttachmentPool = {}
local CollisionPartPool = {}
local ActiveAttachments = {}
local ActiveCollisionParts = {}

-- Initialize pools
local function initializePools()
	-- Attachment pool for beam points
	for i = 1, ATTACHMENT_POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "PooledAttachment" .. i
		attachment.Visible = false
		attachment.Parent = nil
		AttachmentPool[i] = attachment
		ActiveAttachments[attachment] = false
	end
	
	-- Collision part pool
	for i = 1, COLLISION_PART_POOL_SIZE do
		local part = Instance.new("Part")
		part.Name = "CollisionPart" .. i
		part.Size = Vector3new(6, 6, 6)
		part.Shape = Enum.PartType.Ball
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = true  -- For orb collection
		part.Anchored = true
		part.Parent = nil
		
		CollisionPartPool[i] = part
		ActiveCollisionParts[part] = false
	end
	
	print("✅ Continuous beam system pools initialized")
end

-- Get from pools
local function getAttachmentFromPool()
	for i = 1, ATTACHMENT_POOL_SIZE do
		local attachment = AttachmentPool[i]
		if not ActiveAttachments[attachment] then
			ActiveAttachments[attachment] = true
			return attachment
		end
	end
	return nil
end

local function getCollisionPartFromPool()
	for i = 1, COLLISION_PART_POOL_SIZE do
		local part = CollisionPartPool[i]
		if not ActiveCollisionParts[part] then
			ActiveCollisionParts[part] = true
			return part
		end
	end
	return nil
end

-- Return to pools
local function returnAttachmentToPool(attachment)
	if attachment then
		ActiveAttachments[attachment] = false
		attachment.Parent = nil
	end
end

local function returnCollisionPartToPool(part)
	if part then
		ActiveCollisionParts[part] = false
		part.Parent = nil
		part.CFrame = CFramenew(0, -10000, 0)
	end
end

-- Snake class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config or {}
	
	-- Set defaults
	self.config.BaseSpeed = self.config.BaseSpeed or 50
	self.config.TurnSpeed = self.config.TurnSpeed or 4
	self.config.InitialLength = self.config.InitialLength or 10
	self.config.HeadColor = self.config.HeadColor or Color3.fromRGB(0, 255, 0)
	self.config.BodyColors = self.config.BodyColors or {Color3.fromRGB(0, 200, 0)}
	
	if not self.player then
		warn("Failed to get player from character")
		return nil
	end
	
	-- Hide character completely
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
	self.rootPart.CanTouch = true  -- For orb detection
	
	-- Core data
	self.length = self.config.InitialLength
	self.pathPoints = {}  -- Actual path positions
	self.attachments = {}  -- Attachments along the path
	self.beams = {}  -- Beam connections
	self.collisionParts = {}  -- Invisible collision parts
	self.skinName = "Default"
	
	-- Movement state
	self.currentSpeed = self.config.BaseSpeed
	self.isBoosting = false
	self.lastUpdateTime = tick()
	self.direction = self.rootPart.CFrame.LookVector
	
	-- Create container model
	self.model = Instance.new("Model")
	self.model.Name = self.player.Name .. "_Snake"
	self.model.Parent = workspace
	
	-- Create anchor part for attachments
	self.anchorPart = Instance.new("Part")
	self.anchorPart.Name = "SnakeAnchor"
	self.anchorPart.Size = Vector3new(1, 1, 1)
	self.anchorPart.Transparency = 1
	self.anchorPart.CanCollide = false
	self.anchorPart.CanQuery = false
	self.anchorPart.CanTouch = false
	self.anchorPart.Anchored = true
	self.anchorPart.CFrame = self.rootPart.CFrame
	self.anchorPart.Parent = self.model
	
	-- Initialize snake
	self:createHead()
	self:initializePath()
	self:createBeamChain()
	
	-- Start update loops
	self:startUpdateLoops()
	
	-- Handle skin
	self:applySkin(self.config.SkinName or "Default")
	
	-- Tag for other systems
	self.model:SetAttribute("SnakeOwner", self.player.Name)
	self.model:SetAttribute("SnakeLength", self.length)
	
	return self
end

function Snake:createHead()
	-- Create visible head
	self.head = Instance.new("Part")
	self.head.Name = "Head"
	self.head.Size = self.config.HeadSize or Vector3new(5, 5, 5)
	self.head.Shape = Enum.PartType.Ball
	self.head.Material = Enum.Material.Neon
	self.head.Color = self.config.HeadColor
	self.head.TopSurface = Enum.SurfaceType.Smooth
	self.head.BottomSurface = Enum.SurfaceType.Smooth
	self.head.CanCollide = false
	self.head.CanQuery = false
	self.head.CanTouch = false
	self.head.Anchored = true
	self.head.Parent = self.model
	
	-- Create eyes
	local eyeSize = Vector3new(1, 1, 1)
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
	
	-- Pupils
	local pupilSize = Vector3new(0.5, 0.5, 0.5)
	self.leftPupil = Instance.new("Part")
	self.leftPupil.Name = "LeftPupil"
	self.leftPupil.Size = pupilSize
	self.leftPupil.Shape = Enum.PartType.Ball
	self.leftPupil.Material = Enum.Material.Neon
	self.leftPupil.Color = Color3.new(0, 0, 0)
	self.leftPupil.CanCollide = false
	self.leftPupil.Anchored = true
	self.leftPupil.Parent = self.model
	
	self.rightPupil = self.leftPupil:Clone()
	self.rightPupil.Name = "RightPupil"
	self.rightPupil.Parent = self.model
	
	-- Head glow
	local glow = Instance.new("PointLight")
	glow.Brightness = 2
	glow.Range = 10
	glow.Color = self.config.HeadColor
	glow.Parent = self.head
end

function Snake:initializePath()
	-- Create initial path behind the snake
	local startPos = self.rootPart.Position
	local startDir = -self.rootPart.CFrame.LookVector  -- Behind the snake
	
	-- Calculate total path distance needed
	local totalDistance = self.length * BEAM_WIDTH_BASE
	local numPoints = mathFloor(totalDistance / PATH_RESOLUTION) + 1
	
	-- Create path points
	for i = 0, numPoints do
		local distance = i * PATH_RESOLUTION
		local position = startPos + startDir * distance
		
		table.insert(self.pathPoints, {
			position = position,
			distance = distance,
			width = self:getWidthAtDistance(distance)
		})
	end
end

function Snake:createBeamChain()
	-- Clear existing
	for _, beam in ipairs(self.beams) do
		beam:Destroy()
	end
	self.beams = {}
	
	for _, attachment in ipairs(self.attachments) do
		returnAttachmentToPool(attachment)
	end
	self.attachments = {}
	
	-- Create attachments along the path
	local attachmentSpacing = BEAM_WIDTH_BASE * 0.8  -- Slightly overlapping for smoothness
	local numAttachments = mathFloor(self.length * BEAM_WIDTH_BASE / attachmentSpacing)
	
	for i = 0, numAttachments do
		local attachment = getAttachmentFromPool()
		if attachment then
			attachment.Parent = self.anchorPart
			attachment.WorldPosition = self:getPositionAtDistance(i * attachmentSpacing)
			table.insert(self.attachments, attachment)
		end
	end
	
	-- Create beams between attachments
	for i = 1, #self.attachments - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "BodyBeam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]
		
		-- Visual properties
		beam.Width0 = self:getWidthAtDistance((i - 1) * attachmentSpacing)
		beam.Width1 = self:getWidthAtDistance(i * attachmentSpacing)
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Segments = BEAM_SEGMENTS
		beam.Transparency = BEAM_TRANSPARENCY
		
		-- Color based on pattern
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		
		-- Texture for pattern
		beam.Texture = BEAM_TEXTURE
		beam.TextureSpeed = BEAM_TEXTURE_SPEED
		beam.TextureLength = 2
		beam.TextureMode = Enum.TextureMode.Wrap
		
		beam.FaceCamera = true
		beam.Parent = self.anchorPart
		
		table.insert(self.beams, beam)
	end
	
	-- Create collision parts along the snake
	self:updateCollisionParts()
end

function Snake:getPositionAtDistance(distance)
	-- Find position along the path at given distance
	local currentDist = 0
	
	for i = 2, #self.pathPoints do
		local p1 = self.pathPoints[i - 1]
		local p2 = self.pathPoints[i]
		local segmentLength = (p2.position - p1.position).Magnitude
		
		if currentDist + segmentLength >= distance then
			-- Interpolate within this segment
			local t = (distance - currentDist) / segmentLength
			return p1.position:Lerp(p2.position, t)
		end
		
		currentDist = currentDist + segmentLength
	end
	
	-- Return last point if distance exceeds path
	return self.pathPoints[#self.pathPoints].position
end

function Snake:getWidthAtDistance(distance)
	-- Calculate width based on distance from head
	local maxDistance = self.length * BEAM_WIDTH_BASE
	local t = distance / maxDistance
	
	-- Taper towards tail
	local baseWidth = BEAM_WIDTH_BASE * self:calculateGrowthFactor()
	return baseWidth * (1 - t * 0.3)  -- 30% taper to tail
end

function Snake:calculateGrowthFactor()
	-- Scale based on length
	local baseLength = self.config.InitialLength or 10
	local growthRate = 0.02  -- 2% per unit length
	return 1 + (self.length - baseLength) * growthRate
end

function Snake:updateCollisionParts()
	-- Clear old collision parts
	for _, part in ipairs(self.collisionParts) do
		returnCollisionPartToPool(part)
	end
	self.collisionParts = {}
	
	-- Create collision parts at intervals
	local collisionSpacing = BEAM_WIDTH_BASE * 2  -- Less dense than visual
	local numParts = mathMin(mathFloor(self.length * BEAM_WIDTH_BASE / collisionSpacing), COLLISION_PART_POOL_SIZE)
	
	for i = 0, numParts - 1 do
		local part = getCollisionPartFromPool()
		if part then
			local distance = i * collisionSpacing
			part.Position = self:getPositionAtDistance(distance)
			part.Size = Vector3new(1, 1, 1) * self:getWidthAtDistance(distance)
			part.Parent = self.model
			table.insert(self.collisionParts, part)
			
			-- Tag for collision detection
			part:SetAttribute("SnakeOwner", self.player.Name)
			part:SetAttribute("SegmentIndex", i)
		end
	end
end

function Snake:updatePath()
	-- Add new point at head
	local headPos = self.rootPart.Position
	local newPoint = {
		position = headPos,
		distance = 0,
		width = self:getWidthAtDistance(0)
	}
	
	-- Only add if moved enough
	if #self.pathPoints > 0 then
		local lastPoint = self.pathPoints[1]
		local dist = (headPos - lastPoint.position).Magnitude
		
		if dist < PATH_RESOLUTION * 0.5 then
			return  -- Don't add point yet
		end
	end
	
	-- Add new point
	table.insert(self.pathPoints, 1, newPoint)
	
	-- Recalculate distances
	local totalDist = 0
	for i = 2, #self.pathPoints do
		local dist = (self.pathPoints[i].position - self.pathPoints[i-1].position).Magnitude
		totalDist = totalDist + dist
		self.pathPoints[i].distance = totalDist
	end
	
	-- Trim path to snake length
	local maxDistance = self.length * BEAM_WIDTH_BASE
	for i = #self.pathPoints, 1, -1 do
		if self.pathPoints[i].distance > maxDistance then
			table.remove(self.pathPoints, i)
		else
			break
		end
	end
end

function Snake:updateAttachments()
	-- Update attachment positions along the path
	local attachmentSpacing = BEAM_WIDTH_BASE * 0.8
	
	for i, attachment in ipairs(self.attachments) do
		local distance = (i - 1) * attachmentSpacing
		attachment.WorldPosition = self:getPositionAtDistance(distance)
	end
	
	-- Update beam widths
	for i, beam in ipairs(self.beams) do
		local distance0 = (i - 1) * attachmentSpacing
		local distance1 = i * attachmentSpacing
		beam.Width0 = self:getWidthAtDistance(distance0)
		beam.Width1 = self:getWidthAtDistance(distance1)
	end
end

function Snake:updateHead()
	-- Update head position and rotation
	local headCF = self.rootPart.CFrame
	self.head.CFrame = headCF
	
	-- Update eyes
	local growthFactor = self:calculateGrowthFactor()
	local eyeOffset = 1.5 * growthFactor
	local eyeForward = 2 * growthFactor
	
	self.leftEye.CFrame = headCF * CFramenew(-eyeOffset, 0, -eyeForward)
	self.rightEye.CFrame = headCF * CFramenew(eyeOffset, 0, -eyeForward)
	
	self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3)
	
	-- Scale head with growth
	local headSize = (self.config.HeadSize or Vector3new(5, 5, 5)) * growthFactor
	self.head.Size = headSize
end

function Snake:startUpdateLoops()
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		-- Update path
		self:updatePath()
		
		-- Update visual components
		self:updateHead()
		self:updateAttachments()
		
		-- Update collision parts less frequently
		if tick() - self.lastUpdateTime > 0.1 then
			self:updateCollisionParts()
			self.lastUpdateTime = tick()
		end
		
		-- Update model attribute
		self.model:SetAttribute("SnakeLength", self.length)
	end)
end

function Snake:setLength(newLength)
	self.length = mathMax(10, newLength)  -- Minimum length of 10
	
	-- Recreate beam chain if length changed significantly
	local numAttachmentsNeeded = mathFloor(self.length * BEAM_WIDTH_BASE / (BEAM_WIDTH_BASE * 0.8))
	if math.abs(numAttachmentsNeeded - #self.attachments) > 5 then
		self:createBeamChain()
	end
end

function Snake:applySkin(skinName)
	self.skinName = skinName
	
	-- Get skin data
	local skinData = self:getSkinData(skinName)
	if not skinData then return end
	
	-- Apply colors
	self.config.HeadColor = skinData.HeadColor or self.config.HeadColor
	self.config.BodyColors = skinData.BodyColors or self.config.BodyColors
	
	-- Update head color
	self.head.Color = self.config.HeadColor
	
	-- Update beam colors
	for i, beam in ipairs(self.beams) do
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
	end
end

function Snake:getSkinData(skinName)
	-- This would normally load from a module
	local skins = {
		Default = {
			HeadColor = Color3.fromRGB(0, 255, 0),
			BodyColors = {Color3.fromRGB(0, 200, 0)}
		},
		Fire = {
			HeadColor = Color3.fromRGB(255, 100, 0),
			BodyColors = {Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 150, 0)}
		},
		Ocean = {
			HeadColor = Color3.fromRGB(0, 150, 255),
			BodyColors = {Color3.fromRGB(0, 100, 200), Color3.fromRGB(0, 200, 255)}
		}
	}
	
	return skins[skinName]
end

function Snake:destroy()
	-- Cleanup
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	-- Return all pooled objects
	for _, attachment in ipairs(self.attachments) do
		returnAttachmentToPool(attachment)
	end
	
	for _, part in ipairs(self.collisionParts) do
		returnCollisionPartToPool(part)
	end
	
	-- Destroy model
	if self.model then
		self.model:Destroy()
	end
end

-- Module initialization
local module = {}

function module.new(character, config)
	return Snake.new(character, config)
end

function module.init()
	initializePools()
end

-- Auto-initialize on require
module.init()

return module