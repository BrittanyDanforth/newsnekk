--[[
	SNAKE SYSTEM INTEGRATION
	
	This script integrates the optimized snake system with the existing CharacterSetup
	It handles:
	- Loading the appropriate OptimizedSnakeSystem version
	- Creating the snake when player spawns 
	- Managing snake lifecycle and cleanup
	- Syncing with gameplay systems
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Create remotes folder if it doesn't exist
local remotesFolder = ReplicatedStorage:FindFirstChild("SnakeRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "SnakeRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

-- Create menu integration remotes
local spawnRemote = remotesFolder:FindFirstChild("SpawnSnake") or Instance.new("RemoteEvent")
spawnRemote.Name = "SpawnSnake"
spawnRemote.Parent = remotesFolder

local respawnRemote = remotesFolder:FindFirstChild("RespawnSnake") or Instance.new("RemoteEvent")
respawnRemote.Name = "RespawnSnake"
respawnRemote.Parent = remotesFolder

-- Load the best available OptimizedSnakeSystem
local function loadSnakeSystem()
	-- Try V9 first (latest version with unified rendering)
	local success, systemV9 = pcall(function()
		return require(ServerScriptService:WaitForChild("OptimizedSnakeSystemV9", 5))
	end)
	if success and systemV9 then
		print("✅ Loaded OptimizedSnakeSystemV9 (ULTIMATE)")
		return systemV9
	end
	
	-- Try V4
	local success4, systemV4 = pcall(function()
		return require(ServerScriptService:WaitForChild("OptimizedSnakeSystemV4", 5))
	end)
	if success4 and systemV4 then
		print("✅ Loaded OptimizedSnakeSystemV4")
		return systemV4
	end
	
	-- Try V3
	local success3, systemV3 = pcall(function()
		return require(ServerScriptService:WaitForChild("OptimizedSnakeSystemV3", 5))
	end)
	if success3 and systemV3 then
		print("✅ Loaded OptimizedSnakeSystemV3")
		return systemV3
	end
	
	-- Try V2
	local success2, systemV2 = pcall(function()
		return require(ServerScriptService:WaitForChild("OptimizedSnakeSystemV2", 5))
	end)
	if success2 and systemV2 then
		print("✅ Loaded OptimizedSnakeSystemV2")
		return systemV2
	end
	
	-- Fallback to V1
	local success1, systemV1 = pcall(function()
		return require(ServerScriptService:WaitForChild("OptimizedSnakeSystem", 5))
	end)
	if success1 and systemV1 then
		print("✅ Loaded OptimizedSnakeSystemV1 (Fallback)")
		return systemV1
	end
	
	error("❌ No OptimizedSnakeSystem module found!")
end

-- Load the system
local OptimizedSnakeSystem = loadSnakeSystem()

-- Initialize the snake system
OptimizedSnakeSystem.init()

-- Store references to player snakes
local playerSnakes = {}
_G.PlayerSnakes = playerSnakes -- Make globally accessible

-- Default configuration
local DEFAULT_CONFIG = {
	InitialLength = 500,  -- Normal starting length
	MaxSegments = 50000,  -- MASSIVE SNAKES! Was 10000
	SegmentSpacing = 3.2,  -- Original spacing
	SegmentSize = Vector3.new(4, 4, 4),  -- Original size
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
	GlowRange = 6
}

-- Create/update length value
local function updateLengthValue(player, length)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	
	local lengthValue = leaderstats:FindFirstChild("Length") or Instance.new("IntValue")
	lengthValue.Name = "Length"
	lengthValue.Value = length
	lengthValue.Parent = leaderstats
	
	-- Also update for AI system
	player:SetAttribute("Length", length)
end

-- Skins configuration
local SKINS = {
	["Green"] = {
		HeadColor = Color3.fromRGB(76, 217, 100),
		BodyColors = {
			Color3.fromRGB(60, 180, 80),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(100, 220, 120),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(60, 180, 80),
		}
	},
	["Blue"] = {
		HeadColor = Color3.fromRGB(100, 149, 237),
		BodyColors = {
			Color3.fromRGB(65, 105, 225),
			Color3.fromRGB(100, 149, 237),
			Color3.fromRGB(135, 206, 250),
			Color3.fromRGB(100, 149, 237),
			Color3.fromRGB(65, 105, 225),
		}
	},
	["Red"] = {
		HeadColor = Color3.fromRGB(220, 20, 60),
		BodyColors = {
			Color3.fromRGB(178, 34, 34),
			Color3.fromRGB(220, 20, 60),
			Color3.fromRGB(255, 69, 0),
			Color3.fromRGB(220, 20, 60),
			Color3.fromRGB(178, 34, 34),
		}
	},
	["Purple"] = {
		HeadColor = Color3.fromRGB(147, 112, 219),
		BodyColors = {
			Color3.fromRGB(138, 43, 226),
			Color3.fromRGB(147, 112, 219),
			Color3.fromRGB(186, 85, 211),
			Color3.fromRGB(147, 112, 219),
			Color3.fromRGB(138, 43, 226),
		}
	},
	["Rainbow"] = {
		HeadColor = Color3.fromRGB(255, 255, 255),
		BodyColors = {
			Color3.fromRGB(255, 0, 0),
			Color3.fromRGB(255, 127, 0),
			Color3.fromRGB(255, 255, 0),
			Color3.fromRGB(0, 255, 0),
			Color3.fromRGB(0, 0, 255),
			Color3.fromRGB(75, 0, 130),
			Color3.fromRGB(148, 0, 211),
		}
	},
	["Galaxy"] = {
		HeadColor = Color3.fromRGB(100, 65, 165),
		BodyColors = {
			Color3.fromRGB(25, 25, 112),
			Color3.fromRGB(72, 61, 139),
			Color3.fromRGB(123, 104, 238),
			Color3.fromRGB(147, 112, 219),
			Color3.fromRGB(138, 43, 226),
		}
	}
}

-- Create snake for player with skin and length
local function createSnake(player, character)
	-- Clean up old snake
	if playerSnakes[player] then
		playerSnakes[player]:destroy()
		playerSnakes[player] = nil
	end
	
	-- Get selected skin (check if player is respawning with JustRevived)
	local selectedSkin = player:GetAttribute("SelectedSkin") or "Green"
	local skin = SKINS[selectedSkin] or SKINS["Green"]
	
	-- Merge skin with default config
	local config = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		config[key] = value
	end
	for key, value in pairs(skin) do
		config[key] = value
	end
	
	-- Check if player is respawning with revive
	local isReviving = player:GetAttribute("RevivingNow")
	local justRevived = player:GetAttribute("JustRevived")
	
	if isReviving or justRevived then
		-- Use the stored revive length
		local reviveLength = player:GetAttribute("ReviveSnakeLength") or 200
		config.InitialLength = math.max(200, reviveLength) -- Minimum 200 on revive
		
		-- Clear reviving flag
		player:SetAttribute("RevivingNow", false)
	else
		-- Normal spawn
		config.InitialLength = 500
	end
	
	-- Create the snake  
	local snake = OptimizedSnakeSystem.createSnake(character, config)
	if snake then
		playerSnakes[player] = snake
		
		-- Initialize length tracking
		updateLengthValue(player, config.InitialLength)
		
		-- Track length changes
		local lastLength = config.InitialLength
		task.spawn(function()
			while snake and snake.model and snake.model.Parent do
				local currentLength = snake:getLength()
				if currentLength ~= lastLength then
					lastLength = currentLength
					updateLengthValue(player, currentLength)
				end
				task.wait(0.1)
			end
		end)
		
		-- Listen for skin changes
		player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
			if snake and snake.model and snake.model.Parent then
				local newSkin = player:GetAttribute("SelectedSkin") or "Green"
				local skinData = SKINS[newSkin] or SKINS["Green"]
				snake:setSkin(skinData)
			end
		end)
		
		-- Track boost states
		local function updateBoostState()
			if snake and snake.model and snake.model.Parent then
				local isBoosting = player:GetAttribute("ActiveSpeedBoost") or 
				                  player:GetAttribute("ActiveMegaSpeed") or
				                  false
				snake:setBoosting(isBoosting)
			end
		end
		
		player:GetAttributeChangedSignal("ActiveSpeedBoost"):Connect(updateBoostState)
		player:GetAttributeChangedSignal("ActiveMegaSpeed"):Connect(updateBoostState)
		
		print("✅ Snake created for", player.Name, "with length", config.InitialLength)
	end
end

-- Handle menu spawn request
spawnRemote.OnServerEvent:Connect(function(player)
	print("🎮 SpawnSnake request from", player.Name)
	
	-- Get or wait for character
	local character = player.Character
	if not character then
		player:LoadCharacter()
		character = player.CharacterAdded:Wait()
		task.wait(0.1) -- Small delay to ensure character is ready
	end
	
	-- Clear any revive attributes from previous life
	player:SetAttribute("JustRevived", false)
	player:SetAttribute("RevivingNow", false)
	player:SetAttribute("ReviveInvincible", false)
	
	-- Create the snake
	createSnake(player, character)
end)

-- Handle respawn after death
respawnRemote.OnServerEvent:Connect(function(player)
	print("💀 RespawnSnake request from", player.Name)
	
	-- Check if player has revive and wants to use it
	local hasRevive = player:GetAttribute("HasRevive") or false
	local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
	
	if hasRevive and revivesAvailable > 0 then
		-- Will be handled by GamepassHandler when user clicks revive
		return
	end
	
	-- Normal respawn
	player:LoadCharacter()
end)

-- Clean up on player death
local function onCharacterDeath(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			local player = Players:GetPlayerFromCharacter(character)
			if player and playerSnakes[player] then
				-- Store snake length before death for potential revive
				local currentLength = playerSnakes[player]:getLength()
				player:SetAttribute("ReviveSnakeLength", math.floor(currentLength * 0.5)) -- 50% on revive
				
				-- Destroy the snake
				playerSnakes[player]:destroy()
				playerSnakes[player] = nil
				print("💀 Snake destroyed for", player.Name)
			end
		end)
	end
end

-- Handle player character spawn
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	
	-- Set up death handling
	onCharacterDeath(character)
	
	-- Only create snake if spawning from menu or reviving
	-- The menu will call SpawnSnake when ready
	if player:GetAttribute("JustRevived") then
		-- Revive spawn - create snake immediately
		createSnake(player, character)
	end
end

-- Connect player events
Players.PlayerAdded:Connect(function(player)
	-- Initialize attributes
	player:SetAttribute("SelectedSkin", "Green")
	player:SetAttribute("ReviveSnakeLength", 200)
	player:SetAttribute("JustRevived", false)
	player:SetAttribute("RevivingNow", false)
	
	player.CharacterAdded:Connect(onCharacterAdded)
end)

-- Cleanup on player leaving
Players.PlayerRemoving:Connect(function(player)
	if playerSnakes[player] then
		playerSnakes[player]:destroy()
		playerSnakes[player] = nil
	end
end)

print("✅ Snake System Integration loaded!")