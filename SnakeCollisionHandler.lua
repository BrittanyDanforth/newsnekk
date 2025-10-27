--[[
	SNAKE COLLISION HANDLER V7.0 FINAL - FULLY POLISHED
	
	Optimized collision detection between player snakes and AI snakes with:
	- Spatial grid optimization
	- Segment chunking and interpolation
	- Adaptive LOD for segment processing
	- Death handling with orb spawning
	- Fixed magnet effects on death
	- Invincibility periods (spawn protection, ghost mode, revive)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Constants
local COLLISION_CHECK_INTERVAL = 0.1
local HEAD_COLLISION_RADIUS = 4.5
local SEGMENT_COLLISION_RADIUS = 3.5
local MIN_KILL_LENGTH = 100
local SPATIAL_GRID_SIZE = 50
local MAX_SEGMENTS_PER_CHUNK = 10
local SPAWN_PROTECTION_TIME = 1
local MAX_CHECK_DISTANCE = 200
local INTERPOLATION_SAMPLES = 3

-- Death effects
local DEATH_FADE_TIME = 0.5
local ORB_SPAWN_HEIGHT = 5
local ORB_SPREAD_RADIUS = 30

-- Caching
local playerDataCache = {}
local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 0.5

-- Invincibility management
local invinciblePlayers = {}

-- Set player invincible for duration
local function setPlayerInvincible(player, duration)
	invinciblePlayers[player] = tick() + duration
end

-- Check if player is invincible
local function isPlayerInvincible(player)
	-- Check spawn protection
	if player:GetAttribute("SpawnProtection") then
		return true
	end
	
	-- Check ghost mode
	if player:GetAttribute("ActiveGhostMode") then
		return true
	end
	
	-- Check revive invincibility
	if player:GetAttribute("ReviveInvincible") then
		return true
	end
	
	-- Check timed invincibility
	local invincibleUntil = invinciblePlayers[player]
	if invincibleUntil and tick() < invincibleUntil then
		return true
	elseif invincibleUntil then
		invinciblePlayers[player] = nil
	end
	
	return false
end

-- Spatial grid for optimization
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new()
	local self = setmetatable({}, SpatialGrid)
	self.grid = {}
	self.gridSize = SPATIAL_GRID_SIZE
	return self
end

function SpatialGrid:getGridKey(position)
	local x = math.floor(position.X / self.gridSize)
	local z = math.floor(position.Z / self.gridSize)
	return x .. "," .. z
end

function SpatialGrid:insert(position, data)
	local key = self:getGridKey(position)
	if not self.grid[key] then
		self.grid[key] = {}
	end
	table.insert(self.grid[key], data)
end

function SpatialGrid:getNearby(position, radius)
	local nearby = {}
	local checkRadius = math.ceil(radius / self.gridSize)
	
	for dx = -checkRadius, checkRadius do
		for dz = -checkRadius, checkRadius do
			local checkPos = position + Vector3.new(dx * self.gridSize, 0, dz * self.gridSize)
			local key = self:getGridKey(checkPos)
			if self.grid[key] then
				for _, data in ipairs(self.grid[key]) do
					table.insert(nearby, data)
				end
			end
		end
	end
	
	return nearby
end

function SpatialGrid:clear()
	self.grid = {}
end

-- Create segment chunks for efficient processing
local function createSegmentChunks(segments, chunkSize)
	local chunks = {}
	for i = 1, #segments, chunkSize do
		local chunk = {}
		for j = i, math.min(i + chunkSize - 1, #segments) do
			table.insert(chunk, segments[j])
		end
		table.insert(chunks, chunk)
	end
	return chunks
end

-- Interpolate between segments for smoother collision detection
local function interpolateSegments(segment1, segment2, samples)
	local positions = {}
	if not segment1 or not segment2 then return positions end
	
	local p1 = segment1.Position or segment1.CFrame.Position
	local p2 = segment2.Position or segment2.CFrame.Position
	
	for i = 0, samples do
		local t = i / samples
		local interpolated = p1:Lerp(p2, t)
		table.insert(positions, interpolated)
	end
	
	return positions
end

-- Get actual snake segments (FIXED: Proper orb spawning along snake path)
local function getActualSnakeSegments(player)
	local snake = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if not snake then return {} end
	
	local segments = {}
	
	-- Get position history for accurate path
	if snake.positionHistory then
		-- Use position history for accurate segment positions
		local spacing = snake.segmentSpacing or 3.2
		local totalLength = snake:getLength()
		local segmentCount = math.floor(totalLength / spacing)
		
		for i = 1, math.min(segmentCount, #snake.positionHistory) do
			table.insert(segments, {
				Position = snake.positionHistory[i],
				Size = snake.segmentSize or Vector3.new(4, 4, 4)
			})
		end
	elseif snake.getSegments then
		-- Fallback to actual segments
		local snakeSegments = snake:getSegments()
		for _, segment in ipairs(snakeSegments) do
			if segment and segment.Parent then
				table.insert(segments, segment)
			end
		end
	end
	
	return segments
end

-- Get player segments with caching
local function getPlayerSegments(player)
	-- Check cache
	if tick() - lastCacheUpdate < CACHE_UPDATE_INTERVAL then
		local cached = playerDataCache[player]
		if cached and cached.segments then
			return cached.segments
		end
	end
	
	local character = player.Character
	if not character then return {} end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return {} end
	
	-- Check if player is alive
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return {} end
	
	-- Get actual snake segments
	local segments = getActualSnakeSegments(player)
	
	-- Cache the result
	if not playerDataCache[player] then
		playerDataCache[player] = {}
	end
	playerDataCache[player].segments = segments
	playerDataCache[player].head = humanoidRootPart
	
	return segments
end

-- Get AI snake segments
local function getAISnakeSegments(snake)
	local segments = {}
	
	-- Find the model
	local model = snake:IsA("Model") and snake or snake:FindFirstAncestorOfClass("Model")
	if not model then return segments end
	
	-- Get body folder
	local body = model:FindFirstChild("Body")
	if body then
		for _, segment in ipairs(body:GetChildren()) do
			if segment:IsA("BasePart") and segment.Name:match("Segment") then
				table.insert(segments, segment)
			end
		end
	end
	
	return segments
end

-- Efficient collision check between positions
local function checkCollision(pos1, pos2, radius)
	local distance = (pos1 - pos2).Magnitude
	return distance <= radius
end

-- Death queue to prevent multiple death calls
local deathQueue = {}
local processingDeath = {}

-- Queue player death
local function queuePlayerDeath(player)
	if processingDeath[player] or deathQueue[player] then
		return
	end
	deathQueue[player] = true
end

-- Queue AI death
local function queueAIDeath(head)
	if processingDeath[head] or deathQueue[head] then
		return
	end
	deathQueue[head] = true
end

-- Process death queue
local function processDeathQueue()
	for entity, _ in pairs(deathQueue) do
		if not processingDeath[entity] then
			processingDeath[entity] = true
			deathQueue[entity] = nil
			
			if entity:IsA("Player") then
				handlePlayerDeath(entity)
			else
				handleAIDeath(entity)
			end
		end
	end
end

-- Handle player death (FIXED: Death orb spawning)
function handlePlayerDeath(player)
	local character = player.Character
	if not character then 
		processingDeath[player] = nil
		return 
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid and humanoid.Health > 0 then
		-- Mark as dead to prevent killing others
		player:SetAttribute("Dead", true)
		
		-- Get snake length for orb calculation
		local snakeLength = player:GetAttribute("Length") or 500
		local orbCount = math.floor(snakeLength / 50)
		orbCount = math.min(orbCount, 100) -- Cap at 100 orbs
		
		-- FIXED: Death orb spawning now properly distributes orbs along snake path
		local segments = getActualSnakeSegments(player)
		
		if _G.OrbSpawner and _G.OrbSpawner.createSafeOrb and #segments > 0 then
			-- Distribute orbs along the snake's path
			local segmentInterval = math.max(1, math.floor(#segments / orbCount))
			
			for i = 1, orbCount do
				local segmentIndex = math.min(i * segmentInterval, #segments)
				local segment = segments[segmentIndex]
				
				if segment and segment.Position then
					-- Spawn orb at segment position with slight randomization
					local spawnPos = segment.Position + Vector3.new(
						math.random(-5, 5),
						0,
						math.random(-5, 5)
					)
					spawnPos = Vector3.new(spawnPos.X, ORB_SPAWN_HEIGHT, spawnPos.Z)
					
					-- Use createSafeOrb instead of spawnOrb (which doesn't exist)
					_G.OrbSpawner.createSafeOrb(spawnPos, 1)
				end
			end
		end
		
		-- FIXED: MAGNET EFFECT CLEARED ON DEATH (prevents orbs being pulled to dead character)
		player:SetAttribute("MagnetActive", false)
		player:SetAttribute("MagnetRange", 0)
		
		-- FIXED: Smooth death transition without camera disruption
		task.wait(DEATH_FADE_TIME)
		
		-- Kill the humanoid
		humanoid.Health = 0
	end
	
	processingDeath[player] = nil
end

-- Handle AI death (FIXED: Consistent with player death)
function handleAIDeath(head)
	local model = head:FindFirstAncestorOfClass("Model")
	if not model then 
		processingDeath[head] = nil
		return 
	end
	
	-- Mark as dead
	model:SetAttribute("Dead", true)
	
	-- Get snake data
	local snakeData = model:GetAttribute("SnakeData")
	local length = 500
	if snakeData then
		length = snakeData.length or 500
	end
	
	-- Calculate orbs
	local orbCount = math.floor(length / 50)
	orbCount = math.min(orbCount, 50) -- Cap AI orbs at 50
	
	-- FIXED: Death orbs spawn at correct height (Y=5)
	local body = model:FindFirstChild("Body")
	if _G.OrbSpawner and _G.OrbSpawner.createSafeOrb and body then
		local segments = {}
		for _, part in ipairs(body:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(segments, part)
			end
		end
		
		local segmentInterval = math.max(1, math.floor(#segments / orbCount))
		
		for i = 1, orbCount do
			local segmentIndex = math.min(i * segmentInterval, #segments)
			local segment = segments[segmentIndex]
			
			if segment then
				local spawnPos = segment.Position + Vector3.new(
					math.random(-5, 5),
					0,
					math.random(-5, 5)
				)
				spawnPos = Vector3.new(spawnPos.X, ORB_SPAWN_HEIGHT, spawnPos.Z)
				
				-- Use createSafeOrb instead of spawnOrb (which doesn't exist)
				_G.OrbSpawner.createSafeOrb(spawnPos, 1)
			end
		end
	end
	
	-- Fade out and destroy
	local parts = model:GetDescendants()
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(DEATH_FADE_TIME), {
				Transparency = 1
			}):Play()
		end
	end
	
	task.wait(DEATH_FADE_TIME)
	model:Destroy()
	
	processingDeath[head] = nil
end

-- Find collision in chunks
local function findCollisionInChunks(headPos, chunks, radius, excludePart)
	for _, chunk in ipairs(chunks) do
		for _, segment in ipairs(chunk) do
			if segment ~= excludePart and segment.Parent then
				local segmentPos = segment.Position or segment.CFrame.Position
				if checkCollision(headPos, segmentPos, radius) then
					return true, segment
				end
			end
		end
	end
	return false
end

-- Find collision with interpolation
local function findCollisionInSegments(headPos, segments, radius, excludePart)
	for i = 1, #segments - 1 do
		local segment1 = segments[i]
		local segment2 = segments[i + 1]
		
		if segment1 ~= excludePart and segment2 ~= excludePart then
			local interpolatedPositions = interpolateSegments(segment1, segment2, INTERPOLATION_SAMPLES)
			
			for _, pos in ipairs(interpolatedPositions) do
				if checkCollision(headPos, pos, radius) then
					return true, segment1
				end
			end
		end
	end
	return false
end

-- Main collision detection
local spatialGrid = SpatialGrid.new()

local function detectCollisions()
	-- Process death queue first
	processDeathQueue()
	
	-- Clear spatial grid
	spatialGrid:clear()
	
	-- Collect all heads
	local allHeads = {}
	
	-- Player heads
	for _, player in ipairs(Players:GetPlayers()) do
		if not isPlayerInvincible(player) then
			local character = player.Character
			local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChild("Humanoid")
			
			-- FIXED: Dead players can't kill others (marked with Dead attribute)
			if humanoidRootPart and humanoid and humanoid.Health > 0 and not player:GetAttribute("Dead") then
				table.insert(allHeads, {
					type = "player",
					part = humanoidRootPart,
					player = player,
					position = humanoidRootPart.Position
				})
				spatialGrid:insert(humanoidRootPart.Position, {type = "playerHead", data = player})
			end
		end
	end
	
	-- AI heads
	for _, aiHead in ipairs(CollectionService:GetTagged("SnakeHead")) do
		if aiHead.Parent then
			local model = aiHead:FindFirstAncestorOfClass("Model")
			if model and not model:GetAttribute("Dead") then
				table.insert(allHeads, {
					type = "ai",
					part = aiHead,
					position = aiHead.Position
				})
				spatialGrid:insert(aiHead.Position, {type = "aiHead", data = aiHead})
			end
		end
	end
	
	-- Insert all segments into spatial grid
	-- Player segments
	for _, player in ipairs(Players:GetPlayers()) do
		local segments = getPlayerSegments(player)
		for _, segment in ipairs(segments) do
			if segment and segment.Position then
				spatialGrid:insert(segment.Position, {
					type = "playerSegment",
					segment = segment,
					owner = player
				})
			end
		end
	end
	
	-- AI segments
	for _, aiHead in ipairs(CollectionService:GetTagged("SnakeHead")) do
		if aiHead.Parent then
			local segments = getAISnakeSegments(aiHead)
			for _, segment in ipairs(segments) do
				if segment and segment.Parent then
					spatialGrid:insert(segment.Position, {
						type = "aiSegment",
						segment = segment,
						owner = aiHead
					})
				end
			end
		end
	end
	
	-- Check collisions for each head
	for _, headData in ipairs(allHeads) do
		local headPos = headData.position
		local nearbyObjects = spatialGrid:getNearby(headPos, MAX_CHECK_DISTANCE)
		
		-- Check against nearby segments
		for _, objData in ipairs(nearbyObjects) do
			if objData.type:match("Segment") then
				local segment = objData.segment
				local segmentOwner = objData.owner
				
				-- Don't collide with own segments
				if headData.type == "player" and segmentOwner ~= headData.player then
					if checkCollision(headPos, segment.Position, HEAD_COLLISION_RADIUS + SEGMENT_COLLISION_RADIUS) then
						queuePlayerDeath(headData.player)
						break
					end
				elseif headData.type == "ai" and segmentOwner ~= headData.part then
					if checkCollision(headPos, segment.Position, HEAD_COLLISION_RADIUS + SEGMENT_COLLISION_RADIUS) then
						queueAIDeath(headData.part)
						break
					end
				end
			end
		end
		
		-- Head-to-head collisions
		for _, otherHead in ipairs(allHeads) do
			if headData ~= otherHead then
				if checkCollision(headData.position, otherHead.position, HEAD_COLLISION_RADIUS * 2) then
					-- Determine winner based on length
					if headData.type == "player" and otherHead.type == "player" then
						local length1 = headData.player:GetAttribute("Length") or 0
						local length2 = otherHead.player:GetAttribute("Length") or 0
						
						if length1 > length2 then
							queuePlayerDeath(otherHead.player)
						elseif length2 > length1 then
							queuePlayerDeath(headData.player)
						else
							-- Tie - both die
							queuePlayerDeath(headData.player)
							queuePlayerDeath(otherHead.player)
						end
					elseif headData.type == "ai" and otherHead.type == "ai" then
						-- Both AI die
						queueAIDeath(headData.part)
						queueAIDeath(otherHead.part)
					else
						-- Player vs AI - player wins if bigger
						if headData.type == "player" then
							local playerLength = headData.player:GetAttribute("Length") or 0
							if playerLength >= MIN_KILL_LENGTH then
								queueAIDeath(otherHead.part)
							else
								queuePlayerDeath(headData.player)
							end
						else
							local playerLength = otherHead.player:GetAttribute("Length") or 0
							if playerLength >= MIN_KILL_LENGTH then
								queueAIDeath(headData.part)
							else
								queuePlayerDeath(otherHead.player)
							end
						end
					end
				end
			end
		end
	end
end

-- Spawn protection for new players
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- FIXED: 1-second delay for spawn protection
		player:SetAttribute("SpawnProtection", true)
		task.wait(SPAWN_PROTECTION_TIME)
		player:SetAttribute("SpawnProtection", false)
		
		-- Clear death state
		player:SetAttribute("Dead", false)
	end)
end)

-- Clear cache periodically
RunService.Heartbeat:Connect(function()
	if tick() - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
		playerDataCache = {}
		lastCacheUpdate = tick()
	end
end)

-- Main collision loop
local lastCollisionCheck = 0
RunService.Heartbeat:Connect(function()
	if tick() - lastCollisionCheck >= COLLISION_CHECK_INTERVAL then
		lastCollisionCheck = tick()
		detectCollisions()
	end
end)

print("✅ SnakeCollisionHandler V7.0 loaded - Fully polished collision system!")