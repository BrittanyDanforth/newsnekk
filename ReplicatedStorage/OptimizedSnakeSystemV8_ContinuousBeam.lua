-- Optimized Snake System V8 - CONTINUOUS BEAM SYSTEM (Slither.io Style)
-- Integrates with SnakeSystemIntegration and SnakeNetworkHandler
-- NO GAPS POSSIBLE - Uses beam technology

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Performance constants
local ATTACHMENT_POOL_SIZE = 500
local COLLISION_PART_POOL_SIZE = 100
local PATH_RESOLUTION = 2
local NETWORK_UPDATE_RATE = 15  -- Match SnakeNetworkHandler
local BEAM_SEGMENTS = 10
local HISTORY_SIZE = 2000

-- Visual settings
local BEAM_WIDTH_BASE = 4
local BEAM_TEXTURE = "rbxasset://textures/ui/LuaChat/icons/ic-check.png"
local BEAM_TEXTURE_SPEED = 2
local BEAM_TRANSPARENCY = NumberSequence.new(0)

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local tick = tick

-- Object pools
local AttachmentPool = {}
local CollisionPartPool = {}
local ActiveAttachments = {}
local ActiveCollisionParts = {}

-- Module
local OptimizedSnakeSystemV8 = {}

-- Initialize pools
local function initializePools()
	-- Create attachment pool
	for i = 1, ATTACHMENT_POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "PooledAttachment" .. i
		attachment.Visible = false
		attachment.Parent = nil
		AttachmentPool[i] = attachment
		ActiveAttachments[attachment] = false
	end
	
	-- Create collision part pool
	for i = 1, COLLISION_PART_POOL_SIZE do
		local part = Instance.new("Part")
		part.Name = "CollisionPart" .. i
		part.Size = Vector3new(6, 6, 6)
		part.Shape = Enum.PartType.Ball
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = true
		part.Anchored = true
		part.Parent = nil
		
		CollisionPartPool[i] = part
		ActiveCollisionParts[part] = false
	end
	
	print("✅ Continuous beam pools initialized")
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

-- Create network events (compatible with existing system)
local function createNetworkEvents()
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end
	
	-- Use same event names as other versions
	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate"}
	for _, eventName in ipairs(events) do
		if not folder:FindFirstChild(eventName) then
			local event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = folder
		end
	end
	
	return folder
end

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
	
	-- Apply defaults
	self.config.InitialLength = self.config.InitialLength or 10
	self.config.HeadSize = self.config.HeadSize or Vector3new(4.5, 4.5, 4.5)
	self.config.SegmentSize = self.config.SegmentSize or Vector3new(4, 4, 4)
	self.config.HeadColor = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.config.BodyColors = self.config.BodyColors or {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	}
	
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
	
	-- Core data
	self.length = self.config.InitialLength
	self.pathPoints = {}
	self.attachments = {}
	self.beams = {}
	self.collisionParts = {}
	self.skinName = self.config.SkinName or "Default"
	
	-- Movement history (for network sync)
	self.positionHistory = {}
	self.historyIndex = 0
	
	-- State
	self.isBoosting = false
	self.lastUpdateTime = tick()
	self.networkUpdateTime = 0
	
	-- Create model
	self.model = Instance.new("Model")
	self.model.Name = self.player.Name .. "_Snake"
	self.model.Parent = workspace
	
	-- Anchor part for attachments
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
	
	-- Initialize
	self:createHead()
	self:initializePath()
	self:createBeamChain()
	self:startUpdateLoops()
	
	-- Apply initial skin
	if self.config.SkinName then
		self:applySkin(self.config.SkinName)
	end
	
	-- Tag for other systems
	self.model:SetAttribute("SnakeOwner", self.player.Name)
	self.model:SetAttribute("SnakeLength", self.length)
	CollectionService:AddTag(self.model, "PlayerSnake")
	
	return self
end

function Snake:createHead()
	-- Create head (invisible, just for collision)
	self.head = Instance.new("Part")
	self.head.Name = "Head"
	self.head.Size = self.config.HeadSize
	self.head.Shape = Enum.PartType.Ball
	self.head.Material = Enum.Material.Neon
	self.head.Color = self.config.HeadColor
	self.head.Transparency = 1  -- Invisible like other systems
	self.head.CanCollide = false
	self.head.CanQuery = false
	self.head.CanTouch = false
	self.head.Anchored = true
	self.head.Parent = self.model
	
	-- Create visible eyes
	local eyeSize = Vector3new(0.8, 0.8, 0.8)
	
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
	local pupilSize = Vector3new(0.4, 0.4, 0.4)
	
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
	glow.Brightness = 1.5
	glow.Range = 6
	glow.Color = self.config.HeadColor
	glow.Parent = self.head
end

function Snake:initializePath()
	-- Create initial straight path
	local startPos = self.rootPart.Position
	local startDir = -self.rootPart.CFrame.LookVector
	
	local totalDistance = self.length * BEAM_WIDTH_BASE
	local numPoints = mathFloor(totalDistance / PATH_RESOLUTION) + 1
	
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
	
	-- Calculate attachment count based on length
	local attachmentSpacing = BEAM_WIDTH_BASE * 0.8
	local numAttachments = mathMin(mathFloor(self.length * BEAM_WIDTH_BASE / attachmentSpacing), ATTACHMENT_POOL_SIZE - 1)
	
	-- Create attachments
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
		
		-- Apply pattern colors
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
		
		-- Texture
		beam.Texture = BEAM_TEXTURE
		beam.TextureSpeed = BEAM_TEXTURE_SPEED
		beam.TextureLength = 2
		beam.TextureMode = Enum.TextureMode.Wrap
		
		beam.FaceCamera = true
		beam.Parent = self.anchorPart
		
		table.insert(self.beams, beam)
	end
	
	-- Update collision parts
	self:updateCollisionParts()
end

function Snake:getPositionAtDistance(distance)
	-- Interpolate position along path
	local currentDist = 0
	
	for i = 2, #self.pathPoints do
		local p1 = self.pathPoints[i - 1]
		local p2 = self.pathPoints[i]
		local segmentLength = (p2.position - p1.position).Magnitude
		
		if currentDist + segmentLength >= distance then
			local t = (distance - currentDist) / segmentLength
			return p1.position:Lerp(p2.position, t)
		end
		
		currentDist = currentDist + segmentLength
	end
	
	return self.pathPoints[#self.pathPoints].position
end

function Snake:getWidthAtDistance(distance)
	-- Calculate width with taper
	local maxDistance = self.length * BEAM_WIDTH_BASE
	local t = distance / maxDistance
	
	-- Growth factor based on length
	local growthFactor = self:calculateGrowthFactor()
	local baseWidth = (self.config.SegmentSize.X or 4) * growthFactor
	
	-- Taper to tail
	return baseWidth * (1 - t * 0.3)
end

function Snake:calculateGrowthFactor()
	-- Match other optimized systems growth
	local baseLength = self.config.InitialLength or 10
	
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

function Snake:updateCollisionParts()
	-- Clear old parts
	for _, part in ipairs(self.collisionParts) do
		returnCollisionPartToPool(part)
	end
	self.collisionParts = {}
	
	-- Create collision parts
	local spacing = BEAM_WIDTH_BASE * 2
	local numParts = mathMin(mathFloor(self.length * BEAM_WIDTH_BASE / spacing), COLLISION_PART_POOL_SIZE)
	
	for i = 0, numParts - 1 do
		local part = getCollisionPartFromPool()
		if part then
			local distance = i * spacing
			part.Position = self:getPositionAtDistance(distance)
			part.Size = Vector3new(1, 1, 1) * self:getWidthAtDistance(distance)
			part.Parent = self.model
			table.insert(self.collisionParts, part)
			
			-- Tag for collision
			part:SetAttribute("SnakeOwner", self.player.Name)
			part:SetAttribute("SegmentIndex", i)
			CollectionService:AddTag(part, "SnakeSegment")
		end
	end
end

function Snake:updatePath()
	-- Add new head position
	local headPos = self.rootPart.Position
	local newPoint = {
		position = headPos,
		distance = 0,
		width = self:getWidthAtDistance(0)
	}
	
	-- Check minimum distance
	if #self.pathPoints > 0 then
		local lastPoint = self.pathPoints[1]
		local dist = (headPos - lastPoint.position).Magnitude
		
		if dist < PATH_RESOLUTION * 0.5 then
			return
		end
	end
	
	-- Add to path
	table.insert(self.pathPoints, 1, newPoint)
	
	-- Recalculate distances
	local totalDist = 0
	for i = 2, #self.pathPoints do
		local dist = (self.pathPoints[i].position - self.pathPoints[i-1].position).Magnitude
		totalDist = totalDist + dist
		self.pathPoints[i].distance = totalDist
	end
	
	-- Trim to length
	local maxDistance = self.length * BEAM_WIDTH_BASE
	for i = #self.pathPoints, 1, -1 do
		if self.pathPoints[i].distance > maxDistance then
			table.remove(self.pathPoints, i)
		else
			break
		end
	end
	
	-- Add to history for networking
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = {
		position = headPos,
		lookVector = self.rootPart.CFrame.LookVector,
		time = tick()
	}
end

function Snake:updateAttachments()
	-- Update attachment positions
	local spacing = BEAM_WIDTH_BASE * 0.8
	
	for i, attachment in ipairs(self.attachments) do
		local distance = (i - 1) * spacing
		attachment.WorldPosition = self:getPositionAtDistance(distance)
	end
	
	-- Update beam widths
	for i, beam in ipairs(self.beams) do
		local distance0 = (i - 1) * spacing
		local distance1 = i * spacing
		beam.Width0 = self:getWidthAtDistance(distance0)
		beam.Width1 = self:getWidthAtDistance(distance1)
	end
end

function Snake:updateHead()
	-- Update head and eyes
	local growthFactor = self:calculateGrowthFactor()
	local headCF = self.rootPart.CFrame
	
	self.head.CFrame = headCF
	self.head.Size = self.config.HeadSize * growthFactor
	
	-- Update eyes with proper scaling
	local eyeSpacing = 0.7 * growthFactor
	local eyeHeight = 0.7 * growthFactor
	local eyeForward = -1.5 * growthFactor
	
	self.leftEye.CFrame = headCF * CFramenew(-eyeSpacing, eyeHeight, eyeForward)
	self.rightEye.CFrame = headCF * CFramenew(eyeSpacing, eyeHeight, eyeForward)
	
	self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
	self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
	
	-- Scale eyes
	local eyeScale = growthFactor * 0.8
	self.leftEye.Size = Vector3new(0.8, 0.8, 0.8) * eyeScale
	self.rightEye.Size = Vector3new(0.8, 0.8, 0.8) * eyeScale
	self.leftPupil.Size = Vector3new(0.4, 0.4, 0.4) * eyeScale
	self.rightPupil.Size = Vector3new(0.4, 0.4, 0.4) * eyeScale
end

function Snake:startUpdateLoops()
	-- Main update
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		-- Update path
		self:updatePath()
		
		-- Update visuals
		self:updateHead()
		self:updateAttachments()
		
		-- Update collision less frequently
		if tick() - self.lastUpdateTime > 0.1 then
			self:updateCollisionParts()
			self.lastUpdateTime = tick()
		end
		
		-- Network update
		if tick() - self.networkUpdateTime > (1 / NETWORK_UPDATE_RATE) then
			self.networkUpdateTime = tick()
			self:sendNetworkUpdate()
		end
		
		-- Update attributes
		self.model:SetAttribute("SnakeLength", self.length)
	end)
end

function Snake:sendNetworkUpdate()
	-- Send position data to server (compatible with SnakeNetworkHandler)
	local networkFolder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not networkFolder then return end
	
	local positionUpdate = networkFolder:FindFirstChild("PositionUpdate")
	if positionUpdate and self.player == Players.LocalPlayer then
		-- Compress data
		local compressedHistory = {}
		for i = 1, mathMin(10, #self.positionHistory) do
			local data = self.positionHistory[i]
			if data then
				table.insert(compressedHistory, {
					p = Vector3new(
						math.floor(data.position.X * 10) / 10,
						math.floor(data.position.Y * 10) / 10,
						math.floor(data.position.Z * 10) / 10
					),
					l = data.lookVector
				})
			end
		end
		
		positionUpdate:FireServer({
			history = compressedHistory,
			length = self.length,
			boosting = self.isBoosting
		})
	end
end

function Snake:setLength(newLength)
	self.length = mathMax(10, newLength)
	
	-- Update network
	local networkFolder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if networkFolder then
		local lengthUpdate = networkFolder:FindFirstChild("LengthUpdate")
		if lengthUpdate and self.player == Players.LocalPlayer then
			lengthUpdate:FireServer(self.length)
		end
	end
	
	-- Recreate beams if needed
	local numAttachmentsNeeded = mathFloor(self.length * BEAM_WIDTH_BASE / (BEAM_WIDTH_BASE * 0.8))
	if math.abs(numAttachmentsNeeded - #self.attachments) > 5 then
		self:createBeamChain()
	end
end

function Snake:applySkin(skinName)
	self.skinName = skinName
	
	-- Load skin data (would come from your skin system)
	local skinData = self:getSkinData(skinName)
	if not skinData then return end
	
	-- Apply colors
	self.config.HeadColor = skinData.HeadColor or self.config.HeadColor
	self.config.BodyColors = skinData.BodyColors or self.config.BodyColors
	
	-- Update visuals
	self.head.Color = self.config.HeadColor
	local glow = self.head:FindFirstChild("PointLight")
	if glow then
		glow.Color = self.config.HeadColor
	end
	
	-- Update beams
	for i, beam in ipairs(self.beams) do
		local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
		beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
	end
	
	-- Send to network
	local networkFolder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if networkFolder then
		local skinUpdate = networkFolder:FindFirstChild("SkinUpdate")
		if skinUpdate and self.player == Players.LocalPlayer then
			skinUpdate:FireServer(skinName)
		end
	end
end

function Snake:getSkinData(skinName)
	-- This should match your existing skin system
	-- For now, basic skins
	local skins = {
		Default = {
			HeadColor = Color3.fromRGB(76, 217, 100),
			BodyColors = {
				Color3.fromRGB(60, 180, 80),
				Color3.fromRGB(80, 200, 100),
				Color3.fromRGB(100, 220, 120),
				Color3.fromRGB(80, 200, 100),
				Color3.fromRGB(60, 180, 80),
			}
		},
		Fire = {
			HeadColor = Color3.fromRGB(255, 100, 0),
			BodyColors = {
				Color3.fromRGB(255, 0, 0),
				Color3.fromRGB(255, 150, 0),
				Color3.fromRGB(255, 100, 0),
				Color3.fromRGB(255, 200, 0)
			}
		},
		Ocean = {
			HeadColor = Color3.fromRGB(0, 150, 255),
			BodyColors = {
				Color3.fromRGB(0, 100, 200),
				Color3.fromRGB(0, 200, 255),
				Color3.fromRGB(0, 150, 255),
				Color3.fromRGB(0, 180, 255)
			}
		}
	}
	
	return skins[skinName]
end

function Snake:destroy()
	-- Cleanup
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
	
	-- Return pooled objects
	for _, attachment in ipairs(self.attachments) do
		returnAttachmentToPool(attachment)
	end
	
	for _, part in ipairs(self.collisionParts) do
		returnCollisionPartToPool(part)
	end
	
	-- Remove tags
	if self.model then
		CollectionService:RemoveTag(self.model, "PlayerSnake")
	end
	
	-- Destroy model
	if self.model then
		self.model:Destroy()
	end
end

-- Module functions (compatible with existing system)
function OptimizedSnakeSystemV8.new(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV8.init()
	-- Initialize pools
	initializePools()
	
	-- Create network folder (for compatibility)
	createNetworkEvents()
	
	print("✅ OptimizedSnakeSystemV8 - Continuous Beam System initialized!")
end

return OptimizedSnakeSystemV8