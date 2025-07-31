--[[
SNAKE SYSTEM INTEGRATION - COLLISION FIXED + ORB SPAWN FIXED
This script integrates the optimized snake system with proper collision isolation
and fixed death orb spawning along snake segments
Place this in ServerScriptService
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

-- Create collision groups for proper isolation
local COLLISION_GROUPS = {
	PlayerSnake = "PlayerSnake",
	AISnake = "AISnake",
	Default = "Default"
}

-- Setup collision groups
local function setupCollisionGroups()
	-- Create groups if they don't exist
	for _, groupName in pairs(COLLISION_GROUPS) do
		pcall(function()
			PhysicsService:CreateCollisionGroup(groupName)
		end)
	end
	
	-- Set collision rules
	-- Player snakes don't collide with themselves
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUPS.PlayerSnake, COLLISION_GROUPS.PlayerSnake, false)
	-- AI snakes don't collide with themselves
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUPS.AISnake, COLLISION_GROUPS.AISnake, false)
	-- Player and AI snakes don't physically collide (handled by collision system)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUPS.PlayerSnake, COLLISION_GROUPS.AISnake, false)
end

setupCollisionGroups()

-- Load the optimized system FIRST to create networking folder
local OptimizedSnakeSystem

-- Try V4 first, then V3, then V2, then V1
local v4Success, v4Result = pcall(function()
	return require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV4", 2))
end)

if v4Success and v4Result then
	OptimizedSnakeSystem = v4Result
	print("✅ Loaded OptimizedSnakeSystemV4 - PERFORMANCE!")
else
	-- Try V3
	local v3Success, v3Result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV3", 2))
	end)

	if v3Success and v3Result then
		OptimizedSnakeSystem = v3Result
		print("✅ Loaded OptimizedSnakeSystemV3 - SMOOTH!")
	else
		-- Try V2
		local v2Success, v2Result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV2", 2))
		end)

		if v2Success and v2Result then
			OptimizedSnakeSystem = v2Result
			print("✅ Loaded OptimizedSnakeSystemV2")
		else
			-- Fallback to V1
			local v1Success, v1Result = pcall(function()
				return require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystem"))
			end)

			if v1Success and v1Result then
				OptimizedSnakeSystem = v1Result
				print("✅ Loaded OptimizedSnakeSystem V1")
			else
				error("❌ Failed to load any OptimizedSnakeSystem module!")
			end
		end
	end
end

-- Initialize the system (creates networking folder)
OptimizedSnakeSystem.init()

-- Wait a moment for folder creation
wait(0.1)

-- NOW load the network handler
local SnakeNetworkHandler = nil
pcall(function()
	SnakeNetworkHandler = require(ServerScriptService:WaitForChild("SnakeNetworkHandler"))
	if SnakeNetworkHandler and SnakeNetworkHandler.init then
		SnakeNetworkHandler.init()
	end
end)

-- Store active snakes
local activeSnakes = {}

-- Create/Get RemoteEvents for menu integration
local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
remoteEvents.Name = "RemoteEvents"

local spawnSnake = remoteEvents:FindFirstChild("SpawnSnake") or Instance.new("RemoteEvent", remoteEvents)
spawnSnake.Name = "SpawnSnake"

local respawnSnake = remoteEvents:FindFirstChild("RespawnSnake") or Instance.new("RemoteEvent", remoteEvents)
respawnSnake.Name = "RespawnSnake"

-- Default configuration with collision fixes
local DEFAULT_CONFIG = {
	InitialLength = 1000,
	MaxSegments = 50000,
	SegmentSpacing = 3.2,
	SegmentSize = Vector3.new(4, 4, 4),
	HeadSize = Vector3.new(4.5, 4.5, 4.5),
	HeadColor = Color3.fromRGB(76, 217, 100),
	BodyColors = {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	},
	HeadMaterial = Enum.Material.Neon,
	BodyMaterial = Enum.Material.Neon,
	GlowIntensity = 2,
	GlowRange = 6,
	-- Add collision properties
	CanCollide = false,  -- Disable physical collision
	CollisionGroup = COLLISION_GROUPS.PlayerSnake
}

-- Get skin configuration
local function getSkinConfig(player)
	local skinName = player:GetAttribute("SelectedSkin") or "Default"

	-- Try to get skin data from your existing system
	local skinData = nil
	pcall(function()
		local snakeSkins = require(ReplicatedStorage:FindFirstChild("SnakeSkins"))
		if snakeSkins and snakeSkins[skinName] then
			skinData = snakeSkins[skinName]
		end
	end)

	if skinData then
		-- Merge with default config
		local config = {}
		for k, v in pairs(DEFAULT_CONFIG) do
			config[k] = skinData[k] or v
		end
		return config
	end

	return DEFAULT_CONFIG
end

-- Set collision properties for snake parts
local function setSnakePartCollision(part, isHead)
	if not part then return end
	
	-- Disable physical collision (handled by collision system)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	
	-- Set collision group
	PhysicsService:SetPartCollisionGroup(part, COLLISION_GROUPS.PlayerSnake)
	
	-- Add identifier for collision system
	part:SetAttribute("IsSnakePart", true)
	part:SetAttribute("IsSnakeHead", isHead or false)
end

-- FIXED: Spawn death orbs along snake path
local function spawnDeathOrbsAlongSnake(snake, snakeLength)
	if not snake or not snake.segments then 
		warn("No snake segments found for orb spawning")
		return 
	end
	
	local segments = snake.segments
	local totalSegments = #segments
	
	if totalSegments == 0 then
		warn("Snake has no segments for orb spawning")
		return
	end
	
	-- Calculate orb distribution
	local orbsPerSegment = 1 / 2.5 -- One orb every 2.5 segments
	local totalOrbs = math.clamp(math.floor(snakeLength * orbsPerSegment), 3, 40) -- Cap at 40 orbs
	
	-- Dynamic value calculation based on snake length
	local baseValue = 1
	if snakeLength <= 50 then
		local totalValue = math.floor(snakeLength * 0.6)
		baseValue = math.max(1, math.floor(totalValue / totalOrbs))
	elseif snakeLength <= 200 then
		local totalValue = math.floor(snakeLength * 0.45)
		baseValue = math.max(1, math.floor(totalValue / totalOrbs))
	elseif snakeLength <= 500 then
		local totalValue = math.floor(snakeLength * 0.35)
		baseValue = math.max(1, math.floor(totalValue / totalOrbs))
	else
		local totalValue = math.min(math.floor(snakeLength * 0.25), 200)
		baseValue = math.max(1, math.floor(totalValue / totalOrbs))
	end
	
	-- Spawn orbs distributed along the snake
	local spawnedOrbs = 0
	local skipInterval = math.max(1, math.floor(totalSegments / totalOrbs))
	
	print(string.format("Spawning %d orbs along snake with %d segments (skip interval: %d)", totalOrbs, totalSegments, skipInterval))
	
	-- Use OrbUtils if available, otherwise use global OrbSpawner
	local OrbUtils = nil
	pcall(function()
		OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))
	end)
	
	for i = 1, totalSegments, skipInterval do
		if spawnedOrbs >= totalOrbs then break end
		
		local segment = segments[i]
		if segment and segment:IsA("BasePart") and segment.Parent then
			local pos = segment.Position
			
			-- Small random offset to prevent perfect stacking
			local offset = Vector3.new(
				(math.random() - 0.5) * 3,
				0,
				(math.random() - 0.5) * 3
			)
			
			-- Spawn orb at segment position
			local spawnPos = pos + offset + Vector3.new(0, 2, 0) -- 2 studs above segment
			
			if OrbUtils and OrbUtils.spawnOrbAt then
				-- Use OrbUtils (matches collision handler)
				pcall(function()
					OrbUtils.spawnOrbAt(spawnPos, baseValue)
				end)
			elseif _G.OrbSpawner and _G.OrbSpawner.spawnOrb then
				-- Fallback to global OrbSpawner
				pcall(function()
					_G.OrbSpawner.spawnOrb(spawnPos, baseValue)
				end)
			else
				warn("No orb spawning system available")
			end
			
			spawnedOrbs = spawnedOrbs + 1
		end
	end
	
	-- Ensure minimum orbs spawn at head position if needed
	if spawnedOrbs < 3 and segments[1] then
		local headSegment = segments[1]
		if headSegment and headSegment:IsA("BasePart") and headSegment.Parent then
			for j = 1, 3 - spawnedOrbs do
				local offset = Vector3.new(
					(math.random() - 0.5) * 5,
					0,
					(math.random() - 0.5) * 5
				)
				local spawnPos = headSegment.Position + offset + Vector3.new(0, 2, 0)
				
				if OrbUtils and OrbUtils.spawnOrbAt then
					pcall(function()
						OrbUtils.spawnOrbAt(spawnPos, baseValue)
					end)
				elseif _G.OrbSpawner and _G.OrbSpawner.spawnOrb then
					pcall(function()
						_G.OrbSpawner.spawnOrb(spawnPos, baseValue)
					end)
				end
			end
		end
	end
	
	print(string.format("✅ Spawned %d death orbs along snake path", spawnedOrbs))
end

-- Handle character spawning
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then 
		wait(0.1)
		player = Players:GetPlayerFromCharacter(character)
		if not player then
			warn("Could not get player from character")
			return
		end
	end

	-- Clean up old snake
	if activeSnakes[player] then
		activeSnakes[player]:destroy()
		activeSnakes[player] = nil
	end

	-- Wait for character to load
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	-- IMPORTANT: Disable collision on character parts
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			part.CanCollide = false
			part.CanTouch = false
		end
	end

	wait(0.5) -- Small delay for stability

	-- Get configuration
	local config = getSkinConfig(player)

	print("Creating snake with config - InitialLength:", config.InitialLength, "MaxSegments:", config.MaxSegments)

	-- Create optimized snake
	print("🐍 Creating snake for", player.Name, "with config:", config.InitialLength, "length")
	local success, snake = pcall(function()
		return OptimizedSnakeSystem.createSnake(character, config)
	end)

	if not success then
		warn("❌ Error creating snake:", snake)
		return
	end

	if not snake then
		warn("❌ Failed to create snake for", player.Name)
		return
	end

	print("✅ Snake created successfully for", player.Name)
	activeSnakes[player] = snake

	-- COLLISION FIX: Set collision properties on all snake parts
	if snake.head then
		setSnakePartCollision(snake.head, true)
	end
	
	if snake.segments then
		for _, segment in ipairs(snake.segments) do
			if segment and segment:IsA("BasePart") then
				setSnakePartCollision(segment, false)
			end
		end
	end

	-- Add to global table for collision handler
	if not _G.PlayerSnakes then
		_G.PlayerSnakes = {}
	end
	_G.PlayerSnakes[player] = snake

	-- Override snake's segment creation to apply collision settings
	local originalAddSegment = snake.addSegment
	if originalAddSegment then
		snake.addSegment = function(self, ...)
			local segment = originalAddSegment(self, ...)
			if segment and segment:IsA("BasePart") then
				setSnakePartCollision(segment, false)
			end
			return segment
		end
	end

	-- Setup boost tracking
	if snake.setBoosting then
		-- Create RemoteEvent for boost state
		local boostEvent = remoteEvents:FindFirstChild("UpdateBoostState")
		if not boostEvent then
			boostEvent = Instance.new("RemoteEvent")
			boostEvent.Name = "UpdateBoostState"
			boostEvent.Parent = remoteEvents
		end

		-- Listen for boost state changes
		local boostConnection
		boostConnection = boostEvent.OnServerEvent:Connect(function(eventPlayer, isBoosting)
			if eventPlayer == player and activeSnakes[player] then
				activeSnakes[player]:setBoosting(isBoosting)
			end
		end)

		-- Store connection for cleanup
		if not snake._connections then
			snake._connections = {}
		end
		snake._connections.boost = boostConnection
	end

	-- Ensure leaderstats exist
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local lengthValue = leaderstats:FindFirstChild("Length")
	if not lengthValue then
		lengthValue = Instance.new("IntValue")
		lengthValue.Name = "Length"
		lengthValue.Value = config.InitialLength or 55
		lengthValue.Parent = leaderstats
	else
		lengthValue.Value = config.InitialLength or 55
	end

	-- Handle length updates
	if lengthValue then
		-- Initial length
		snake:updateLength(lengthValue.Value)

		-- Listen for changes with collision fix
		local lengthConnection = lengthValue.Changed:Connect(function(newLength)
			if snake and activeSnakes[player] == snake then
				snake:updateLength(newLength)
				
				-- Reapply collision settings to new segments
				if snake.segments then
					for _, segment in ipairs(snake.segments) do
						if segment and segment:IsA("BasePart") then
							setSnakePartCollision(segment, false)
						end
					end
				end
			end
		end)
		
		-- Store connection
		if not snake._connections then
			snake._connections = {}
		end
		snake._connections.length = lengthConnection
	end

	-- Update loop - monitor for character removal/death
	local updateConnection
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		if not character.Parent or humanoid.Health <= 0 then
			updateConnection:Disconnect()
			return
		end
		
		-- Ensure collision settings persist
		if snake.head and snake.head.CanCollide then
			snake.head.CanCollide = false
		end
	end)

	-- Handle skin changes
	local skinConnection
	skinConnection = player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
		if snake and activeSnakes[player] == snake then
			local newConfig = getSkinConfig(player)
			if snake.head then
				snake.head.Color = newConfig.HeadColor
				snake.head.Material = newConfig.HeadMaterial
			end
			snake.config = newConfig
		end
	end)

	-- Store connections
	snake.monitorConnection = updateConnection
	snake.skinConnection = skinConnection

	-- Handle death
	local deathConnection
	deathConnection = humanoid.Died:Connect(function()
		if activeSnakes[player] then
			-- Disconnect all connections immediately
			if updateConnection then
				updateConnection:Disconnect()
			end
			if skinConnection then
				skinConnection:Disconnect()
			end
			if deathConnection then
				deathConnection:Disconnect()
			end

			-- Cleanup all stored connections
			if snake._connections then
				for _, conn in pairs(snake._connections) do
					if conn then
						conn:Disconnect()
					end
				end
			end

			-- Get snake length for death orbs
			local snakeLength = lengthValue and lengthValue.Value or 55

			print(string.format("🐍 Snake died - Length: %d, Spawning orbs along snake path", snakeLength))

			-- FIXED: Spawn orbs along snake segments instead of just at death position
			spawnDeathOrbsAlongSnake(snake, snakeLength)

			-- Clean up snake
			activeSnakes[player]:destroy()
			activeSnakes[player] = nil

			-- Remove from global table
			if _G.PlayerSnakes then
				_G.PlayerSnakes[player] = nil
			end
		end
	end)
end

-- Handle players
Players.PlayerAdded:Connect(function(player)
	-- Setup leaderstats if not exists
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player

		local length = Instance.new("IntValue")
		length.Name = "Length"
		length.Value = 55
		length.Parent = leaderstats
	end

	-- Connect character spawning
	player.CharacterAdded:Connect(onCharacterAdded)

	-- Handle existing character
	if player.Character then
		onCharacterAdded(player.Character)
	end
end)

-- Cleanup on player leaving
Players.PlayerRemoving:Connect(function(player)
	if activeSnakes[player] then
		activeSnakes[player]:destroy()
		activeSnakes[player] = nil
	end
	
	-- Clean up from global table
	if _G.PlayerSnakes then
		_G.PlayerSnakes[player] = nil
	end
end)

-- Handle existing players
for _, player in pairs(Players:GetPlayers()) do
	if player.Character then
		onCharacterAdded(player.Character)
	else
		player.CharacterAdded:Connect(onCharacterAdded)
	end
end

-- Handle spawn requests from menu
local respawnEvent = ReplicatedStorage:FindFirstChild("RespawnSnake")
if respawnEvent then
	respawnEvent.OnServerEvent:Connect(function(player)
		print("🎮 Respawn requested for:", player.Name)
		if player.Character then
			player.Character:Destroy()
		end
		wait(0.1)
		local success, err = pcall(function()
			player:LoadCharacter()
		end)
		if not success then
			warn("❌ Failed to load character:", err)
		else
			print("✅ Character loaded for:", player.Name)
		end
		print("🐍 Respawned player:", player.Name)
	end)
end

print("✅ Snake System Integration loaded with collision fixes!")
print("🛡️ Collision groups configured:")
print("   - PlayerSnake: No self-collision")
print("   - AISnake: No self-collision")
print("   - Physical collisions disabled (handled by collision system)")
print("💎 Death orbs now spawn along snake path, not bunched together!")