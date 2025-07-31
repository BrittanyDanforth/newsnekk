--[[
	SNAKE SYSTEM INTEGRATION
	Placed in ServerScriptService
	
	This script integrates the optimized snake system with the existing CharacterSetup
--]]

-- Wait for CharacterSetup to load first
local characterSetup = script.Parent:WaitForChild("CharacterSetup")

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- Wait for required modules
local Systems = ReplicatedStorage:WaitForChild("Systems")
local Modules = ReplicatedStorage:WaitForChild("Modules")

-- Enhanced loading order
local OptimizedSnakeSystem
local loadOrder = {"V9", "V4", "V3", "V2", "V1"}  -- Try V9 first!

for _, version in ipairs(loadOrder) do
	local systemName = "OptimizedSnakeSystem" .. version
	local success, module = pcall(function()
		return Modules:WaitForChild(systemName, 2)
	end)
	
	if success and module then
		local loadSuccess, system = pcall(function()
			return require(module)
		end)
		
		if loadSuccess then
			OptimizedSnakeSystem = system
			print("Successfully loaded", systemName)
			break
		else
			warn("Failed to require", systemName, ":", system)
		end
	end
end

-- Fallback to V1 if nothing else loaded
if not OptimizedSnakeSystem then
	OptimizedSnakeSystem = require(Modules:WaitForChild("OptimizedSnakeSystem"))
	print("Loaded default OptimizedSnakeSystem")
end

-- Initialize the system
OptimizedSnakeSystem.init()

-- Setup RemoteEvents for menu integration
local Events = ReplicatedStorage:FindFirstChild("Events") or Instance.new("Folder")
Events.Name = "Events"
Events.Parent = ReplicatedStorage

local spawnSnakeRemote = Events:FindFirstChild("SpawnSnake") or Instance.new("RemoteEvent")
spawnSnakeRemote.Name = "SpawnSnake"
spawnSnakeRemote.Parent = Events

local respawnSnakeRemote = Events:FindFirstChild("RespawnSnake") or Instance.new("RemoteEvent")
respawnSnakeRemote.Name = "RespawnSnake"
respawnSnakeRemote.Parent = Events

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

-- SKIN CONFIGURATIONS
local SKIN_CONFIGS = {
	Green = DEFAULT_CONFIG,
	
	Blue = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(64, 150, 255),
		BodyColors = {
			Color3.fromRGB(48, 112, 191),
			Color3.fromRGB(64, 150, 255),
			Color3.fromRGB(80, 188, 255),
			Color3.fromRGB(64, 150, 255),
			Color3.fromRGB(48, 112, 191),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Red = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(255, 89, 89),
		BodyColors = {
			Color3.fromRGB(191, 67, 67),
			Color3.fromRGB(255, 89, 89),
			Color3.fromRGB(255, 120, 120),
			Color3.fromRGB(255, 89, 89),
			Color3.fromRGB(191, 67, 67),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Purple = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(191, 89, 255),
		BodyColors = {
			Color3.fromRGB(143, 67, 191),
			Color3.fromRGB(191, 89, 255),
			Color3.fromRGB(210, 120, 255),
			Color3.fromRGB(191, 89, 255),
			Color3.fromRGB(143, 67, 191),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Yellow = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(255, 221, 89),
		BodyColors = {
			Color3.fromRGB(191, 166, 67),
			Color3.fromRGB(255, 221, 89),
			Color3.fromRGB(255, 236, 120),
			Color3.fromRGB(255, 221, 89),
			Color3.fromRGB(191, 166, 67),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Pink = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(255, 170, 255),
		BodyColors = {
			Color3.fromRGB(204, 136, 204),
			Color3.fromRGB(255, 170, 255),
			Color3.fromRGB(255, 200, 255),
			Color3.fromRGB(255, 170, 255),
			Color3.fromRGB(204, 136, 204),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Black = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(40, 40, 40),
		BodyColors = {
			Color3.fromRGB(20, 20, 20),
			Color3.fromRGB(40, 40, 40),
			Color3.fromRGB(60, 60, 60),
			Color3.fromRGB(40, 40, 40),
			Color3.fromRGB(20, 20, 20),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	White = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(240, 240, 240),
		BodyColors = {
			Color3.fromRGB(200, 200, 200),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(200, 200, 200),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 2,
		GlowRange = 6
	},
	
	Rainbow = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(255, 0, 0),
		BodyColors = {
			Color3.fromRGB(255, 0, 0),    -- Red
			Color3.fromRGB(255, 127, 0),  -- Orange
			Color3.fromRGB(255, 255, 0),  -- Yellow
			Color3.fromRGB(0, 255, 0),    -- Green
			Color3.fromRGB(0, 0, 255),    -- Blue
			Color3.fromRGB(75, 0, 130),   -- Indigo
			Color3.fromRGB(148, 0, 211),  -- Violet
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 3,
		GlowRange = 8,
		IsRainbow = true  -- Special flag for rainbow effect
	},
	
	Gold = {
		InitialLength = DEFAULT_CONFIG.InitialLength,
		MaxSegments = DEFAULT_CONFIG.MaxSegments,
		SegmentSpacing = DEFAULT_CONFIG.SegmentSpacing,
		SegmentSize = DEFAULT_CONFIG.SegmentSize,
		HeadSize = DEFAULT_CONFIG.HeadSize,
		HeadColor = Color3.fromRGB(255, 215, 0),
		BodyColors = {
			Color3.fromRGB(184, 134, 11),
			Color3.fromRGB(218, 165, 32),
			Color3.fromRGB(255, 215, 0),
			Color3.fromRGB(218, 165, 32),
			Color3.fromRGB(184, 134, 11),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon,
		GlowIntensity = 3,
		GlowRange = 8
	},
}

-- Store player snakes
local playerSnakes = {}
_G.PlayerSnakes = playerSnakes  -- Global reference for other scripts

-- Function to create snake for player
local function createSnake(player, character)
	-- Remove existing snake if any
	if playerSnakes[player] then
		playerSnakes[player]:destroy()
		playerSnakes[player] = nil
	end
	
	-- Wait a frame to ensure character is ready
	RunService.Heartbeat:Wait()
	
	-- Get selected skin
	local selectedSkin = player:GetAttribute("SelectedSkin") or "Green"
	local config = SKIN_CONFIGS[selectedSkin] or DEFAULT_CONFIG
	
	-- Check for revive
	local isReviving = player:GetAttribute("RevivingNow")
	if isReviving then
		-- Use revive length
		local reviveLength = player:GetAttribute("ReviveSnakeLength") or config.InitialLength
		config = table.clone(config)
		config.InitialLength = reviveLength
		print("Creating revived snake with length:", reviveLength)
	end
	
	-- Apply gamepass multipliers
	local growthMultiplier = player:GetAttribute("GrowthMultiplier") or 1
	config = table.clone(config)
	config.GrowthMultiplier = growthMultiplier
	
	-- Create the snake
	local snake = OptimizedSnakeSystem.createSnake(character, config)
	playerSnakes[player] = snake
	
	-- Update global reference if OrbSpawner exists
	if _G.OrbSpawner then
		_G.OrbSpawner.PlayerSnakes = playerSnakes
	end
	
	-- Track snake length
	local lengthUpdateConnection
	lengthUpdateConnection = RunService.Heartbeat:Connect(function()
		if snake and snake.getLength then
			local currentLength = snake:getLength()
			if currentLength ~= player:GetAttribute("SnakeLength") then
				player:SetAttribute("SnakeLength", currentLength)
			end
		else
			lengthUpdateConnection:Disconnect()
		end
	end)
	
	-- Clean up connection when snake is destroyed
	if snake and snake.Destroyed then
		snake.Destroyed:Connect(function()
			if lengthUpdateConnection then
				lengthUpdateConnection:Disconnect()
			end
		end)
	end
	
	-- Handle skin updates
	local skinConnection
	skinConnection = player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
		local newSkin = player:GetAttribute("SelectedSkin") or "Green"
		local newConfig = SKIN_CONFIGS[newSkin] or DEFAULT_CONFIG
		
		if snake and snake.updateVisuals then
			snake:updateVisuals(newConfig)
			print("Updated snake skin to:", newSkin)
		end
	end)
	
	-- Handle boost state updates
	local function updateBoostState()
		if not snake or not snake.setBoosting then return end
		
		local hasActiveBoost = player:GetAttribute("ActiveSpeedBoost") or 
			player:GetAttribute("ActiveMegaSpeed") or
			player:GetAttribute("ActiveGrowthBoost") or
			false
			
		snake:setBoosting(hasActiveBoost)
	end
	
	-- Listen for boost changes
	local boostConnections = {
		player:GetAttributeChangedSignal("ActiveSpeedBoost"):Connect(updateBoostState),
		player:GetAttributeChangedSignal("ActiveMegaSpeed"):Connect(updateBoostState),
		player:GetAttributeChangedSignal("ActiveGrowthBoost"):Connect(updateBoostState),
	}
	
	-- Add ghost mode handling
	local function updateGhostMode()
		if not snake or not snake.setGhostMode then return end
		
		local hasGhostMode = player:GetAttribute("ActiveGhostMode") or false
		snake:setGhostMode(hasGhostMode)
	end
	
	-- Listen for ghost mode changes
	local ghostConnection = player:GetAttributeChangedSignal("ActiveGhostMode"):Connect(updateGhostMode)
	table.insert(boostConnections, ghostConnection)
	
	-- Clean up when character is removed
	character.AncestryChanged:Connect(function()
		if character.Parent == nil then
			if snake then
				snake:destroy()
			end
			playerSnakes[player] = nil
			skinConnection:Disconnect()
			for _, conn in ipairs(boostConnections) do
				conn:Disconnect()
			end
		end
	end)
	
	return snake
end

-- Handle player spawning
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	
	-- Clear reviving flag after spawn
	if player:GetAttribute("RevivingNow") then
		task.wait(0.1)  -- Small delay to ensure everything is set up
		player:SetAttribute("RevivingNow", false)
	end
	
	-- Wait for HumanoidRootPart
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then return end
	
	-- Create snake
	createSnake(player, character)
end

-- Connect to existing players
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

-- Connect to new players
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	if playerSnakes[player] then
		playerSnakes[player]:destroy()
		playerSnakes[player] = nil
	end
end)

-- Handle spawn requests from menu
spawnSnakeRemote.OnServerEvent:Connect(function(player)
	if player.Character then
		-- Create snake when player spawns from menu
		createSnake(player, player.Character)
	end
end)

-- Handle respawn requests
respawnSnakeRemote.OnServerEvent:Connect(function(player)
	if player.Character then
		player.Character:BreakJoints()  -- Force respawn
	end
end)