-- This goes into Workspace and is a script
-- Spawns and manages multiple AI snakes in the Workspace
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local AISnake = require(ReplicatedStorage:WaitForChild("AISnake"))

-- === CONFIGURATION ===
local NUM_SNAKES   = 8          -- reduced from 10+ for better performance
local SPAWN_RADIUS = 350        -- Increased to spread them out more
local SPAWN_HEIGHT = 5
local SPAWN_CENTER = Vector3.new(0, SPAWN_HEIGHT, 0)
local MIN_SPAWN_DISTANCE = 100  -- Minimum distance between spawn points

-- === AI SNAKE MANAGEMENT ===
local aiSnakes = {}
local spawnPositions = {} -- Track spawn positions to avoid clustering

-- Function to get random spawn position that's not too close to others
local function getRandomSpawnPosition()
	local maxAttempts = 50
	local attempt = 0
	
	while attempt < maxAttempts do
		attempt = attempt + 1
		
		local angle = math.random() * 2 * math.pi
		local radius = math.random(150, SPAWN_RADIUS) -- Start further from center
		local x = SPAWN_CENTER.X + radius * math.cos(angle)
		local z = SPAWN_CENTER.Z + radius * math.sin(angle)

		-- Add some random offset
		x = x + math.random(-20, 20)
		z = z + math.random(-20, 20)

		local newPos = Vector3.new(x, SPAWN_HEIGHT, z)
		
		-- Check distance from other spawn positions
		local tooClose = false
		for _, existingPos in ipairs(spawnPositions) do
			if (newPos - existingPos).Magnitude < MIN_SPAWN_DISTANCE then
				tooClose = true
				break
			end
		end
		
		if not tooClose then
			table.insert(spawnPositions, newPos)
			-- Remove old positions to prevent list from growing forever
			if #spawnPositions > NUM_SNAKES * 2 then
				table.remove(spawnPositions, 1)
			end
			return newPos
		end
	end
	
	-- Fallback if we couldn't find a good position
	local angle = math.random() * 2 * math.pi
	local radius = math.random(200, SPAWN_RADIUS)
	return Vector3.new(
		SPAWN_CENTER.X + radius * math.cos(angle),
		SPAWN_HEIGHT,
		SPAWN_CENTER.Z + radius * math.sin(angle)
	)
end

-- Initial spawn with delays to prevent all spawning at once
task.spawn(function()
	for i = 1, NUM_SNAKES do
		local pos = getRandomSpawnPosition()
		aiSnakes[i] = AISnake.new(pos)
		task.wait(0.5) -- Longer delay between spawns
	end
end)

-- Auto-respawn any snake that dies/disappears
local lastRespawnCheck = 0
RunService.Stepped:Connect(function()
	local now = tick()
	
	-- Only check every 2 seconds to reduce lag
	if now - lastRespawnCheck < 2 then
		return
	end
	lastRespawnCheck = now
	
	for i = 1, NUM_SNAKES do
		local snake = aiSnakes[i]
		if not snake or not snake.RootPart or not snake.RootPart.Parent then
			-- Respawn at random position with delay
			task.spawn(function()
				task.wait(math.random() * 2) -- Random delay 0-2 seconds
				local pos = getRandomSpawnPosition()
				aiSnakes[i] = AISnake.new(pos)
			end)
		end
	end
end)