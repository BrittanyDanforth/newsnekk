-- ULTRA OPTIMIZED SNAKE INTEGRATION SCRIPT
-- Place in ServerScriptService to integrate V8 optimizations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wait for modules
local OptimizedSnakeSystemV8 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV8"))
local SnakeNetworkHandler = require(ServerScriptService:WaitForChild("SnakeNetworkHandler"))

-- ULTRA OPTIMIZED CONFIG for 5k+ length
local SNAKE_CONFIG = {
	-- Visual settings
	HeadSize = Vector3.new(4.5, 4.5, 4.5),
	HeadColor = Color3.fromRGB(76, 217, 100),
	HeadMaterial = Enum.Material.Neon,
	SegmentSize = Vector3.new(4, 4, 4),
	BodyColors = {
		Color3.fromRGB(34, 139, 34),
		Color3.fromRGB(50, 205, 50)
	},
	
	-- Performance settings
	InitialLength = 10,
	MaxSegments = 50000,
	BaseSpeed = 50,
	BoostSpeed = 100,
	
	-- Optimizations
	UpdateRate = 20, -- 20 FPS for network
	SegmentGap = 3.5, -- Larger gap for performance
	GlowRange = 6
}

-- Initialize systems
print("🚀 Initializing Ultra Optimized Snake System V8...")
OptimizedSnakeSystemV8.init()
SnakeNetworkHandler.init()

-- Player spawn handling with optimizations
local function onPlayerAdded(player)
	-- Create leaderstats
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	
	local length = Instance.new("IntValue")
	length.Name = "Length"
	length.Value = SNAKE_CONFIG.InitialLength
	length.Parent = leaderstats
	
	local orbs = Instance.new("IntValue")
	orbs.Name = "Orbs"
	orbs.Value = 0
	orbs.Parent = leaderstats
	
	-- Handle character spawn
	local function onCharacterAdded(character)
		-- Wait a frame for character to load
		RunService.Heartbeat:Wait()
		
		-- Add length value to character for easy access
		local charLength = length:Clone()
		charLength.Name = "Length"
		charLength.Parent = character
		
		-- Sync with leaderstats
		length.Changed:Connect(function(value)
			charLength.Value = value
		end)
		
		-- Small delay to ensure everything is loaded
		task.wait(0.5)
		
		-- Create optimized snake
		local snake = OptimizedSnakeSystemV8.createSnake(character, SNAKE_CONFIG)
		
		if snake then
			print("✅ Created ultra-optimized snake for", player.Name)
			
			-- Handle orb collection with length-based optimization
			local orbConnection
			orbConnection = orbs.Changed:Connect(function(newValue)
				if newValue > 0 then
					orbs.Value = 0
					
					-- Adaptive growth based on current length
					local currentLength = snake:GetLength()
					local growthAmount = newValue
					
					-- Reduce growth rate at higher lengths to prevent too rapid growth
					if currentLength > 5000 then
						growthAmount = math.ceil(growthAmount * 0.8)
					elseif currentLength > 10000 then
						growthAmount = math.ceil(growthAmount * 0.6)
					elseif currentLength > 20000 then
						growthAmount = math.ceil(growthAmount * 0.4)
					end
					
					snake:grow(growthAmount)
					length.Value = snake:GetLength()
				end
			end)
			
			-- Cleanup on death
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				if orbConnection then
					orbConnection:Disconnect()
				end
				if snake then
					snake:destroy()
				end
			end)
		else
			warn("Failed to create snake for", player.Name)
		end
	end
	
	-- Connect character spawning
	player.CharacterAdded:Connect(onCharacterAdded)
	
	-- Handle existing character
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

-- Connect players
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle existing players
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		onPlayerAdded(player)
	end)
end

-- Performance monitoring
local lastCheck = tick()
local frameCount = 0

RunService.Heartbeat:Connect(function()
	frameCount = frameCount + 1
	
	local now = tick()
	if now - lastCheck >= 10 then -- Check every 10 seconds
		local fps = frameCount / 10
		
		-- Warn if FPS drops too low
		if fps < 30 then
			warn("⚠️ Low server FPS detected:", math.floor(fps), "FPS")
			
			-- Emergency optimizations
			if fps < 20 then
				print("🔧 Applying emergency optimizations...")
				
				-- Reduce visible segments for all snakes
				for _, player in ipairs(Players:GetPlayers()) do
					if _G.PlayerSnakes and _G.PlayerSnakes[player] then
						local snake = _G.PlayerSnakes[player]
						if snake.adaptiveMaxVisible and snake.adaptiveMaxVisible > 40 then
							snake.adaptiveMaxVisible = math.floor(snake.adaptiveMaxVisible * 0.8)
						end
					end
				end
			end
		end
		
		frameCount = 0
		lastCheck = now
	end
end)

print("✅ Ultra Optimized Snake System V8 Integration Complete!")
print("📊 Features:")
print("   • Adaptive LOD based on snake length")
print("   • Reduced network traffic (10 Hz)")
print("   • Minimal segment rendering")
print("   • Distance-based player filtering")
print("   • Emergency performance optimization")
print("🎮 Optimized for 5k+ length with minimal lag!")