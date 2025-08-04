-- ClientSnakeHandler.lua
-- Modern client-side snake handler with prediction and visual effects
-- Place in StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

-- Modern APIs
local osclock = os.clock
local taskwait = task.wait
local taskspawn = task.spawn

-- Get local player
local localPlayer = Players.LocalPlayer

-- Wait for remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local collisionReport = remotes:WaitForChild("CollisionReport")
local snakeDied = remotes:WaitForChild("SnakeDied")
local requestRespawn = remotes:WaitForChild("RequestRespawn")
local updateSnakeState = remotes:WaitForChild("UpdateSnakeState")

-- === CLIENT SNAKE HANDLER ===
local ClientSnakeHandler = {}
ClientSnakeHandler.__index = ClientSnakeHandler

-- Constants
local CONSTANTS = {
	-- Collision
	HEAD_COLLISION_SIZE = Vector3.new(4, 4, 4),
	BODY_COLLISION_SIZE = Vector3.new(3, 3, 3),
	PREDICTION_CHECK_RATE = 60, -- Hz (every frame)
	
	-- Visual
	DEATH_EFFECT_DURATION = 1,
	PARTICLE_LIFETIME = 2,
	
	-- Audio
	COLLISION_SOUND_VOLUME = 0.5,
	DEATH_SOUND_VOLUME = 0.7
}

function ClientSnakeHandler.new()
	local self = setmetatable({}, ClientSnakeHandler)
	
	-- State tracking
	self._localSnake = nil
	self._otherSnakes = {}
	self._isDead = false
	self._lastCollisionTime = 0
	
	-- Visual effects cache
	self._effectsCache = {}
	
	-- Initialize
	self:_initialize()
	
	return self
end

function ClientSnakeHandler:_initialize()
	-- Connect to remote events
	updateSnakeState.OnClientEvent:Connect(function(player, state, data)
		self:_onSnakeStateUpdate(player, state, data)
	end)
	
	snakeDied.OnClientEvent:Connect(function(player, deathData)
		self:_onSnakeDied(player, deathData)
	end)
	
	-- Set up local collision prediction
	self:_setupCollisionPrediction()
	
	-- Set up respawn UI
	self:_setupRespawnUI()
end

-- === COLLISION PREDICTION ===
function ClientSnakeHandler:_setupCollisionPrediction()
	-- Run collision checks on RenderStepped for smooth prediction
	self._predictionConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if self._localSnake and not self._isDead then
			self:_predictCollisions()
		end
	end)
end

function ClientSnakeHandler:_predictCollisions()
	local character = localPlayer.Character
	if not character then return end
	
	local head = character:FindFirstChild("HumanoidRootPart")
	if not head then return end
	
	-- Prepare spatial query
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {character}
	
	-- Check for collisions
	local hits = workspace:GetPartBoundsInBox(
		head.CFrame, 
		CONSTANTS.HEAD_COLLISION_SIZE, 
		params
	)
	
	-- Process hits
	for _, hitPart in ipairs(hits) do
		local hitPlayer = self:_getPlayerFromPart(hitPart)
		if hitPlayer and hitPlayer ~= localPlayer then
			-- Check cooldown
			local currentTime = osclock()
			if currentTime - self._lastCollisionTime > 0.5 then
				self._lastCollisionTime = currentTime
				
				-- Play immediate visual feedback
				self:_playCollisionEffect(head.Position)
				
				-- Report to server
				collisionReport:FireServer({
					hitPlayer = hitPlayer,
					hitPosition = hitPart.Position,
					isHeadCollision = self:_isHeadPart(hitPart)
				})
			end
		end
	end
end

-- === VISUAL EFFECTS ===
function ClientSnakeHandler:_playCollisionEffect(position)
	-- Create impact particles
	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Parent = workspace.Terrain
	
	local particle = Instance.new("ParticleEmitter")
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Rate = 100
	particle.Lifetime = NumberRange.new(0.5, 1)
	particle.VelocityInheritance = 0
	particle.EmissionDirection = Enum.NormalId.Top
	particle.Speed = NumberRange.new(10, 20)
	particle.SpreadAngle = Vector2.new(360, 360)
	particle.Parent = attachment
	
	-- Play sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_water_low.mp3"
	sound.Volume = CONSTANTS.COLLISION_SOUND_VOLUME
	sound.Parent = attachment
	sound:Play()
	
	-- Clean up after effect
	taskspawn(function()
		taskwait(0.1)
		particle.Enabled = false
		taskwait(CONSTANTS.PARTICLE_LIFETIME)
		attachment:Destroy()
	end)
end

function ClientSnakeHandler:_onSnakeDied(player, deathData)
	-- Play death effects at the position
	self:_playDeathEffect(deathData.position)
	
	-- If it's the local player, show respawn UI
	if player == localPlayer then
		self._isDead = true
		self:_showRespawnUI()
	end
end

function ClientSnakeHandler:_playDeathEffect(position)
	-- Create explosion effect
	local part = Instance.new("Part")
	part.Name = "DeathEffect"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Position = position
	part.Parent = workspace
	
	-- Multiple particle emitters for dramatic effect
	for i = 1, 3 do
		local attachment = Instance.new("Attachment")
		attachment.Parent = part
		
		local particle = Instance.new("ParticleEmitter")
		particle.Texture = "rbxasset://textures/particles/smoke_main.dds"
		particle.Rate = 200
		particle.Lifetime = NumberRange.new(1, 2)
		particle.VelocityInheritance = 0
		particle.EmissionDirection = Enum.NormalId.Top
		particle.Speed = NumberRange.new(20, 40)
		particle.SpreadAngle = Vector2.new(360, 360)
		particle.Color = ColorSequence.new(Color3.new(1, 0.5, 0))
		particle.Parent = attachment
	end
	
	-- Death sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = CONSTANTS.DEATH_SOUND_VOLUME
	sound.Parent = part
	sound:Play()
	
	-- Clean up
	taskspawn(function()
		taskwait(CONSTANTS.DEATH_EFFECT_DURATION)
		part:Destroy()
	end)
end

-- === RESPAWN UI ===
function ClientSnakeHandler:_setupRespawnUI()
	-- Create respawn GUI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RespawnUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = localPlayer.PlayerGui
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.3, 0, 0.2, 0)
	frame.Position = UDim2.new(0.35, 0, 0.4, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	
	-- Modern UI corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "You Died!"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.Parent = frame
	
	local respawnButton = Instance.new("TextButton")
	respawnButton.Size = UDim2.new(0.6, 0, 0.3, 0)
	respawnButton.Position = UDim2.new(0.2, 0, 0.6, 0)
	respawnButton.BackgroundColor3 = Color3.new(0.2, 0.8, 0.2)
	respawnButton.Text = "Respawn"
	respawnButton.TextColor3 = Color3.new(1, 1, 1)
	respawnButton.TextScaled = true
	respawnButton.Font = Enum.Font.SourceSans
	respawnButton.Parent = frame
	
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = respawnButton
	
	-- Button functionality
	respawnButton.MouseButton1Click:Connect(function()
		requestRespawn:FireServer()
		screenGui.Enabled = false
		self._isDead = false
	end)
	
	self._respawnUI = screenGui
end

function ClientSnakeHandler:_showRespawnUI()
	if self._respawnUI then
		self._respawnUI.Enabled = true
	end
end

-- === UTILITY FUNCTIONS ===
function ClientSnakeHandler:_getPlayerFromPart(part)
	-- Check if part belongs to a character
	local humanoid = part.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return Players:GetPlayerFromCharacter(part.Parent)
	end
	
	-- Check if it's a snake segment (would need naming convention)
	if part.Name:match("Segment") then
		-- Extract player name from model name (e.g., "Snake_PlayerName")
		local model = part.Parent
		if model and model.Name:match("Snake_") then
			local playerName = model.Name:gsub("Snake_", "")
			return Players:FindFirstChild(playerName)
		end
	end
	
	return nil
end

function ClientSnakeHandler:_isHeadPart(part)
	return part.Name == "HumanoidRootPart" or part.Name:match("Head")
end

function ClientSnakeHandler:_onSnakeStateUpdate(player, state, data)
	if state == "spawned" then
		if player == localPlayer then
			self._localSnake = data
			self._isDead = false
		else
			self._otherSnakes[player] = data
		end
	elseif state == "destroyed" then
		if player == localPlayer then
			self._localSnake = nil
		else
			self._otherSnakes[player] = nil
		end
	end
end

-- === CLEANUP ===
function ClientSnakeHandler:Destroy()
	if self._predictionConnection then
		self._predictionConnection:Disconnect()
	end
	
	if self._respawnUI then
		self._respawnUI:Destroy()
	end
end

-- Initialize
return ClientSnakeHandler.new()