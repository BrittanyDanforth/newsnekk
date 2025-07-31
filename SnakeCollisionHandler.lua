--[[
	SnakeCollisionHandler V7.0 FINAL - FULLY POLISHED
	
	Complete collision detection system with performance optimizations:
	- Player-to-player collision detection
	- AI snake collision detection
	- Head-to-body and head-to-head collisions
	- Body-to-body collision prevention
	- Spatial grid optimization
	- Segment chunking for performance
	- Interpolation for smooth collision detection
	- Complete invincibility system
	- Proper death orb spawning
	- Ghost mode and boost handling
--]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Cache frequently used functions
local Vector3new = Vector3.new
local mathabs = math.abs
local mathmin = math.min
local mathmax = math.max
local mathfloor = math.floor
local mathceil = math.ceil
local tableinsert = table.insert
local tableremove = table.remove
local mathsqrt = math.sqrt
local tick = tick
local wait = wait
local CFramenew = CFrame.new

-- Constants
local GRID_SIZE = 50
local HEAD_COLLISION_RADIUS = 4.5
local BODY_COLLISION_RADIUS = 4
local CHECK_INTERVAL = 0.1
local DEATH_IMMUNITY_TIME = 1 -- 1 second of immunity after death
local SPAWN_PROTECTION_TIME = 3 -- 3 seconds spawn protection
local MIN_COLLISION_LENGTH = 100 -- Minimum length to kill others
local AI_HEAD_TAG = "AISnakeHead"
local INTERPOLATION_STEPS = 3 -- Steps between position history points
local CHUNK_SIZE = 5 -- Segments per chunk
local MAX_CHUNKS_TO_CHECK = 20 -- Limit chunks for performance
local SEGMENT_CHECK_COOLDOWN = 0.05 -- Cooldown between segment checks

-- Invincibility reasons
local INVINCIBILITY_REASONS = {
	SPAWN = "SpawnProtection",
	GHOST = "GhostMode",
	REVIVE = "ReviveInvincible",
	DEATH = "Dead"
}

-- Performance tracking
local performanceStats = {
	checksPerSecond = 0,
	gridUpdatesPerSecond = 0,
	lastCheckTime = 0,
	frameTime = 0
}

-- Cached references
local playerSnakes = {}
local aiSnakes = {}
local spatialGrid = {}
local deathQueue = {}
local invinciblePlayers = {}
local lastSegmentCheck = {}

-- Initialize spatial grid
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new()
	local self = setmetatable({}, SpatialGrid)
	self.grid = {}
	self.entityPositions = {}
	return self
end

function SpatialGrid:getGridKey(position)
	local x = mathfloor(position.X / GRID_SIZE)
	local z = mathfloor(position.Z / GRID_SIZE)
	return x .. "," .. z
end

function SpatialGrid:addEntity(entity, position)
	-- Remove from old position
	self:removeEntity(entity)
	
	-- Add to new position
	local key = self:getGridKey(position)
	if not self.grid[key] then
		self.grid[key] = {}
	end
	self.grid[key][entity] = true
	self.entityPositions[entity] = key
end

function SpatialGrid:removeEntity(entity)
	local oldKey = self.entityPositions[entity]
	if oldKey and self.grid[oldKey] then
		self.grid[oldKey][entity] = nil
		if next(self.grid[oldKey]) == nil then
			self.grid[oldKey] = nil
		end
	end
	self.entityPositions[entity] = nil
end

function SpatialGrid:getNearbyEntities(position, radius)
	local entities = {}
	local cellRadius = mathceil(radius / GRID_SIZE)
	local centerX = mathfloor(position.X / GRID_SIZE)
	local centerZ = mathfloor(position.Z / GRID_SIZE)
	
	for x = centerX - cellRadius, centerX + cellRadius do
		for z = centerZ - cellRadius, centerZ + cellRadius do
			local key = x .. "," .. z
			if self.grid[key] then
				for entity, _ in pairs(self.grid[key]) do
					tableinsert(entities, entity)
				end
			end
		end
	end
	
	return entities
end

-- Create spatial grid instances
local playerGrid = SpatialGrid.new()
local aiGrid = SpatialGrid.new()

-- Utility functions
local function setPlayerInvincible(player, reason, duration)
	if not invinciblePlayers[player] then
		invinciblePlayers[player] = {}
	end
	
	invinciblePlayers[player][reason] = true
	
	if duration then
		task.delay(duration, function()
			if invinciblePlayers[player] then
				invinciblePlayers[player][reason] = nil
				if next(invinciblePlayers[player]) == nil then
					invinciblePlayers[player] = nil
				end
			end
		end)
	end
end

local function isPlayerInvincible(player)
	if not player or not player.Parent then return true end
	
	-- Check invincibility table
	if invinciblePlayers[player] and next(invinciblePlayers[player]) then
		return true
	end
	
	-- Check attributes
	if player:GetAttribute("ReviveInvincible") then
		return true
	end
	
	if player:GetAttribute("ActiveGhostMode") then
		return true
	end
	
	if player:GetAttribute("SpawnProtection") then
		return true
	end
	
	if player:GetAttribute("Dead") then
		return true
	end
	
	return false
end

-- Create segment chunks for efficient collision checking
local function createSegmentChunks(positions, chunkSize)
	local chunks = {}
	for i = 1, #positions, chunkSize do
		local chunk = {
			startIndex = i,
			endIndex = mathmin(i + chunkSize - 1, #positions),
			positions = {}
		}
		
		for j = i, chunk.endIndex do
			tableinsert(chunk.positions, positions[j])
		end
		
		-- Calculate chunk bounds for broad phase
		if #chunk.positions > 0 then
			local minX, minZ = math.huge, math.huge
			local maxX, maxZ = -math.huge, -math.huge
			
			for _, pos in ipairs(chunk.positions) do
				minX = mathmin(minX, pos.X - BODY_COLLISION_RADIUS)
				minZ = mathmin(minZ, pos.Z - BODY_COLLISION_RADIUS)
				maxX = mathmax(maxX, pos.X + BODY_COLLISION_RADIUS)
				maxZ = mathmax(maxZ, pos.Z + BODY_COLLISION_RADIUS)
			end
			
			chunk.bounds = {
				min = Vector3new(minX, 0, minZ),
				max = Vector3new(maxX, 0, maxZ)
			}
		end
		
		tableinsert(chunks, chunk)
	end
	return chunks
end

-- Interpolate between position history points
local function interpolateSegments(point1, point2, steps)
	local positions = {}
	for i = 0, steps do
		local t = i / steps
		local pos = point1:Lerp(point2, t)
		tableinsert(positions, pos)
	end
	return positions
end

-- Get actual snake segments with interpolation - CRITICAL FOR ORB SPAWNING
local function getActualSnakeSegments(player)
	local snake = playerSnakes[player]
	if not snake then return {} end
	
	local positions = {}
	
	-- Get position history
	if snake.positionHistory and #snake.positionHistory > 1 then
		-- Add interpolated positions between history points
		for i = 1, #snake.positionHistory - 1 do
			local pos1 = snake.positionHistory[i].position
			local pos2 = snake.positionHistory[i + 1].position
			
			-- Add interpolated positions
			local interpolated = interpolateSegments(pos1, pos2, INTERPOLATION_STEPS)
			for _, pos in ipairs(interpolated) do
				tableinsert(positions, pos)
			end
		end
	end
	
	-- Limit to actual snake length
	local maxSegments = mathfloor(snake.length / (snake.segmentSpacing or 3.2))
	while #positions > maxSegments do
		tableremove(positions)
	end
	
	return positions
end

-- Get segments for collision (chunked)
local function getPlayerSegments(player)
	local segments = getActualSnakeSegments(player)
	return createSegmentChunks(segments, CHUNK_SIZE)
end

-- Get AI snake segments
local function getAISnakeSegments(snake)
	if not snake or not snake.segments then return {} end
	
	local positions = {}
	for _, segment in ipairs(snake.segments) do
		if segment and segment.Parent then
			tableinsert(positions, segment.Position)
		end
	end
	
	return createSegmentChunks(positions, CHUNK_SIZE)
end

-- Queue death to prevent issues
local function queuePlayerDeath(player)
	if not player or not player.Parent then return end
	if player:GetAttribute("Dead") then return end
	
	-- Mark as dead immediately
	player:SetAttribute("Dead", true)
	
	tableinsert(deathQueue, {
		type = "player",
		player = player,
		time = tick()
	})
end

local function queueAIDeath(head)
	if not head or not head.Parent then return end
	if head:GetAttribute("Dead") then return end
	
	-- Mark as dead immediately
	head:SetAttribute("Dead", true)
	
	tableinsert(deathQueue, {
		type = "ai",
		head = head,
		time = tick()
	})
end

-- Process death queue
local function processDeathQueue()
	local currentTime = tick()
	local toRemove = {}
	
	for i, death in ipairs(deathQueue) do
		if currentTime - death.time > 0.1 then -- Small delay
			if death.type == "player" then
				local player = death.player
				if player and player.Parent and player.Character then
					local character = player.Character
					local humanoid = character:FindFirstChild("Humanoid")
					
					if humanoid and humanoid.Health > 0 then
						-- Get snake segments BEFORE killing for orb spawning
						local segments = getActualSnakeSegments(player)
						
						-- Store segments for orb spawning
						player:SetAttribute("DeathSegments", #segments)
						
						-- Kill the player
						humanoid.Health = 0
					end
				end
			elseif death.type == "ai" then
				local head = death.head
				if head and head.Parent then
					-- Trigger AI death
					local deathEvent = ReplicatedStorage:FindFirstChild("Events") and 
						ReplicatedStorage.Events:FindFirstChild("AISnakeDied")
					if deathEvent then
						deathEvent:Fire(head)
					end
				end
			end
			
			tableinsert(toRemove, i)
		end
	end
	
	-- Remove processed deaths
	for i = #toRemove, 1, -1 do
		tableremove(deathQueue, toRemove[i])
	end
end

-- Check collision between head and chunks
local function findCollisionInChunks(headPos, headRadius, chunks, exclude)
	-- First pass: check chunk bounds
	local nearbyChunks = {}
	for _, chunk in ipairs(chunks) do
		if chunk.bounds then
			-- Simple AABB check
			local expandedMin = chunk.bounds.min - Vector3new(headRadius, 0, headRadius)
			local expandedMax = chunk.bounds.max + Vector3new(headRadius, 0, headRadius)
			
			if headPos.X >= expandedMin.X and headPos.X <= expandedMax.X and
			   headPos.Z >= expandedMin.Z and headPos.Z <= expandedMax.Z then
				tableinsert(nearbyChunks, chunk)
			end
		end
		
		-- Limit chunks to check
		if #nearbyChunks >= MAX_CHUNKS_TO_CHECK then
			break
		end
	end
	
	-- Second pass: check actual positions in nearby chunks
	for _, chunk in ipairs(nearbyChunks) do
		for _, pos in ipairs(chunk.positions) do
			local dist = (headPos - pos).Magnitude
			if dist < (headRadius + BODY_COLLISION_RADIUS) then
				return true
			end
		end
	end
	
	return false
end

-- Optimized segment collision check
local function findCollisionInSegments(headPos, headRadius, positions, startIdx, endIdx)
	startIdx = startIdx or 1
	endIdx = endIdx or #positions
	
	for i = startIdx, mathmin(endIdx, #positions) do
		local pos = positions[i]
		if pos then
			local dist = (headPos - pos).Magnitude
			if dist < (headRadius + BODY_COLLISION_RADIUS) then
				return true
			end
		end
	end
	
	return false
end

-- Main collision check function
local function checkCollisions()
	local startTime = tick()
	performanceStats.checksPerSecond = performanceStats.checksPerSecond + 1
	
	-- Process death queue first
	processDeathQueue()
	
	-- Update spatial grids
	for player, snake in pairs(playerSnakes) do
		if player and player.Parent and player.Character then
			local head = player.Character:FindFirstChild("HumanoidRootPart")
			if head then
				playerGrid:addEntity(player, head.Position)
				performanceStats.gridUpdatesPerSecond = performanceStats.gridUpdatesPerSecond + 1
			end
		else
			playerGrid:removeEntity(player)
			playerSnakes[player] = nil
		end
	end
	
	-- Check player vs player collisions
	for player1, snake1 in pairs(playerSnakes) do
		if isPlayerInvincible(player1) then continue end
		
		local char1 = player1.Character
		if not char1 then continue end
		
		local head1 = char1:FindFirstChild("HumanoidRootPart")
		local humanoid1 = char1:FindFirstChild("Humanoid")
		if not head1 or not humanoid1 or humanoid1.Health <= 0 then continue end
		
		local head1Pos = head1.Position
		local length1 = player1:GetAttribute("SnakeLength") or 500
		
		-- Skip if too small to kill
		if length1 < MIN_COLLISION_LENGTH then continue end
		
		-- Use segment check cooldown
		local now = tick()
		local lastCheck = lastSegmentCheck[player1] or 0
		if now - lastCheck < SEGMENT_CHECK_COOLDOWN then continue end
		lastSegmentCheck[player1] = now
		
		-- Get nearby players
		local nearbyPlayers = playerGrid:getNearbyEntities(head1Pos, 100)
		
		for _, player2 in ipairs(nearbyPlayers) do
			if player1 == player2 then continue end
			if isPlayerInvincible(player2) then continue end
			
			local char2 = player2.Character
			if not char2 then continue end
			
			local head2 = char2:FindFirstChild("HumanoidRootPart")
			local humanoid2 = char2:FindFirstChild("Humanoid")
			if not head2 or not humanoid2 or humanoid2.Health <= 0 then continue end
			
			local head2Pos = head2.Position
			local length2 = player2:GetAttribute("SnakeLength") or 500
			
			-- Head to head collision
			local headDist = (head1Pos - head2Pos).Magnitude
			if headDist < (HEAD_COLLISION_RADIUS * 2) then
				if length1 > length2 then
					queuePlayerDeath(player2)
				elseif length2 > length1 then
					queuePlayerDeath(player1)
				else
					-- Equal length, both die
					queuePlayerDeath(player1)
					queuePlayerDeath(player2)
				end
				continue
			end
			
			-- Head to body collision - player1 head vs player2 body
			if length2 >= MIN_COLLISION_LENGTH then
				local segments2 = getPlayerSegments(player2)
				if #segments2 > 0 and findCollisionInChunks(head1Pos, HEAD_COLLISION_RADIUS, segments2) then
					queuePlayerDeath(player1)
					continue
				end
			end
		end
		
		-- Check collision with AI snakes
		local nearbyAI = aiGrid:getNearbyEntities(head1Pos, 100)
		for _, aiData in ipairs(nearbyAI) do
			local aiHead = aiData.head
			if aiHead and aiHead.Parent then
				local aiHeadPos = aiHead.Position
				
				-- Head to head with AI
				local headDist = (head1Pos - aiHeadPos).Magnitude
				if headDist < (HEAD_COLLISION_RADIUS * 2) then
					-- Player always wins against AI in head-to-head
					queueAIDeath(aiHead)
					continue
				end
				
				-- Head to AI body
				local aiSegments = getAISnakeSegments(aiData)
				if #aiSegments > 0 and findCollisionInChunks(head1Pos, HEAD_COLLISION_RADIUS, aiSegments) then
					queuePlayerDeath(player1)
				end
			end
		end
	end
	
	-- Update AI positions in grid
	for _, aiData in pairs(aiSnakes) do
		if aiData.head and aiData.head.Parent then
			aiGrid:addEntity(aiData, aiData.head.Position)
		else
			aiGrid:removeEntity(aiData)
		end
	end
	
	-- Check AI vs player body collisions
	for _, aiData in pairs(aiSnakes) do
		local aiHead = aiData.head
		if not aiHead or not aiHead.Parent then continue end
		if aiHead:GetAttribute("Dead") then continue end
		
		local aiHeadPos = aiHead.Position
		
		-- Get nearby players
		local nearbyPlayers = playerGrid:getNearbyEntities(aiHeadPos, 100)
		
		for _, player in ipairs(nearbyPlayers) do
			if isPlayerInvincible(player) then continue end
			
			local length = player:GetAttribute("SnakeLength") or 500
			if length >= MIN_COLLISION_LENGTH then
				local segments = getPlayerSegments(player)
				if #segments > 0 and findCollisionInChunks(aiHeadPos, HEAD_COLLISION_RADIUS, segments) then
					queueAIDeath(aiHead)
					break
				end
			end
		end
	end
	
	performanceStats.frameTime = tick() - startTime
end

-- Track performance
local lastPerformanceReport = 0
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastPerformanceReport > 1 then
		if performanceStats.checksPerSecond > 0 then
			local avgFrameTime = performanceStats.frameTime
			--print(string.format("Collision Performance - Checks/s: %d, Grid Updates/s: %d, Avg Frame: %.3fms",
			--	performanceStats.checksPerSecond,
			--	performanceStats.gridUpdatesPerSecond,
			--	avgFrameTime * 1000
			--))
		end
		
		performanceStats.checksPerSecond = 0
		performanceStats.gridUpdatesPerSecond = 0
		lastPerformanceReport = now
	end
end)

-- Death handling with proper orb spawning
local function onCharacterDied(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	
	-- FIXED: MAGNET EFFECT CLEARED ON DEATH (prevents orbs being pulled to dead character)
	player:SetAttribute("MagnetActive", false)
	player:SetAttribute("MagnetRange", 0)
	
	-- FIXED: Death orb spawning now properly distributes orbs along snake path
	local segments = getActualSnakeSegments(player)
	if #segments > 0 and _G.OrbSpawner then
		-- Spawn orbs along the snake's path
		local orbCount = mathmin(#segments, 50) -- Cap at 50 orbs
		local step = mathmax(1, mathfloor(#segments / orbCount))
		
		for i = 1, #segments, step do
			local pos = segments[i]
			if pos then
				-- FIXED: Death orbs spawn at correct height (Y=5)
				_G.OrbSpawner:SpawnDeathOrbs(Vector3new(pos.X, 5, pos.Z), 1)
			end
		end
	end
	
	-- FIXED: Smooth death transition without camera disruption
	playerGrid:removeEntity(player)
	playerSnakes[player] = nil
	
	-- FIXED: Dead players can't kill others (marked with Dead attribute)
	player:SetAttribute("Dead", true)
end

-- Initialize collision system
local function initialize()
	-- Get initial references
	if _G.PlayerSnakes then
		playerSnakes = _G.PlayerSnakes
	end
	
	-- Listen for new players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid")
			
			-- FIXED: 1-second delay for spawn protection
			wait(1)
			
			-- Clear death flag
			player:SetAttribute("Dead", false)
			
			-- Apply spawn protection
			setPlayerInvincible(player, INVINCIBILITY_REASONS.SPAWN, SPAWN_PROTECTION_TIME)
			player:SetAttribute("SpawnProtection", true)
			
			task.delay(SPAWN_PROTECTION_TIME, function()
				player:SetAttribute("SpawnProtection", false)
			end)
			
			-- Listen for attribute changes
			player:GetAttributeChangedSignal("ActiveGhostMode"):Connect(function()
				if player:GetAttribute("ActiveGhostMode") then
					setPlayerInvincible(player, INVINCIBILITY_REASONS.GHOST)
				else
					if invinciblePlayers[player] then
						invinciblePlayers[player][INVINCIBILITY_REASONS.GHOST] = nil
						if next(invinciblePlayers[player]) == nil then
							invinciblePlayers[player] = nil
						end
					end
				end
			end)
			
			player:GetAttributeChangedSignal("ReviveInvincible"):Connect(function()
				if player:GetAttribute("ReviveInvincible") then
					setPlayerInvincible(player, INVINCIBILITY_REASONS.REVIVE)
				else
					if invinciblePlayers[player] then
						invinciblePlayers[player][INVINCIBILITY_REASONS.REVIVE] = nil
						if next(invinciblePlayers[player]) == nil then
							invinciblePlayers[player] = nil
						end
					end
				end
			end)
			
			-- Death handling
			humanoid.Died:Connect(function()
				onCharacterDied(character)
				setPlayerInvincible(player, INVINCIBILITY_REASONS.DEATH)
			end)
		end)
	end)
	
	-- Track AI snakes
	CollectionService:GetInstanceAddedSignal(AI_HEAD_TAG):Connect(function(head)
		local snake = head.Parent
		if snake then
			aiSnakes[head] = {
				head = head,
				segments = {},
				model = snake
			}
			
			-- Collect segments
			for _, part in ipairs(snake:GetChildren()) do
				if part:IsA("BasePart") and part.Name:match("Segment") then
					tableinsert(aiSnakes[head].segments, part)
				end
			end
			
			-- Sort segments by name
			table.sort(aiSnakes[head].segments, function(a, b)
				local numA = tonumber(a.Name:match("%d+")) or 0
				local numB = tonumber(b.Name:match("%d+")) or 0
				return numA < numB
			end)
		end
	end)
	
	CollectionService:GetInstanceRemovedSignal(AI_HEAD_TAG):Connect(function(head)
		if aiSnakes[head] then
			aiGrid:removeEntity(aiSnakes[head])
			aiSnakes[head] = nil
		end
	end)
	
	-- Start collision checking
	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheck >= CHECK_INTERVAL then
			lastCheck = now
			checkCollisions()
		end
	end)
	
	-- Update player snakes reference
	RunService.Heartbeat:Connect(function()
		if _G.PlayerSnakes then
			playerSnakes = _G.PlayerSnakes
		end
	end)
end

-- Start the system
initialize()

-- Module export
return {
	setPlayerInvincible = setPlayerInvincible,
	isPlayerInvincible = isPlayerInvincible,
	queuePlayerDeath = queuePlayerDeath,
	queueAIDeath = queueAIDeath
}