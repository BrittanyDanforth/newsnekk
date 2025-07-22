-- Collision Performance Patch
-- Fixes lag issues with large snakes by optimizing collision checks

local CollisionPerformancePatch = {}

-- Performance constants
local MAX_SEGMENTS_TO_CHECK = 100  -- Limit collision checks
local COLLISION_SKIP_FRAMES = 3    -- Skip frames for distant snakes
local SEGMENT_CHECK_INTERVAL = 5   -- Check every Nth segment for large snakes
local DISTANCE_CULLING = 500       -- Don't check collisions beyond this distance

-- Frame counters for each snake
local frameCounters = {}

function CollisionPerformancePatch.optimizeCollisionCheck(snake1, snake2, frameCount)
	-- Initialize frame counter
	local key = tostring(snake1) .. "_" .. tostring(snake2)
	frameCounters[key] = frameCounters[key] or 0
	
	-- Get positions
	local pos1 = snake1.Position or (snake1.HeadParts and snake1.HeadParts.head and snake1.HeadParts.head.Position)
	local pos2 = snake2.Position or (snake2.HeadParts and snake2.HeadParts.head and snake2.HeadParts.head.Position)
	
	if not pos1 or not pos2 then return false end
	
	-- Distance culling
	local distance = (pos1 - pos2).Magnitude
	if distance > DISTANCE_CULLING then
		return false -- Too far to collide
	end
	
	-- Frame skipping for distant snakes
	if distance > 100 then
		frameCounters[key] = frameCounters[key] + 1
		if frameCounters[key] % COLLISION_SKIP_FRAMES ~= 0 then
			return false -- Skip this frame
		end
	end
	
	return true -- Proceed with collision check
end

function CollisionPerformancePatch.optimizeSegmentChecks(segments, maxLength)
	if #segments <= MAX_SEGMENTS_TO_CHECK then
		return segments -- Small snake, check all segments
	end
	
	-- For large snakes, sample segments
	local optimizedSegments = {}
	local skipInterval = math.ceil(#segments / MAX_SEGMENTS_TO_CHECK)
	
	-- Always include first 20 segments (near head)
	for i = 1, math.min(20, #segments) do
		table.insert(optimizedSegments, segments[i])
	end
	
	-- Sample the rest
	for i = 21, #segments, skipInterval do
		table.insert(optimizedSegments, segments[i])
	end
	
	return optimizedSegments
end

function CollisionPerformancePatch.shouldCheckCollision(player, otherEntity, frameCount)
	-- Skip collision checks based on various criteria
	
	-- Check if player is boosting (reduced collision accuracy during boost)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.WalkSpeed > 30 then
			-- Boosting - check less frequently
			return frameCount % 2 == 0
		end
	end
	
	return true
end

function CollisionPerformancePatch.optimizeBatchUpdate(entities, batchSize)
	-- Process entities in batches to reduce frame drops
	local batches = {}
	local currentBatch = {}
	
	for i, entity in ipairs(entities) do
		table.insert(currentBatch, entity)
		if #currentBatch >= batchSize then
			table.insert(batches, currentBatch)
			currentBatch = {}
		end
	end
	
	if #currentBatch > 0 then
		table.insert(batches, currentBatch)
	end
	
	return batches
end

-- Cache for collision pairs to avoid duplicate checks
local collisionPairCache = {}
local cacheResetTimer = 0

function CollisionPerformancePatch.resetCollisionCache(deltaTime)
	cacheResetTimer = cacheResetTimer + deltaTime
	if cacheResetTimer > 0.1 then -- Reset every 0.1 seconds
		collisionPairCache = {}
		cacheResetTimer = 0
	end
end

function CollisionPerformancePatch.hasCollisionBeenChecked(entity1, entity2)
	local key1 = tostring(entity1) .. "_" .. tostring(entity2)
	local key2 = tostring(entity2) .. "_" .. tostring(entity1)
	
	if collisionPairCache[key1] or collisionPairCache[key2] then
		return true
	end
	
	collisionPairCache[key1] = true
	return false
end

-- Optimize position history updates
function CollisionPerformancePatch.optimizeHistoryUpdate(snake, frameCount)
	-- Large snakes update history less frequently
	if snake.length > 5000 then
		return frameCount % 3 == 0
	elseif snake.length > 1000 then
		return frameCount % 2 == 0
	end
	return true
end

return CollisionPerformancePatch