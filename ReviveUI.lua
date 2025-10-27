--[[
	REVIVE UI
	
	Creates and manages the revive prompt UI that appears when a player dies
	and has revives available. Shows death message, revive options, and timer.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Get remotes
local remotesFolder = ReplicatedStorage:WaitForChild("SnakeRemotes")
local promptReviveRemote = remotesFolder:WaitForChild("PromptRevive")

-- Create the revive UI
local function createReviveUI()
	-- Main screen GUI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RevivePrompt"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	
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
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	container.BorderSizePixel = 0
	container.Parent = screenGui
	
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 20)
	containerCorner.Parent = container
	
	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = Color3.fromRGB(255, 60, 60)
	containerStroke.Transparency = 0.5
	containerStroke.Thickness = 3
	containerStroke.Parent = container
	
	-- Death message
	local deathText = Instance.new("TextLabel")
	deathText.Name = "DeathText"
	deathText.Size = UDim2.new(0.9, 0, 0.25, 0)
	deathText.Position = UDim2.new(0.5, 0, 0.15, 0)
	deathText.AnchorPoint = Vector2.new(0.5, 0.5)
	deathText.BackgroundTransparency = 1
	deathText.Text = "YOU DIED!"
	deathText.TextColor3 = Color3.fromRGB(255, 60, 60)
	deathText.TextScaled = true
	deathText.Font = Enum.Font.SourceSansBold
	deathText.Parent = container
	
	-- Revive question
	local reviveQuestion = Instance.new("TextLabel")
	reviveQuestion.Name = "ReviveQuestion"
	reviveQuestion.Size = UDim2.new(0.9, 0, 0.15, 0)
	reviveQuestion.Position = UDim2.new(0.5, 0, 0.35, 0)
	reviveQuestion.AnchorPoint = Vector2.new(0.5, 0.5)
	reviveQuestion.BackgroundTransparency = 1
	reviveQuestion.Text = "Use a revive?"
	reviveQuestion.TextColor3 = Color3.fromRGB(200, 200, 200)
	reviveQuestion.TextScaled = true
	reviveQuestion.Font = Enum.Font.SourceSans
	reviveQuestion.Parent = container
	
	-- Revives remaining
	local revivesText = Instance.new("TextLabel")
	revivesText.Name = "RevivesText"
	revivesText.Size = UDim2.new(0.9, 0, 0.1, 0)
	revivesText.Position = UDim2.new(0.5, 0, 0.48, 0)
	revivesText.AnchorPoint = Vector2.new(0.5, 0.5)
	revivesText.BackgroundTransparency = 1
	revivesText.Text = "Revives remaining: 0"
	revivesText.TextColor3 = Color3.fromRGB(150, 150, 150)
	revivesText.TextScaled = true
	revivesText.Font = Enum.Font.SourceSans
	revivesText.Parent = container
	
	-- Button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "ButtonContainer"
	buttonContainer.Size = UDim2.new(0.9, 0, 0.2, 0)
	buttonContainer.Position = UDim2.new(0.5, 0, 0.7, 0)
	buttonContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = container
	
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0.05, 0)
	buttonLayout.Parent = buttonContainer
	
	-- Revive button
	local reviveButton = Instance.new("TextButton")
	reviveButton.Name = "ReviveButton"
	reviveButton.Size = UDim2.new(0.4, 0, 1, 0)
	reviveButton.BackgroundColor3 = Color3.fromRGB(76, 217, 100)
	reviveButton.Text = "REVIVE"
	reviveButton.TextColor3 = Color3.fromRGB(10, 10, 15)
	reviveButton.TextScaled = true
	reviveButton.Font = Enum.Font.SourceSansBold
	reviveButton.Parent = buttonContainer
	
	local reviveCorner = Instance.new("UICorner")
	reviveCorner.CornerRadius = UDim.new(0, 10)
	reviveCorner.Parent = reviveButton
	
	-- Respawn button
	local respawnButton = Instance.new("TextButton")
	respawnButton.Name = "RespawnButton"
	respawnButton.Size = UDim2.new(0.4, 0, 1, 0)
	respawnButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	respawnButton.Text = "RESPAWN"
	respawnButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	respawnButton.TextScaled = true
	respawnButton.Font = Enum.Font.SourceSansBold
	respawnButton.Parent = buttonContainer
	
	local respawnCorner = Instance.new("UICorner")
	respawnCorner.CornerRadius = UDim.new(0, 10)
	respawnCorner.Parent = respawnButton
	
	-- Timer bar
	local timerBar = Instance.new("Frame")
	timerBar.Name = "TimerBar"
	timerBar.Size = UDim2.new(0.9, 0, 0.05, 0)
	timerBar.Position = UDim2.new(0.5, 0, 0.9, 0)
	timerBar.AnchorPoint = Vector2.new(0.5, 0.5)
	timerBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	timerBar.BorderSizePixel = 0
	timerBar.Parent = container
	
	local timerBarCorner = Instance.new("UICorner")
	timerBarCorner.CornerRadius = UDim.new(1, 0)
	timerBarCorner.Parent = timerBar
	
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.Size = UDim2.new(1, 0, 1, 0)
	timerFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerBar
	
	local timerFillCorner = Instance.new("UICorner")
	timerFillCorner.CornerRadius = UDim.new(1, 0)
	timerFillCorner.Parent = timerFill
	
	return screenGui, {
		container = container,
		revivesText = revivesText,
		reviveButton = reviveButton,
		respawnButton = respawnButton,
		timerFill = timerFill
	}
end

-- Handle revive prompt
promptReviveRemote.OnClientEvent:Connect(function(revivesRemaining)
	-- Create UI
	local ui, elements = createReviveUI()
	
	-- Update revives text
	elements.revivesText.Text = "Revives remaining: " .. revivesRemaining
	
	-- Timer
	local timerDuration = 5
	local startTime = tick()
	
	-- Timer update
	local timerConnection
	timerConnection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local remaining = math.max(0, timerDuration - elapsed)
		local progress = remaining / timerDuration
		
		elements.timerFill.Size = UDim2.new(progress, 0, 1, 0)
		
		if remaining <= 0 then
			timerConnection:Disconnect()
			-- Auto-respawn
			promptReviveRemote:FireServer(false)
			ui:Destroy()
		end
	end)
	
	-- Button handlers
	elements.reviveButton.MouseButton1Click:Connect(function()
		timerConnection:Disconnect()
		promptReviveRemote:FireServer(true)
		ui:Destroy()
	end)
	
	elements.respawnButton.MouseButton1Click:Connect(function()
		timerConnection:Disconnect()
		promptReviveRemote:FireServer(false)
		ui:Destroy()
	end)
	
	-- Animate entrance
	elements.container.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(elements.container, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.new(0.4, 0, 0.35, 0)
	}):Play()
end)

print("ReviveUI loaded!")