-- SnakeCollisionHandler_Modern.lua
-- A professional-grade collision handling system following 2024-2025 Roblox best practices
-- Implements: Spatial queries, Trove pattern, Modern APIs, Client-Server hybrid model

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

-- Modern API replacements
local osclock = os.clock
local taskwait = task.wait
local taskspawn = task.spawn
local taskdefer = task.defer

-- === TROVE PATTERN IMPLEMENTATION ===
-- Manages lifecycle of all resources to prevent memory leaks
local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({
		_objects = {},
		_cleaning = false
	}, Trove)
end

function Trove:Add(object)
	if self._cleaning then
		error("Cannot add to Trove while cleaning")
	end
	
	table.insert(self._objects, object)
	return object
end

function Trove:AddPromise(promise)
	if promise.cancel then
		self:Add(function()
			promise:cancel()
		end)
	end
	return promise
end

function Trove:Clean()
	if self._cleaning then
		return
	end
	
	self._cleaning = true
	
	-- Clean in reverse order (LIFO)
	for i = #self._objects, 1, -1 do
		local object = self._objects[i]
		local objectType = typeof(object)
		
		if objectType == "function" then
			object()
		elseif objectType == "RBXScriptConnection" then
			object:Disconnect()
		elseif objectType == "Instance" then
			object:Destroy()
		elseif objectType == "table" and object.Destroy then
			object:Destroy()
		elseif objectType == "table" and object.Clean then
			object:Clean()
		end
	end
	
	table.clear(self._objects)
end

Trove.Destroy = Trove.Clean

-- === MODULE DEFINITION ===
local SnakeCollisionHandler = {}
SnakeCollisionHandler.__index = SnakeCollisionHandler

-- Constants
local CONSTANTS = {
	-- Collision
	HEAD_COLLISION_SIZE = Vector3.new(4, 4, 4),
	BODY_COLLISION_SIZE = Vector3.new(3, 3, 3),
	COLLISION_CHECK_RATE = 20, -- Hz
	COLLISION_CHECK_INTERVAL = 1 / 20,
	
	-- Optimization
	SPATIAL_QUERY_DISTANCE = 100,
	MAX_COLLISION_CHECKS_PER_FRAME = 50,
	
	-- Security
	MIN_TIME_BETWEEN_COLLISIONS = 0.5,
	MAX_COLLISION_REPORT_DISTANCE = 10,
	
	-- Death
	DEATH_CLEANUP_DELAY = 0.1,
	ORB_SPAWN_HEIGHT = 5,
	INVINCIBILITY_DURATION = 3
}

-- === INITIALIZATION ===
function SnakeCollisionHandler.new()
	local self = setmetatable({}, SnakeCollisionHandler)
	
	-- Core state management
	self._activeSnakes = {} -- [Player] = SnakeData
	self._snakeTroves = {} -- [Player] = Trove
	self._deadPlayers = {} -- [Player] = true
	self._invinciblePlayers = {} -- [Player] = expiryTime
	
	-- Collision tracking
	self._lastCollisionTime = {} -- [Player] = osclock()
	self._collisionCooldowns = {} -- [Player] = osclock()
	
	-- Performance optimization
	self._spatialQueryParams = OverlapParams.new()
	self._spatialQueryParams.FilterType = Enum.RaycastFilterType.Whitelist
	self._spatialQueryParams.MaxParts = CONSTANTS.MAX_COLLISION_CHECKS_PER_FRAME
	
	-- Initialize remotes
	self:_initializeRemotes()
	
	-- Connect core systems
	self:_connectCoreSystems()
	
	return self
end

-- === REMOTE INITIALIZATION ===
function SnakeCollisionHandler:_initializeRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	
	-- Core remotes
	self._remotes = {
		CollisionReport = self:_getOrCreateRemote(remotesFolder, "CollisionReport", "RemoteEvent"),
		SnakeDied = self:_getOrCreateRemote(remotesFolder, "SnakeDied", "RemoteEvent"),
		RequestRespawn = self:_getOrCreateRemote(remotesFolder, "RequestRespawn", "RemoteEvent"),
		UpdateSnakeState = self:_getOrCreateRemote(remotesFolder, "UpdateSnakeState", "RemoteEvent")
	}
	
	-- Connect remote handlers
	self._remotes.CollisionReport.OnServerEvent:Connect(function(player, hitData)
		self:_onCollisionReported(player, hitData)
	end)
	
	self._remotes.RequestRespawn.OnServerEvent:Connect(function(player)
		self:_onRespawnRequested(player)
	end)
end

function SnakeCollisionHandler:_getOrCreateRemote(parent, name, className)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

-- === CORE SYSTEMS ===
function SnakeCollisionHandler:_connectCoreSystems()
	-- Main collision detection loop
	self._collisionConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_processCollisions(deltaTime)
	end)
	
	-- Player lifecycle
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
	
	-- Disable auto-spawning for full control
	Players.CharacterAutoLoads = false
end

-- === PLAYER LIFECYCLE ===
function SnakeCollisionHandler:_onPlayerAdded(player)
	-- Initialize player state
	self._lastCollisionTime[player] = 0
	self._collisionCooldowns[player] = 0
	
	-- Handle character spawning
	player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(player, character)
	end)
	
	-- Initial spawn
	taskwait(1) -- Allow time for data loading
	player:LoadCharacter()
end

function SnakeCollisionHandler:_onPlayerRemoving(player)
	-- Clean up all player resources
	self:_destroySnake(player)
	
	-- Clear state
	self._activeSnakes[player] = nil
	self._deadPlayers[player] = nil
	self._invinciblePlayers[player] = nil
	self._lastCollisionTime[player] = nil
	self._collisionCooldowns[player] = nil
end

function SnakeCollisionHandler:_onCharacterAdded(player, character)
	-- Clean up any existing snake
	self:_destroySnake(player)
	
	-- Create new snake
	taskwait(0.1) -- Allow character to fully load
	self:_createSnake(player, character)
end

-- === SNAKE CREATION ===
function SnakeCollisionHandler:_createSnake(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- Create Trove for this snake
	local trove = Trove.new()
	self._snakeTroves[player] = trove
	
	-- Initialize snake data
	local snakeData = {
		player = player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		head = rootPart, -- For now, using rootPart as head
		segments = {},
		length = 10, -- Starting length
		alive = true,
		createdAt = osclock()
	}
	
	self._activeSnakes[player] = snakeData
	
	-- Set invincibility on spawn
	self._invinciblePlayers[player] = osclock() + CONSTANTS.INVINCIBILITY_DURATION
	
	-- Prevent default death behavior
	trove:Add(humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		if humanoid.Health <= 0 and snakeData.alive then
			self:_handleDeath(player)
		end
	end))
	
	-- Initialize collision group
	self:_setupCollisionGroup(snakeData)
	
	-- Notify clients
	self._remotes.UpdateSnakeState:FireAllClients(player, "spawned", {
		position = rootPart.Position,
		length = snakeData.length
	})
	
	print(string.format("[SnakeCollisionHandler] Created snake for %s", player.Name))
end

-- === COLLISION DETECTION ===
function SnakeCollisionHandler:_processCollisions(deltaTime)
	local currentTime = osclock()
	
	-- Process each active snake
	for player, snakeData in pairs(self._activeSnakes) do
		if snakeData.alive and not self:_isInvincible(player) then
			self:_checkSnakeCollisions(player, snakeData, currentTime)
		end
	end
end

function SnakeCollisionHandler:_checkSnakeCollisions(player, snakeData, currentTime)
	-- Skip if on cooldown
	if currentTime < (self._collisionCooldowns[player] or 0) then
		return
	end
	
	local head = snakeData.head
	if not head or not head.Parent then
		return
	end
	
	-- Prepare spatial query
	local queryParams = self._spatialQueryParams
	local filterList = {}
	
	-- Add all other snake heads to filter
	for otherPlayer, otherSnakeData in pairs(self._activeSnakes) do
		if otherPlayer ~= player and otherSnakeData.alive and otherSnakeData.head then
			table.insert(filterList, otherSnakeData.head)
			-- Add body segments
			for _, segment in ipairs(otherSnakeData.segments) do
				if segment and segment.Parent then
					table.insert(filterList, segment)
				end
			end
		end
	end
	
	queryParams.FilterDescendantsInstances = filterList
	
	-- Perform spatial query for head collisions
	local headCFrame = head.CFrame
	local headHits = workspace:GetPartBoundsInBox(headCFrame, CONSTANTS.HEAD_COLLISION_SIZE, queryParams)
	
	-- Process hits
	for _, hitPart in ipairs(headHits) do
		local hitSnakeData = self:_getSnakeFromPart(hitPart)
		if hitSnakeData and hitSnakeData.player ~= player then
			-- Validate collision
			if self:_validateCollision(player, snakeData, hitSnakeData, hitPart) then
				-- Head-to-head collision
				if hitPart == hitSnakeData.head then
					self:_processHeadToHeadCollision(player, hitSnakeData.player)
				else
					-- Head-to-body collision
					self:_processHeadToBodyCollision(player, hitSnakeData.player)
				end
				
				-- Set cooldown
				self._collisionCooldowns[player] = currentTime + CONSTANTS.MIN_TIME_BETWEEN_COLLISIONS
				break
			end
		end
	end
end

function SnakeCollisionHandler:_validateCollision(player, snakeData, hitSnakeData, hitPart)
	-- Check if both snakes are alive
	if not snakeData.alive or not hitSnakeData.alive then
		return false
	end
	
	-- Check invincibility
	if self:_isInvincible(player) or self:_isInvincible(hitSnakeData.player) then
		return false
	end
	
	-- Distance validation
	local distance = (snakeData.head.Position - hitPart.Position).Magnitude
	if distance > CONSTANTS.MAX_COLLISION_REPORT_DISTANCE then
		return false
	end
	
	return true
end

-- === COLLISION HANDLERS ===
function SnakeCollisionHandler:_processHeadToHeadCollision(player1, player2)
	print(string.format("[Collision] Head-to-head: %s vs %s", player1.Name, player2.Name))
	
	-- Determine winner based on velocity
	local snake1 = self._activeSnakes[player1]
	local snake2 = self._activeSnakes[player2]
	
	local vel1 = snake1.head.AssemblyLinearVelocity
	local vel2 = snake2.head.AssemblyLinearVelocity
	
	local dir12 = (snake2.head.Position - snake1.head.Position).Unit
	local dir21 = -dir12
	
	local dot1 = vel1:Dot(dir12)
	local dot2 = vel2:Dot(dir21)
	
	-- Both die if charging at each other
	if dot1 > 2 and dot2 > 2 then
		self:_handleDeath(player1)
		self:_handleDeath(player2)
	elseif dot1 > 2 then
		self:_handleDeath(player1)
	elseif dot2 > 2 then
		self:_handleDeath(player2)
	end
end

function SnakeCollisionHandler:_processHeadToBodyCollision(hitter, victim)
	print(string.format("[Collision] %s hit %s's body", hitter.Name, victim.Name))
	self:_handleDeath(hitter)
end

-- === CLIENT COLLISION VALIDATION ===
function SnakeCollisionHandler:_onCollisionReported(player, hitData)
	-- Validate player is alive
	local snakeData = self._activeSnakes[player]
	if not snakeData or not snakeData.alive then
		return
	end
	
	-- Rate limiting
	local currentTime = osclock()
	local lastReport = self._lastCollisionTime[player] or 0
	if currentTime - lastReport < CONSTANTS.MIN_TIME_BETWEEN_COLLISIONS then
		return
	end
	
	-- Validate hit data
	if not hitData or not hitData.hitPlayer or not hitData.hitPosition then
		return
	end
	
	local hitPlayer = hitData.hitPlayer
	local hitPosition = hitData.hitPosition
	
	-- Validate hit player
	local hitSnakeData = self._activeSnakes[hitPlayer]
	if not hitSnakeData or not hitSnakeData.alive then
		return
	end
	
	-- Distance validation
	local distance = (snakeData.head.Position - hitPosition).Magnitude
	if distance > CONSTANTS.MAX_COLLISION_REPORT_DISTANCE then
		warn(string.format("[Security] Player %s reported collision too far away", player.Name))
		return
	end
	
	-- Process validated collision
	self._lastCollisionTime[player] = currentTime
	
	if hitData.isHeadCollision then
		self:_processHeadToHeadCollision(player, hitPlayer)
	else
		self:_processHeadToBodyCollision(player, hitPlayer)
	end
end

-- === DEATH HANDLING ===
function SnakeCollisionHandler:_handleDeath(player)
	local snakeData = self._activeSnakes[player]
	if not snakeData or not snakeData.alive then
		return
	end
	
	-- Mark as dead immediately
	snakeData.alive = false
	self._deadPlayers[player] = true
	
	print(string.format("[Death] Processing death for %s", player.Name))
	
	-- Store death position and length for orb spawning
	local deathPosition = snakeData.head.Position
	local snakeLength = snakeData.length
	
	-- Notify all clients about the death
	self._remotes.SnakeDied:FireAllClients(player, {
		position = deathPosition,
		length = snakeLength,
		timestamp = osclock()
	})
	
	-- Spawn orbs on server
	taskspawn(function()
		self:_spawnDeathOrbs(deathPosition, snakeLength)
	end)
	
	-- Clean up snake after delay
	taskwait(CONSTANTS.DEATH_CLEANUP_DELAY)
	self:_destroySnake(player)
end

function SnakeCollisionHandler:_spawnDeathOrbs(position, length)
	-- Calculate orb distribution
	local orbCount = math.floor(length / 5)
	local orbValue = math.max(1, math.floor(length / orbCount))
	
	for i = 1, orbCount do
		local angle = (i / orbCount) * math.pi * 2
		local radius = math.random(5, 15)
		local offset = Vector3.new(
			math.cos(angle) * radius,
			0,
			math.sin(angle) * radius
		)
		
		local orbPosition = position + offset
		orbPosition = Vector3.new(orbPosition.X, CONSTANTS.ORB_SPAWN_HEIGHT, orbPosition.Z)
		
		-- Create orb (assuming OrbUtils module exists)
		-- OrbUtils.spawnOrbAt(orbPosition, orbValue)
	end
end

-- === SNAKE DESTRUCTION ===
function SnakeCollisionHandler:_destroySnake(player)
	-- Get and clean trove
	local trove = self._snakeTroves[player]
	if trove then
		trove:Clean()
		self._snakeTroves[player] = nil
	end
	
	-- Clear snake data
	self._activeSnakes[player] = nil
	
	print(string.format("[Cleanup] Destroyed snake for %s", player.Name))
end

-- === RESPAWN HANDLING ===
function SnakeCollisionHandler:_onRespawnRequested(player)
	-- Validate player is dead
	if not self._deadPlayers[player] then
		return
	end
	
	-- Clear dead state
	self._deadPlayers[player] = nil
	
	-- Respawn character
	player:LoadCharacter()
end

-- === UTILITY FUNCTIONS ===
function SnakeCollisionHandler:_isInvincible(player)
	local expiryTime = self._invinciblePlayers[player]
	if expiryTime and osclock() < expiryTime then
		return true
	end
	
	-- Clean up expired invincibility
	if expiryTime then
		self._invinciblePlayers[player] = nil
	end
	
	return false
end

function SnakeCollisionHandler:_getSnakeFromPart(part)
	-- Check all active snakes
	for _, snakeData in pairs(self._activeSnakes) do
		if part == snakeData.head then
			return snakeData
		end
		
		for _, segment in ipairs(snakeData.segments) do
			if part == segment then
				return snakeData
			end
		end
	end
	
	return nil
end

function SnakeCollisionHandler:_setupCollisionGroup(snakeData)
	-- Set up collision groups to optimize spatial queries
	local head = snakeData.head
	if head then
		head.CollisionGroup = "SnakeHeads"
	end
	
	for _, segment in ipairs(snakeData.segments) do
		if segment then
			segment.CollisionGroup = "SnakeBodies"
		end
	end
end

-- === MODULE CLEANUP ===
function SnakeCollisionHandler:Destroy()
	-- Disconnect main systems
	if self._collisionConnection then
		self._collisionConnection:Disconnect()
	end
	
	-- Clean up all snakes
	for player, _ in pairs(self._activeSnakes) do
		self:_destroySnake(player)
	end
	
	-- Clear all state
	table.clear(self._activeSnakes)
	table.clear(self._snakeTroves)
	table.clear(self._deadPlayers)
	table.clear(self._invinciblePlayers)
	table.clear(self._lastCollisionTime)
	table.clear(self._collisionCooldowns)
end

return SnakeCollisionHandler