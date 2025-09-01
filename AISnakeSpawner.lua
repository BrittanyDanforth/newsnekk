-- This goes into Workspace and is a script
-- Spawns and manages multiple AI snakes in the Workspace
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local AISnake = require(ReplicatedStorage:WaitForChild("AISnake"))

-- === CONFIGURATION ===
local NUM_SNAKES   = 8          -- reduced from 10+ for better performance
local SPAWN_RADIUS = 300        -- INCREASED to spread them out more
local SPAWN_HEIGHT = 5
local SPAWN_CENTER = Vector3.new(0, SPAWN_HEIGHT, 0)
local MIN_SPAWN_DISTANCE = 100  -- Minimum distance between spawn points

-- === AI SNAKE MANAGEMENT ===
local aiSnakes = {}
local recentSpawnPositions = {}  -- Track recent spawn positions
local spawnDebounce = {}        -- Prevent rapid respawning

-- Function to check if position is too close to recent spawns
local function isTooCloseToRecentSpawns(position)
	for _, recentPos in ipairs(recentSpawnPositions) do
		if (position - recentPos).Magnitude < MIN_SPAWN_DISTANCE then
			return true
		end
	end
	return false
end

-- Function to get random spawn position
local function getRandomSpawnPosition()
	local maxAttempts = 20
	local attempts = 0

	repeat
		attempts = attempts + 1
		local angle = math.random() * 2 * math.pi
		local radius = math.random(150, SPAWN_RADIUS)  -- Increased minimum radius
		local x = SPAWN_CENTER.X + radius * math.cos(angle)
		local z = SPAWN_CENTER.Z + radius * math.sin(angle)

		-- Add some random offset
		x = x + math.random(-30, 30)
		z = z + math.random(-30, 30)

		local position = Vector3.new(x, SPAWN_HEIGHT, z)

		if not isTooCloseToRecentSpawns(position) or attempts >= maxAttempts then
			-- Add to recent positions (keep only last 5)
			table.insert(recentSpawnPositions, position)
			if #recentSpawnPositions > 5 then
				table.remove(recentSpawnPositions, 1)
			end
			return position
		end
	until attempts >= maxAttempts

	-- Fallback position if all attempts fail
	return Vector3.new(
		math.random(-SPAWN_RADIUS, SPAWN_RADIUS),
		SPAWN_HEIGHT,
		math.random(-SPAWN_RADIUS, SPAWN_RADIUS)
	)
end

-- Function to safely spawn a snake
local function spawnSnake(index)
	-- Clean up old snake if it exists
	if aiSnakes[index] then
		-- Call cleanup method if available
		if aiSnakes[index].Cleanup then
			aiSnakes[index]:Cleanup()
		end
		aiSnakes[index] = nil
	end
	
	-- Get spawn position
	local pos = getRandomSpawnPosition()
	
	-- Create new snake with proper initialization
	local success, newSnake = pcall(function()
		return AISnake.new(pos)
	end)
	
	if success and newSnake then
		aiSnakes[index] = newSnake
		
		-- Ensure the snake is properly positioned (no dragging)
		if newSnake.RootPart then
			newSnake.RootPart.CFrame = CFrame.new(pos)
			newSnake.RootPart.Velocity = Vector3.new(0, 0, 0)
			newSnake.RootPart.RotVelocity = Vector3.new(0, 0, 0)
			
			-- Anchor temporarily to prevent physics glitches
			newSnake.RootPart.Anchored = true
			task.wait(0.1)
			newSnake.RootPart.Anchored = false
		end
		
		print("✅ Spawned AI Snake", index, "at", pos)
		return true
	else
		warn("Failed to spawn AI Snake", index, ":", newSnake or "Unknown error")
		return false
	end
end

-- Initial spawn with staggered timing
print("🐍 Spawning AI Snakes...")
for i = 1, NUM_SNAKES do
	spawnSnake(i)
	task.wait(0.5) -- Increased delay to prevent overlap
end
print("✅ All AI Snakes spawned!")

-- Respawn management with proper debouncing
local RESPAWN_COOLDOWN = 3 -- seconds
local lastCheckTime = 0

RunService.Heartbeat:Connect(function()
	local now = tick()
	
	-- Only check every 0.5 seconds to reduce load
	if now - lastCheckTime < 0.5 then
		return
	end
	lastCheckTime = now
	
	for i = 1, NUM_SNAKES do
		local snake = aiSnakes[i]
		
		-- Check if snake needs respawning
		local needsRespawn = false
		
		if not snake then
			needsRespawn = true
		elseif snake.RootPart then
			-- Check if snake still exists and is in workspace
			if not snake.RootPart.Parent then
				needsRespawn = true
			elseif snake.RootPart.Position.Y < -50 then
				-- Snake fell off the map
				needsRespawn = true
			end
		else
			needsRespawn = true
		end
		
		-- Respawn if needed and cooldown has passed
		if needsRespawn then
			if not spawnDebounce[i] or now - spawnDebounce[i] > RESPAWN_COOLDOWN then
				spawnDebounce[i] = now
				
				-- Delay respawn slightly to prevent clustering
				task.spawn(function()
					task.wait(math.random() * 0.5)
					spawnSnake(i)
				end)
			end
		end
	end
end)

-- Cleanup on script removal
script.AncestryChanged:Connect(function()
	if not script.Parent then
		-- Clean up all snakes
		for i = 1, NUM_SNAKES do
			if aiSnakes[i] and aiSnakes[i].Cleanup then
				aiSnakes[i]:Cleanup()
			end
		end
	end
end)