--!strict
-- SnakeGameServer - Main server initialization script
-- Demonstrates proper usage of the modernized SnakeCollisionHandler

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for modules to be available
local Modules = ServerScriptService:WaitForChild("Modules")
local SnakeCollisionHandler = require(Modules:WaitForChild("SnakeCollisionHandler"))

-- Configuration
local DISABLE_CHARACTER_AUTO_LOADS = true -- Required for custom respawn system

-- Initialize the game
local function InitializeGame()
    print("🐍 Initializing Snake Game Server...")
    
    -- Disable automatic character loading for custom respawn control
    if DISABLE_CHARACTER_AUTO_LOADS then
        Players.CharacterAutoLoads = false
        print("✅ Character auto-loads disabled")
    end
    
    -- Initialize the collision handler
    SnakeCollisionHandler:Initialize()
    print("✅ Collision handler initialized")
    
    -- Set up custom spawn logic
    Players.PlayerAdded:Connect(function(player)
        print(string.format("👤 Player %s joined", player.Name))
        
        -- Wait a moment before spawning
        task.wait(1)
        
        -- Load character
        player:LoadCharacter()
        
        -- Set up respawn button (example)
        player.CharacterAdded:Connect(function(character)
            -- Character spawned successfully
            print(string.format("✅ Character spawned for %s", player.Name))
        end)
    end)
    
    print("🎮 Snake Game Server initialized successfully!")
end

-- Error handling wrapper
local success, error = pcall(InitializeGame)
if not success then
    warn("❌ Failed to initialize Snake Game Server:", error)
else
    print("✨ Server ready for players!")
end