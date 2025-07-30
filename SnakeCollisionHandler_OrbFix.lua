-- SnakeCollisionHandler V7.0 OPTIMIZED: V7.0 DEATH ORB SYSTEM
-- All V7 functionality preserved with performance optimizations
-- DEATH ORB SYSTEM: Using exact V7.0 death orb spawning (no shrinking/disappearing)
--   - Direct spawning without delays or batching
--   - Spawns along entire snake path
--   - Simple random offset (2 studs)
--   - No spawn protection workarounds needed

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- === OPTIMIZED PERFORMANCE CONSTANTS ===
local SEGMENT_CHUNK_SIZE = 96 -- Increased from 64 for better batching
local COLLISION_GRID_SIZE = 120 -- Slightly larger cells
local ADAPTIVE_LOD_THRESHOLD = 100
local EXTREME_LENGTH_THRESHOLD = 500
local ULTRA_LENGTH_THRESHOLD = 1000 -- For mega snakes
local CACHE_EXPIRY = 1.5 -- Slightly longer cache
local YIELD_INTERVAL = 150 -- Less frequent yielding
local NETWORK_COMPENSATION = 0.1
local COLLISION_FRAME_SKIP = 5 -- Process every 5 frames (12 Hz)

-- === COLLISION CONSTANTS (UNCHANGED FROM V7) ===
local HEAD_COLLISION_DISTANCE = 3.5
local BODY_COLLISION_DISTANCE = 2.8
local MIN_COLLISION_DISTANCE = 2.0
local COLLISION_BUFFER = 0.5

-- === FIXED ORB SPAWNING SYSTEM (FROM V7.0) ===
local ORB_SPAWN_HEIGHT = 2 -- Standard height above ground for orbs
local MIN_ORB_SPACING = 3 -- Minimum distance between spawned orbs

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
		lastClear = 0
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

	if not self.cells[key] then
		self.cells[key] = {}
	end

	table.insert(self.cells[key], object)
	self.objectCount = self.objectCount + 1
end

function SpatialGrid:query(position, radius)
	local results = {}
	local cellRadius = math.ceil(radius / self.cellSize)
	local cx, cz = self:getCell(position)

	-- Limit search radius for performance
	cellRadius = math.min(cellRadius, 3)

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

	return results
end

function SpatialGrid:clear()
	-- Only clear if enough time has passed
	local currentTime = tick()
	if currentTime - self.lastClear < 0.5 then
		return
	end
	
	for k in pairs(self.cells) do
		self.cells[k] = nil
	end
	self.objectCount = 0
	self.lastClear = currentTime
end

-- === COLLISION CACHE ===
local CollisionCache = {
	playerSegments = {},
	aiSegments = {},
	spatialGrid = SpatialGrid.new(),
	frameCache = {}
}

-- === FIXED ORB SPAWNING SYSTEM ===
local ORB_SPAWN_HEIGHT = 2 -- Standard height above ground for orbs
local MIN_ORB_SPACING = 3 -- Minimum distance between spawned orbs

local function spawnOrbDirect(position, value)
	-- Direct spawn with minimal processing
	local success, err = pcall(function()
		OrbUtils.spawnOrbAt(position, value)
	end)

	if not success then
		warn("Orb spawn failed:", err)
	end
end

-- === HEAD RETRIEVAL (OPTIMIZED) ===
local headCache = {
	players = {},
	ai = {},
	lastUpdate = 0
}

local function getPlayerHeads()
	local currentTime = tick()
	if currentTime - headCache.lastUpdate < 0.1 then
		return headCache.players
	end

	local heads = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Parent then
				heads[#heads + 1] = {player = player, part = root}
			end
		end
	end

	headCache.players = heads
	headCache.lastUpdate = currentTime
	return heads
end

local function getAISnakeHeads()
	local heads = {}
	if AISnakeModule._activeSnakes then
		for _, snake in AISnakeModule._activeSnakes do
			if snake.HeadParts and snake.HeadParts.head and snake.HeadParts.head.Parent then
				heads[#heads + 1] = snake.HeadParts.head
			end
		end
	end
	headCache.ai = heads
	return heads
end

-- === OPTIMIZED SEGMENT PROCESSING ===
local function createSegmentChunks(segments, snakeLength)
	local chunks = {}
	local currentChunk = {
		segments = {},
		bounds = {
			min = Vector3.new(math.huge, math.huge, math.huge),
			max = Vector3.new(-math.huge, -math.huge, -math.huge)
		},
		center = Vector3.new(0, 0, 0),
		radius = 0
	}

	-- Use larger chunks for ultra-long snakes
	local chunkSize = snakeLength > ULTRA_LENGTH_THRESHOLD and SEGMENT_CHUNK_SIZE * 1.5 or SEGMENT_CHUNK_SIZE
	
	local processedCount = 0
	for i, seg in ipairs(segments) do
		local pos = seg.Position or seg.position
		if pos then
			-- Update bounding box
			currentChunk.bounds.min = Vector3.new(
				math.min(currentChunk.bounds.min.X, pos.X),
				math.min(currentChunk.bounds.min.Y, pos.Y),
				math.min(currentChunk.bounds.min.Z, pos.Z)
			)
			currentChunk.bounds.max = Vector3.new(
				math.max(currentChunk.bounds.max.X, pos.X),
				math.max(currentChunk.bounds.max.Y, pos.Y),
				math.max(currentChunk.bounds.max.Z, pos.Z)
			)

			currentChunk.segments[#currentChunk.segments + 1] = seg

			if #currentChunk.segments >= chunkSize then
				-- Calculate chunk center and radius
				currentChunk.center = (currentChunk.bounds.min + currentChunk.bounds.max) * 0.5
				currentChunk.radius = (currentChunk.bounds.max - currentChunk.bounds.min).Magnitude * 0.5

				chunks[#chunks + 1] = currentChunk
				currentChunk = {
					segments = {},
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
		if processedCount % YIELD_INTERVAL == 0 then
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

-- === OPTIMIZED INTERPOLATION ===
local function interpolateSegments(segmentParts, snakeLength)
	local segments = {}
	local minSpacing = SnakeConfig.SegmentSpacing or 2.2

	-- More aggressive LOD for ultra-long snakes
	local skipFactor = 1
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		skipFactor = 4 -- Very aggressive skipping
	elseif snakeLength > EXTREME_LENGTH_THRESHOLD then
		skipFactor = 3
	elseif snakeLength > ADAPTIVE_LOD_THRESHOLD then
		skipFactor = 2
	end

	local processedCount = 0
	for i = 1, #segmentParts - 1, skipFactor do
		local a = segmentParts[i]
		local b = segmentParts[math.min(i + skipFactor, #segmentParts)]

		if a and b and a.Parent and b.Parent then
			segments[#segments + 1] = a

			-- Reduced interpolation for long snakes
			if snakeLength < EXTREME_LENGTH_THRESHOLD then
				local segmentProgress = i / snakeLength
				local densityFactor = 0.5

				if segmentProgress < 0.15 then
					densityFactor = 0.25
				elseif segmentProgress > 0.85 then
					densityFactor = 0.4
				end

				local interpStep = minSpacing * densityFactor
				local dist = (a.Position - b.Position).Magnitude

				if dist > interpStep then
					local numInterp = math.ceil(dist / interpStep)
					numInterp = math.min(numInterp, 2) -- Max 2 interpolated segments
					
					for j = 1, numInterp do
						local alpha = j / (numInterp + 1)
						local interpPos = a.Position:Lerp(b.Position, alpha)
						segments[#segments + 1] = {
							Position = interpPos,
							_isVirtual = true,
							_priority = segmentProgress < 0.3 and 2 or 1
						}
					end
				end
			end
		end

		processedCount = processedCount + 1
		if processedCount % YIELD_INTERVAL == 0 then
			task.wait()
		end
	end

	if #segmentParts > 0 and segmentParts[#segmentParts].Parent then
		segments[#segments + 1] = segmentParts[#segmentParts]
	end

	return segments
end

-- === FIXED: Get actual snake segments for orb spawning ===
local function getActualSnakeSegments(player)
	-- First try the new snake model system
	local snakeModel = Workspace:FindFirstChild("Snake_" .. player.Name)
	if snakeModel then
		local segments = {}
		local i = 1
		while true do
			local segment = snakeModel:FindFirstChild("Segment" .. i)
			if segment and segment:IsA("BasePart") then
				segments[#segments + 1] = segment
				i = i + 1
			else
				break
			end
		end
		if #segments > 0 then
			if DEBUG_COLLISIONS then
				print(string.format("[ORB DEBUG] Found %d segments in Snake_%s model", #segments, player.Name))
			end
			return segments
		end
	end
	
	-- Try the global snake system
	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance and snakeInstance.segments then
		local segments = {}
		for _, seg in ipairs(snakeInstance.segments) do
			if seg and seg:IsA("BasePart") and seg.Parent then
				segments[#segments + 1] = seg
			end
		end
		if #segments > 0 then
			if DEBUG_COLLISIONS then
				print(string.format("[ORB DEBUG] Found %d segments in _G.PlayerSnakes", #segments))
			end
			return segments
		end
	end
	
	-- Try from cache
	local cacheData = CollisionCache.playerSegments[player]
	if cacheData and cacheData.realSegments then
		local segments = {}
		for _, seg in ipairs(cacheData.realSegments) do
			if seg and seg:IsA("BasePart") and seg.Parent then
				segments[#segments + 1] = seg
			end
		end
		if #segments > 0 then
			if DEBUG_COLLISIONS then
				print(string.format("[ORB DEBUG] Found %d segments in cache", #segments))
			end
			return segments
		end
	end
	
	if DEBUG_COLLISIONS then
		warn(string.format("[ORB DEBUG] No segments found for player %s", player.Name))
	end
	return nil
end

-- === SEGMENT RETRIEVAL (OPTIMIZED) ===
local function getPlayerSegments(player)
	local cache = CollisionCache.playerSegments[player]
	local currentTime = tick()

	if cache and (currentTime - cache.lastUpdate) < CACHE_EXPIRY then
		return cache
	end

	-- Get actual segments
	local segmentParts = getActualSnakeSegments(player) or {}
	local snakeLength = #segmentParts
	
	-- Also check length from leaderstats
	if player:FindFirstChild("leaderstats") then
		local lengthValue = player.leaderstats:FindFirstChild("Length")
		if lengthValue then
			snakeLength = math.max(snakeLength, lengthValue.Value or snakeLength)
		end
	end
	
	if #segmentParts == 0 then return nil end

	-- Use direct segments for ultra-long snakes
	local interpolatedSegments
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		interpolatedSegments = segmentParts
	else
		interpolatedSegments = interpolateSegments(segmentParts, snakeLength)
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

	local segmentParts = {}
	for _, seg in ipairs(snake.Segments) do
		if seg and seg.Parent and seg.Parent.Parent then
			segmentParts[#segmentParts + 1] = seg
		end
	end

	local snakeLength = #segmentParts
	if snakeLength == 0 then return nil end

	-- Less interpolation for AI snakes
	local interpolatedSegments = snakeLength > EXTREME_LENGTH_THRESHOLD and segmentParts or interpolateSegments(segmentParts, snakeLength)

	local chunks = nil
	if snakeLength > EXTREME_LENGTH_THRESHOLD then
		chunks = createSegmentChunks(interpolatedSegments, snakeLength)
	end

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

	local cacheData = {
		segments = interpolatedSegments,
		realSegments = segmentParts,
		chunks = chunks,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}

	CollisionCache.aiSegments[snake] = cacheData
	return cacheData
end

-- === DEATH HANDLERS (UNCHANGED LOGIC) ===
local function queuePlayerDeath(player)
	if not player or not player.Parent then return end
	if deadPlayers[player] then return end
	if isPlayerInvincible(player) then return end

	for _, death in ipairs(deathQueue) do
		if death.type == "player" and death.target == player then
			return
		end
	end

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

-- === FIXED DEATH PROCESSING WITH PROPER ORB SPAWNING ===
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
						-- Get snake length from leaderstats
						local snakeLength = 55
						if player:FindFirstChild("leaderstats") then
							local lengthValue = player.leaderstats:FindFirstChild("Length")
							if lengthValue then
								snakeLength = lengthValue.Value or 55
							end
						end

						-- FIXED: Get actual snake segments properly
						local segments = getActualSnakeSegments(player)
						
						-- IMPORTANT: Store segment positions BEFORE the snake gets destroyed
						local segmentPositions = {}
						if segments and #segments > 0 then
							for i, seg in ipairs(segments) do
								if seg and seg:IsA("BasePart") and seg.Parent and seg.Position then
									segmentPositions[i] = seg.Position -- Vector3 values are copied by value
								end
							end
						end
						
						-- Get actual snake segments (V7.0 style)
						local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
						if snakeInstance and snakeInstance.segments then
							local segments = snakeInstance.segments
							local totalLength = #segments
							
							-- Calculate orb distribution
							local orbsPerSegment = 1 / 2.5 -- One orb every 2.5 segments
							local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, 30)
							
							-- Dynamic value calculation based on snake length
							local baseValue = 1
							if totalLength <= 50 then
								-- Small snakes: give back 60% of length
								local totalValue = math.floor(totalLength * 0.6)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 200 then
								-- Medium snakes: give back 45% of length
								local totalValue = math.floor(totalLength * 0.45)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 500 then
								-- Large snakes: give back 35% of length
								local totalValue = math.floor(totalLength * 0.35)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							else
								-- Very large snakes: give back 25% of length with cap
								local totalValue = math.min(math.floor(totalLength * 0.25), 200)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							end
							
							local valuePerOrb = baseValue
							
							-- Spawn orbs along the snake path with error handling
							local spawnedOrbs = 0
							for i = 1, totalLength do
								if math.random() < orbsPerSegment then
									local seg = segments[i]
									if seg and seg.Parent and seg.Position then
										local pos = seg.Position
										
										-- Small random offset to prevent perfect stacking
										local offset = Vector3.new(
											(math.random() - 0.5) * 2,
											0,
											(math.random() - 0.5) * 2
										)
										
										-- Spawn at segment position with small offset
										local success = pcall(function()
											spawnOrbDirect(pos + offset + Vector3.new(0, ORB_SPAWN_HEIGHT, 0), valuePerOrb)
											spawnedOrbs = spawnedOrbs + 1
										end)
										
										if not success then
											warn("Failed to spawn orb for player death")
										end
									end
								end
							end
							
							-- Ensure at least some orbs spawn
							if spawnedOrbs == 0 and totalLength > 0 then
								local firstSeg = segments[1]
								if firstSeg and firstSeg.Parent and firstSeg.Position then
									pcall(function()
										spawnOrbDirect(firstSeg.Position + Vector3.new(0, ORB_SPAWN_HEIGHT, 0), valuePerOrb)
									end)
								end
							end
						else
							-- No fallback needed - V7.0 style
						end

						deadPlayers[player] = true
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
								local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, 30)

								-- Dynamic value calculation
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

								local valuePerOrb = baseValue

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

																-- Spawn orbs along the snake path with error handling
								local spawnedOrbs = 0
								for i = 1, totalLength do
									if math.random() < orbsPerSegment then
										local seg = segments[i]
										if seg and seg.Parent and seg.Position then
											local pos = seg.Position
											
											-- Small random offset
											local offset = Vector3.new(
												(math.random() - 0.5) * 2,
												0,
												(math.random() - 0.5) * 2
											)
											
											-- Ensure proper height
											local spawnPos = Vector3.new(
												pos.X + offset.X,
												math.max(groundY + ORB_SPAWN_HEIGHT, pos.Y),
												pos.Z + offset.Z
											)
											
											local success = pcall(function()
												spawnOrbDirect(spawnPos, valuePerOrb)
												spawnedOrbs = spawnedOrbs + 1
											end)
											
											if not success then
												warn("Failed to spawn orb for AI death")
											end
										end
									end
								end
								
								-- Ensure at least some orbs spawn
								if spawnedOrbs == 0 and totalLength > 0 then
									local firstSeg = segments[1]
									if firstSeg and firstSeg.Parent and firstSeg.Position then
										pcall(function()
											local spawnPos = Vector3.new(
												firstSeg.Position.X,
												math.max(groundY + ORB_SPAWN_HEIGHT, firstSeg.Position.Y),
												firstSeg.Position.Z
											)
											spawnOrbDirect(spawnPos, valuePerOrb)
										end)
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
		-- Quick distance check
		local centerDist = (headPos - chunk.center).Magnitude
		if centerDist <= chunk.radius + effectiveDist then
			-- Check segments in chunk
			for _, seg in ipairs(chunk.segments) do
				local segPos = seg.Position or seg.position
				if segPos then
					-- Use squared distance for performance
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
						return true
					end
				end
			end
		end
	else
		-- Direct iteration
		local checked = 0
		local maxCheck = math.min(#segments, 300) -- Limit segments checked
		
		for i = 1, maxCheck do
			local seg = segments[i]
			if seg then
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
			
			checked = checked + 1
			if checked % 50 == 0 then
				-- Brief yield for very long checks
				task.wait()
			end
		end
	end
	return false
end

-- === MAIN COLLISION LOOP (KEEP V7 LOGIC WITH OPTIMIZATIONS) ===
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

	-- Clear frame cache
	CollisionCache.frameCache = {}

	local playerHeads = getPlayerHeads()
	local aiHeads = getAISnakeHeads()

	if #playerHeads == 0 and #aiHeads == 0 then
		return
	end

	-- === ALL COLLISION CHECKS FROM V7 (UNCHANGED LOGIC) ===
	
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
							-- Quick bounds check
							if segmentData.bounds and not checkBoundsOverlap(
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
						if segmentData.bounds and not checkBoundsOverlap(
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
							if DEBUG_COLLISIONS then
								print(string.format("[COLLISION] %s hit %s's body", playerA.Name, playerB.Name))
							end
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
						if segmentData.bounds and not checkBoundsOverlap(
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

	-- Head-to-head collisions (UNCHANGED FROM V7)
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
				if DEBUG_COLLISIONS then
					print(string.format("[INVINCIBILITY] Skipping collision - PlayerA: %s (invincible: %s), PlayerB: %s (invincible: %s)", 
						playerA.Name, tostring(playerAInvincible), playerB.Name, tostring(playerBInvincible)))
				end
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
					if DEBUG_COLLISIONS then
						print(string.format("[DEATH] Player A dies: %s (dotA: %.2f, dotB: %.2f)", playerA.Name, dotA, dotB))
					end
					queuePlayerDeath(playerA)
				elseif dotB > 2 and not (dotA > 2) then
					if DEBUG_COLLISIONS then
						print(string.format("[DEATH] Player B dies: %s (dotA: %.2f, dotB: %.2f)", playerB.Name, dotA, dotB))
					end
					queuePlayerDeath(playerB)
				elseif dotA > 2 and dotB > 2 then
					if DEBUG_COLLISIONS then
						print(string.format("[DEATH] Both die simultaneously: %s and %s (dotA: %.2f, dotB: %.2f)", playerA.Name, playerB.Name, dotA, dotB))
					end
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
			if DEBUG_COLLISIONS then
				print(string.format("[INVINCIBILITY] Skipping Player vs AI collision - Player: %s (invincible: %s)", 
					player.Name, tostring(playerInvincible)))
			end
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
						if segmentData.bounds and not checkBoundsOverlap(
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

	-- Clear spatial grid
	CollisionCache.spatialGrid:clear()
end)

-- === OPTIMIZED CACHE CLEANUP ===
task.spawn(function()
	while true do
		task.wait(45) -- Less frequent cleanup

		local currentTime = tick()
		
		-- Clean player cache
		for player, cache in pairs(CollisionCache.playerSegments) do
			if currentTime - cache.lastUpdate > 10 or not player.Parent then
				CollisionCache.playerSegments[player] = nil
			end
		end

		-- Clean AI cache
		for snake, cache in pairs(CollisionCache.aiSegments) do
			if currentTime - cache.lastUpdate > 10 or not snake._active then
				CollisionCache.aiSegments[snake] = nil
			end
		end

		-- Clean dead tracking
		for aiHead, _ in pairs(deadAISnakes) do
			if not aiHead or not aiHead.Parent then
				deadAISnakes[aiHead] = nil
			end
		end
		
		for player, _ in pairs(deadPlayers) do
			if not player or not player.Parent then
				deadPlayers[player] = nil
			end
		end
	end
end)

-- === MEMORY MONITORING (FIXED) ===
task.spawn(function()
	while true do
		task.wait(60) -- Check memory every minute
		
		-- Use gcinfo() instead of collectgarbage("count")
		local memoryMB = gcinfo() / 1024
		
		if DEBUG_COLLISIONS and memoryMB > 500 then
			warn(string.format("[MEMORY] High memory usage: %.1f MB", memoryMB))
		end
		
		-- Process any remaining orb spawns
		if #orbSpawnBuffer > 50 then
			warn("[ORB BUFFER] Large orb spawn buffer:", #orbSpawnBuffer)
		end
	end
end)

print("⚡ SnakeCollisionHandler V7.0 OPTIMIZED - V7.0 DEATH ORB SYSTEM")
print("🚀 All V7 functionality preserved with performance optimizations")
print("💎 DEATH ORBS: Using exact V7.0 spawning (no shrinking/disappearing)")
print("   - Direct spawning along entire snake")
print("   - No delays or batching")
print("   - 2 stud random offset")
print("🔧 Optimizations: Aggressive LOD, bounds checking, spatial grid")
print("📊 Performance: 12Hz checks, 96 chunk size, 1.5s cache")

-- Debug command (unchanged from V7)
local function toggleDebug()
	DEBUG_COLLISIONS = not DEBUG_COLLISIONS
	print("🔍 Collision debug mode: " .. (DEBUG_COLLISIONS and "ENABLED" or "DISABLED"))
	if DEBUG_COLLISIONS then
		print("   - Orb spawning debug enabled")
		print("   - Collision detection debug enabled")
	end
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