--[[
	REVIVE UI CLIENT SCRIPT
	Creates and manages the revive prompt UI
--]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Constants
local player = Players.LocalPlayer

-- Wait for events
local Events = ReplicatedStorage:WaitForChild("Events")
local promptReviveRemote = Events:WaitForChild("PromptRevive")

-- Create revive UI
local function createReviveUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RevivePrompt"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 1000
	
	-- Dark overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui
	
	-- Main container
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0.4, 0, 0.35, 0)
	container.Position = UDim2.new(0.3, 0, 0.3, 0)
	container.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	container.BorderSizePixel = 0
	container.Parent = screenGui
	
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 20)
	containerCorner.Parent = container
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Text = "YOU DIED!"
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 89, 89)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.8, 0, 0.25, 0)
	title.Position = UDim2.new(0.1, 0, 0.05, 0)
	title.Parent = container
	
	-- Question
	local question = Instance.new("TextLabel")
	question.Name = "Question"
	question.Text = "Use a revive?"
	question.Font = Enum.Font.FredokaOne
	question.TextScaled = true
	question.TextColor3 = Color3.fromRGB(255, 255, 255)
	question.BackgroundTransparency = 1
	question.Size = UDim2.new(0.8, 0, 0.15, 0)
	question.Position = UDim2.new(0.1, 0, 0.3, 0)
	question.Parent = container
	
	-- Revives left
	local revivesLeft = Instance.new("TextLabel")
	revivesLeft.Name = "RevivesLeft"
	revivesLeft.Text = "Revives remaining: 0"
	revivesLeft.Font = Enum.Font.FredokaOne
	revivesLeft.TextScaled = true
	revivesLeft.TextColor3 = Color3.fromRGB(200, 200, 200)
	revivesLeft.BackgroundTransparency = 1
	revivesLeft.Size = UDim2.new(0.8, 0, 0.1, 0)
	revivesLeft.Position = UDim2.new(0.1, 0, 0.45, 0)
	revivesLeft.Parent = container
	
	-- Button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "Buttons"
	buttonContainer.Size = UDim2.new(0.8, 0, 0.2, 0)
	buttonContainer.Position = UDim2.new(0.1, 0, 0.6, 0)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = container
	
	-- Revive button
	local reviveButton = Instance.new("TextButton")
	reviveButton.Name = "ReviveButton"
	reviveButton.Text = "REVIVE"
	reviveButton.Font = Enum.Font.FredokaOne
	reviveButton.TextScaled = true
	reviveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	reviveButton.BackgroundColor3 = Color3.fromRGB(76, 217, 100)
	reviveButton.Size = UDim2.new(0.45, 0, 1, 0)
	reviveButton.Position = UDim2.new(0, 0, 0, 0)
	reviveButton.BorderSizePixel = 0
	reviveButton.Parent = buttonContainer
	
	local reviveCorner = Instance.new("UICorner")
	reviveCorner.CornerRadius = UDim.new(0, 12)
	reviveCorner.Parent = reviveButton
	
	-- Respawn button
	local respawnButton = Instance.new("TextButton")
	respawnButton.Name = "RespawnButton"
	respawnButton.Text = "RESPAWN"
	respawnButton.Font = Enum.Font.FredokaOne
	respawnButton.TextScaled = true
	respawnButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	respawnButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	respawnButton.Size = UDim2.new(0.45, 0, 1, 0)
	respawnButton.Position = UDim2.new(0.55, 0, 0, 0)
	respawnButton.BorderSizePixel = 0
	respawnButton.Parent = buttonContainer
	
	local respawnCorner = Instance.new("UICorner")
	respawnCorner.CornerRadius = UDim.new(0, 12)
	respawnCorner.Parent = respawnButton
	
	-- Timer bar
	local timerBar = Instance.new("Frame")
	timerBar.Name = "TimerBar"
	timerBar.Size = UDim2.new(0.8, 0, 0.05, 0)
	timerBar.Position = UDim2.new(0.1, 0, 0.85, 0)
	timerBar.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	timerBar.BorderSizePixel = 0
	timerBar.Parent = container
	
	local timerBarCorner = Instance.new("UICorner")
	timerBarCorner.CornerRadius = UDim.new(0, 4)
	timerBarCorner.Parent = timerBar
	
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.Size = UDim2.new(1, 0, 1, 0)
	timerFill.BackgroundColor3 = Color3.fromRGB(255, 170, 50)
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerBar
	
	local timerFillCorner = Instance.new("UICorner")
	timerFillCorner.CornerRadius = UDim.new(0, 4)
	timerFillCorner.Parent = timerFill
	
	return screenGui, {
		container = container,
		revivesLeft = revivesLeft,
		reviveButton = reviveButton,
		respawnButton = respawnButton,
		timerFill = timerFill
	}
end

-- Handle revive prompt
promptReviveRemote.OnClientEvent:Connect(function(revivesAvailable, snakeLength)
	-- Create UI
	local ui, elements = createReviveUI()
	ui.Parent = player:WaitForChild("PlayerGui")
	
	-- Update revives display
	elements.revivesLeft.Text = "Revives remaining: " .. revivesAvailable
	
	-- Timer
	local timeLeft = 10
	local timerConnection
	
	local function cleanup()
		if timerConnection then
			timerConnection:Disconnect()
		end
		ui:Destroy()
	end
	
	-- Button handlers
	elements.reviveButton.MouseButton1Click:Connect(function()
		promptReviveRemote:FireServer(true)
		cleanup()
	end)
	
	elements.respawnButton.MouseButton1Click:Connect(function()
		promptReviveRemote:FireServer(false)
		cleanup()
	end)
	
	-- Start timer
	timerConnection = RunService.Heartbeat:Connect(function(dt)
		timeLeft = timeLeft - dt
		
		if timeLeft <= 0 then
			-- Auto-respawn
			promptReviveRemote:FireServer(false)
			cleanup()
		else
			-- Update timer bar
			elements.timerFill.Size = UDim2.new(timeLeft / 10, 0, 1, 0)
		end
	end)
	
	-- Animate entrance
	elements.container.Size = UDim2.new(0, 0, 0, 0)
	elements.container.Position = UDim2.new(0.5, 0, 0.5, 0)
	
	TweenService:Create(elements.container, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.new(0.4, 0, 0.35, 0),
		Position = UDim2.new(0.3, 0, 0.3, 0)
	}):Play()
end)