-- Optimized Snake System V8 - PURE BEAM RENDERING
-- Ultra-smooth beam-based snake body for maximum performance

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

-- Performance constants
local ATTACHMENT_POOL_SIZE = 1000
local BEAM_POOL_SIZE = 500
local NETWORK_UPDATE_RATE = 20
local MAX_VISIBLE_ATTACHMENTS = 300  -- More attachments for smoother curves
local BOOST_VISIBLE_ATTACHMENTS = 250
local HISTORY_SIZE = 2000
local BEAM_TEXTURE = "" -- No texture for clean solid look, set to texture ID if you want patterns

-- Attachment spacing
local ATTACHMENT_SPACING = 0.5 -- Ultra-close spacing for no gaps

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
	
	-- Initialize beam pool with premium appearance
	for i = 1, BEAM_POOL_SIZE do
		local beam = Instance.new("Beam")
		beam.Name = "PooledBeam" .. i
		
		-- Premium beam settings for smooth, round appearance
		beam.Texture = "rbxasset://textures/ui/LuaApp/graphic/gr-radial-thin-glow-64.png" -- Radial glow texture
		beam.TextureSpeed = 0
		beam.TextureLength = 0.5
		beam.TextureMode = Enum.TextureMode.Static
		
		-- Width settings for round appearance
		beam.Width0 = 6
		beam.Width1 = 6
		
		-- Face camera for consistent appearance from all angles
		beam.FaceCamera = true
		
		-- Maximum segments for ultra-smooth curves
		beam.Segments = 100
		
		-- Lighting for glowing effect
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		beam.Brightness = 2
		
		-- Transparency for smooth edges
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.3)
		})
		
		-- No curve distortion
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		
		-- Slight offset to prevent overlapping
		beam.ZOffset = -0.1
		
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
	-- Wait a frame to ensure ReplicatedStorage is ready
	wait()
	
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
		print("✅ Created SnakeNetworking folder")
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

function Snake:getInterpolatedHistory(targetTime)
	-- Find two history points around the target time
	local bestBefore, bestAfter = nil, nil
	local currentTime = tick()
	
	-- Search through recent history
	for i = 0, mathMin(100, self.historySize - 1) do
		local index = self.historyIndex - i
		if index < 1 then index = index + self.historySize end
		
		local entry = self.positionHistory[index]
		if entry and entry.time then
			if entry.time <= targetTime then
				if not bestBefore or entry.time > bestBefore.time then
					bestBefore = entry
				end
			else
				if not bestAfter or entry.time < bestAfter.time then
					bestAfter = entry
				end
			end
			
			-- Stop searching if we found both
			if bestBefore and bestAfter then
				break
			end
		end
	end
	
	-- Interpolate between points
	if bestBefore and bestAfter and bestAfter.time > bestBefore.time then
		local alpha = (targetTime - bestBefore.time) / (bestAfter.time - bestBefore.time)
		alpha = mathMin(mathMax(alpha, 0), 1)
		
		return {
			position = bestBefore.position:Lerp(bestAfter.position, alpha),
			lookVector = bestBefore.lookVector:Lerp(bestAfter.lookVector, alpha).Unit,
			time = targetTime
		}
	end
	
	-- Fallback to nearest
	return bestBefore or bestAfter or self.positionHistory[self.historyIndex]
end

function Snake:createHead()
	-- Create a sleek, modern head design
	local head = Instance.new("Part")
	head.Name = "SnakeHead"
	local headSize = self.config.HeadSize or Vector3.new(20, 20, 20) -- MASSIVE head!
	head.Size = headSize
	head.Shape = Enum.PartType.Block -- Block shape for consistency
	head.Material = Enum.Material.Neon -- Match body glow style
	head.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Transparency = 0.1 -- Slight transparency to match beam aesthetic
	head.Reflectance = 0
	head.CastShadow = false -- No shadows for glowing effect
	head.Parent = self.model
	
	-- Force head to be properly sized
	head.Size = Vector3.new(5.2, 5.2, 5.2)  -- Slightly smaller for better proportion
	print("HEAD SIZE SET TO:", head.Size)

	-- Tag for collision
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- No inner glow needed - head is already neon material

	-- Add subtle glow to match body
	local glow = Instance.new("PointLight")
	glow.Brightness = 1.5  -- Subtle glow
	glow.Range = 6
	glow.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	glow.Parent = head

	-- Modern eye design - flat rectangular eyes
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(1.0, 1.5, 0.2) -- Smaller eyes for compact head
		eye.Shape = Enum.PartType.Block
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		-- Eye glow
		local eyeGlow = Instance.new("SurfaceLight")
		eyeGlow.Face = Enum.NormalId.Front
		eyeGlow.Brightness = 2
		eyeGlow.Color = Color3.fromRGB(255, 255, 255)
		eyeGlow.Parent = eye

		return eye, nil -- No pupils for cleaner look
	end

	self.leftEye = createEye("LeftEye", -1.2)
	self.rightEye = createEye("RightEye", 1.2)
	self.head = head

	-- Create multiple attachment points for smoother head-to-body transition
	self.headAttachments = {}
	
	-- Front attachment (for first body beam)
	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Name = "HeadAttachmentFront"
	frontAttachment.Position = Vector3.new(0, 0, -headSize.Z/2)
	frontAttachment.Parent = head
	self.headAttachments[1] = frontAttachment
	
	-- Back attachment (for smoother transition)
	local backAttachment = Instance.new("Attachment")
	backAttachment.Name = "HeadAttachmentBack" 
	backAttachment.Position = Vector3.new(0, 0, headSize.Z/2)
	backAttachment.Parent = head
	self.headAttachments[2] = backAttachment
	
	-- Keep reference for compatibility
	self.headAttachment = backAttachment
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
	self.visibleAttachmentCount = mathMin(self.length * 3, maxVisible) -- More attachments for smoother body
	
	local growthFactor = self:calculateGrowthFactor()
	local beamWidth = 5 * growthFactor -- Base width
	local spacing = ATTACHMENT_SPACING * growthFactor
	
	-- Create invisible parts for collision detection at key points
	self.collisionParts = {}
	
	-- Get initial position and direction
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	
	-- Create transition attachments from head to body
	local transitionCount = 3
	for i = 1, transitionCount do
		local attachment = getAttachmentFromPool()
		if attachment then
			attachment.Name = "TransitionAttachment" .. i
			local progress = i / transitionCount
			local offset = startLook * (progress * spacing * 2)
			attachment.WorldPosition = startPos - offset
			self.attachments[i] = attachment
			self.attachmentPositions[i] = attachment.WorldPosition
		end
	end
	
	-- Create main body attachments
	for i = transitionCount + 1, self.visibleAttachmentCount do
		local attachment = getAttachmentFromPool()
		if attachment then
			attachment.Name = "BodyAttachment" .. i
			
			-- Set initial position behind head
			local offset = startLook * ((i - 1) * spacing)
			attachment.WorldPosition = startPos - offset
			self.attachmentPositions[i] = attachment.WorldPosition
			
			self.attachments[i] = attachment
			
			-- Create collision part every 10 attachments
			if i % 10 == 0 and i <= 60 then
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
		end
	end
	
	-- Create beams with smooth transitions
	for i = 1, self.visibleAttachmentCount - 1 do
		local beam = getBeamFromPool()
		if beam and self.attachments[i] and self.attachments[i+1] then
			beam.Attachment0 = self.attachments[i]
			beam.Attachment1 = self.attachments[i+1]
			
			-- Smooth color gradient along body
			local progress = i / self.visibleAttachmentCount
			local colorIndex = math.floor(progress * #self.config.BodyColors) + 1
			colorIndex = math.min(colorIndex, #self.config.BodyColors)
			local color = self.config.BodyColors[colorIndex]
			
			-- Create gradient effect
			local nextColorIndex = (colorIndex % #self.config.BodyColors) + 1
			local nextColor = self.config.BodyColors[nextColorIndex]
			
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.5, Color3.new(
					(color.R + nextColor.R) / 2,
					(color.G + nextColor.G) / 2,
					(color.B + nextColor.B) / 2
				)),
				ColorSequenceKeypoint.new(1, nextColor)
			})
			
			-- Width tapering
			local widthMultiplier = 1 - (progress * 0.4) -- Taper to 60% at tail
			beam.Width0 = beamWidth * widthMultiplier
			beam.Width1 = beamWidth * widthMultiplier * 0.95 -- Slight taper per segment
			
			self.beams[i] = beam
		end
	end
	
	-- Special head-to-body beam with smooth transition
	if #self.attachments > 0 then
		local headBeam = getBeamFromPool()
		if headBeam then
			headBeam.Attachment0 = self.headAttachment
			headBeam.Attachment1 = self.attachments[1]
			
			-- Match head color transitioning to body
			local headColor = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
			local bodyColor = self.config.BodyColors[1]
			
			headBeam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, headColor),
				ColorSequenceKeypoint.new(0.3, headColor),
				ColorSequenceKeypoint.new(0.7, bodyColor),
				ColorSequenceKeypoint.new(1, bodyColor)
			})
			
			-- Smooth width transition from huge head to body
			headBeam.Width0 = self.head.Size.X * 0.5  -- Start at half head width since head is huge
			headBeam.Width1 = beamWidth * 1.2  -- Slightly wider body connection
			
			-- Extra transparency for smooth blend
			headBeam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.2, 0.2),
				NumberSequenceKeypoint.new(0.8, 0.2),
				NumberSequenceKeypoint.new(1, 0.3)
			})
			
			table.insert(self.beams, 1, headBeam)
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
	-- MINIMUM size of 5.2, can only get bigger with growth
	local baseSize = math.max(5.2, (self.config.HeadSize or Vector3.new(5.2, 5.2, 5.2)).X)
	local headSize = Vector3.new(baseSize, baseSize, baseSize) * growthFactor
	
	-- Never let it get smaller than 5.2x5.2x5.2
	headSize = Vector3.new(
		math.max(5.2, headSize.X),
		math.max(5.2, headSize.Y),
		math.max(5.2, headSize.Z)
	)
	
	self.head.Size = headSize
	print("UPDATE HEAD SIZE TO:", headSize)
	
	local currentPos = self.rootPart.Position
	local currentLook = self.rootPart.CFrame.LookVector
	local headCF = CFramenew(currentPos, currentPos + currentLook)
	self.head.CFrame = headCF
	
	-- Head updates handled above
	
	-- Update eyes with sleek positioning
	if self.leftEye and self.rightEye then
		local eyeScale = growthFactor
		self.leftEye.Size = Vector3.new(1.0, 1.5, 0.2) * eyeScale
		self.rightEye.Size = Vector3.new(1.0, 1.5, 0.2) * eyeScale
		
		local eyeSeparation = 1.4 * growthFactor  -- Spacing for 5.775 head
		local eyeHeight = 0.6 * growthFactor
		local eyeForward = -(headSize.Z / 2 + 0.1)  -- Position ON the front face, not inside
		
		-- Position eyes on the front face
		self.leftEye.CFrame = headCF * CFramenew(-eyeSeparation, eyeHeight, eyeForward)
		self.rightEye.CFrame = headCF * CFramenew(eyeSeparation, eyeHeight, eyeForward)
	end
	
	-- Update head light
	local glow = self.head:FindFirstChild("PointLight")
	if glow then
		glow.Range = 6 * growthFactor
		glow.Brightness = 1.5
	end
end

function Snake:updateBeamBody()
	local growthFactor = self:calculateGrowthFactor()
	local beamWidth = 5 * growthFactor
	local spacing = ATTACHMENT_SPACING * growthFactor
	
	-- Update visible attachment count
	local targetVisible = self.isBoosting and BOOST_VISIBLE_ATTACHMENTS or MAX_VISIBLE_ATTACHMENTS
	targetVisible = mathMin(self.length * 2, targetVisible) -- More attachments relative to length
	
	-- Update attachment positions based on history
	local currentTime = tick()
	local speed = self.config.BaseSpeed or 50
	if self.isBoosting then
		speed = speed * 2
	end
	
	-- First pass: Update positions
	for i = 1, mathMin(#self.attachments, targetVisible) do
		local attachment = self.attachments[i]
		if attachment then
			-- Calculate position from history with interpolation
			local distanceBehind = (i - 1) * spacing
			local timeOffset = distanceBehind / speed
			local historyTime = currentTime - timeOffset
			
			-- Use interpolated history for smoother curves
			local historyData = self:getInterpolatedHistory(historyTime)
			if historyData then
				local targetPos = historyData.position
				local currentWorldPos = attachment.WorldPosition
				
				-- Dynamic lerp based on turning speed
				local turnSpeed = 0
				if i > 1 and self.attachmentPositions[i-1] then
					local prevPos = self.attachmentPositions[i-1]
					turnSpeed = (targetPos - prevPos).Unit:Dot(historyData.lookVector)
				end
				
				-- Stronger lerp when turning for tighter curves
				local baseLerp = 0.5
				local turnLerp = mathMax(0.7, 1 - math.abs(turnSpeed))
				local lerpFactor = baseLerp * turnLerp
				
				if currentWorldPos.Y > -9000 then
					targetPos = currentWorldPos:Lerp(targetPos, lerpFactor)
				end
				
				attachment.WorldPosition = targetPos
				self.attachmentPositions[i] = targetPos
			end
		end
	end
	
	-- Second pass: Smooth out sharp angles
	for i = 3, mathMin(#self.attachments - 1, targetVisible - 1) do
		if self.attachmentPositions[i-1] and self.attachmentPositions[i] and self.attachmentPositions[i+1] then
			local prev = self.attachmentPositions[i-1]
			local curr = self.attachmentPositions[i]
			local next = self.attachmentPositions[i+1]
			
			-- Calculate angle
			local dir1 = (curr - prev).Unit
			local dir2 = (next - curr).Unit
			local dot = dir1:Dot(dir2)
			
			-- If angle is too sharp, smooth it
			if dot < 0.9 then -- ~25 degree threshold
				local smoothed = (prev + next) / 2
				local blend = 0.3 * (1 - dot) -- More smoothing for sharper angles
				self.attachments[i].WorldPosition = curr:Lerp(smoothed, blend)
				self.attachmentPositions[i] = self.attachments[i].WorldPosition
			end
		end
	end
	
	-- Update beam widths and colors
	for i = 1, #self.beams do
		local beam = self.beams[i]
		if beam and beam.Enabled and i < targetVisible then
			-- Variable width for more organic look
			local segmentProgress = i / targetVisible
			local widthMultiplier = 1 - (segmentProgress * 0.3) -- Taper towards tail
			
			beam.Width0 = beamWidth * widthMultiplier
			beam.Width1 = beamWidth * widthMultiplier
			
			-- Make beams thicker to appear more round
			beam.Width0 = beam.Width0 * 1.2
			beam.Width1 = beam.Width1 * 1.2
			
			-- Smooth width transitions between segments
			if i > 1 and self.beams[i-1] then
				local prevBeam = self.beams[i-1]
				beam.Width0 = prevBeam.Width1
			end
			
			-- Pulse effect when boosting
			if self.isBoosting then
				local pulse = math.sin(currentTime * 10 + i * 0.1) * 0.15 + 1
				beam.Width0 = beam.Width0 * pulse
				beam.Width1 = beam.Width1 * pulse
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