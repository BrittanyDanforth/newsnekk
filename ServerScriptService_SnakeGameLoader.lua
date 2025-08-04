-- SnakeGameLoader.lua
-- Place this in ServerScriptService to initialize the snake game

local ServerScriptService = game:GetService("ServerScriptService")

-- Require the modern collision handler module
local SnakeCollisionHandler = require(script.Parent:WaitForChild("SnakeCollisionHandler_Modern"))

-- Initialize the game system
local gameHandler = SnakeCollisionHandler.new()

print("[SnakeGame] Initialized with modern architecture")
print("✅ Using spatial queries for precise collision detection")
print("✅ Trove pattern for automatic memory management")
print("✅ Client-server hybrid model for responsiveness")
print("✅ Modern Luau APIs (task.wait, os.clock)")
print("✅ Secure validation of all client reports")

-- Handle game shutdown gracefully
game:BindToClose(function()
	gameHandler:Destroy()
	print("[SnakeGame] Cleaned up successfully")
end)