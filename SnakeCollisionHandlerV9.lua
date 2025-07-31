-- SnakeCollisionHandler V9.0: ULTRA-OPTIMIZED COLLISION SYSTEM
-- Major fixes: Extreme performance optimization for 1000+ segment snakes
-- New features: Segment batching, distance-based LOD, smart collision zones

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- Get or create death notification event
local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
remoteEvents.Name = "RemoteEvents"
local deathNotifyEvent = remoteEvents:FindFirstChild("PlayerDeath") or Instance.new("RemoteEvent", remoteEvents)
deathNotifyEvent.Name = "PlayerDeath"

local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- === ULTRA-OPTIMIZED PERFORMANCE CONSTANTS ===
local COLLISION_CHECK_INTERVAL = 0.1 -- Check collisions 10 times per second max
local SEGMENT_BATCH_SIZE = 50 -- Process segments in batches
local MAX_SEGMENTS_TO_CHECK = 200 -- Maximum segments to check per snake
local LONG_SNAKE_THRESHOLD = 500 -- Snake is considered "long" above this
local ULTRA_LONG_THRESHOLD = 1000 -- Special handling for massive snakes

-- === DISTANCE-BASED LOD SYSTEM ===
local LOD_DISTANCES = {
	CLOSE = 50,    -- Check every segment
	MEDIUM = 150,  -- Check every 2nd segment
	FAR = 300,     -- Check every 5th segment
	EXTREME = 500  -- Check every 10th segment
}

-- === OPTIMIZED COLLISION SETTINGS ===
local BODY_COLLISION_DISTANCE = 3.0
local HEAD_COLLISION_DISTANCE = 3.5
local MIN_COLLISION_DISTANCE = 2.0
local COLLISION_BUFFER = 0.2
local SPAWN_PROTECTION_TIME = 3
local MIN_AI_SPAWN_DISTANCE = 50

-- === ORB SPAWNING ===
local ORB_SPAWN_HEIGHT = 3
local GUARANTEED_ORB_COUNT = 5
local MAX_ORBS_PER_DEATH = 30

-- === HEAD-TO-HEAD SETTINGS ===
local HEAD_TO_HEAD_ANGLE_THRESHOLD = 0.5
local HEAD_TO_HEAD_SPEED_THRESHOLD = 5

-- === WALL COLLISION SETTINGS ===
local WALL_ORB_DROP_AMOUNT = 3
local WALL_ORB_DROP_COOLDOWN = 8.0
local WALL_DAMAGE_MULTIPLIER = 0.95
local WALL_PUSH_TIME = 6.0
local WALL_PUSH_FORCE = 80
local WALL_WARNING_TIME = 4.0
local WALL_PUSH_IMMUNITY_TIME = 30.0
local WALL_CHECK_INTERVAL = 1.0

-- === TRACKING TABLES ===
local deadPlayers = {}
local deadAISnakes = {}
local invinciblePlayers = {}
local spawnProtectedAI = {}
local wallCollisionCooldowns = {}
local wallContactTime = {}
local wallPushImmunity = {}
local wallLastCheck = {}
local recentCollisions = {}
local deathQueue = {}
local isProcessingDeaths = false

-- === PERFORMANCE TRACKING ===
local performanceStats = {
	lastFrameTime = 0,
	avgFrameTime = 0,
	collisionChecks = 0,
	segmentsProcessed = 0
}

-- === OPTIMIZED COLLISION CACHE ===
local CollisionCache = {
	playerData = {}, -- Stores optimized collision data per player
	aiData = {},     -- Stores optimized collision data per AI
	lastUpdate = 0,
	updateInterval = 0.1 -- Update cache every 100ms
}

-- === SEGMENT OPTIMIZATION SYSTEM ===
local function optimizeSegments(segments, snakeLength, distanceToHead)
	if not segments or #segments == 0 then return {} end
	
	local optimized = {}
	local skipFactor = 1
	
	-- Determine skip factor based on snake length and distance
	if snakeLength > ULTRA_LONG_THRESHOLD then
		-- Ultra long snakes: aggressive optimization
		if distanceToHead > LOD_DISTANCES.EXTREME then
			skipFactor = 20 -- Check every 20th segment for far checks
		elseif distanceToHead > LOD_DISTANCES.FAR then
			skipFactor = 10
		elseif distanceToHead > LOD_DISTANCES.MEDIUM then
			skipFactor = 5
		else
			skipFactor = 3
		end
	elseif snakeLength > LONG_SNAKE_THRESHOLD then
		-- Long snakes: moderate optimization
		if distanceToHead > LOD_DISTANCES.FAR then
			skipFactor = 10
		elseif distanceToHead > LOD_DISTANCES.MEDIUM then
			skipFactor = 3
		else
			skipFactor = 2
		end
	else
		-- Normal snakes: minimal optimization
		if distanceToHead > LOD_DISTANCES.MEDIUM then
			skipFactor = 2
		end
	end
	
	-- Always include first few segments (head area)
	for i = 1, math.min(10, #segments) do
		if segments[i] and segments[i].Parent then
			table.insert(optimized, segments[i])
		end
	end
	
	-- Sample remaining segments based on skip factor
	local startIdx = 11
	local endIdx = math.min(#segments, MAX_SEGMENTS_TO_CHECK)
	
	for i = startIdx, endIdx, skipFactor do
		if segments[i] and segments[i].Parent then
			table.insert(optimized, segments[i])
		end
	end
	
	-- Always include tail segments for accuracy
	local tailStart = math.max(endIdx + 1, #segments - 5)
	for i = tailStart, #segments do
		if segments[i] and segments[i].Parent then
			table.insert(optimized, segments[i])
		end
	end
	
	return optimized
end

-- === BATCH COLLISION CHECKING ===
local function checkCollisionBatch(headPos, segments, collisionDist, startIdx, endIdx)
	local effectiveDist = collisionDist + COLLISION_BUFFER
	local effectiveDistSq = effectiveDist * effectiveDist -- Use squared distance for performance
	
	for i = startIdx, math.min(endIdx, #segments) do
		local segment = segments[i]
		if segment and segment.Parent then
			local segPos = segment.Position
			if segPos then
				-- Use squared distance to avoid expensive sqrt
				local distSq = (headPos.X - segPos.X)^2 + (headPos.Y - segPos.Y)^2 + (headPos.Z - segPos.Z)^2
				if distSq < effectiveDistSq then
					-- Only do exact distance check if within squared threshold
					local dist = math.sqrt(distSq)
					if dist < effectiveDist then
						return true
					end
				end
			end
		end
	end
	return false
end

-- === ULTRA-FAST SEGMENT RETRIEVAL ===
local function getOptimizedPlayerSegments(player, checkingHeadPos)
	local currentTime = tick()
	local cache = CollisionCache.playerData[player]
	
	-- Use cached data if fresh
	if cache and (currentTime - cache.lastUpdate) < CollisionCache.updateInterval then
		return cache
	end
	
	-- Try new snake system first
	local snakeModel = Workspace:FindFirstChild("Snake_" .. player.Name)
	local segments = {}
	local snakeLength = 10
	
	if snakeModel then
		-- Get length from leaderstats
		if player:FindFirstChild("leaderstats") then
			local lengthValue = player.leaderstats:FindFirstChild("Length")
			if lengthValue then
				snakeLength = lengthValue.Value or snakeLength
			end
		end
		
		-- Determine segment check interval based on length
		local checkInterval = 1
		if snakeLength > ULTRA_LONG_THRESHOLD then
			checkInterval = 4 -- Check every 4th segment for ultra long snakes
		elseif snakeLength > LONG_SNAKE_THRESHOLD then
			checkInterval = 2 -- Check every other segment for long snakes
		end
		
		-- Collect segments efficiently
		local maxSegments = math.min(500, snakeLength) -- Cap at 500 segments
		for i = 1, maxSegments, checkInterval do
			local seg = snakeModel:FindFirstChild("Segment" .. i)
			if seg and seg:IsA("BasePart") and seg.Parent then
				table.insert(segments, seg)
			else
				-- No more segments found
				break
			end
		end
	else
		-- Fallback to old system
		local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
		if snakeInstance and snakeInstance.segments then
			-- Use actual segments, no interpolation for performance
			for i, seg in ipairs(snakeInstance.segments) do
				if seg and seg.Parent then
					table.insert(segments, seg)
				end
			end
			snakeLength = #segments
		end
	end
	
	-- Optimize segments based on checking position
	local optimizedSegments = segments
	if checkingHeadPos and #segments > 50 then
		local distance = checkingHeadPos and segments[1] and 
			(checkingHeadPos - segments[1].Position).Magnitude or 0
		optimizedSegments = optimizeSegments(segments, snakeLength, distance)
	end
	
	-- Calculate bounds for broad phase
	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}
	
	for _, seg in ipairs(optimizedSegments) do
		local pos = seg.Position
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
	
	-- Store in cache
	local cacheData = {
		segments = optimizedSegments,
		fullSegments = segments, -- Keep full segments for orb spawning
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}
	
	CollisionCache.playerData[player] = cacheData
	return cacheData
end

local function getOptimizedAISegments(snake, checkingHeadPos)
	if not snake or not snake.Segments then return nil end
	
	local currentTime = tick()
	local cache = CollisionCache.aiData[snake]
	
	-- Use cached data if fresh
	if cache and (currentTime - cache.lastUpdate) < CollisionCache.updateInterval then
		return cache
	end
	
	local segments = {}
	for _, seg in ipairs(snake.Segments) do
		if seg and seg.Parent then
			table.insert(segments, seg)
		end
	end
	
	local snakeLength = #segments
	if snakeLength == 0 then return nil end
	
	-- Optimize segments for collision checking
	local optimizedSegments = segments
	if checkingHeadPos and snakeLength > 50 then
		local distance = checkingHeadPos and segments[1] and 
			(checkingHeadPos - segments[1].Position).Magnitude or 0
		optimizedSegments = optimizeSegments(segments, snakeLength, distance)
	end
	
	-- Calculate bounds
	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}
	
	for _, seg in ipairs(optimizedSegments) do
		local pos = seg.Position
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
	
	local cacheData = {
		segments = optimizedSegments,
		fullSegments = segments,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}
	
	CollisionCache.aiData[snake] = cacheData
	return cacheData
end

-- === FAST COLLISION CHECK ===
local function checkOptimizedCollision(headPos, segmentData, collisionDist)
	if not segmentData or not segmentData.segments then return false end
	
	-- Broad phase: check bounds first
	local bounds = segmentData.bounds
	if bounds then
		local expandedDist = collisionDist + 10
		if headPos.X < bounds.min.X - expandedDist or headPos.X > bounds.max.X + expandedDist or
		   headPos.Z < bounds.min.Z - expandedDist or headPos.Z > bounds.max.Z + expandedDist then
			return false
		end
	end
	
	-- Process segments in batches for better performance
	local segments = segmentData.segments
	local batchSize = SEGMENT_BATCH_SIZE
	
	for i = 1, #segments, batchSize do
		if checkCollisionBatch(headPos, segments, collisionDist, i, i + batchSize - 1) then
			return true
		end
		
		-- Yield occasionally for ultra-long snakes
		if segmentData.length > ULTRA_LONG_THRESHOLD and i % 200 == 0 then
			task.wait()
		end
	end
	
	return false
end

-- === INVINCIBILITY SYSTEM (kept from original) ===
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

local function setAISpawnProtection(aiHead)
	spawnProtectedAI[aiHead] = os.clock() + SPAWN_PROTECTION_TIME
end

local function isAIProtected(aiHead)
	if not aiHead then return false end
	local protectionEnd = spawnProtectedAI[aiHead]
	if protectionEnd then
		if os.clock() < protectionEnd then
			return true
		else
			spawnProtectedAI[aiHead] = nil
		end
	end
	return false
end

-- === WALL COLLISION FUNCTIONS (kept from original) ===
local function checkWallCollision(position, snakeLength, isHead)
	if not isHead then return false end
	
	local mapHalf = 400
	local wallThreshold = mapHalf - 10
	
	if math.abs(position.X) > wallThreshold or math.abs(position.Z) > wallThreshold then
		local distToWallX = mapHalf - math.abs(position.X)
		local distToWallZ = mapHalf - math.abs(position.Z)
		
		if distToWallX < 10 or distToWallZ < 10 then
			return true
		end
	end
	return false
end

local function handleWallCollision(entity, isPlayer)
	if not entity then return end
	
	local key = isPlayer and entity or (entity.Name or tostring(entity))
	if not key then return end
	
	local currentTime = tick()
	
	if wallCollisionCooldowns[key] and currentTime - wallCollisionCooldowns[key] < WALL_ORB_DROP_COOLDOWN then
		return
	end
	
	wallCollisionCooldowns[key] = currentTime
	
	local snakeData
	if isPlayer then
		snakeData = _G.PlayerSnakes and _G.PlayerSnakes[entity]
	else
		snakeData = entity
	end
	
	if not snakeData or not snakeData.segments then return end
	
	local currentLength = #snakeData.segments
	if currentLength <= 10 then return end
	
	local headPos = snakeData.segments[1] and snakeData.segments[1].Position
	if headPos then
		local mapBoundary = 395
		
		local orbValue = 1
		if currentLength > 50 then orbValue = 2 end
		if currentLength > 100 then orbValue = 3 end
		if currentLength > 200 then orbValue = 5 end
		if currentLength > 500 then orbValue = 10 end
		if currentLength > 1000 then orbValue = 15 end
		
		for i = 1, WALL_ORB_DROP_AMOUNT do
			local randomOffset = Vector3.new(
				math.random(-10, 10),
				0,
				math.random(-10, 10)
			)
			
			local orbPos = headPos + randomOffset
			orbPos = Vector3.new(
				math.clamp(orbPos.X, -mapBoundary, mapBoundary),
				5,
				math.clamp(orbPos.Z, -mapBoundary, mapBoundary)
			)
			
			local orb = OrbUtils.spawnOrbAt(orbPos, orbValue)
			if orb and isPlayer then
				orb:SetAttribute("SpawnedByUserId", entity.UserId)
				orb:SetAttribute("SpawnTime", tick())
			end
		end
		
		if isPlayer and snakeData.shrink and currentLength > 10 then
			local baseLoss = WALL_ORB_DROP_AMOUNT * 3
			if currentLength > 100 then baseLoss = 15 end
			if currentLength > 300 then baseLoss = 25 end
			if currentLength > 500 then baseLoss = 40 end
			if currentLength > 1000 then baseLoss = 60 end
			
			local segmentsToRemove = math.min(baseLoss, currentLength - 10)
			if segmentsToRemove > 0 then
				snakeData.shrink(segmentsToRemove)
			end
		end
	end
end

-- === OPTIMIZED DEATH HANDLERS ===
local function spawnOrbDirect(position, value)
	local success, err = pcall(function()
		if not position or position ~= position then
			position = Vector3.new(0, ORB_SPAWN_HEIGHT, 0)
		end
		value = math.clamp(value or 1, 1, 50)
		OrbUtils.spawnOrbAt(position, value)
	end)
	return success
end

local function queuePlayerDeath(player)
	if not player or not player.Parent then return end
	
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root.Position.Y < -5 then return end
	
	if deadPlayers[player] then return end
	if isPlayerInvincible(player) then return end
	
	for _, death in ipairs(deathQueue) do
		if death.type == "player" and death.target == player then return end
	end
	
	deadPlayers[player] = tick()
	
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
		deathNotifyEvent:FireClient(player, "died")
	end
	
	table.insert(deathQueue, {
		type = "player",
		target = player,
		timestamp = tick()
	})
end

local function queueAIDeath(head)
	if not head or not head.Parent or head.Name ~= "AISnakeHead" then return end
	if deadAISnakes[head] then return end
	
	local aiSnake = nil
	for _, snake in AISnakeModule._activeSnakes do
		if snake and snake._active and snake.HeadParts and snake.HeadParts.head == head then
			aiSnake = snake
			break
		end
	end
	
	if not aiSnake then return end
	if isAIProtected(head) then return end
	
	for _, death in ipairs(deathQueue) do
		if death.type == "ai" and death.target == head then return end
	end
	
	deadAISnakes[head] = tick()
	
	table.insert(deathQueue, {
		type = "ai",
		target = head,
		timestamp = tick()
	})
end

-- === FAST HEAD RETRIEVAL ===
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
				local head = snake.HeadParts.head
				heads[#heads + 1] = head
				
				if not spawnProtectedAI[head] and not deadAISnakes[head] then
					if not snake.Segments or #snake.Segments < 50 then
						setAISpawnProtection(head)
					end
				end
			end
		end
	end
	headCache.ai = heads
	return heads
end

-- === OPTIMIZED COLLISION DETECTION ===
local function isRecentCollision(entityA, entityB)
	local key = tostring(entityA) .. "-" .. tostring(entityB)
	local reverseKey = tostring(entityB) .. "-" .. tostring(entityA)
	
	local currentTime = tick()
	
	if recentCollisions[key] and currentTime - recentCollisions[key] < 1.0 then
		return true
	end
	if recentCollisions[reverseKey] and currentTime - recentCollisions[reverseKey] < 1.0 then
		return true
	end
	
	recentCollisions[key] = currentTime
	recentCollisions[reverseKey] = currentTime
	
	for k, time in pairs(recentCollisions) do
		if currentTime - time > 2 then
			recentCollisions[k] = nil
		end
	end
	
	return false
end

local function determineHeadToHeadWinner(headA, headB, velA, velB, lengthA, lengthB)
	if not velA or velA.Magnitude < 0.1 then
		velA = headA.AssemblyLinearVelocity
	end
	if not velB or velB.Magnitude < 0.1 then
		velB = headB.AssemblyLinearVelocity
	end
	
	local dirAB = (headB.Position - headA.Position)
	if dirAB.Magnitude < 0.1 then
		return math.random() > 0.5 and "A" or "B"
	end
	dirAB = dirAB.Unit
	local dirBA = -dirAB
	
	local dotA = velA.Magnitude > 0.1 and velA.Unit:Dot(dirAB) or 0
	local dotB = velB.Magnitude > 0.1 and velB.Unit:Dot(dirBA) or 0
	
	local speedA = velA.Magnitude
	local speedB = velB.Magnitude
	
	if dotA > HEAD_TO_HEAD_ANGLE_THRESHOLD and dotB > HEAD_TO_HEAD_ANGLE_THRESHOLD then
		lengthA = lengthA or 100
		lengthB = lengthB or 100
		
		if math.abs(lengthA - lengthB) > 20 then
			return lengthA > lengthB and "B" or "A"
		else
			local aggressionA = speedA * dotA
			local aggressionB = speedB * dotB
			
			if math.abs(aggressionA - aggressionB) < 0.5 then
				aggressionA = aggressionA + math.random() * 0.2
				aggressionB = aggressionB + math.random() * 0.2
			end
			
			return aggressionA > aggressionB and "B" or "A"
		end
	else
		if math.abs(dotA - dotB) < 0.1 then
			return speedA > speedB and "B" or "A"
		else
			return dotA > dotB and "B" or "A"
		end
	end
end

-- === DEATH PROCESSING (kept from original but optimized) ===
task.spawn(function()
	while true do
		task.wait(0.033)
		
		if #deathQueue > 0 and not isProcessingDeaths then
			isProcessingDeaths = true
			local death = table.remove(deathQueue, 1)
			
			if death.type == "player" then
				local player = death.target
				
				if not player.Parent then
					isProcessingDeaths = false
					continue
				end
				
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChild("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local snakeData = getOptimizedPlayerSegments(player)
						if snakeData and snakeData.fullSegments then
							local segments = snakeData.fullSegments
							local totalLength = #segments
							
							local orbsPerSegment = 1 / 2.5
							local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, MAX_ORBS_PER_DEATH)
							
							local baseValue = 1
							if totalLength <= 100 then
								local totalValue = math.floor(totalLength * 0.30)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 200 then
								local totalValue = math.floor(totalLength * 0.25)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							elseif totalLength <= 500 then
								local totalValue = math.floor(totalLength * 0.20)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							else
								local totalValue = math.min(math.floor(totalLength * 0.15), 150)
								baseValue = math.max(1, math.floor(totalValue / totalOrbs))
							end
							
							local valuePerOrb = baseValue
							
							local spawnedOrbs = 0
							for i = 1, totalLength do
								if math.random() < orbsPerSegment then
									local seg = segments[i]
									if seg and seg.Parent and seg.Position then
										local pos = seg.Position
										
										local offset = Vector3.new(
											(math.random() - 0.5) * 2,
											0,
											(math.random() - 0.5) * 2
										)
										
										local spawnPos = Vector3.new(
											pos.X + offset.X,
											ORB_SPAWN_HEIGHT,
											pos.Z + offset.Z
										)
										
										local success = pcall(function()
											spawnOrbDirect(spawnPos, valuePerOrb)
											spawnedOrbs = spawnedOrbs + 1
										end)
									end
								end
							end
							
							if spawnedOrbs < GUARANTEED_ORB_COUNT then
								local deathPos = humanoid.RootPart and humanoid.RootPart.Position or (segments[1] and segments[1].Position)
								if deathPos then
									for i = spawnedOrbs + 1, GUARANTEED_ORB_COUNT do
										local angle = (i / GUARANTEED_ORB_COUNT) * math.pi * 2
										local radius = 5 + (i * 2)
										local spawnPos = Vector3.new(
											deathPos.X + math.cos(angle) * radius,
											ORB_SPAWN_HEIGHT,
											deathPos.Z + math.sin(angle) * radius
										)
										
										local success = spawnOrbDirect(spawnPos, valuePerOrb)
										if success then
											spawnedOrbs = spawnedOrbs + 1
										end
									end
								end
							end
						end
						
						-- Handle character cleanup
						task.spawn(function()
							task.wait(0.1)
							
							if character and character.Parent then
								local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
								if root then
									root.CFrame = CFrame.new(0, -500, 0)
								end
								
								for _, part in ipairs(character:GetDescendants()) do
									if part:IsA("BasePart") or part:IsA("Decal") then
										part.Transparency = 1
									end
									if part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
										part.Enabled = false
									end
								end
								
								character.Parent = game:GetService("ServerStorage")
							end
						end)
						
						-- Clear dead flag after respawn time
						task.spawn(function()
							task.wait(5)
							deadPlayers[player] = nil
						end)
						
						-- Clean up snake segments
						task.spawn(function()
							local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
							if snakeInstance and snakeInstance.segments then
								for _, segment in ipairs(snakeInstance.segments) do
									if segment and segment.Parent then
										segment:Destroy()
									end
								end
							end
							
							if character then
								for _, child in ipairs(character:GetDescendants()) do
									if child:IsA("BasePart") and (child.Name:match("Segment") or child.Name:match("segment")) then
										child:Destroy()
									end
								end
							end
							
							local segmentFolder = character and character:FindFirstChild("Segments")
							if segmentFolder then
								segmentFolder:Destroy()
							end
							
							local segmentContainer = workspace:FindFirstChild("SegmentContainer")
							if segmentContainer then
								for _, child in ipairs(segmentContainer:GetChildren()) do
									if child.Name:find(player.Name) or (child:GetAttribute("Owner") == player.Name) then
										child:Destroy()
									end
								end
							end
							
							if _G.PlayerSnakes then
								_G.PlayerSnakes[player] = nil
							end
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
								
								local orbsPerSegment = 1 / 2.5
								local totalOrbs = math.clamp(math.floor(totalLength * orbsPerSegment), 3, MAX_ORBS_PER_DEATH)
								
								local baseValue = 1
								if totalLength <= 100 then
									local totalValue = math.floor(totalLength * 0.30)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								elseif totalLength <= 200 then
									local totalValue = math.floor(totalLength * 0.25)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								elseif totalLength <= 500 then
									local totalValue = math.floor(totalLength * 0.20)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								else
									local totalValue = math.min(math.floor(totalLength * 0.15), 150)
									baseValue = math.max(1, math.floor(totalValue / totalOrbs))
								end
								
								local valuePerOrb = baseValue
								
								local spawnedOrbs = 0
								for i = 1, totalLength do
									if math.random() < orbsPerSegment then
										local seg = segments[i]
										if seg and seg.Parent and seg.Position then
											local pos = seg.Position
											
											local offset = Vector3.new(
												(math.random() - 0.5) * 2,
												0,
												(math.random() - 0.5) * 2
											)
											
											local spawnPos = Vector3.new(
												pos.X + offset.X,
												ORB_SPAWN_HEIGHT,
												pos.Z + offset.Z
											)
											
											local success = pcall(function()
												spawnOrbDirect(spawnPos, valuePerOrb)
												spawnedOrbs = spawnedOrbs + 1
											end)
										end
									end
								end
								
								if spawnedOrbs < GUARANTEED_ORB_COUNT then
									local deathPos = head.Position
									if deathPos then
										for i = spawnedOrbs + 1, GUARANTEED_ORB_COUNT do
											local angle = (i / GUARANTEED_ORB_COUNT) * math.pi * 2
											local radius = 5 + (i * 2)
											local spawnPos = Vector3.new(
												deathPos.X + math.cos(angle) * radius,
												ORB_SPAWN_HEIGHT,
												deathPos.Z + math.sin(angle) * radius
											)
											
											local success = spawnOrbDirect(spawnPos, valuePerOrb)
											if success then
												spawnedOrbs = spawnedOrbs + 1
											end
										end
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

-- === MAIN COLLISION LOOP (ULTRA-OPTIMIZED) ===
local lastCollisionTime = 0
local collisionRunning = false

RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	
	-- Throttle collision checks
	if currentTime - lastCollisionTime < COLLISION_CHECK_INTERVAL then
		return
	end
	
	-- Prevent multiple collision checks running at once
	if collisionRunning then
		return
	end
	
	collisionRunning = true
	lastCollisionTime = currentTime
	
	-- Performance monitoring
	local frameStart = tick()
	performanceStats.collisionChecks = 0
	performanceStats.segmentsProcessed = 0
	
	local playerHeads = getPlayerHeads()
	local aiHeads = getAISnakeHeads()
	
	if #playerHeads == 0 and #aiHeads == 0 then
		collisionRunning = false
		return
	end
	
	-- Player wall collisions and deaths from AI/other players
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part
		
		if isPlayerInvincible(player) then
			continue
		end
		
		if head and head.Parent then
			local headPos = head.Position
			
			if headPos.Y < -5 or headPos.Y > 50 then
				continue
			end
			
			-- Wall collision check (throttled)
			local lastCheck = wallLastCheck[player] or 0
			if currentTime - lastCheck >= WALL_CHECK_INTERVAL then
				wallLastCheck[player] = currentTime
				
				local playerSnakeData = getOptimizedPlayerSegments(player, headPos)
				local playerSnakeLength = playerSnakeData and playerSnakeData.length or 10
				
				local hasImmunity = wallPushImmunity[player] and currentTime - wallPushImmunity[player] < WALL_PUSH_IMMUNITY_TIME
				if checkWallCollision(headPos, playerSnakeLength, true) and not player:GetAttribute("BeingPushedFromWall") and not hasImmunity then
					handleWallCollision(player, true)
					
					-- Handle wall push logic (simplified from original)
					local key = player
					if not wallContactTime[key] then
						wallContactTime[key] = tick()
					end
					
					local contactDuration = tick() - wallContactTime[key]
					
					if contactDuration > WALL_PUSH_TIME then
						-- Push player away from wall
						local character = player.Character
						if character and character:FindFirstChild("HumanoidRootPart") then
							local root = character.HumanoidRootPart
							
							if checkWallCollision(root.Position, playerSnakeLength, true) then
								local velocity = root.AssemblyLinearVelocity or Vector3.zero
								if velocity.Magnitude <= 10 then
									local pushDirection = -root.CFrame.LookVector
									
									local pos = root.Position
									if math.abs(pos.X) > 390 then
										pushDirection = Vector3.new(-math.sign(pos.X) * WALL_PUSH_FORCE, 0, 0)
									elseif math.abs(pos.Z) > 390 then
										pushDirection = Vector3.new(0, 0, -math.sign(pos.Z) * WALL_PUSH_FORCE)
									end
									
									local bodyVelocity = Instance.new("BodyVelocity")
									bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
									bodyVelocity.Velocity = pushDirection * 0.6
									bodyVelocity.Parent = root
									
									local bodyPosition = Instance.new("BodyPosition")
									bodyPosition.MaxForce = Vector3.new(50000, 0, 50000)
									bodyPosition.Position = root.Position + pushDirection.Unit * 7
									bodyPosition.D = 3500
									bodyPosition.P = 20000
									bodyPosition.Parent = root
									
									game:GetService("Debris"):AddItem(bodyVelocity, 0.5)
									game:GetService("Debris"):AddItem(bodyPosition, 0.7)
									
									wallContactTime[key] = nil
									wallPushImmunity[player] = tick()
									
									player:SetAttribute("BeingPushedFromWall", true)
									task.spawn(function()
										task.wait(1.5)
										player:SetAttribute("BeingPushedFromWall", false)
									end)
								end
							end
						end
					end
				else
					if wallContactTime[player] then
						wallContactTime[player] = nil
					end
				end
			end
			
			-- Check collision with AI snakes
			if AISnakeModule._activeSnakes then
				for _, snake in AISnakeModule._activeSnakes do
					if snake and snake._active then
						if snake.HeadParts and snake.HeadParts.head and deadAISnakes[snake.HeadParts.head] then
							continue
						end
						
						local segmentData = getOptimizedAISegments(snake, headPos)
						if segmentData then
							performanceStats.segmentsProcessed = performanceStats.segmentsProcessed + #segmentData.segments
							
							if checkOptimizedCollision(headPos, segmentData, BODY_COLLISION_DISTANCE) then
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
			
			if headPosA.Y < -5 or headPosA.Y > 50 then
				continue
			end
			
			for j = 1, #playerHeads do
				if i ~= j then
					local headDataB = playerHeads[j]
					local playerB = headDataB.player
					
					local segmentData = getOptimizedPlayerSegments(playerB, headPosA)
					if segmentData then
						performanceStats.segmentsProcessed = performanceStats.segmentsProcessed + #segmentData.segments
						
						if checkOptimizedCollision(headPosA, segmentData, BODY_COLLISION_DISTANCE) then
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
			if isAIProtected(aiHead) then
				continue
			end
			
			local aiPos = aiHead.Position
			
			if aiPos.Y < -10 or aiPos.Y > 100 then
				continue
			end
			
			for _, headData in ipairs(playerHeads) do
				local player = headData.player
				
				if deadPlayers[player] then
					continue
				end
				
				if not isPlayerInvincible(player) then
					local segmentData = getOptimizedPlayerSegments(player, aiPos)
					if segmentData then
						performanceStats.segmentsProcessed = performanceStats.segmentsProcessed + #segmentData.segments
						
						if checkOptimizedCollision(aiPos, segmentData, BODY_COLLISION_DISTANCE) then
							queueAIDeath(aiHead)
							break
						end
					end
				end
			end
		end
	end
	
	-- Player head vs AI body collisions (Player kills AI)
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part
		
		if deadPlayers[player] then
			continue
		end
		
		if head and head.Parent then
			local headPos = head.Position
			
			if AISnakeModule._activeSnakes then
				for _, aiSnake in AISnakeModule._activeSnakes do
					if aiSnake and aiSnake._active and aiSnake.HeadParts and aiSnake.HeadParts.head then
						if isAIProtected(aiSnake.HeadParts.head) or deadAISnakes[aiSnake.HeadParts.head] then
							continue
						end
						
						local aiHeadPos = aiSnake.HeadParts.head.Position
						local distToHead = (headPos - aiHeadPos).Magnitude
						if distToHead < HEAD_COLLISION_DISTANCE * 1.5 then
							continue
						end
						
						local aiSegmentData = getOptimizedAISegments(aiSnake, headPos)
						if aiSegmentData then
							performanceStats.segmentsProcessed = performanceStats.segmentsProcessed + #aiSegmentData.segments
							
							if checkOptimizedCollision(headPos, aiSegmentData, BODY_COLLISION_DISTANCE) then
								local hitHead = false
								if aiSnake.HeadParts and aiSnake.HeadParts.head then
									local headDist = (headPos - aiSnake.HeadParts.head.Position).Magnitude
									if headDist < HEAD_COLLISION_DISTANCE then
										hitHead = true
									end
								end
								
								if not hitHead then
									queueAIDeath(aiSnake.HeadParts.head)
									
									if aiSnake.setConfidenceBuff then
										aiSnake:setConfidenceBuff()
									end
									break
								end
							end
						end
					end
				end
			end
		end
	end
	
	-- Head-to-head collisions (simplified)
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
			
			if isRecentCollision(playerA, playerB) then
				continue
			end
			
			local dist = (headA.Position - headB.Position).Magnitude
			
			if dist < HEAD_COLLISION_DISTANCE then
				performanceStats.collisionChecks = performanceStats.collisionChecks + 1
				
				local velA = headA.AssemblyLinearVelocity or headA.Velocity or Vector3.zero
				local velB = headB.AssemblyLinearVelocity or headB.Velocity or Vector3.zero
				
				if velA.Magnitude < HEAD_TO_HEAD_SPEED_THRESHOLD and velB.Magnitude < HEAD_TO_HEAD_SPEED_THRESHOLD then
					continue
				end
				
				local playerADies = false
				local playerBDies = false
				
				local segDataB = getOptimizedPlayerSegments(playerB, headA.Position)
				if segDataB and segDataB.segments and #segDataB.segments > 3 then
					for idx = 4, #segDataB.segments do
						local seg = segDataB.segments[idx]
						if seg and seg.Parent then
							local segPos = seg.Position
							if (headA.Position - segPos).Magnitude < BODY_COLLISION_DISTANCE then
								playerADies = true
								break
							end
						end
					end
				end
				
				local segDataA = getOptimizedPlayerSegments(playerA, headB.Position)
				if segDataA and segDataA.segments and #segDataA.segments > 3 then
					for idx = 4, #segDataA.segments do
						local seg = segDataA.segments[idx]
						if seg and seg.Parent then
							local segPos = seg.Position
							if (headB.Position - segPos).Magnitude < BODY_COLLISION_DISTANCE then
								playerBDies = true
								break
							end
						end
					end
				end
				
				if playerADies and playerBDies then
					local charA = playerA.Character
					local charB = playerB.Character
					local lengthValueA = charA and charA:FindFirstChild("Length")
					local lengthValueB = charB and charB:FindFirstChild("Length")
					local lengthA = lengthValueA and lengthValueA.Value or 100
					local lengthB = lengthValueB and lengthValueB.Value or 100
					
					local winner = determineHeadToHeadWinner(headA, headB, velA, velB, lengthA, lengthB)
					if winner == "A" then
						queuePlayerDeath(playerB)
					else
						queuePlayerDeath(playerA)
					end
				elseif playerADies then
					queuePlayerDeath(playerA)
				elseif playerBDies then
					queuePlayerDeath(playerB)
				else
					local charA = playerA.Character
					local charB = playerB.Character
					local lengthValueA = charA and charA:FindFirstChild("Length")
					local lengthValueB = charB and charB:FindFirstChild("Length")
					local lengthA = lengthValueA and lengthValueA.Value or 100
					local lengthB = lengthValueB and lengthValueB.Value or 100
					
					local loser = determineHeadToHeadWinner(headA, headB, velA, velB, lengthA, lengthB)
					if loser == "A" then
						queuePlayerDeath(playerA)
					else
						queuePlayerDeath(playerB)
					end
				end
				break
			end
		end
	end
	
	-- Player vs AI head-to-head (simplified)
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
				if dist < HEAD_COLLISION_DISTANCE then
					performanceStats.collisionChecks = performanceStats.collisionChecks + 1
					
					local playerDies = false
					local aiDies = false
					
					local aiSnake = nil
					if AISnakeModule and AISnakeModule._activeSnakes then
						for _, snake in AISnakeModule._activeSnakes do
							if snake.HeadParts and snake.HeadParts.head == aiHead then
								aiSnake = snake
								break
							end
						end
					end
					
					if aiSnake and aiSnake.Segments then
						for idx = 4, math.min(#aiSnake.Segments, 50) do
							local seg = aiSnake.Segments[idx]
							if seg and seg.Parent then
								if (head.Position - seg.Position).Magnitude < BODY_COLLISION_DISTANCE then
									playerDies = true
									break
								end
							end
						end
					end
					
					local segData = getOptimizedPlayerSegments(player, aiHead.Position)
					if segData and segData.segments and #segData.segments > 3 then
						for idx = 4, math.min(#segData.segments, 50) do
							local seg = segData.segments[idx]
							if seg and seg.Parent then
								if (aiHead.Position - seg.Position).Magnitude < BODY_COLLISION_DISTANCE then
									aiDies = true
									break
								end
							end
						end
					end
					
					if playerDies and aiDies then
						local velPlayer = head.AssemblyLinearVelocity or head.Velocity or Vector3.zero
						local velAI = aiHead.AssemblyLinearVelocity or aiHead.Velocity or Vector3.zero
						
						if velPlayer.Magnitude > velAI.Magnitude then
							queueAIDeath(aiHead)
						else
							queuePlayerDeath(player)
						end
					elseif playerDies then
						queuePlayerDeath(player)
					elseif aiDies then
						queueAIDeath(aiHead)
					else
						local velPlayer = head.AssemblyLinearVelocity or head.Velocity or Vector3.zero
						local velAI = aiHead.AssemblyLinearVelocity or aiHead.Velocity or Vector3.zero
						local dirToAI = (aiHead.Position - head.Position).Unit
						local dirToPlayer = -dirToAI
						
						local dotPlayer = velPlayer:Dot(dirToAI)
						local dotAI = velAI:Dot(dirToPlayer)
						
						local speedPlayer = velPlayer.Magnitude
						local speedAI = velAI.Magnitude
						
						local scorePlayer = dotPlayer * speedPlayer
						local scoreAI = dotAI * speedAI
						
						if scorePlayer > scoreAI then
							queueAIDeath(aiHead)
						else
							queuePlayerDeath(player)
						end
					end
				end
			end
		end
	end
	
	-- AI vs AI collisions (minimal checks for performance)
	for i = 1, #aiHeads - 1 do
		local headA = aiHeads[i]
		if headA and headA.Parent then
			if isAIProtected(headA) then
				continue
			end
			
			for j = i + 1, math.min(#aiHeads, i + 5) do -- Only check nearby AI
				local headB = aiHeads[j]
				if headB and headB.Parent then
					if isAIProtected(headB) then
						continue
					end
					
					local dist = (headA.Position - headB.Position).Magnitude
					if dist < HEAD_COLLISION_DISTANCE then
						performanceStats.collisionChecks = performanceStats.collisionChecks + 1
						
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
	
	-- Performance tracking
	local frameTime = tick() - frameStart
	performanceStats.lastFrameTime = frameTime
	performanceStats.avgFrameTime = performanceStats.avgFrameTime * 0.9 + frameTime * 0.1
	
	collisionRunning = false
end)

-- === CLEANUP SYSTEMS ===
-- Player cleanup
Players.PlayerRemoving:Connect(function(player)
	deadPlayers[player] = nil
	invinciblePlayers[player] = nil
	wallCollisionCooldowns[player] = nil
	wallContactTime[player] = nil
	wallPushImmunity[player] = nil
	wallLastCheck[player] = nil
	
	if CollisionCache.playerData then
		CollisionCache.playerData[player] = nil
	end
	
	if _G.PlayerSnakes and _G.PlayerSnakes[player] then
		local snake = _G.PlayerSnakes[player]
		if snake.segments then
			for _, segment in ipairs(snake.segments) do
				if segment and segment.Parent then
					segment:Destroy()
				end
			end
		end
		_G.PlayerSnakes[player] = nil
	end
	
	for _, container in ipairs(workspace:GetChildren()) do
		if container.Name == "AISegmentContainer" or container.Name == "SegmentContainer" then
			for _, model in ipairs(container:GetChildren()) do
				if model:IsA("Model") then
					local shouldDestroy = false
					
					if model.Name:find(player.Name) or
						model:GetAttribute("PlayerName") == player.Name or
						model:GetAttribute("Owner") == player.Name then
						shouldDestroy = true
					end
					
					if model.Name:match("AISnakeModel_table:") then
						for _, desc in ipairs(model:GetDescendants()) do
							if desc:IsA("ObjectValue") and desc.Value == player then
								shouldDestroy = true
								break
							end
						end
					end
					
					if shouldDestroy then
						model:Destroy()
					end
				end
			end
		end
	end
	
	for key, _ in pairs(recentCollisions) do
		if key:find(tostring(player)) then
			recentCollisions[key] = nil
		end
	end
end)

-- Invincibility setup
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

-- Periodic cleanup
task.spawn(function()
	while true do
		task.wait(10)
		
		for player, _ in pairs(deadPlayers) do
			if not player.Parent then
				deadPlayers[player] = nil
			end
		end
		
		for player, _ in pairs(deadPlayers) do
			if player.Parent and player.Character then
				local humanoid = player.Character:FindFirstChild("Humanoid")
				if humanoid and humanoid.Health > 0 then
					deadPlayers[player] = nil
				end
			end
		end
		
		for head, timestamp in pairs(deadAISnakes) do
			if not head.Parent or (type(timestamp) == "number" and tick() - timestamp > 30) then
				deadAISnakes[head] = nil
			end
		end
		
		local currentTime = tick()
		for player, timestamp in pairs(deadPlayers) do
			if type(timestamp) == "number" and currentTime - timestamp > 30 then
				deadPlayers[player] = nil
			end
		end
	end
end)

-- Cache cleanup
task.spawn(function()
	while true do
		task.wait(30)
		
		local currentTime = tick()
		
		for player, cache in pairs(CollisionCache.playerData) do
			if not player.Parent or currentTime - cache.lastUpdate > 5 then
				CollisionCache.playerData[player] = nil
			end
		end
		
		for snake, cache in pairs(CollisionCache.aiData) do
			if not snake._active or currentTime - cache.lastUpdate > 5 then
				CollisionCache.aiData[snake] = nil
			end
		end
		
		for aiHead, _ in pairs(deadAISnakes) do
			if not aiHead or not aiHead.Parent then
				deadAISnakes[aiHead] = nil
			end
		end
	end
end)

-- Performance monitoring
task.spawn(function()
	while true do
		task.wait(5)
		if performanceStats.avgFrameTime > 0.05 then -- Alert if frame time exceeds 50ms
			warn(string.format("[PERFORMANCE] High collision frame time: %.2fms (checks: %d, segments: %d)", 
				performanceStats.avgFrameTime * 1000,
				performanceStats.collisionChecks,
				performanceStats.segmentsProcessed
			))
		end
	end
end)

print("⚡ SnakeCollisionHandler V9.0 ULTRA-OPTIMIZED - EXTREME PERFORMANCE MODE")
print("🚀 Features: Distance-based LOD, segment batching, smart collision zones")
print("📊 Optimizations: 10Hz collision checks, max 200 segments per snake, adaptive LOD")
print("🎯 Performance: Squared distance checks, batch processing, minimal allocations")
print("🐍 Ultra-long snake support: Special handling for 1000+ segment snakes")

-- Debug command
local debugEnabled = false
local function toggleDebug()
	debugEnabled = not debugEnabled
	print("🔍 Collision debug mode: " .. (debugEnabled and "ENABLED" or "DISABLED"))
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