--[[
	SLITHER.IO MENU CLIENT SCRIPT
	BEAUTIFUL SLITHER.IO MENU V3.0 - DARK & RELIABLE
	
	This script creates a beautiful, reliable slither.io-style menu for Roblox with:
	- Dark, sleek design
	- Fixed UI disappearing issues
	- Enhanced spawn reliability
	- Animated particles
	- Glass morphism effects
	- Premium buttons
--]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

-- Constants
local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Hide default leaderboard
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- Screen setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SlitherIOMenu"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true

-- Track active sounds
local activeSounds = {}

-- Function to create click sound
local function playClickSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/uuhhh.mp3"
	sound.Volume = 0.5
	sound.Parent = SoundService
	sound:Play()
	activeSounds[sound] = true
	sound.Ended:Connect(function()
		activeSounds[sound] = nil
		sound:Destroy()
	end)
end

-- Wait for events
local Events = ReplicatedStorage:WaitForChild("Events", 5)
local spawnSnakeRemote = Events and Events:FindFirstChild("SpawnSnake")
local respawnSnakeRemote = Events and Events:FindFirstChild("RespawnSnake")
local setGraphicsModeRemote = Events and Events:FindFirstChild("SetGraphicsMode")

-- UI State
local menuVisible = true
local settingsPanelOpen = false
local sharePanelOpen = false
local selectedSkin = "Green"

-- Create main container
local mainContainer = Instance.new("Frame")
mainContainer.Name = "MainContainer"
mainContainer.Size = UDim2.new(1, 0, 1, 0)
mainContainer.Position = UDim2.new(0, 0, 0, 0)
mainContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainContainer.BorderSizePixel = 0
mainContainer.Parent = screenGui

-- Create animated background
local animatedBg = Instance.new("Frame")
animatedBg.Name = "AnimatedBackground"
animatedBg.Size = UDim2.new(1, 0, 1, 0)
animatedBg.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
animatedBg.BorderSizePixel = 0
animatedBg.Parent = mainContainer

-- Add gradient overlay
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 30)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 30, 50)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 30))
})
gradient.Rotation = 45
gradient.Parent = animatedBg

-- Particles container
local particlesFrame = Instance.new("Frame")
particlesFrame.Name = "Particles"
particlesFrame.Size = UDim2.new(1, 0, 1, 0)
particlesFrame.BackgroundTransparency = 1
particlesFrame.Parent = animatedBg

-- Create floating particles
local particles = {}
for i = 1, 30 do
	local particle = Instance.new("Frame")
	particle.Size = UDim2.new(0, math.random(3, 8), 0, math.random(3, 8))
	particle.Position = UDim2.new(math.random(), 0, math.random(), 0)
	particle.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
	particle.BorderSizePixel = 0
	particle.Parent = particlesFrame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = particle
	
	-- Store particle data
	particles[i] = {
		frame = particle,
		speed = math.random(10, 30) / 100,
		offset = math.random() * math.pi * 2
	}
end

-- Animate particles
local particleConnection
particleConnection = RunService.Heartbeat:Connect(function()
	if not screenGui.Parent then
		particleConnection:Disconnect()
		return
	end
	
	for _, data in ipairs(particles) do
		local time = tick() * data.speed + data.offset
		local yPos = (math.sin(time) + 1) / 2
		data.frame.Position = UDim2.new(data.frame.Position.X.Scale, 0, yPos, 0)
		data.frame.BackgroundTransparency = 0.7 + math.sin(time * 2) * 0.2
	end
end)

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Text = "SLITHER.IO"
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.TextStrokeTransparency = 0.5
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.6, 0, 0.15, 0)
title.Position = UDim2.new(0.2, 0, 0.05, 0)
title.Parent = mainContainer

-- Add glow effect to title
local titleGlow = Instance.new("ImageLabel")
titleGlow.Name = "Glow"
titleGlow.Image = "rbxasset://textures/ui/LuaChat/9-slice/glow.png"
titleGlow.ImageColor3 = Color3.fromRGB(100, 200, 255)
titleGlow.ImageTransparency = 0.5
titleGlow.ScaleType = Enum.ScaleType.Slice
titleGlow.SliceCenter = Rect.new(31, 31, 33, 33)
titleGlow.Size = UDim2.new(1.2, 0, 1.5, 0)
titleGlow.Position = UDim2.new(-0.1, 0, -0.25, 0)
titleGlow.BackgroundTransparency = 1
titleGlow.Parent = title

-- Create menu content frame
local menuContent = Instance.new("Frame")
menuContent.Name = "MenuContent"
menuContent.Size = UDim2.new(0.8, 0, 0.7, 0)
menuContent.Position = UDim2.new(0.1, 0, 0.25, 0)
menuContent.BackgroundTransparency = 1
menuContent.Parent = mainContainer

-- Function to create premium button
local function createPremiumButton(text, position, color, onClick)
	local button = Instance.new("TextButton")
	button.Name = text .. "Button"
	button.Text = text
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = color or Color3.fromRGB(50, 150, 255)
	button.Size = UDim2.new(0.35, 0, 0.12, 0)
	button.Position = position
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Parent = menuContent
	
	-- Glass effect
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Size = UDim2.new(1, 0, 0.5, 0)
	glass.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	glass.BackgroundTransparency = 0.9
	glass.BorderSizePixel = 0
	glass.Parent = button
	
	local glassGradient = Instance.new("UIGradient")
	glassGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	})
	glassGradient.Rotation = 90
	glassGradient.Parent = glass
	
	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button
	
	local glassCorner = Instance.new("UICorner")
	glassCorner.CornerRadius = UDim.new(0, 12)
	glassCorner.Parent = glass
	
	-- Shadow
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.Image = "rbxasset://textures/ui/LuaChat/9-slice/glow.png"
	shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	shadow.ImageTransparency = 0.5
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(31, 31, 33, 33)
	shadow.Size = UDim2.new(1.1, 0, 1.2, 0)
	shadow.Position = UDim2.new(-0.05, 0, -0.05, 0)
	shadow.BackgroundTransparency = 1
	shadow.ZIndex = 0
	shadow.Parent = button
	
	-- Hover effect
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		TweenService:Create(button, TweenInfo.new(0.2), {
			Size = UDim2.new(0.37, 0, 0.13, 0),
			BackgroundColor3 = Color3.fromRGB(
				math.min(255, button.BackgroundColor3.R * 255 + 30),
				math.min(255, button.BackgroundColor3.G * 255 + 30),
				math.min(255, button.BackgroundColor3.B * 255 + 30)
			)
		}):Play()
	end)
	
	button.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(button, TweenInfo.new(0.2), {
			Size = UDim2.new(0.35, 0, 0.12, 0),
			BackgroundColor3 = color or Color3.fromRGB(50, 150, 255)
		}):Play()
	end)
	
	button.MouseButton1Click:Connect(function()
		playClickSound()
		-- Click animation
		TweenService:Create(button, TweenInfo.new(0.1), {
			Size = UDim2.new(0.33, 0, 0.11, 0)
		}):Play()
		wait(0.1)
		TweenService:Create(button, TweenInfo.new(0.1), {
			Size = hovering and UDim2.new(0.37, 0, 0.13, 0) or UDim2.new(0.35, 0, 0.12, 0)
		}):Play()
		
		if onClick then
			onClick()
		end
	end)
	
	return button
end

-- Play button
local playButton = createPremiumButton(
	"PLAY",
	UDim2.new(0.325, 0, 0.2, 0),
	Color3.fromRGB(76, 217, 100),
	function()
		if spawnSnakeRemote then
			-- Hide menu first
			menuVisible = false
			mainContainer.Visible = false
			
			-- Fire spawn remote
			spawnSnakeRemote:FireServer()
			
			-- Set attribute to track we're playing
			player:SetAttribute("IsPlaying", true)
		end
	end
)

-- Settings button
local settingsButton = createPremiumButton(
	"SETTINGS",
	UDim2.new(0.05, 0, 0.4, 0),
	Color3.fromRGB(255, 170, 50),
	function()
		settingsPanelOpen = not settingsPanelOpen
		if settingsPanelOpen then
			-- Open settings panel
			createSettingsPanel()
		else
			-- Close settings panel
			local panel = menuContent:FindFirstChild("SettingsPanel")
			if panel then
				panel:Destroy()
			end
		end
	end
)

-- Share button
local shareButton = createPremiumButton(
	"SHARE",
	UDim2.new(0.6, 0, 0.4, 0),
	Color3.fromRGB(150, 100, 255),
	function()
		sharePanelOpen = not sharePanelOpen
		if sharePanelOpen then
			-- Open share panel
			createSharePanel()
		else
			-- Close share panel
			local panel = menuContent:FindFirstChild("SharePanel")
			if panel then
				panel:Destroy()
			end
		end
	end
)

-- Shop button (placeholder)
local shopButton = createPremiumButton(
	"SHOP",
	UDim2.new(0.05, 0, 0.6, 0),
	Color3.fromRGB(255, 100, 150),
	function()
		-- Shop functionality to be implemented
		print("Shop clicked")
	end
)

-- Graphics button
local graphicsQuality = "High"
local graphicsButton = createPremiumButton(
	"GRAPHICS: HIGH",
	UDim2.new(0.6, 0, 0.6, 0),
	Color3.fromRGB(100, 200, 255),
	function()
		-- Cycle through graphics modes
		if graphicsQuality == "High" then
			graphicsQuality = "Medium"
			graphicsButton.Text = "GRAPHICS: MEDIUM"
		elseif graphicsQuality == "Medium" then
			graphicsQuality = "Low"
			graphicsButton.Text = "GRAPHICS: LOW"
		else
			graphicsQuality = "High"
			graphicsButton.Text = "GRAPHICS: HIGH"
		end
		
		-- Send to server
		if setGraphicsModeRemote then
			setGraphicsModeRemote:FireServer(graphicsQuality)
		end
		
		-- Store preference
		player:SetAttribute("GraphicsQuality", graphicsQuality)
	end
)

-- Skin selector
local skinFrame = Instance.new("Frame")
skinFrame.Name = "SkinSelector"
skinFrame.Size = UDim2.new(0.9, 0, 0.15, 0)
skinFrame.Position = UDim2.new(0.05, 0, 0.8, 0)
skinFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
skinFrame.BorderSizePixel = 0
skinFrame.Parent = menuContent

local skinCorner = Instance.new("UICorner")
skinCorner.CornerRadius = UDim.new(0, 12)
skinCorner.Parent = skinFrame

local skinLabel = Instance.new("TextLabel")
skinLabel.Text = "SELECT SKIN:"
skinLabel.Font = Enum.Font.FredokaOne
skinLabel.TextScaled = true
skinLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
skinLabel.BackgroundTransparency = 1
skinLabel.Size = UDim2.new(0.25, 0, 0.4, 0)
skinLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
skinLabel.Parent = skinFrame

-- Skin options
local skins = {
	{name = "Green", color = Color3.fromRGB(76, 217, 100)},
	{name = "Blue", color = Color3.fromRGB(64, 150, 255)},
	{name = "Red", color = Color3.fromRGB(255, 89, 89)},
	{name = "Purple", color = Color3.fromRGB(191, 89, 255)},
	{name = "Yellow", color = Color3.fromRGB(255, 221, 89)},
	{name = "Pink", color = Color3.fromRGB(255, 170, 255)},
	{name = "Black", color = Color3.fromRGB(40, 40, 40)},
	{name = "White", color = Color3.fromRGB(240, 240, 240)},
	{name = "Rainbow", color = Color3.fromRGB(255, 0, 0)},
	{name = "Gold", color = Color3.fromRGB(255, 215, 0)}
}

local skinButtons = Instance.new("Frame")
skinButtons.Name = "SkinButtons"
skinButtons.Size = UDim2.new(0.7, 0, 0.8, 0)
skinButtons.Position = UDim2.new(0.25, 0, 0.1, 0)
skinButtons.BackgroundTransparency = 1
skinButtons.Parent = skinFrame

local skinLayout = Instance.new("UIListLayout")
skinLayout.FillDirection = Enum.FillDirection.Horizontal
skinLayout.Padding = UDim.new(0, 5)
skinLayout.Parent = skinButtons

for _, skin in ipairs(skins) do
	local skinButton = Instance.new("TextButton")
	skinButton.Name = skin.name .. "Skin"
	skinButton.Size = UDim2.new(0.095, 0, 1, 0)
	skinButton.BackgroundColor3 = skin.color
	skinButton.Text = ""
	skinButton.BorderSizePixel = 0
	skinButton.Parent = skinButtons
	
	local skinButtonCorner = Instance.new("UICorner")
	skinButtonCorner.CornerRadius = UDim.new(0, 8)
	skinButtonCorner.Parent = skinButton
	
	-- Selection indicator
	if skin.name == selectedSkin then
		local selection = Instance.new("UIStroke")
		selection.Name = "Selection"
		selection.Color = Color3.fromRGB(255, 255, 255)
		selection.Thickness = 3
		selection.Parent = skinButton
	end
	
	skinButton.MouseButton1Click:Connect(function()
		playClickSound()
		-- Remove old selection
		for _, btn in pairs(skinButtons:GetChildren()) do
			if btn:IsA("TextButton") then
				local oldSelection = btn:FindFirstChild("Selection")
				if oldSelection then
					oldSelection:Destroy()
				end
			end
		end
		
		-- Add new selection
		local selection = Instance.new("UIStroke")
		selection.Name = "Selection"
		selection.Color = Color3.fromRGB(255, 255, 255)
		selection.Thickness = 3
		selection.Parent = skinButton
		
		selectedSkin = skin.name
		player:SetAttribute("SelectedSkin", selectedSkin)
	end)
end

-- Leaderboard
local leaderboard = Instance.new("Frame")
leaderboard.Name = "Leaderboard"
leaderboard.Size = UDim2.new(0.25, 0, 0.4, 0)
leaderboard.Position = UDim2.new(0.72, 0, 0.05, 0)
leaderboard.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
leaderboard.BackgroundTransparency = 0.3
leaderboard.BorderSizePixel = 0
leaderboard.Parent = mainContainer

local leaderboardCorner = Instance.new("UICorner")
leaderboardCorner.CornerRadius = UDim.new(0, 12)
leaderboardCorner.Parent = leaderboard

local leaderboardTitle = Instance.new("TextLabel")
leaderboardTitle.Text = "TOP PLAYERS"
leaderboardTitle.Font = Enum.Font.FredokaOne
leaderboardTitle.TextScaled = true
leaderboardTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
leaderboardTitle.BackgroundTransparency = 1
leaderboardTitle.Size = UDim2.new(0.9, 0, 0.15, 0)
leaderboardTitle.Position = UDim2.new(0.05, 0, 0.05, 0)
leaderboardTitle.Parent = leaderboard

-- Server info
local serverInfo = Instance.new("Frame")
serverInfo.Name = "ServerInfo"
serverInfo.Size = UDim2.new(0.25, 0, 0.15, 0)
serverInfo.Position = UDim2.new(0.03, 0, 0.85, 0)
serverInfo.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
serverInfo.BackgroundTransparency = 0.3
serverInfo.BorderSizePixel = 0
serverInfo.Parent = mainContainer

local serverCorner = Instance.new("UICorner")
serverCorner.CornerRadius = UDim.new(0, 12)
serverCorner.Parent = serverInfo

local playersLabel = Instance.new("TextLabel")
playersLabel.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
playersLabel.Font = Enum.Font.FredokaOne
playersLabel.TextScaled = true
playersLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
playersLabel.BackgroundTransparency = 1
playersLabel.Size = UDim2.new(0.9, 0, 0.45, 0)
playersLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
playersLabel.Parent = serverInfo

-- Update player count
Players.PlayerAdded:Connect(function()
	playersLabel.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
end)

Players.PlayerRemoving:Connect(function()
	wait(0.1)
	playersLabel.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
end)

-- Settings Panel Creation
function createSettingsPanel()
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.new(0.5, 0, 0.6, 0)
	panel.Position = UDim2.new(0.25, 0, 0.2, 0)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Parent = menuContent
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel
	
	local panelTitle = Instance.new("TextLabel")
	panelTitle.Text = "SETTINGS"
	panelTitle.Font = Enum.Font.FredokaOne
	panelTitle.TextScaled = true
	panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Size = UDim2.new(0.8, 0, 0.15, 0)
	panelTitle.Position = UDim2.new(0.1, 0, 0.05, 0)
	panelTitle.Parent = panel
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Text = "X"
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.BackgroundColor3 = Color3.fromRGB(255, 89, 89)
	closeButton.Size = UDim2.new(0.1, 0, 0.1, 0)
	closeButton.Position = UDim2.new(0.85, 0, 0.05, 0)
	closeButton.BorderSizePixel = 0
	closeButton.Parent = panel
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton
	
	closeButton.MouseButton1Click:Connect(function()
		playClickSound()
		settingsPanelOpen = false
		panel:Destroy()
	end)
end

-- Share Panel Creation
function createSharePanel()
	local panel = Instance.new("Frame")
	panel.Name = "SharePanel"
	panel.Size = UDim2.new(0.5, 0, 0.4, 0)
	panel.Position = UDim2.new(0.25, 0, 0.3, 0)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Parent = menuContent
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel
	
	local panelTitle = Instance.new("TextLabel")
	panelTitle.Text = "SHARE GAME"
	panelTitle.Font = Enum.Font.FredokaOne
	panelTitle.TextScaled = true
	panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Size = UDim2.new(0.8, 0, 0.2, 0)
	panelTitle.Position = UDim2.new(0.1, 0, 0.05, 0)
	panelTitle.Parent = panel
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Text = "X"
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.BackgroundColor3 = Color3.fromRGB(255, 89, 89)
	closeButton.Size = UDim2.new(0.1, 0, 0.15, 0)
	closeButton.Position = UDim2.new(0.85, 0, 0.05, 0)
	closeButton.BorderSizePixel = 0
	closeButton.Parent = panel
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton
	
	closeButton.MouseButton1Click:Connect(function()
		playClickSound()
		sharePanelOpen = false
		panel:Destroy()
	end)
end

-- Function to create menu
local function createMenu(onPlay)
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	-- Set initial skin
	player:SetAttribute("SelectedSkin", selectedSkin)
	
	-- Show menu
	mainContainer.Visible = true
	menuVisible = true
end

-- Character death handling
local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	-- Handle death
	humanoid.Died:Connect(function()
		-- Wait a bit for death to process
		wait(0.5)
		
		-- Show menu again on death
		if not menuVisible then
			menuVisible = true
			mainContainer.Visible = true
			
			-- Clear playing state
			player:SetAttribute("IsPlaying", false)
		end
	end)
end

-- Connect character events
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Clean up on remove
screenGui.AncestryChanged:Connect(function()
	if not screenGui.Parent then
		-- Clean up connections
		if particleConnection then
			particleConnection:Disconnect()
		end
		
		-- Clean up sounds
		for sound, _ in pairs(activeSounds) do
			if sound and sound.Parent then
				sound:Destroy()
			end
		end
		activeSounds = {}
	end
end)

-- Initialize menu
createMenu()

-- Return module
return {
	Show = function()
		mainContainer.Visible = true
		menuVisible = true
	end,
	Hide = function()
		mainContainer.Visible = false
		menuVisible = false
	end,
	IsVisible = function()
		return menuVisible
	end
}