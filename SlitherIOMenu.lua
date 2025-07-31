--[[
	BEAUTIFUL SLITHER.IO MENU V3.0 - DARK & RELIABLE
	
	FEATURES:
	- Dark, sleek design with animated particles
	- Glass morphism effects
	- Premium UI/UX with smooth animations
	- Fixed UI disappearing issues
	- Enhanced spawn reliability
	- Perfect integration with snake system
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hide default leaderboard
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- Get remotes
local remotesFolder = ReplicatedStorage:WaitForChild("SnakeRemotes")
local spawnRemote = remotesFolder:WaitForChild("SpawnSnake")
local respawnRemote = remotesFolder:WaitForChild("RespawnSnake")
local graphicsRemote = remotesFolder:FindFirstChild("SetGraphicsMode")

-- Settings Panel Handler
local settingsPanel, sharePanel

-- Graphics mode state
local currentGraphicsMode = "High"

-- Function to create the menu
local function createMenu(onPlay)
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SlitherIOMenu"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1
	screenGui.Parent = playerGui
	
	-- Background (Dark gradient)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	background.BorderSizePixel = 0
	background.Parent = screenGui
	
	-- Gradient overlay
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 45
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 25)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 20, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 45))
	})
	gradient.Parent = background
	
	-- Animated particles container
	local particleContainer = Instance.new("Frame")
	particleContainer.Name = "ParticleContainer"
	particleContainer.Size = UDim2.new(1, 0, 1, 0)
	particleContainer.BackgroundTransparency = 1
	particleContainer.Parent = background
	
	-- Create animated particles
	local particles = {}
	for i = 1, 30 do
		local particle = Instance.new("Frame")
		particle.Size = UDim2.new(0, math.random(2, 6), 0, math.random(2, 6))
		particle.Position = UDim2.new(math.random(), 0, math.random(), 0)
		particle.BackgroundColor3 = Color3.fromRGB(76, 217, 100)
		particle.BackgroundTransparency = 0.7
		particle.BorderSizePixel = 0
		particle.Parent = particleContainer
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = particle
		
		-- Store particle data
		particles[i] = {
			frame = particle,
			speed = math.random() * 0.5 + 0.5,
			startY = particle.Position.Y.Scale
		}
	end
	
	-- Animate particles
	RunService.Heartbeat:Connect(function(dt)
		for _, data in ipairs(particles) do
			local currentY = data.frame.Position.Y.Scale
			local newY = currentY - (data.speed * dt * 0.1)
			
			if newY < -0.1 then
				newY = 1.1
				data.frame.Position = UDim2.new(math.random(), 0, newY, 0)
			else
				data.frame.Position = UDim2.new(data.frame.Position.X.Scale, 0, newY, 0)
			end
		end
	end)
	
	-- Main container (Glass morphism)
	local mainContainer = Instance.new("Frame")
	mainContainer.Name = "MainContainer"
	mainContainer.Size = UDim2.new(0.9, 0, 0.85, 0)
	mainContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	mainContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mainContainer.BackgroundTransparency = 0.3
	mainContainer.BorderSizePixel = 0
	mainContainer.Parent = screenGui
	
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 20)
	containerCorner.Parent = mainContainer
	
	-- Glass effect
	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = Color3.fromRGB(76, 217, 100)
	containerStroke.Transparency = 0.8
	containerStroke.Thickness = 2
	containerStroke.Parent = mainContainer
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.8, 0, 0.15, 0)
	title.Position = UDim2.new(0.5, 0, 0.1, 0)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Text = "SLITHER.IO"
	title.TextColor3 = Color3.fromRGB(76, 217, 100)
	title.TextScaled = true
	title.Font = Enum.Font.SourceSansBold
	title.Parent = mainContainer
	
	-- Title glow
	local titleGlow = title:Clone()
	titleGlow.Name = "TitleGlow"
	titleGlow.Position = UDim2.new(0.5, 0, 0.1, 2)
	titleGlow.TextTransparency = 0.5
	titleGlow.TextColor3 = Color3.fromRGB(76, 217, 100)
	titleGlow.Parent = mainContainer
	
	-- Animate title
	local titleTween = TweenService:Create(title, 
		TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{TextColor3 = Color3.fromRGB(100, 255, 150)}
	)
	titleTween:Play()
	
	-- Center content
	local centerContent = Instance.new("Frame")
	centerContent.Name = "CenterContent"
	centerContent.Size = UDim2.new(0.4, 0, 0.7, 0)
	centerContent.Position = UDim2.new(0.5, 0, 0.55, 0)
	centerContent.AnchorPoint = Vector2.new(0.5, 0.5)
	centerContent.BackgroundTransparency = 1
	centerContent.Parent = mainContainer
	
	-- Play button
	local playButton = Instance.new("TextButton")
	playButton.Name = "PlayButton"
	playButton.Size = UDim2.new(1, 0, 0.15, 0)
	playButton.Position = UDim2.new(0.5, 0, 0.2, 0)
	playButton.AnchorPoint = Vector2.new(0.5, 0.5)
	playButton.BackgroundColor3 = Color3.fromRGB(76, 217, 100)
	playButton.Text = "PLAY"
	playButton.TextColor3 = Color3.fromRGB(10, 10, 15)
	playButton.TextScaled = true
	playButton.Font = Enum.Font.SourceSansBold
	playButton.Parent = centerContent
	
	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(0, 12)
	playCorner.Parent = playButton
	
	-- Play button hover effect
	playButton.MouseEnter:Connect(function()
		TweenService:Create(playButton, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(100, 255, 130),
			Size = UDim2.new(1.05, 0, 0.16, 0)
		}):Play()
	end)
	
	playButton.MouseLeave:Connect(function()
		TweenService:Create(playButton, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(76, 217, 100),
			Size = UDim2.new(1, 0, 0.15, 0)
		}):Play()
	end)
	
	-- Settings button
	local settingsButton = Instance.new("TextButton")
	settingsButton.Name = "SettingsButton"
	settingsButton.Size = UDim2.new(1, 0, 0.12, 0)
	settingsButton.Position = UDim2.new(0.5, 0, 0.4, 0)
	settingsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	settingsButton.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	settingsButton.Text = "SETTINGS"
	settingsButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	settingsButton.TextScaled = true
	settingsButton.Font = Enum.Font.SourceSansBold
	settingsButton.Parent = centerContent
	
	local settingsCorner = Instance.new("UICorner")
	settingsCorner.CornerRadius = UDim.new(0, 10)
	settingsCorner.Parent = settingsButton
	
	-- Share button
	local shareButton = Instance.new("TextButton")
	shareButton.Name = "ShareButton"
	shareButton.Size = UDim2.new(1, 0, 0.12, 0)
	shareButton.Position = UDim2.new(0.5, 0, 0.55, 0)
	shareButton.AnchorPoint = Vector2.new(0.5, 0.5)
	shareButton.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	shareButton.Text = "SHARE"
	shareButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	shareButton.TextScaled = true
	shareButton.Font = Enum.Font.SourceSansBold
	shareButton.Parent = centerContent
	
	local shareCorner = Instance.new("UICorner")
	shareCorner.CornerRadius = UDim.new(0, 10)
	shareCorner.Parent = shareButton
	
	-- Shop button
	local shopButton = Instance.new("TextButton")
	shopButton.Name = "ShopButton"
	shopButton.Size = UDim2.new(1, 0, 0.12, 0)
	shopButton.Position = UDim2.new(0.5, 0, 0.7, 0)
	shopButton.AnchorPoint = Vector2.new(0.5, 0.5)
	shopButton.BackgroundColor3 = Color3.fromRGB(218, 165, 32)
	shopButton.Text = "SHOP"
	shopButton.TextColor3 = Color3.fromRGB(10, 10, 15)
	shopButton.TextScaled = true
	shopButton.Font = Enum.Font.SourceSansBold
	shopButton.Parent = centerContent
	
	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 10)
	shopCorner.Parent = shopButton
	
	-- Graphics button
	local graphicsButton = Instance.new("TextButton")
	graphicsButton.Name = "GraphicsButton"
	graphicsButton.Size = UDim2.new(1, 0, 0.12, 0)
	graphicsButton.Position = UDim2.new(0.5, 0, 0.85, 0)
	graphicsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	graphicsButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	graphicsButton.Text = "Graphics: " .. currentGraphicsMode
	graphicsButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	graphicsButton.TextScaled = true
	graphicsButton.Font = Enum.Font.SourceSansBold
	graphicsButton.Parent = centerContent
	
	local graphicsCorner = Instance.new("UICorner")
	graphicsCorner.CornerRadius = UDim.new(0, 10)
	graphicsCorner.Parent = graphicsButton
	
	-- Graphics button functionality
	graphicsButton.MouseButton1Click:Connect(function()
		-- Cycle through graphics modes
		if currentGraphicsMode == "High" then
			currentGraphicsMode = "Medium"
		elseif currentGraphicsMode == "Medium" then
			currentGraphicsMode = "Low"
		else
			currentGraphicsMode = "High"
		end
		
		graphicsButton.Text = "Graphics: " .. currentGraphicsMode
		
		-- Send to server if remote exists
		if graphicsRemote then
			graphicsRemote:FireServer(currentGraphicsMode)
		end
	end)
	
	-- Secondary button hover effects
	local function addHoverEffect(button)
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.2), {
				Size = UDim2.new(1.02, 0, 0.13, 0)
			}):Play()
		end)
		
		button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.2), {
				Size = UDim2.new(1, 0, 0.12, 0)
			}):Play()
		end)
	end
	
	addHoverEffect(settingsButton)
	addHoverEffect(shareButton)
	addHoverEffect(shopButton)
	addHoverEffect(graphicsButton)
	
	-- Leaderboard
	local leaderboard = Instance.new("Frame")
	leaderboard.Name = "Leaderboard"
	leaderboard.Size = UDim2.new(0.25, 0, 0.6, 0)
	leaderboard.Position = UDim2.new(0.1, 0, 0.5, 0)
	leaderboard.AnchorPoint = Vector2.new(0.5, 0.5)
	leaderboard.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	leaderboard.BackgroundTransparency = 0.5
	leaderboard.Parent = mainContainer
	
	local leaderCorner = Instance.new("UICorner")
	leaderCorner.CornerRadius = UDim.new(0, 15)
	leaderCorner.Parent = leaderboard
	
	local leaderStroke = Instance.new("UIStroke")
	leaderStroke.Color = Color3.fromRGB(76, 217, 100)
	leaderStroke.Transparency = 0.9
	leaderStroke.Thickness = 1
	leaderStroke.Parent = leaderboard
	
	local leaderTitle = Instance.new("TextLabel")
	leaderTitle.Name = "LeaderTitle"
	leaderTitle.Size = UDim2.new(0.9, 0, 0.15, 0)
	leaderTitle.Position = UDim2.new(0.5, 0, 0.08, 0)
	leaderTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	leaderTitle.BackgroundTransparency = 1
	leaderTitle.Text = "LEADERBOARD"
	leaderTitle.TextColor3 = Color3.fromRGB(76, 217, 100)
	leaderTitle.TextScaled = true
	leaderTitle.Font = Enum.Font.SourceSansBold
	leaderTitle.Parent = leaderboard
	
	-- Server info
	local serverInfo = Instance.new("Frame")
	serverInfo.Name = "ServerInfo"
	serverInfo.Size = UDim2.new(0.25, 0, 0.25, 0)
	serverInfo.Position = UDim2.new(0.9, 0, 0.85, 0)
	serverInfo.AnchorPoint = Vector2.new(0.5, 0.5)
	serverInfo.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	serverInfo.BackgroundTransparency = 0.5
	serverInfo.Parent = mainContainer
	
	local serverCorner = Instance.new("UICorner")
	serverCorner.CornerRadius = UDim.new(0, 15)
	serverCorner.Parent = serverInfo
	
	local serverStroke = Instance.new("UIStroke")
	serverStroke.Color = Color3.fromRGB(76, 217, 100)
	serverStroke.Transparency = 0.9
	serverStroke.Thickness = 1
	serverStroke.Parent = serverInfo
	
	local serverTitle = Instance.new("TextLabel")
	serverTitle.Name = "ServerTitle"
	serverTitle.Size = UDim2.new(0.9, 0, 0.3, 0)
	serverTitle.Position = UDim2.new(0.5, 0, 0.2, 0)
	serverTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	serverTitle.BackgroundTransparency = 1
	serverTitle.Text = "SERVER INFO"
	serverTitle.TextColor3 = Color3.fromRGB(76, 217, 100)
	serverTitle.TextScaled = true
	serverTitle.Font = Enum.Font.SourceSansBold
	serverTitle.Parent = serverInfo
	
	local playerCount = Instance.new("TextLabel")
	playerCount.Name = "PlayerCount"
	playerCount.Size = UDim2.new(0.9, 0, 0.25, 0)
	playerCount.Position = UDim2.new(0.5, 0, 0.5, 0)
	playerCount.AnchorPoint = Vector2.new(0.5, 0.5)
	playerCount.BackgroundTransparency = 1
	playerCount.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
	playerCount.TextColor3 = Color3.fromRGB(200, 200, 200)
	playerCount.TextScaled = true
	playerCount.Font = Enum.Font.SourceSans
	playerCount.Parent = serverInfo
	
	-- Update player count
	Players.PlayerAdded:Connect(function()
		playerCount.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
	end)
	
	Players.PlayerRemoving:Connect(function()
		wait(0.1)
		playerCount.Text = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
	end)
	
	-- Settings panel creation
	settingsButton.MouseButton1Click:Connect(function()
		if settingsPanel then
			settingsPanel:Destroy()
			settingsPanel = nil
			return
		end
		
		settingsPanel = Instance.new("Frame")
		settingsPanel.Name = "SettingsPanel"
		settingsPanel.Size = UDim2.new(0.3, 0, 0.5, 0)
		settingsPanel.Position = UDim2.new(0.35, 0, 0.5, 0)
		settingsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
		settingsPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
		settingsPanel.BackgroundTransparency = 0.2
		settingsPanel.ZIndex = 10
		settingsPanel.Parent = mainContainer
		
		local settingsPanelCorner = Instance.new("UICorner")
		settingsPanelCorner.CornerRadius = UDim.new(0, 15)
		settingsPanelCorner.Parent = settingsPanel
		
		local settingsPanelStroke = Instance.new("UIStroke")
		settingsPanelStroke.Color = Color3.fromRGB(76, 217, 100)
		settingsPanelStroke.Transparency = 0.7
		settingsPanelStroke.Thickness = 2
		settingsPanelStroke.Parent = settingsPanel
		
		-- Settings title
		local settingsTitle = Instance.new("TextLabel")
		settingsTitle.Size = UDim2.new(0.9, 0, 0.15, 0)
		settingsTitle.Position = UDim2.new(0.5, 0, 0.08, 0)
		settingsTitle.AnchorPoint = Vector2.new(0.5, 0.5)
		settingsTitle.BackgroundTransparency = 1
		settingsTitle.Text = "SETTINGS"
		settingsTitle.TextColor3 = Color3.fromRGB(76, 217, 100)
		settingsTitle.TextScaled = true
		settingsTitle.Font = Enum.Font.SourceSansBold
		settingsTitle.Parent = settingsPanel
		
		-- Close button
		local closeButton = Instance.new("TextButton")
		closeButton.Size = UDim2.new(0.1, 0, 0.1, 0)
		closeButton.Position = UDim2.new(0.95, 0, 0.05, 0)
		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		closeButton.Text = "X"
		closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeButton.TextScaled = true
		closeButton.Font = Enum.Font.SourceSansBold
		closeButton.Parent = settingsPanel
		
		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 5)
		closeCorner.Parent = closeButton
		
		closeButton.MouseButton1Click:Connect(function()
			settingsPanel:Destroy()
			settingsPanel = nil
		end)
		
		-- Add settings content here
		local settingsInfo = Instance.new("TextLabel")
		settingsInfo.Size = UDim2.new(0.9, 0, 0.7, 0)
		settingsInfo.Position = UDim2.new(0.5, 0, 0.55, 0)
		settingsInfo.AnchorPoint = Vector2.new(0.5, 0.5)
		settingsInfo.BackgroundTransparency = 1
		settingsInfo.Text = "Settings coming soon!"
		settingsInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
		settingsInfo.TextScaled = true
		settingsInfo.Font = Enum.Font.SourceSans
		settingsInfo.Parent = settingsPanel
	end)
	
	-- Share panel creation
	shareButton.MouseButton1Click:Connect(function()
		if sharePanel then
			sharePanel:Destroy()
			sharePanel = nil
			return
		end
		
		sharePanel = Instance.new("Frame")
		sharePanel.Name = "SharePanel"
		sharePanel.Size = UDim2.new(0.3, 0, 0.4, 0)
		sharePanel.Position = UDim2.new(0.65, 0, 0.5, 0)
		sharePanel.AnchorPoint = Vector2.new(0.5, 0.5)
		sharePanel.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
		sharePanel.BackgroundTransparency = 0.2
		sharePanel.ZIndex = 10
		sharePanel.Parent = mainContainer
		
		local sharePanelCorner = Instance.new("UICorner")
		sharePanelCorner.CornerRadius = UDim.new(0, 15)
		sharePanelCorner.Parent = sharePanel
		
		local sharePanelStroke = Instance.new("UIStroke")
		sharePanelStroke.Color = Color3.fromRGB(76, 217, 100)
		sharePanelStroke.Transparency = 0.7
		sharePanelStroke.Thickness = 2
		sharePanelStroke.Parent = sharePanel
		
		-- Share title
		local shareTitle = Instance.new("TextLabel")
		shareTitle.Size = UDim2.new(0.9, 0, 0.2, 0)
		shareTitle.Position = UDim2.new(0.5, 0, 0.1, 0)
		shareTitle.AnchorPoint = Vector2.new(0.5, 0.5)
		shareTitle.BackgroundTransparency = 1
		shareTitle.Text = "SHARE GAME"
		shareTitle.TextColor3 = Color3.fromRGB(76, 217, 100)
		shareTitle.TextScaled = true
		shareTitle.Font = Enum.Font.SourceSansBold
		shareTitle.Parent = sharePanel
		
		-- Close button
		local closeButton = Instance.new("TextButton")
		closeButton.Size = UDim2.new(0.1, 0, 0.1, 0)
		closeButton.Position = UDim2.new(0.95, 0, 0.05, 0)
		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		closeButton.Text = "X"
		closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeButton.TextScaled = true
		closeButton.Font = Enum.Font.SourceSansBold
		closeButton.Parent = sharePanel
		
		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 5)
		closeCorner.Parent = closeButton
		
		closeButton.MouseButton1Click:Connect(function()
			sharePanel:Destroy()
			sharePanel = nil
		end)
		
		-- Share info
		local shareInfo = Instance.new("TextLabel")
		shareInfo.Size = UDim2.new(0.9, 0, 0.6, 0)
		shareInfo.Position = UDim2.new(0.5, 0, 0.6, 0)
		shareInfo.AnchorPoint = Vector2.new(0.5, 0.5)
		shareInfo.BackgroundTransparency = 1
		shareInfo.Text = "Invite your friends to play!"
		shareInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
		shareInfo.TextScaled = true
		shareInfo.Font = Enum.Font.SourceSans
		shareInfo.Parent = sharePanel
	end)
	
	-- Play button functionality
	playButton.MouseButton1Click:Connect(function()
		print("Play button clicked!")
		-- Clear any panels
		if settingsPanel then
			settingsPanel:Destroy()
			settingsPanel = nil
		end
		if sharePanel then
			sharePanel:Destroy()
			sharePanel = nil
		end
		
		-- Hide the menu with fade animation
		TweenService:Create(screenGui, TweenInfo.new(0.5), {
			GroupTransparency = 1
		}):Play()
		
		wait(0.5)
		screenGui:Destroy()
		
		-- Callback
		if onPlay then
			onPlay()
		end
		
		-- Fire the spawn remote
		spawnRemote:FireServer()
		print("Spawn remote fired!")
	end)
	
	-- Shop button functionality (placeholder)
	shopButton.MouseButton1Click:Connect(function()
		-- TODO: Implement shop
		print("Shop button clicked - Coming soon!")
	end)
	
	return screenGui
end

-- Show menu on character death
local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	humanoid.Died:Connect(function()
		print("Player died - showing menu")
		
		-- Small delay to ensure death is processed
		wait(0.5)
		
		-- Create menu on death
		createMenu(function()
			print("Respawning player...")
			respawnRemote:FireServer()
		end)
	end)
end

-- Initial menu display
createMenu(function()
	print("Initial spawn")
end)

-- Connect character added
player.CharacterAdded:Connect(onCharacterAdded)

-- Also handle if character already exists
if player.Character then
	onCharacterAdded(player.Character)
end

print("SlitherIO Menu V3.0 loaded!")