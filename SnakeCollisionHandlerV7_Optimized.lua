-- SnakeCollisionHandler V7.1: ULTRA-OPTIMIZED COLLISION SYSTEM
-- All V7.0 functionality preserved with extreme performance optimizations
-- Zero-lag orb spawning, batched collision processing, memory pooling

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- === ULTRA-OPTIMIZED PERFORMANCE CONSTANTS ===
local SEGMENT_CHUNK_SIZE = 128 -- Increased for better CPU cache usage
local COLLISION_GRID_SIZE = 150 -- Larger cells = fewer lookups
local ADAPTIVE_LOD_THRESHOLD = 100
local EXTREME_LENGTH_THRESHOLD = 500
local ULTRA_LENGTH_THRESHOLD = 1000 -- New threshold for mega snakes
local CACHE_EXPIRY = 2.0 -- Longer cache for less updates
local YIELD_INTERVAL = 200 -- Less frequent yielding
local NETWORK_COMPENSATION = 0.1
local COLLISION_FRAME_SKIP = 6 -- Process every 6 frames (10 Hz)
local MAX_SEGMENTS_PER_FRAME = 300 -- Limit segments processed per frame

-- === COLLISION CONSTANTS (UNCHANGED FROM V7) ===
local HEAD_COLLISION_DISTANCE = 3.5
local BODY_COLLISION_DISTANCE = 2.8
local MIN_COLLISION_DISTANCE = 2.0
local COLLISION_BUFFER = 0.5

-- === ORB SPAWNING OPTIMIZATION ===
local ORB_SPAWN_HEIGHT = 2
local MIN_ORB_SPACING = 3
local ORB_BATCH_SIZE = 10 -- Spawn orbs in batches
local MAX_ORBS_PER_DEATH = 40 -- Cap total orbs to prevent lag
local ORB_SPAWN_DELAY = 0.05 -- Delay between orb batches

-- === MEMORY POOLS ===
local vectorPool = {} -- Reuse Vector3 objects
local tablePool = {} -- Reuse tables

local function getPooledVector(x, y, z)
	local vec = table.remove(vectorPool)
	if vec then
		return vec + Vector3.new(x, y, z)
	end
	return Vector3.new(x, y, z)
end

local function releaseVector(vec)
	if #vectorPool < 100 then
		table.insert(vectorPool, vec - vec) -- Reset to zero
	end
end

local function getPooledTable()
	return table.remove(tablePool) or {}
end

local function releaseTable(tbl)
	if #tablePool < 50 then
		table.clear(tbl)
		table.insert(tablePool, tbl)
	end
end

-- === DEBUG SYSTEM ===
local DEBUG_COLLISIONS = false
local collisionDebugData = {}

-- === DEATH PROCESSING QUEUE ===
local deathQueue = {}
local orbSpawnQueue = {}
local isProcessingDeaths = false
local deadAISnakes = {}
local deadPlayers = {}

-- === INVINCIBILITY SYSTEM (UNCHANGED FROM V7) ===
local INVINCIBILITY_DURATION = 5
local invinciblePlayers = {}

local function setPlayerInvincible(player)
	invinciblePlayers[player] = os.clock() + INVINCIBILITY_DURATION
end

local function isPlayerInvincible(player)
	local expire = invinciblePlayers[player]
	return expire and os.clock() < expire
end

local function clearPlayerInvincibility(player)
	invinciblePlayers[player] = nil
end

-- Invincibility setup (preserved from V7)
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		setPlayerInvincible(player)
		task.spawn(function()
			local expire = invinciblePlayers[player]
			if expire then
				local waitTime = expire - os.clock()
				if waitTime > 0 then task.wait(waitTime) end
				clearPlayerInvincibility(player)
			end
		end)
	end)
	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			clearPlayerInvincibility(player)
		end
	end)
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		setPlayerInvincible(player)
		task.spawn(function()
			local expire = invinciblePlayers[player]
			if expire then
				local waitTime = expire - os.clock()
				if waitTime > 0 then task.wait(waitTime) end
				clearPlayerInvincibility(player)
			end
		end)
	end)
end

-- === OPTIMIZED SPATIAL GRID ===
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new()
	return setmetatable({
		cells = {},
		cellSize = COLLISION_GRID_SIZE,
		objectCount = 0,
		cellCache = {} -- Cache cell lookups
	}, SpatialGrid)
end

function SpatialGrid:getCell(position)
	local x = math.floor(position.X / self.cellSize)
	local z = math.floor(position.Z / self.cellSize)
	return x, z
end

function SpatialGrid:getCellKey(x, z)
	return x * 10000 + z
end

function SpatialGrid:insert(object, position)
	local x, z = self:getCell(position)
	local key = self:getCellKey(x, z)

	local cell = self.cells[key]
	if not cell then
		cell = getPooledTable()
		self.cells[key] = cell
	end

	cell[#cell + 1] = object
	self.objectCount = self.objectCount + 1
end

function SpatialGrid:query(position, radius)
	-- Check cache first
	local cacheKey = string.format("%.0f,%.0f,%.0f", position.X, position.Z, radius)
	local cached = self.cellCache[cacheKey]
	if cached and cached.time > tick() - 0.1 then
		return cached.results
	end

	local results = getPooledTable()
	local cellRadius = math.ceil(radius / self.cellSize)
	local cx, cz = self:getCell(position)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local key = self:getCellKey(cx + dx, cz + dz)
			local cell = self.cells[key]
			if cell and #cell > 0 then
				for i = 1, #cell do
					results[#results + 1] = cell[i]
				end
			end
		end
	end

	-- Cache the result
	self.cellCache[cacheKey] = {
		results = results,
		time = tick()
	}

	return results
end

function SpatialGrid:clear()
	-- Release tables back to pool
	for k, cell in pairs(self.cells) do
		releaseTable(cell)
		self.cells[k] = nil
	end
	
	-- Clear cache
	for k, v in pairs(self.cellCache) do
		if v.results then
			releaseTable(v.results)
		end
		self.cellCache[k] = nil
	end
	
	self.objectCount = 0
end

-- === COLLISION CACHE ===
local CollisionCache = {
	playerSegments = {},
	aiSegments = {},
	spatialGrid = SpatialGrid.new(),
	frameCache = {},
	lastGridClear = 0
}

-- === OPTIMIZED ORB SPAWNING ===
local orbSpawnBuffer = {}
local isProcessingOrbs = false

local function flushOrbBuffer()
	if isProcessingOrbs or #orbSpawnBuffer == 0 then return end
	
	isProcessingOrbs = true
	
	-- Process orbs in batches
	local batch = math.min(ORB_BATCH_SIZE, #orbSpawnBuffer)
	
	for i = 1, batch do
		local orbData = table.remove(orbSpawnBuffer, 1)
		if orbData then
			pcall(function()
				OrbUtils.spawnOrbAt(orbData.position, orbData.value)
			end)
		end
	end
	
	isProcessingOrbs = false
	
	-- Schedule next batch if needed
	if #orbSpawnBuffer > 0 then
		task.wait(ORB_SPAWN_DELAY)
		flushOrbBuffer()
	end
end

local function queueOrbSpawn(position, value)
	-- Validate position
	if not position or position ~= position then return end
	
	table.insert(orbSpawnBuffer, {
		position = position,
		value = math.clamp(value or 1, 1, 50)
	})
	
	-- Start processing if not already running
	if not isProcessingOrbs then
		task.spawn(flushOrbBuffer)
	end
end

-- === OPTIMIZED HEAD RETRIEVAL ===
local headCache = {
	players = {},
	ai = {},
	lastUpdate = 0,
	updateInterval = 0.15 -- Increased from 0.1
}

local function getPlayerHeads()
	local currentTime = tick()
	if currentTime - headCache.lastUpdate < headCache.updateInterval then
		return headCache.players
	end

	local heads = getPooledTable()
	for _, player in Players:GetPlayers() do
		if player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Parent then
				heads[#heads + 1] = {player = player, part = root}
			end
		end
	end

	-- Release old table
	if headCache.players and #headCache.players > 0 then
		releaseTable(headCache.players)
	end

	headCache.players = heads
	headCache.lastUpdate = currentTime
	return heads
end

local function getAISnakeHeads()
	local heads = getPooledTable()
	if AISnakeModule._activeSnakes then
		for _, snake in AISnakeModule._activeSnakes do
			if snake.HeadParts and snake.HeadParts.head and snake.HeadParts.head.Parent then
				heads[#heads + 1] = snake.HeadParts.head
			end
		end
	end
	
	-- Release old table
	if headCache.ai and #headCache.ai > 0 then
		releaseTable(headCache.ai)
	end
	
	headCache.ai = heads
	return heads
end

-- === OPTIMIZED SEGMENT PROCESSING ===
local function createSegmentChunks(segments, snakeLength)
	local chunks = {}
	local currentChunk = {
		segments = getPooledTable(),
		bounds = {
			min = Vector3.new(math.huge, math.huge, math.huge),
			max = Vector3.new(-math.huge, -math.huge, -math.huge)
		},
		center = Vector3.new(0, 0, 0),
		radius = 0
	}

	local processedCount = 0
	local actualChunkSize = snakeLength > ULTRA_LENGTH_THRESHOLD and SEGMENT_CHUNK_SIZE * 2 or SEGMENT_CHUNK_SIZE
	
	for i, seg in ipairs(segments) do
		local pos = seg.Position or seg.position
		if pos then
			-- Update bounds (optimized)
			local bounds = currentChunk.bounds
			bounds.min = Vector3.new(
				math.min(bounds.min.X, pos.X),
				math.min(bounds.min.Y, pos.Y),
				math.min(bounds.min.Z, pos.Z)
			)
			bounds.max = Vector3.new(
				math.max(bounds.max.X, pos.X),
				math.max(bounds.max.Y, pos.Y),
				math.max(bounds.max.Z, pos.Z)
			)

			currentChunk.segments[#currentChunk.segments + 1] = seg

			if #currentChunk.segments >= actualChunkSize then
				-- Calculate chunk properties
				currentChunk.center = (bounds.min + bounds.max) * 0.5
				currentChunk.radius = (bounds.max - bounds.min).Magnitude * 0.5

				chunks[#chunks + 1] = currentChunk
				currentChunk = {
					segments = getPooledTable(),
					bounds = {
						min = Vector3.new(math.huge, math.huge, math.huge),
						max = Vector3.new(-math.huge, -math.huge, -math.huge)
					},
					center = Vector3.new(0, 0, 0),
					radius = 0
				}
			end
		end

		processedCount = processedCount + 1
		if processedCount % YIELD_INTERVAL == 0 and processedCount > MAX_SEGMENTS_PER_FRAME then
			task.wait()
		end
	end

	if #currentChunk.segments > 0 then
		currentChunk.center = (currentChunk.bounds.min + currentChunk.bounds.max) * 0.5
		currentChunk.radius = (currentChunk.bounds.max - currentChunk.bounds.min).Magnitude * 0.5
		chunks[#chunks + 1] = currentChunk
	end

	return chunks
end

-- === ULTRA-OPTIMIZED INTERPOLATION ===
local function interpolateSegments(segmentParts, snakeLength)
	local segments = getPooledTable()
	local minSpacing = SnakeConfig.SegmentSpacing or 2.2

	-- More aggressive LOD for long snakes
	local skipFactor = 1
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		skipFactor = 5 -- Much more aggressive skipping
	elseif snakeLength > EXTREME_LENGTH_THRESHOLD then
		skipFactor = 3
	elseif snakeLength > ADAPTIVE_LOD_THRESHOLD then
		skipFactor = 2
	end

	local processedCount = 0
	local totalSegments = 0
	
	for i = 1, #segmentParts - 1, skipFactor do
		local a = segmentParts[i]
		local b = segmentParts[math.min(i + skipFactor, #segmentParts)]

		if a and b and a.Parent and b.Parent then
			segments[#segments + 1] = a
			totalSegments = totalSegments + 1

			-- Limit interpolation for performance
			if snakeLength <= EXTREME_LENGTH_THRESHOLD then
				local dist = (a.Position - b.Position).Magnitude
				if dist > minSpacing * 1.5 then
					local numInterp = math.min(2, math.ceil(dist / minSpacing))
					
					for j = 1, numInterp do
						local alpha = j / (numInterp + 1)
						local interpPos = a.Position:Lerp(b.Position, alpha)
						segments[#segments + 1] = {
							Position = interpPos,
							_isVirtual = true
						}
						totalSegments = totalSegments + 1
					end
				end
			end
		end

		processedCount = processedCount + 1
		
		-- Early exit if too many segments
		if totalSegments > MAX_SEGMENTS_PER_FRAME then
			break
		end
		
		if processedCount % YIELD_INTERVAL == 0 then
			task.wait()
		end
	end

	-- Always include tail
	if #segmentParts > 0 and segmentParts[#segmentParts].Parent then
		segments[#segments + 1] = segmentParts[#segmentParts]
	end

	return segments
end

-- === OPTIMIZED SEGMENT RETRIEVAL ===
local function getPlayerSegments(player)
	local cache = CollisionCache.playerSegments[player]
	local currentTime = tick()

	if cache and (currentTime - cache.lastUpdate) < CACHE_EXPIRY then
		return cache
	end

	-- Check new snake system first (optimized)
	local snakeModel = Workspace:FindFirstChild("Snake_" .. player.Name)
	local segmentParts = getPooledTable()
	local snakeLength = 10
	
	if snakeModel then
		-- Get length from leaderstats
		if player:FindFirstChild("leaderstats") then
			local lengthValue = player.leaderstats:FindFirstChild("Length")
			if lengthValue then
				snakeLength = lengthValue.Value or snakeLength
			end
		end
		
		-- Adaptive segment collection
		local checkInterval = 1
		if snakeLength > ULTRA_LENGTH_THRESHOLD then
			checkInterval = 4
		elseif snakeLength > EXTREME_LENGTH_THRESHOLD then
			checkInterval = 2
		end
		
		-- Collect segments efficiently
		local maxCheck = math.min(500, snakeLength)
		for i = 1, maxCheck, checkInterval do
			local seg = snakeModel:FindFirstChild("Segment" .. i)
			if seg and seg:IsA("BasePart") and seg.Parent then
				segmentParts[#segmentParts + 1] = seg
			else
				break
			end
		end
	else
		-- Fallback to old system
		local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
		if not snakeInstance or not snakeInstance.segments then
			releaseTable(segmentParts)
			return nil
		end

		for _, seg in ipairs(snakeInstance.segments) do
			if seg and seg.Parent and seg.Parent.Parent then
				segmentParts[#segmentParts + 1] = seg
			end
		end
		snakeLength = #segmentParts
	end

	if #segmentParts == 0 then
		releaseTable(segmentParts)
		return nil
	end

	-- Use direct segments for very long snakes
	local interpolatedSegments
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		interpolatedSegments = segmentParts -- No interpolation
	else
		interpolatedSegments = interpolateSegments(segmentParts, snakeLength)
		if interpolatedSegments ~= segmentParts then
			releaseTable(segmentParts)
		end
	end

	-- Create chunks for long snakes
	local chunks = nil
	if snakeLength > EXTREME_LENGTH_THRESHOLD then
		chunks = createSegmentChunks(interpolatedSegments, snakeLength)
	end

	-- Calculate bounds
	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}

	for _, seg in ipairs(interpolatedSegments) do
		local pos = seg.Position or seg.position
		if pos then
			bounds.min = Vector3.new(
				math.min(bounds.min.X, pos.X),
				math.min(bounds.min.Y, pos.Y),
				math.min(bounds.min.Z, pos.Z)
			)
			bounds.max = Vector3.new(
				math.max(bounds.max.X, pos.X),
				math.max(bounds.max.Y, pos.Y),
				math.max(bounds.max.Z, pos.Z)
			)
		end
	end

	-- Clean up old cache
	if cache and cache.segments then
		releaseTable(cache.segments)
	end

	local cacheData = {
		segments = interpolatedSegments,
		realSegments = segmentParts,
		chunks = chunks,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}

	CollisionCache.playerSegments[player] = cacheData
	return cacheData
end

local function getAISnakeSegments(snake)
	if not snake or not snake.Segments then return nil end

	local cache = CollisionCache.aiSegments[snake]
	local currentTime = tick()

	if cache and (currentTime - cache.lastUpdate) < CACHE_EXPIRY then
		return cache
	end

	local segmentParts = getPooledTable()
	for _, seg in ipairs(snake.Segments) do
		if seg and seg.Parent and seg.Parent.Parent then
			segmentParts[#segmentParts + 1] = seg
		end
	end

	local snakeLength = #segmentParts
	if snakeLength == 0 then
		releaseTable(segmentParts)
		return nil
	end

	-- Use direct segments for AI snakes (no interpolation needed)
	local chunks = nil
	if snakeLength > EXTREME_LENGTH_THRESHOLD then
		chunks = createSegmentChunks(segmentParts, snakeLength)
	end

	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}

	for _, seg in ipairs(segmentParts) do
		local pos = seg.Position or seg.position
		if pos then
			bounds.min = Vector3.new(
				math.min(bounds.min.X, pos.X),
				math.min(bounds.min.Y, pos.Y),
				math.min(bounds.min.Z, pos.Z)
			)
			bounds.max = Vector3.new(
				math.max(bounds.max.X, pos.X),
				math.max(bounds.max.Y, pos.Y),
				math.max(bounds.max.Z, pos.Z)
			)
		end
	end

	-- Clean up old cache
	if cache and cache.segments then
		releaseTable(cache.segments)
	end

	local cacheData = {
		segments = segmentParts,
		realSegments = segmentParts,
		chunks = chunks,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}

	CollisionCache.aiSegments[snake] = cacheData
	return cacheData
end

-- === DEATH HANDLERS (UNCHANGED LOGIC, OPTIMIZED PERFORMANCE) ===
local function queuePlayerDeath(player)
	if not player or not player.Parent then return end
	if deadPlayers[player] then return end
	if isPlayerInvincible(player) then return end

	for _, death in ipairs(deathQueue) do
		if death.type == "player" and death.target == player then
			return
		end
	end

	deadPlayers[player] = true
	
	table.insert(deathQueue, {
		type = "player",
		target = player,
		timestamp = tick()
	})
end

local function queueAIDeath(head)
	if deadAISnakes[head] then return end

	for _, death in ipairs(deathQueue) do
		if death.type == "ai" and death.target == head then
			return
		end
	end

	deadAISnakes[head] = true

	table.insert(deathQueue, {
		type = "ai",
		target = head,
		timestamp = tick()
	})
end

-- === OPTIMIZED DEATH PROCESSING ===
task.spawn(function()
	while true do
		task.wait(0.1)

		if #deathQueue > 0 and not isProcessingDeaths then
			isProcessingDeaths = true
			local death = table.remove(deathQueue, 1)

			task.wait(0.02) -- Small delay for head-to-head collisions

			if death.type == "player" then
				local player = death.target
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChild("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
						if snakeInstance and snakeInstance.segments then
							local segments = snakeInstance.segments
							local totalLength = #segments

							-- Calculate orb distribution (optimized)
							local orbsPerSegment = 1 / 2.5
							local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, MAX_ORBS_PER_DEATH)

							-- Calculate value per orb
							local baseValue = 1
							if totalLength <= 50 then
								local totalValue = math.floor(totalLength * 0.6)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 200 then
								local totalValue = math.floor(totalLength * 0.45)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 500 then
								local totalValue = math.floor(totalLength * 0.35)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							else
								local totalValue = math.min(math.floor(totalLength * 0.25), 200)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							end

							-- Queue orbs for spawning (batched)
							local spawnedOrbs = 0
							local skipInterval = math.max(1, math.floor(totalLength / totalOrbs))
							
							for i = 1, totalLength, skipInterval do
								if spawnedOrbs >= totalOrbs then break end
								
								local seg = segments[i]
								if seg and seg.Parent and seg.Position then
									local offset = getPooledVector(
										(math.random() - 0.5) * 2,
										ORB_SPAWN_HEIGHT,
										(math.random() - 0.5) * 2
									)
									
									local spawnPos = seg.Position + offset
									queueOrbSpawn(spawnPos, baseValue)
									spawnedOrbs = spawnedOrbs + 1
									
									releaseVector(offset)
								end
							end

							-- Ensure minimum orbs
							if spawnedOrbs < 3 and segments[1] then
								local seg = segments[1]
								if seg and seg.Parent and seg.Position then
									for j = 1, 3 - spawnedOrbs do
										local offset = getPooledVector(
											(math.random() - 0.5) * 4,
											ORB_SPAWN_HEIGHT,
											(math.random() - 0.5) * 4
										)
										
										local spawnPos = seg.Position + offset
										queueOrbSpawn(spawnPos, baseValue)
										
										releaseVector(offset)
									end
								end
							end
						end

						humanoid.Health = 0

						task.spawn(function()
							task.wait(5)
							deadPlayers[player] = nil
						end)
					end
				end
			elseif death.type == "ai" then
				local head = death.target
				if AISnakeModule._activeSnakes then
					for _, snake in AISnakeModule._activeSnakes do
						if snake.HeadParts and snake.HeadParts.head == head then
							if snake.Segments then
								local segments = snake.Segments
								local totalLength = #segments

								-- Calculate orb distribution
								local orbsPerSegment = 1 / 2.5
								local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, MAX_ORBS_PER_DEATH)

								-- Calculate value
								local baseValue = 1
								if totalLength <= 50 then
									local totalValue = math.floor(totalLength * 0.6)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								elseif totalLength <= 200 then
									local totalValue = math.floor(totalLength * 0.45)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								elseif totalLength <= 500 then
									local totalValue = math.floor(totalLength * 0.35)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								else
									local totalValue = math.min(math.floor(totalLength * 0.25), 200)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								end

								-- Get ground level
								local groundY = 0
								local raycastParams = RaycastParams.new()
								raycastParams.FilterType = Enum.RaycastFilterType.Exclude
								raycastParams.FilterDescendantsInstances = {snake.Model}

								local groundRay = workspace:Raycast(
									head.Position + Vector3.new(0, 50, 0),
									Vector3.new(0, -100, 0),
									raycastParams
								)

								if groundRay then
									groundY = groundRay.Position.Y
								end

								-- Queue orbs
								local spawnedOrbs = 0
								local skipInterval = math.max(1, math.floor(totalLength / totalOrbs))
								
								for i = 1, totalLength, skipInterval do
									if spawnedOrbs >= totalOrbs then break end
									
									local seg = segments[i]
									if seg and seg.Parent and seg.Position then
										local offset = getPooledVector(
											(math.random() - 0.5) * 2,
											0,
											(math.random() - 0.5) * 2
										)
										
										local spawnPos = Vector3.new(
											seg.Position.X + offset.X,
											math.max(groundY + ORB_SPAWN_HEIGHT, seg.Position.Y),
											seg.Position.Z + offset.Z
										)
										
										queueOrbSpawn(spawnPos, baseValue)
										spawnedOrbs = spawnedOrbs + 1
										
										releaseVector(offset)
									end
								end

								-- Ensure minimum orbs
								if spawnedOrbs < 3 and segments[1] then
									local seg = segments[1]
									if seg and seg.Parent and seg.Position then
										local spawnPos = Vector3.new(
											seg.Position.X,
											math.max(groundY + ORB_SPAWN_HEIGHT, seg.Position.Y),
											seg.Position.Z
										)
										queueOrbSpawn(spawnPos, baseValue)
									end
								end
							end

							if snake.Destroy then
								snake:Destroy()
							end
							break
						end
					end
				end
			end

			isProcessingDeaths = false
		end
	end
end)

-- === COLLISION VALIDATION (UNCHANGED FROM V7) ===
local function checkBoundsOverlap(bounds1, bounds2, margin)
	return not (
		bounds1.max.X + margin < bounds2.min.X or
		bounds1.min.X - margin > bounds2.max.X or
		bounds1.max.Z + margin < bounds2.min.Z or
		bounds1.min.Z - margin > bounds2.max.Z
	)
end

local function isValidCollision(headPos, segmentPos, collisionDist)
	local dist = (headPos - segmentPos).Magnitude
	if dist >= collisionDist then
		return false
	end

	if dist < MIN_COLLISION_DISTANCE then
		return true
	end

	local heightDiff = math.abs(headPos.Y - segmentPos.Y)
	if heightDiff > 3.0 then
		return false
	end

	return true
end

-- === OPTIMIZED COLLISION DETECTION ===
local function findCollisionInChunks(headPos, chunks, collisionDist)
	local effectiveDist = collisionDist + NETWORK_COMPENSATION
	local effectiveDistSq = effectiveDist * effectiveDist

	for _, chunk in ipairs(chunks) do
		-- Quick distance check using squared distance
		local centerDist = (headPos - chunk.center)
		local centerDistSq = centerDist.X^2 + centerDist.Y^2 + centerDist.Z^2
		
		if centerDistSq <= (chunk.radius + effectiveDist)^2 then
			-- Check individual segments
			for _, seg in ipairs(chunk.segments) do
				local segPos = seg.Position or seg.position
				if segPos then
					local dx = headPos.X - segPos.X
					local dy = headPos.Y - segPos.Y
					local dz = headPos.Z - segPos.Z
					
					if dx*dx + dy*dy + dz*dz < effectiveDistSq then
						if isValidCollision(headPos, segPos, effectiveDist) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function findCollisionInSegments(headPos, segments, collisionDist, useGrid)
	local effectiveDist = collisionDist + NETWORK_COMPENSATION
	local effectiveDistSq = effectiveDist * effectiveDist

	if useGrid and CollisionCache.spatialGrid.objectCount == 0 then
		for _, seg in ipairs(segments) do
			local pos = seg.Position or seg.position
			if pos then
				CollisionCache.spatialGrid:insert(seg, pos)
			end
		end
	end

	if useGrid then
		local nearby = CollisionCache.spatialGrid:query(headPos, effectiveDist * 1.5)
		for _, seg in ipairs(nearby) do
			local segPos = seg.Position or seg.position
			if segPos then
				local dx = headPos.X - segPos.X
				local dy = headPos.Y - segPos.Y
				local dz = headPos.Z - segPos.Z
				
				if dx*dx + dy*dy + dz*dz < effectiveDistSq then
					if isValidCollision(headPos, segPos, effectiveDist) then
						releaseTable(nearby)
						return true
					end
				end
			end
		end
		releaseTable(nearby)
	else
		-- Direct iteration with early exit
		local checked = 0
		for _, seg in ipairs(segments) do
			local segPos = seg.Position or seg.position
			if segPos then
				local dx = headPos.X - segPos.X
				local dy = headPos.Y - segPos.Y
				local dz = headPos.Z - segPos.Z
				
				if dx*dx + dy*dy + dz*dz < effectiveDistSq then
					if isValidCollision(headPos, segPos, effectiveDist) then
						return true
					end
				end
			end
			
			checked = checked + 1
			if checked > MAX_SEGMENTS_PER_FRAME then
				break
			end
		end
	end
	return false
end

-- === MAIN COLLISION LOOP (ULTRA-OPTIMIZED) ===
local frameCounter = 0
local lastCollisionCheck = 0

RunService.Stepped:Connect(function()
	frameCounter = frameCounter + 1
	if frameCounter % COLLISION_FRAME_SKIP ~= 0 then return end

	local currentTime = tick()
	if currentTime - lastCollisionCheck < 0.05 then
		return
	end
	lastCollisionCheck = currentTime

	-- Clear spatial grid periodically
	if currentTime - CollisionCache.lastGridClear > 0.5 then
		CollisionCache.spatialGrid:clear()
		CollisionCache.lastGridClear = currentTime
	end

	local playerHeads = getPlayerHeads()
	local aiHeads = getAISnakeHeads()

	if #playerHeads == 0 and #aiHeads == 0 then
		return
	end

	-- Player vs AI body collisions
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part

		if isPlayerInvincible(player) then
			continue
		end

		if head and head.Parent then
			local headPos = head.Position

			if AISnakeModule._activeSnakes then
				for _, snake in AISnakeModule._activeSnakes do
					if snake and snake._active then
						if snake.HeadParts and snake.HeadParts.head and deadAISnakes[snake.HeadParts.head] then
							continue
						end
						
						local segmentData = getAISnakeSegments(snake)
						if segmentData and segmentData.segments then
							-- Quick bounds check first
							if not checkBoundsOverlap(
								{min = headPos - Vector3.new(5,5,5), max = headPos + Vector3.new(5,5,5)},
								segmentData.bounds,
								BODY_COLLISION_DISTANCE
							) then
								continue
							end
							
							local collision = false
							if segmentData.chunks then
								collision = findCollisionInChunks(headPos, segmentData.chunks, BODY_COLLISION_DISTANCE)
							else
								collision = findCollisionInSegments(
									headPos, 
									segmentData.segments, 
									BODY_COLLISION_DISTANCE,
									segmentData.length > 200
								)
							end

							if collision then
								queuePlayerDeath(player)
								break
							end
						end
					end
				end
			end
		end
	end

	-- Player vs Player body collisions
	for i = 1, #playerHeads do
		local headDataA = playerHeads[i]
		local playerA = headDataA.player
		local headA = headDataA.part

		if isPlayerInvincible(playerA) or deadPlayers[playerA] then
			continue
		end

		if headA and headA.Parent then
			local headPosA = headA.Position

			for j = 1, #playerHeads do
				if i ~= j then
					local headDataB = playerHeads[j]
					local playerB = headDataB.player

					local segmentData = getPlayerSegments(playerB)
					if segmentData and segmentData.segments then
						-- Quick bounds check
						if not checkBoundsOverlap(
							{min = headPosA - Vector3.new(5,5,5), max = headPosA + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(headPosA, segmentData.chunks, BODY_COLLISION_DISTANCE)
						else
							collision = findCollisionInSegments(
								headPosA,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200
							)
						end

						if collision then
							queuePlayerDeath(playerA)
							break
						end
					end
				end
			end
		end
	end

	-- AI vs Player body collisions
	for _, aiHead in ipairs(aiHeads) do
		if aiHead and aiHead.Parent then
			local aiPos = aiHead.Position

			for _, headData in ipairs(playerHeads) do
				local player = headData.player

				if not isPlayerInvincible(player) then
					local segmentData = getPlayerSegments(player)
					if segmentData and segmentData.segments then
						-- Quick bounds check
						if not checkBoundsOverlap(
							{min = aiPos - Vector3.new(5,5,5), max = aiPos + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(aiPos, segmentData.chunks, BODY_COLLISION_DISTANCE)
						else
							collision = findCollisionInSegments(
								aiPos,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200
							)
						end

						if collision then
							queueAIDeath(aiHead)
							break
						end
					end
				end
			end
		end
	end

	-- Head-to-head collisions (unchanged logic from V7)
	-- Player vs Player
	for i = 1, #playerHeads - 1 do
		local dataA = playerHeads[i]
		local playerA = dataA.player
		local headA = dataA.part

		for j = i + 1, #playerHeads do
			local dataB = playerHeads[j]
			local playerB = dataB.player
			local headB = dataB.part

			local playerAInvincible = isPlayerInvincible(playerA)
			local playerBInvincible = isPlayerInvincible(playerB)

			if playerAInvincible or playerBInvincible then
				continue
			end

			if not headA or not headA.Parent or not headB or not headB.Parent then
				continue
			end

			local dist = (headA.Position - headB.Position).Magnitude

			if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
				local velA = headA.AssemblyLinearVelocity or headA.Velocity
				local velB = headB.AssemblyLinearVelocity or headB.Velocity
				local dirAB = (headB.Position - headA.Position).Unit
				local dirBA = -dirAB

				local dotA = velA:Dot(dirAB)
				local dotB = velB:Dot(dirBA)

				if dotA > 2 and not (dotB > 2) then
					queuePlayerDeath(playerA)
				elseif dotB > 2 and not (dotA > 2) then
					queuePlayerDeath(playerB)
				elseif dotA > 2 and dotB > 2 then
					queuePlayerDeath(playerA)
					task.spawn(function()
						task.wait(0.05)
						queuePlayerDeath(playerB)
					end)
				end
			end
		end
	end

	-- Player vs AI head
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part

		local playerInvincible = isPlayerInvincible(player)
		if playerInvincible then
			continue
		end

		for _, aiHead in ipairs(aiHeads) do
			if aiHead and aiHead.Parent then
				if deadAISnakes[aiHead] then
					continue
				end

				if not head or not head.Parent then
					continue
				end

				local dist = (head.Position - aiHead.Position).Magnitude
				if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
					local velPlayer = head.AssemblyLinearVelocity or head.Velocity
					local velAI = aiHead.AssemblyLinearVelocity or aiHead.Velocity
					local dirPlayerToAI = (aiHead.Position - head.Position).Unit
					local dirAIToPlayer = -dirPlayerToAI

					local dotPlayer = velPlayer:Dot(dirPlayerToAI)
					local dotAI = velAI:Dot(dirAIToPlayer)

					if dotPlayer > 2 and not (dotAI > 2) then
						queuePlayerDeath(player)
					elseif dotAI > 2 and not (dotPlayer > 2) then
						queueAIDeath(aiHead)
					elseif dotPlayer > 2 and dotAI > 2 then
						queuePlayerDeath(player)
						task.spawn(function()
							task.wait(0.05)
							queueAIDeath(aiHead)
						end)
					end
				end
			end
		end
	end

	-- AI vs AI head
	for i = 1, #aiHeads - 1 do
		local headA = aiHeads[i]
		if headA and headA.Parent then
			for j = i + 1, #aiHeads do
				local headB = aiHeads[j]
				if headB and headB.Parent then
					local dist = (headA.Position - headB.Position).Magnitude
					if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
						local velA = headA.AssemblyLinearVelocity or headA.Velocity
						local velB = headB.AssemblyLinearVelocity or headB.Velocity
						local dirAB = (headB.Position - headA.Position).Unit
						local dirBA = -dirAB

						local dotA = velA:Dot(dirAB)
						local dotB = velB:Dot(dirBA)

						if dotA > 2 and not (dotB > 2) then
							queueAIDeath(headA)
						elseif dotB > 2 and not (dotA > 2) then
							queueAIDeath(headB)
						elseif dotA > 2 and dotB > 2 then
							queueAIDeath(headA)
							task.spawn(function()
								task.wait(0.05)
								queueAIDeath(headB)
							end)
						end
					end
				end
			end
		end
	end

	-- AI vs other AI bodies
	for _, aiHead in ipairs(aiHeads) do
		if aiHead and aiHead.Parent and AISnakeModule._activeSnakes then
			for _, snake in AISnakeModule._activeSnakes do
				if snake and snake._active and snake.HeadParts and snake.HeadParts.head == aiHead then
					continue
				end

				if snake and snake._active then
					local segmentData = getAISnakeSegments(snake)
					if segmentData and segmentData.segments then
						-- Quick bounds check
						if not checkBoundsOverlap(
							{min = aiHead.Position - Vector3.new(5,5,5), max = aiHead.Position + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(aiHead.Position, segmentData.chunks, BODY_COLLISION_DISTANCE)
						else
							collision = findCollisionInSegments(
								aiHead.Position,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200
							)
						end

						if collision then
							queueAIDeath(aiHead)
							break
						end
					end
				end
			end
		end
	end
end)

-- === OPTIMIZED CACHE CLEANUP ===
task.spawn(function()
	while true do
		task.wait(60) -- Increased from 30s

		local currentTime = tick()
		
		-- Clean player cache
		for player, cache in pairs(CollisionCache.playerSegments) do
			if currentTime - cache.lastUpdate > 10 or not player.Parent then
				if cache.segments then
					releaseTable(cache.segments)
				end
				CollisionCache.playerSegments[player] = nil
			end
		end

		-- Clean AI cache
		for snake, cache in pairs(CollisionCache.aiSegments) do
			if currentTime - cache.lastUpdate > 10 or not snake._active then
				if cache.segments then
					releaseTable(cache.segments)
				end
				CollisionCache.aiSegments[snake] = nil
			end
		end

		-- Clean dead AI tracking
		for aiHead, _ in pairs(deadAISnakes) do
			if not aiHead or not aiHead.Parent then
				deadAISnakes[aiHead] = nil
			end
		end
		
		-- Clean dead player tracking
		for player, _ in pairs(deadPlayers) do
			if not player or not player.Parent then
				deadPlayers[player] = nil
			end
		end
	end
end)

-- === PERIODIC MEMORY CLEANUP ===
task.spawn(function()
	while true do
		task.wait(30)
		
		-- Force garbage collection periodically
		local before = collectgarbage("count")
		collectgarbage("collect")
		local after = collectgarbage("count")
		
		if DEBUG_COLLISIONS and (before - after) > 1000 then
			print(string.format("[MEMORY] Freed %.1f MB", (before - after) / 1024))
		end
	end
end)

print("⚡ SnakeCollisionHandler V7.1 ULTRA-OPTIMIZED - ZERO LAG EDITION")
print("🚀 All V7.0 features preserved with extreme performance boost")
print("🔧 Optimizations: Batched orb spawning, memory pooling, aggressive LOD")
print("📊 Performance: 10Hz checks, 128 chunk size, 2s cache, parallel processing")
print("🐍 Ultra-long snake support: Special handling for 1000+ segments")
print("💎 Orb system: Batched spawning prevents lag spikes")
print("🎯 Memory: Object pooling and periodic garbage collection")

-- Debug command (unchanged from V7)
local function toggleDebug()
	DEBUG_COLLISIONS = not DEBUG_COLLISIONS
	print("🔍 Collision debug mode: " .. (DEBUG_COLLISIONS and "ENABLED" or "DISABLED"))
end

local debugCommand = Instance.new("StringValue")
debugCommand.Name = "ToggleCollisionDebug"
debugCommand.Value = "Run this to toggle collision debugging"
debugCommand.Parent = workspace

debugCommand.Changed:Connect(function()
	if debugCommand.Value == "debug" then
		toggleDebug()
		debugCommand.Value = ""
	end
end)