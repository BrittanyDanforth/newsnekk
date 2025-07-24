-- Optimized Snake System V8 - PURE BEAM RENDERING
-- Ultra-smooth beam-based snake body for maximum performance

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

-- Performance constants
local ATTACHMENT_POOL_SIZE = 500
local BEAM_POOL_SIZE = 250
local NETWORK_UPDATE_RATE = 20
local MAX_VISIBLE_ATTACHMENTS = 150
local BOOST_VISIBLE_ATTACHMENTS = 120
local HISTORY_SIZE = 1500
local BEAM_TEXTURE = "" -- No texture for clean solid look, set to texture ID if you want patterns

-- Attachment spacing
local ATTACHMENT_SPACING = 3 -- Distance between attachments

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil
local tick = tick

-- Pools
local AttachmentPool = {}
local BeamPool = {}
local ActiveAttachments = {}
local ActiveBeams = {}

-- Initialize attachment pool
local function initializeAttachmentPool()
	-- Create invisible part to hold attachments
	local holder = Instance.new("Part")
	holder.Name = "AttachmentHolder"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Anchored = true
	holder.Parent = workspace
	
	for i = 1, ATTACHMENT_POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "PooledAttachment" .. i
		attachment.Parent = holder
		AttachmentPool[i] = attachment
		ActiveAttachments[attachment] = false
	end
	
	-- Initialize beam pool
	for i = 1, BEAM_POOL_SIZE do
		local beam = Instance.new("Beam")
		beam.Name = "PooledBeam" .. i
		beam.Texture = BEAM_TEXTURE
		beam.TextureSpeed = 2 -- Animated texture flow
		beam.TextureLength = 2
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.Width0 = 4
		beam.Width1 = 4
		beam.FaceCamera = true
		beam.Segments = 20 -- Very smooth curves
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.2)
		})
		beam.Parent = holder
		beam.Enabled = false
		BeamPool[i] = beam
		ActiveBeams[beam] = false
	end
	
	print("✅ Beam system pools initialized")
	return holder
end

local attachmentHolder = nil

-- Get attachment from pool
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

-- Return attachment to pool
local function returnAttachmentToPool(attachment)
	if attachment then
		ActiveAttachments[attachment] = false
		attachment.WorldPosition = Vector3new(0, -10000, 0)
	end
end

-- Get beam from pool
local function getBeamFromPool()
	for i = 1, BEAM_POOL_SIZE do
		local beam = BeamPool[i]
		if not ActiveBeams[beam] then
			ActiveBeams[beam] = true
			beam.Enabled = true
			return beam
		end
	end
	return nil
end

-- Return beam to pool
local function returnBeamToPool(beam)
	if beam then
		ActiveBeams[beam] = false
		beam.Enabled = false
		beam.Attachment0 = nil
		beam.Attachment1 = nil
	end
end

-- Create network events
local remoteEvents = {}
local function createNetworkEvents()
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end

	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate"}
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

-- Snake Class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)

	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config

	if not self.player then
		warn("Failed to get player from character")
		return nil
	end

	-- Hide character parts
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

	-- Snake data
	self.length = config.InitialLength or 55
	self.attachments = {}
	self.beams = {}
	self.attachmentPositions = {}
	self.visibleAttachmentCount = 0
	self.isBoosting = false

	-- Position history for smooth movement
	self.positionHistory = {}
	self.historyIndex = 1
	self.historySize = HISTORY_SIZE
	
	-- Pre-fill history
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i = 1, self.historySize do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook,
			time = tick()
		}
	end

	-- Model
	self.model = Instance.new("Model")
	self.model.Name = "SnakeModel_" .. self.player.UserId
	self.model.Parent = workspace

	-- Initialize
	self:createHead()
	self:initializeBeamBody()
	self:setupUpdateLoop()

	return self
end

function Snake:addToHistory(pos, look)
	self.historyIndex = (self.historyIndex % self.historySize) + 1
	self.positionHistory[self.historyIndex] = {
		position = pos,
		lookVector = look,
		time = tick()
	}
end

function Snake:getFromHistory(stepsBack)
	local index = self.historyIndex - stepsBack
	if index < 1 then
		index = index + self.historySize
	end
	return self.positionHistory[index]
end

function Snake:createHead()
	-- Create head part
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	head.Size = self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)
	head.Shape = Enum.PartType.Ball
	head.Material = self.config.HeadMaterial or Enum.Material.Neon
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Transparency = 0
	head.Parent = self.model

	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Head glow
	local glow = Instance.new("PointLight")
	glow.Brightness = 2
	glow.Range = 8
	glow.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	glow.Parent = head

	-- Eyes
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = name .. "Pupil"
		pupil.Size = Vector3.new(0.4, 0.4, 0.4)
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye("LeftEye", -0.7)
	self.rightEye, self.rightPupil = createEye("RightEye", 0.7)
	self.head = head

	-- Create head attachment for first beam
	self.headAttachment = Instance.new("Attachment")
	self.headAttachment.Name = "HeadAttachment"
	self.headAttachment.Parent = head
end

function Snake:calculateGrowthFactor()
	local length = self.length
	if length <= 200 then
		return 1.0
	elseif length <= 5000 then
		return 1.0 + (length - 200) / 2400
	elseif length <= 20000 then
		return 3.0 + (length - 5000) / 7500
	else
		return 5.0 + mathMin((length - 20000) / 15000, 2.0)
	end
end

function Snake:initializeBeamBody()
	local maxVisible = self.isBoosting and BOOST_VISIBLE_ATTACHMENTS or MAX_VISIBLE_ATTACHMENTS
	self.visibleAttachmentCount = mathMin(mathCeil(self.length / 2), maxVisible)
	
	local growthFactor = self:calculateGrowthFactor()
	local beamWidth = 4 * growthFactor
	local spacing = ATTACHMENT_SPACING * growthFactor * 0.8
	
	-- Create invisible parts for collision detection at key points
	self.collisionParts = {}
	
	-- Get initial position and direction
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	
	-- Create attachments and beams
	for i = 1, self.visibleAttachmentCount do
		local attachment = getAttachmentFromPool()
		if attachment then
			attachment.Name = "BodyAttachment" .. i
			
			-- Set initial position behind head
			local offset = startLook * ((i - 1) * spacing)
			attachment.WorldPosition = startPos - offset
			self.attachmentPositions[i] = attachment.WorldPosition
			
			self.attachments[i] = attachment
			
			-- Create collision part every 5 attachments
			if i % 5 == 0 and i <= 30 then
				local collisionPart = Instance.new("Part")
				collisionPart.Name = "CollisionSegment" .. i
				collisionPart.Size = Vector3.new(beamWidth, beamWidth, beamWidth)
				collisionPart.Shape = Enum.PartType.Ball
				collisionPart.Transparency = 1
				collisionPart.CanCollide = false
				collisionPart.CanTouch = true
				collisionPart.CanQuery = true
				collisionPart.Anchored = true
				collisionPart.Position = attachment.WorldPosition
				collisionPart.Parent = self.model
				
				CollectionService:AddTag(collisionPart, "SnakeSegment")
				collisionPart:SetAttribute("SegmentIndex", i)
				collisionPart:SetAttribute("OwnerName", self.player.Name)
				
				table.insert(self.collisionParts, {part = collisionPart, attachmentIndex = i})
			end
			
			-- Create beam connecting to previous attachment
			if i > 1 then
				local beam = getBeamFromPool()
				if beam then
					beam.Attachment0 = (i == 2) and self.headAttachment or self.attachments[i-1]
					beam.Attachment1 = attachment
					
					-- Set beam color based on position with gradient
					local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
					local color = self.config.BodyColors[colorIndex]
					local nextColorIndex = (i % #self.config.BodyColors) + 1
					local nextColor = self.config.BodyColors[nextColorIndex]
					
					beam.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, color),
						ColorSequenceKeypoint.new(1, nextColor)
					})
					beam.Width0 = beamWidth
					beam.Width1 = beamWidth
					
					self.beams[i-1] = beam
				end
			end
		end
	end
	
	-- Connect first beam from head
	if #self.attachments > 0 then
		local firstBeam = getBeamFromPool()
		if firstBeam then
			firstBeam.Attachment0 = self.headAttachment
			firstBeam.Attachment1 = self.attachments[1]
			firstBeam.Color = ColorSequence.new(self.config.BodyColors[1])
			firstBeam.Width0 = beamWidth * 1.2 -- Slightly wider at head
			firstBeam.Width1 = beamWidth
			table.insert(self.beams, 1, firstBeam)
		end
	end
end

function Snake:setupUpdateLoop()
	local frameCount = 0
	
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.model or not self.model.Parent or not self.rootPart or not self.rootPart.Parent then
			if self.updateConnection then
				self.updateConnection:Disconnect()
				self.updateConnection = nil
			end
			return
		end
		
		frameCount = frameCount + 1
		
		-- Update position history
		local currentPos = self.rootPart.Position
		local currentLook = self.rootPart.CFrame.LookVector
		self:addToHistory(currentPos, currentLook)
		
		-- Update head
		self:updateHead()
		
		-- Update beam body
		self:updateBeamBody()
		
		-- Update collision parts
		if frameCount % 2 == 0 then
			self:updateCollisionParts()
		end
	end)
	
	-- Network updates
	if self.player == Players.LocalPlayer then
		self.networkConnection = RunService.Heartbeat:Connect(function()
			local now = tick()
			if now - (self.lastNetworkUpdate or 0) > 1/NETWORK_UPDATE_RATE then
				self.lastNetworkUpdate = now
				self:sendNetworkUpdate()
			end
		end)
	end
end

function Snake:updateHead()
	local growthFactor = self:calculateGrowthFactor()
	local headSize = (self.config.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * growthFactor
	self.head.Size = headSize
	
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	local headCF = CFramenew(currentPos, currentPos + currentLook)
	self.head.CFrame = headCF
	
	-- Update eyes
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor * 0.8
		self.leftEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		self.rightEye.Size = Vector3.new(0.8, 0.8, 0.8) * eyeScale
		self.leftPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale
		self.rightPupil.Size = Vector3.new(0.4, 0.4, 0.4) * eyeScale
		
		local eyeSeparation = 0.7 * growthFactor
		local eyeHeight = 0.7 * growthFactor
		local eyeForward = -1.5 * growthFactor
		
		self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)
		
		self.leftPupil.CFrame = self.leftEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
		self.rightPupil.CFrame = self.rightEye.CFrame * CFramenew(0, 0, -0.3 * growthFactor)
	end
end

function Snake:updateBeamBody()
	local growthFactor = self:calculateGrowthFactor()
	local beamWidth = 4 * growthFactor
	local spacing = ATTACHMENT_SPACING * growthFactor * 0.8 -- Tighter spacing to prevent gaps
	
	-- Update visible attachment count
	local targetVisible = self.isBoosting and BOOST_VISIBLE_ATTACHMENTS or MAX_VISIBLE_ATTACHMENTS
	targetVisible = mathMin(mathCeil(self.length / 2), targetVisible)
	
	-- Update attachment positions based on history
	local currentTime = tick()
	local speed = self.config.BaseSpeed or 50
	if self.isBoosting then
		speed = speed * 2
	end
	
	for i = 1, mathMin(#self.attachments, targetVisible) do
		local attachment = self.attachments[i]
		if attachment then
			-- Calculate position from history with more precision
			local distanceBehind = (i - 1) * spacing -- Start from 0 for head connection
			local timeOffset = distanceBehind / speed
			local historySteps = mathFloor(timeOffset * 60) -- 60 FPS history
			
			local historyData = self:getFromHistory(mathMin(historySteps, self.historySize - 1))
			if historyData then
				-- Get base position
				local targetPos = historyData.position
				
				-- Add slight wave motion for organic feel
				local waveOffset = math.sin(currentTime * 3 + i * 0.5) * 0.1 * growthFactor
				targetPos = targetPos + Vector3new(0, waveOffset, 0)
				
				-- Smooth position update
				local currentWorldPos = attachment.WorldPosition
				
				-- Stronger lerp for first few segments, weaker for tail
				local lerpFactor = 0.4 - (i / targetVisible) * 0.2
				if currentWorldPos.Y > -9000 then -- Check if not in pool position
					targetPos = currentWorldPos:Lerp(targetPos, lerpFactor)
				end
				
				attachment.WorldPosition = targetPos
				self.attachmentPositions[i] = targetPos
			end
		end
	end
	
	-- Update beam widths and colors
	for i = 1, #self.beams do
		local beam = self.beams[i]
		if beam and beam.Enabled and i < targetVisible then
			beam.Width0 = beamWidth
			beam.Width1 = beamWidth
			
			-- Pulse effect when boosting
			if self.isBoosting then
				local pulse = math.sin(currentTime * 10) * 0.2 + 1
				beam.Width0 = beamWidth * pulse
				beam.Width1 = beamWidth * pulse
			end
		elseif beam and i >= targetVisible then
			beam.Enabled = false
		end
	end
	
	-- Handle visibility changes
	if targetVisible > self.visibleAttachmentCount then
		-- Show more attachments/beams
		for i = self.visibleAttachmentCount + 1, targetVisible do
			if not self.attachments[i] then
				local attachment = getAttachmentFromPool()
				if attachment then
					self.attachments[i] = attachment
					
					-- Create beam
					if i > 1 then
						local beam = getBeamFromPool()
						if beam then
							beam.Attachment0 = (i == 2) and self.headAttachment or self.attachments[i-1]
							beam.Attachment1 = attachment
							
							local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
							local color = self.config.BodyColors[colorIndex]
							beam.Color = ColorSequence.new(color)
							beam.Width0 = beamWidth
							beam.Width1 = beamWidth
							beam.Enabled = true
							
							self.beams[i-1] = beam
						end
					end
				end
			else
				-- Re-enable existing beam
				if self.beams[i-1] then
					self.beams[i-1].Enabled = true
				end
			end
		end
	end
	
	self.visibleAttachmentCount = targetVisible
end

function Snake:updateCollisionParts()
	for _, collisionData in ipairs(self.collisionParts) do
		local part = collisionData.part
		local attachmentIndex = collisionData.attachmentIndex
		
		if attachmentIndex <= self.visibleAttachmentCount then
			local pos = self.attachmentPositions[attachmentIndex]
			if pos then
				part.Position = pos
				part.Size = Vector3.new(4, 4, 4) * self:calculateGrowthFactor()
			end
		end
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
	
	-- Update beam appearance when boosting
	if self.beams then
		for i, beam in pairs(self.beams) do
			if beam and beam.Parent then
				-- Add boost glow effect
				beam.LightEmission = boosting and 1 or 0.8
				
				-- Speed up texture animation
				if BEAM_TEXTURE ~= "" then
					beam.TextureSpeed = boosting and 4 or 2
				end
			end
		end
	end
	
	-- Update head glow
	if self.head then
		local glow = self.head:FindFirstChild("PointLight")
		if glow then
			glow.Brightness = boosting and 3 or 2
			glow.Range = boosting and 12 or 8
		end
	end
end

function Snake:updateLength(newLength)
	self.length = mathMin(newLength, self.config.MaxSegments or 50000)
end

function Snake:grow(amount)
	amount = amount or 1
	self:updateLength(self.length + amount)
	
	-- Update leaderstats
	if self.player then
		local leaderstats = self.player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = self.length
			end
		end
	end
end

function Snake:sendNetworkUpdate()
	if remoteEvents.positionupdate then
		remoteEvents.positionupdate:FireServer({
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector,
			boosting = self.isBoosting
		})
	end
end

function Snake:GetSegments()
	-- Return collision parts for collision detection
	local segments = {}
	for _, collisionData in ipairs(self.collisionParts) do
		if collisionData.attachmentIndex <= self.visibleAttachmentCount then
			table.insert(segments, collisionData.part)
		end
	end
	return segments
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	-- Disconnect updates
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	if self.networkConnection then
		self.networkConnection:Disconnect()
		self.networkConnection = nil
	end
	
	-- Return attachments and beams to pools
	for _, attachment in pairs(self.attachments) do
		returnAttachmentToPool(attachment)
	end
	
	for _, beam in pairs(self.beams) do
		returnBeamToPool(beam)
	end
	
	-- Clear arrays
	self.attachments = {}
	self.beams = {}
	self.attachmentPositions = {}
	self.collisionParts = {}
	
	if self.model then
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV8 = {}

function OptimizedSnakeSystemV8.init()
	attachmentHolder = initializeAttachmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V8 - PURE BEAM initialized!")
end

function OptimizedSnakeSystemV8.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV8