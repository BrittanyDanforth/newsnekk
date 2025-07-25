-- Optimized Snake System V7 - SELF-HEALING GAPS + BOOST READY
-- Automatically detects and heals gaps in the snake body

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Performance constants
local SEGMENT_POOL_SIZE = 3000
local NETWORK_UPDATE_RATE = 20
local MAX_VISIBLE_SEGMENTS = 350  -- Increased from 300 for smoother look
local BOOST_VISIBLE_SEGMENTS = 300  -- Increased from 250
local HISTORY_SIZE = 2000  -- Increased from 1500 for better interpolation
local GAP_CHECK_INTERVAL = 5  -- Reduced from 10 for more frequent gap checking

-- Gap healing settings
local MAX_SEGMENT_DISTANCE = 6  -- Reduced from 8 for tighter segments
local GAP_HEAL_SPEED = 0.4  -- Increased from 0.3 for faster gap healing

-- Fast references
local CFramenew = CFrame.new
local Vector3new = Vector3.new
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathCeil = math.ceil
local tick = tick

-- Segment Pool
local SegmentPool = {}
local SegmentPoolIndex = 0
local ActiveSegments = {}

-- Initialize segment pool
local function initializeSegmentPool()
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = Instance.new("Part")
		segment.Name = "PooledSegment"
		segment.Size = Vector3.new(4, 4, 4)
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon
		segment.TopSurface = Enum.SurfaceType.Smooth
		segment.BottomSurface = Enum.SurfaceType.Smooth
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Anchored = true
		segment.Parent = nil
		
		-- Add simple glow
		local glow = Instance.new("PointLight")
		glow.Name = "glow"
		glow.Brightness = 0.5
		glow.Range = 4
		glow.Parent = segment

		SegmentPool[i] = segment
		ActiveSegments[segment] = false
	end
	print("✅ Segment pool initialized with", SEGMENT_POOL_SIZE, "segments")
end

-- Get segment from pool
local function getSegmentFromPool()
	for i = 1, SEGMENT_POOL_SIZE do
		local segment = SegmentPool[i]
		if not ActiveSegments[segment] then
			ActiveSegments[segment] = true
			return segment
		end
	end
	-- Reuse oldest
	SegmentPoolIndex = (SegmentPoolIndex % SEGMENT_POOL_SIZE) + 1
	local segment = SegmentPool[SegmentPoolIndex]
	ActiveSegments[segment] = true
	return segment
end

-- Return segment to pool
local function returnSegmentToPool(segment)
	if segment then
		ActiveSegments[segment] = false
		segment.Parent = nil
		segment.CFrame = CFramenew(0, -10000, 0)
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

	-- Snake data
	self.length = config.InitialLength or 55
	self.segments = {}
	self.segmentPositions = {}  -- Track actual positions for gap detection
	self.visibleSegmentCount = 0
	self.isBoosting = false
	self.lastGapCheck = 0
	self.gapCheckFrame = 0

	-- Position history with interpolation support
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
	self:initializeSegments()
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

-- Interpolate between history points for smoother movement
function Snake:getInterpolatedHistory(targetTime)
	-- Find two history points around the target time
	local bestBefore, bestAfter = nil, nil
	local secondBefore, secondAfter = nil, nil
	
	for i = 1, self.historySize do
		local entry = self.positionHistory[i]
		if entry then
			if entry.time <= targetTime then
				if not bestBefore or entry.time > bestBefore.time then
					secondBefore = bestBefore
					bestBefore = entry
				elseif not secondBefore or entry.time > secondBefore.time then
					secondBefore = entry
				end
			else
				if not bestAfter or entry.time < bestAfter.time then
					secondAfter = bestAfter
					bestAfter = entry
				elseif not secondAfter or entry.time < secondAfter.time then
					secondAfter = entry
				end
			end
		end
	end
	
	-- If we have both points, use Catmull-Rom spline for smooth interpolation
	if bestBefore and bestAfter and bestAfter.time > bestBefore.time then
		local alpha = (targetTime - bestBefore.time) / (bestAfter.time - bestBefore.time)
		alpha = mathMin(mathMax(alpha, 0), 1)
		
		-- Use Catmull-Rom spline if we have 4 points
		if secondBefore and secondAfter then
			-- Catmull-Rom spline interpolation
			local t = alpha
			local t2 = t * t
			local t3 = t2 * t
			
			local p0 = secondBefore.position
			local p1 = bestBefore.position
			local p2 = bestAfter.position
			local p3 = secondAfter.position
			
			-- Catmull-Rom basis with tension factor for smoother curves
			local tension = 0.5
			local v0 = (p2 - p0) * tension
			local v1 = (p3 - p1) * tension
			
			local a = p1
			local b = v0
			local c = (p2 - p1) * 3 - v0 * 2 - v1
			local d = (p1 - p2) * 2 + v0 + v1
			
			local smoothPos = a + b * t + c * t2 + d * t3
			
			-- Smooth look vector interpolation using slerp
			local look1 = bestBefore.lookVector
			local look2 = bestAfter.lookVector
			local dot = look1:Dot(look2)
			dot = mathMin(mathMax(dot, -1), 1)
			
			local smoothLook
			if math.abs(dot) > 0.9995 then
				-- Vectors are very similar, use linear interpolation
				smoothLook = look1:Lerp(look2, alpha).Unit
			else
				-- Use spherical interpolation for smoother rotation
				local theta = math.acos(dot)
				local sinTheta = math.sin(theta)
				local a = math.sin((1 - alpha) * theta) / sinTheta
				local b = math.sin(alpha * theta) / sinTheta
				smoothLook = (look1 * a + look2 * b).Unit
			end
			
			return {
				position = smoothPos,
				lookVector = smoothLook
			}
		else
			-- Fallback to cubic interpolation with easing
			local t = alpha
			-- Smoothstep function for smoother interpolation
			t = t * t * (3 - 2 * t)
			
			return {
				position = bestBefore.position:Lerp(bestAfter.position, t),
				lookVector = bestBefore.lookVector:Lerp(bestAfter.lookVector, t).Unit
			}
		end
	end
	
	-- Fallback to nearest point
	return bestBefore or bestAfter or self.positionHistory[self.historyIndex]
end

function Snake:createHead()
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

	-- Eyes with pupils
	local function createEye(name, xOffset)
		local eye = Instance.new("Part")
		eye.Name = name
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.CanCollide = false
		eye.Anchored = true
		eye.Transparency = 0
		eye.Parent = self.model

		local pupil = Instance.new("Part")
		pupil.Name = name .. "Pupil"
		pupil.Size = Vector3.new(0.4, 0.4, 0.4)
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Transparency = 0
		pupil.Parent = self.model

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye("LeftEye", -0.7)
	self.rightEye, self.rightPupil = createEye("RightEye", 0.7)
	self.head = head
end

function Snake:calculateGrowthFactor()
	local length = self.length
	if length <= 200 then
		return 1.0
	elseif length <= 5000 then
		return 1.0 + (length - 200) / 2400  -- Max 3x at 5000
	elseif length <= 20000 then
		return 3.0 + (length - 5000) / 7500  -- Max 5x at 20000
	else
		return 5.0 + mathMin((length - 20000) / 15000, 2.0)  -- Max 7x
	end
end

function Snake:initializeSegments()
	local maxVisible = self.isBoosting and BOOST_VISIBLE_SEGMENTS or MAX_VISIBLE_SEGMENTS
	self.visibleSegmentCount = mathMin(self.length, maxVisible)
	
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.8  -- Very tight spacing
	
	local startPos = self.rootPart.Position
	local direction = self.rootPart.CFrame.LookVector
	
	for i = 1, self.visibleSegmentCount do
		local segment = getSegmentFromPool()
		if segment then
			segment.Name = "Segment" .. i
			
			-- Position behind head
			local offset = direction * (i * spacing)
			local pos = startPos - offset
			
			-- Color
			local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
			segment.Color = self.config.BodyColors[colorIndex]
			segment.Size = currentSize
			segment.CFrame = CFramenew(pos, pos - direction)
			segment.Parent = self.model
			
			-- Update glow
			local glow = segment:FindFirstChild("glow")
			if glow then
				glow.Color = segment.Color
				glow.Range = 4 * growthFactor
			end
			
			-- Only tag first 150 for collision
			if i <= 150 then
				CollectionService:AddTag(segment, "SnakeSegment")
				segment:SetAttribute("SegmentIndex", i)
				segment:SetAttribute("OwnerName", self.player.Name)
			end
			
			self.segments[i] = segment
			self.segmentPositions[i] = pos
		end
	end
end

function Snake:setupUpdateLoop()
	local frameCount = 0
	
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		-- Safety check
		if not self.model or not self.model.Parent or not self.rootPart or not self.rootPart.Parent then
			if self.updateConnection then
				self.updateConnection:Disconnect()
				self.updateConnection = nil
			end
			return
		end
		
		frameCount = frameCount + 1
		
		-- Always update position history
		local currentPos = self.rootPart.Position
		local currentLook = self.rootPart.CFrame.LookVector
		self:addToHistory(currentPos, currentLook)
		
		-- Update head every frame
		self:updateHead()
		
		-- Update segments with smart rate
		local updateRate = self.isBoosting and 1 or 1  -- Always update every frame for smoothness
		if frameCount % updateRate == 0 then
			self:updateSegments()
		end
		
		-- Check for gaps periodically
		self.gapCheckFrame = self.gapCheckFrame + 1
		if self.gapCheckFrame >= GAP_CHECK_INTERVAL then
			self.gapCheckFrame = 0
			self:checkAndHealGaps()
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
	
	-- Update head glow
	local glow = self.head:FindFirstChild("PointLight")
	if glow then
		glow.Range = (self.config.GlowRange or 6) * growthFactor
	end
end

function Snake:updateSegments()
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local currentSize = baseSize * growthFactor
	local spacing = currentSize.X * 0.65  -- Reduced from 0.8 for tighter spacing
	
	-- Adjust visible segments based on boost
	local targetVisible = self.isBoosting and BOOST_VISIBLE_SEGMENTS or MAX_VISIBLE_SEGMENTS
	targetVisible = mathMin(self.length, targetVisible)
	
	-- Smart history calculation with smoother timing
	local historyStepsPerUnit = self.isBoosting and 1.0 or 1.2  -- Adjusted for smoother movement
	local currentTime = tick()
	
	-- Update existing segments
	for i = 1, mathMin(#self.segments, targetVisible) do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Calculate target time in history
			local distanceBehind = i * spacing
			local timeOffset = distanceBehind / (self.config.BaseSpeed or 50)
			local targetTime = currentTime - timeOffset
			
			-- Get interpolated history for smooth movement
			local historyData = self:getInterpolatedHistory(targetTime)
			
			if historyData then
				local newPos = historyData.position
				local newLook = historyData.lookVector
				
				-- Store position for gap checking
				self.segmentPositions[i] = newPos
				
				-- Apply position
				segment.CFrame = CFramenew(newPos, newPos + newLook)
				segment.Size = currentSize
				
				-- Update glow
				local glow = segment:FindFirstChild("glow")
				if glow then
					glow.Range = 4 * growthFactor
				end
			end
		end
	end
	
	-- Handle visibility changes
	if targetVisible < self.visibleSegmentCount then
		-- Hide extra segments
		for i = targetVisible + 1, self.visibleSegmentCount do
			if self.segments[i] then
				self.segments[i].Parent = nil
			end
		end
	elseif targetVisible > self.visibleSegmentCount then
		-- Show more segments
		for i = self.visibleSegmentCount + 1, targetVisible do
			if self.segments[i] then
				self.segments[i].Parent = self.model
			else
				-- Create new segment
				local segment = getSegmentFromPool()
				if segment then
					segment.Name = "Segment" .. i
					local colorIndex = ((i - 1) % #self.config.BodyColors) + 1
					segment.Color = self.config.BodyColors[colorIndex]
					segment.Size = currentSize
					segment.Parent = self.model
					
					-- Update glow
					local glow = segment:FindFirstChild("glow")
					if glow then
						glow.Color = segment.Color
						glow.Range = 4 * growthFactor
					end
					
					self.segments[i] = segment
					
					-- Only tag first 150 for collision
					if i <= 150 then
						CollectionService:AddTag(segment, "SnakeSegment")
						segment:SetAttribute("SegmentIndex", i)
					end
				end
			end
		end
	end
	
	self.visibleSegmentCount = targetVisible
end

function Snake:checkAndHealGaps()
	-- Check for gaps between consecutive segments
	local growthFactor = self:calculateGrowthFactor()
	local baseSize = self.config.SegmentSize or Vector3.new(4, 4, 4)
	local expectedDistance = (baseSize * growthFactor).X * 0.8
	
	for i = 2, self.visibleSegmentCount do
		local prevPos = self.segmentPositions[i-1]
		local currPos = self.segmentPositions[i]
		
		if prevPos and currPos then
			local distance = (currPos - prevPos).Magnitude
			
			-- If gap detected, interpolate position
			if distance > expectedDistance * 1.5 then
				local segment = self.segments[i]
				if segment and segment.Parent then
					-- Get neighboring positions for smoother curve
					local prevPrevPos = self.segmentPositions[i-2] or prevPos
					local nextPos = self.segmentPositions[i+1] or currPos
					
					-- Use cubic bezier for smooth gap healing
					local targetPos = prevPos + (currPos - prevPos).Unit * expectedDistance
					
					-- Calculate control points for smoother curve
					local controlPoint1 = prevPrevPos:Lerp(prevPos, 1.5)
					local controlPoint2 = nextPos:Lerp(currPos, 1.5)
					
					-- Cubic bezier interpolation
					local t = GAP_HEAL_SPEED
					local t2 = t * t
					local t3 = t2 * t
					local mt = 1 - t
					local mt2 = mt * mt
					local mt3 = mt2 * mt
					
					-- Bezier curve calculation
					local smoothPos = mt3 * currPos +
									 3 * mt2 * t * controlPoint2 +
									 3 * mt * t2 * controlPoint1 +
									 t3 * targetPos
					
					-- Apply smoothed position
					self.segmentPositions[i] = smoothPos
					
					-- Calculate smooth look direction
					local lookDir
					if i < self.visibleSegmentCount then
						local nextSegPos = self.segmentPositions[i+1]
						if nextSegPos then
							lookDir = (smoothPos - nextSegPos).Unit
						else
							lookDir = (prevPos - smoothPos).Unit
						end
					else
						lookDir = (prevPos - smoothPos).Unit
					end
					
					segment.CFrame = CFramenew(smoothPos, smoothPos + lookDir)
				end
			end
		end
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting
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
	-- Return first 150 segments for collision
	local collisionSegments = {}
	for i = 1, mathMin(150, #self.segments) do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(collisionSegments, self.segments[i])
		end
	end
	return collisionSegments
end

function Snake:GetLength()
	return self.length
end

function Snake:destroy()
	-- Disconnect updates first
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	if self.networkConnection then
		self.networkConnection:Disconnect()
		self.networkConnection = nil
	end
	
	-- Disconnect boost connection if exists
	if self._connections and self._connections.boost then
		self._connections.boost:Disconnect()
	end
	
	-- Clear segments
	local segmentsCopy = self.segments
	self.segments = {}
	self.segmentPositions = {}
	
	for _, segment in pairs(segmentsCopy) do
		if segment and segment.Parent then
			CollectionService:RemoveTag(segment, "SnakeSegment")
			returnSegmentToPool(segment)
		end
	end
	
	if self.model then
		if self.head then
			CollectionService:RemoveTag(self.head, "SnakeHead")
		end
		self.model:Destroy()
	end
end

-- Module
local OptimizedSnakeSystemV7 = {}

function OptimizedSnakeSystemV7.init()
	initializeSegmentPool()
	createNetworkEvents()
	print("✅ Optimized Snake System V7 initialized - SELF-HEALING GAPS!")
end

function OptimizedSnakeSystemV7.createSnake(character, config)
	return Snake.new(character, config)
end

return OptimizedSnakeSystemV7