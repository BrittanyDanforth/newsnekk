-- Client Snake Loader - Handles visual rendering of beam snakes
-- Place this in StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- Wait for beam system
local BeamSnakeSystem
local success, result = pcall(function()
	return require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV8_ContinuousBeam"))
end)

if success and result then
	BeamSnakeSystem = result
	print("✅ Client: Loaded Beam Snake System")
else
	warn("❌ Client: Failed to load beam snake system")
	return
end

-- Initialize the system
BeamSnakeSystem.init()

-- Track active snakes
local activeSnakes = {}

-- Function to create visual snake for a character
local function createVisualSnake(character)
	local snakePlayer = Players:GetPlayerFromCharacter(character)
	if not snakePlayer then return end
	
	-- Clean up old snake
	if activeSnakes[snakePlayer] then
		activeSnakes[snakePlayer]:destroy()
		activeSnakes[snakePlayer] = nil
	end
	
	-- Wait for server to set up attributes
	wait(0.5)
	
	-- Get config from attributes
	local config = {
		InitialLength = snakePlayer:GetAttribute("SnakeLength") or 10,
		HeadColor = snakePlayer:GetAttribute("HeadColor") or Color3.fromRGB(76, 217, 100),
		SkinName = snakePlayer:GetAttribute("EquippedSkin") or "Default"
	}
	
	-- Create the visual snake
	local snake = BeamSnakeSystem.new(character, config)
	if snake then
		activeSnakes[snakePlayer] = snake
		print("✅ Client: Created visual snake for", snakePlayer.Name)
		
		-- Monitor length changes
		snakePlayer:GetAttributeChangedSignal("SnakeLength"):Connect(function()
			local newLength = snakePlayer:GetAttribute("SnakeLength")
			if newLength and snake.setLength then
				snake:setLength(newLength)
			end
		end)
		
		-- Monitor skin changes
		snakePlayer:GetAttributeChangedSignal("EquippedSkin"):Connect(function()
			local newSkin = snakePlayer:GetAttribute("EquippedSkin")
			if newSkin and snake.applySkin then
				snake:applySkin(newSkin)
			end
		end)
	end
end

-- Handle all existing players
for _, otherPlayer in pairs(Players:GetPlayers()) do
	if otherPlayer.Character then
		createVisualSnake(otherPlayer.Character)
	end
	
	otherPlayer.CharacterAdded:Connect(createVisualSnake)
end

-- Handle new players
Players.PlayerAdded:Connect(function(newPlayer)
	newPlayer.CharacterAdded:Connect(createVisualSnake)
end)

-- Clean up on player removal
Players.PlayerRemoving:Connect(function(removingPlayer)
	if activeSnakes[removingPlayer] then
		activeSnakes[removingPlayer]:destroy()
		activeSnakes[removingPlayer] = nil
	end
end)

print("✅ Client Snake Loader initialized!")