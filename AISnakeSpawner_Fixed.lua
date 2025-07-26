-- AISnakeSpawner Fixed Version
-- Spawns and manages multiple AI snakes in the Workspace with proper spawn delays
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

-- Wait for the fixed AISnake module
local AISnake = require(ReplicatedStorage:WaitForChild("AISnake_Fixed"))

-- === CONFIGURATION ===
local NUM_SNAKES   = 8          -- Number of AI snakes to maintain
local SPAWN_RADIUS = 250        -- Spawn radius
local SPAWN_HEIGHT = 5
local SPAWN_CENTER = Vector3.new(0, SPAWN_HEIGHT, 0)
local RESPAWN_DELAY = 5         -- Wait 5 seconds before respawning (prevents spam)
local INITIAL_SPAWN_DELAY = 0.5 -- Delay between initial spawns

-- === AI SNAKE MANAGEMENT ===
local aiSnakes = {}
local lastRespawnTime = {}      -- Track when each snake was last respawned

-- Function to get random spawn position
local function getRandomSpawnPosition()
	local angle = math.random() * 2 * math.pi
	local radius = math.random(100, SPAWN_RADIUS)
	local x = SPAWN_CENTER.X + radius * math.cos(angle)
	local z = SPAWN_CENTER.Z + radius * math.sin(angle)

	-- Add some random offset
	x = x + math.random(-20, 20)
	z = z + math.random(-20, 20)

	return Vector3.new(x, SPAWN_HEIGHT, z)
end

-- Initial spawn with delays
print("Spawning", NUM_SNAKES, "AI snakes...")
for i = 1, NUM_SNAKES do
	local pos = getRandomSpawnPosition()
	aiSnakes[i] = AISnake.new(pos)
	lastRespawnTime[i] = tick()
	task.wait(INITIAL_SPAWN_DELAY) -- Delay between spawns to prevent lag
end
print("All AI snakes spawned!")

-- Check counter to reduce check frequency
local checkCounter = 0

-- Auto-respawn any snake that dies/disappears
RunService.Stepped:Connect(function()
	checkCounter = checkCounter + 1
	
	-- Only check every 30 frames (about twice per second)
	if checkCounter % 30 ~= 0 then
		return
	end
	
	local currentTime = tick()
	
	for i = 1, NUM_SNAKES do
		local snake = aiSnakes[i]
		local timeSinceLastRespawn = currentTime - (lastRespawnTime[i] or 0)
		
		-- Check if snake needs respawning
		if (not snake or not snake.RootPart or not snake.RootPart.Parent or snake._destroyed) 
		   and timeSinceLastRespawn >= RESPAWN_DELAY then
			
			-- Clean up old snake if it exists
			if snake and not snake._destroyed then
				pcall(function()
					snake:Destroy()
				end)
			end
			
			-- Respawn at random position
			local pos = getRandomSpawnPosition()
			print("Respawning AI snake", i, "at position", pos)
			aiSnakes[i] = AISnake.new(pos)
			lastRespawnTime[i] = currentTime
		end
	end
end)

-- Clean up on script stop
script.AncestryChanged:Connect(function()
	if not script.Parent then
		-- Destroy all AI snakes when script is removed
		for i = 1, NUM_SNAKES do
			if aiSnakes[i] then
				pcall(function()
					aiSnakes[i]:Destroy()
				end)
			end
		end
	end
end)