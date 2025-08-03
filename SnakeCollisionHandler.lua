-- SnakeCollisionHandler V9.0 COMPLETE REVAMP
-- Professional-grade collision system with proper state management
-- Full death system overhaul with instant freeze mechanics

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Get remotes folder
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ==========================================
-- STATE MANAGEMENT SYSTEM
-- ==========================================
local StateManager = {}
StateManager.__index = StateManager

function StateManager.new()
	return setmetatable({
		playerStates = {},
		aiStates = {},
		deathQueue = {},
		processingDeath = {},
		invincibilityTimers = {},
		frozenSnakes = {},
		cameraConnections = {}
	}, StateManager)
end

function StateManager:GetPlayerState(player)
	if not self.playerStates[player] then
		self.playerStates[player] = {
			alive = true,
			invincible = false,
			invincibleUntil = 0,
			deathTimestamp = 0,
			segments = {},
			segmentPositions = {},
			snakeLength = 0,
			frozen = false,
			processingDeath = false
		}
	end
	return self.playerStates[player]
end

function StateManager:SetPlayerDead(player)
	local state = self:GetPlayerState(player)
	state.alive = false
	state.deathTimestamp = tick()
end

function StateManager:IsPlayerDead(player)
	local state = self:GetPlayerState(player)
	return not state.alive
end

function StateManager:ResetPlayer(player)
	self.playerStates[player] = nil
	self.processingDeath[player] = nil
	self.invincibilityTimers[player] = nil
	self.frozenSnakes[player] = nil
	self:DisconnectCamera(player)
end

function StateManager:SetInvincible(player, duration)
	local state = self:GetPlayerState(player)
	state.invincible = true
	state.invincibleUntil = tick() + duration
	
	-- Auto-remove invincibility after duration
	if self.invincibilityTimers[player] then
		task.cancel(self.invincibilityTimers[player])
	end
	
	self.invincibilityTimers[player] = task.delay(duration, function()
		if self.playerStates[player] then
			self.playerStates[player].invincible = false
			self.playerStates[player].invincibleUntil = 0
		end
		self.invincibilityTimers[player] = nil
	end)
end

function StateManager:IsInvincible(player)
	local state = self:GetPlayerState(player)
	
	-- Check ghost mode
	if player:GetAttribute("ActiveGhostMode") then
		return true
	end
	
	-- Check timed invincibility
	if state.invincible and tick() < state.invincibleUntil then
		return true
	end
	
	return false
end

function StateManager:DisconnectCamera(player)
	if self.cameraConnections[player] then
		for _, connection in pairs(self.cameraConnections[player]) do
			if connection then
				connection:Disconnect()
			end
		end
		self.cameraConnections[player] = nil
	end
end

-- Global state manager instance
local State = StateManager.new()

-- ==========================================
-- DEATH SYSTEM
-- ==========================================
local DeathSystem = {}
DeathSystem.__index = DeathSystem

function DeathSystem.new(stateManager)
	return setmetatable({
		state = stateManager,
		orbSpawnHeight = 5,
		deathFadeTime = 0.5,
		invincibilityDuration = 5
	}, DeathSystem)
end

function DeathSystem:FreezeSnake(player, segments)
	if not segments or #segments == 0 then return {} end
	
	local frozen = {}
	print("🧊 [DEATH] Freezing snake for", player.Name, "with", #segments, "segments")
	
	-- First, stop any active snake controller
	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance then
		-- Disable all movement systems
		if snakeInstance.enabled ~= nil then snakeInstance.enabled = false end
		if snakeInstance.active ~= nil then snakeInstance.active = false end
		if snakeInstance.moving ~= nil then snakeInstance.moving = false end
		
		-- Call any stop methods
		if snakeInstance.stop then pcall(function() snakeInstance:stop() end) end
		if snakeInstance.freeze then pcall(function() snakeInstance:freeze() end) end
		if snakeInstance.disable then pcall(function() snakeInstance:disable() end) end
		
		-- Clear any movement connections
		if snakeInstance.connections then
			for _, conn in pairs(snakeInstance.connections) do
				if conn and conn.Disconnect then
					conn:Disconnect()
				end
			end
		end
	end
	
	-- Freeze each segment
	for i, segment in ipairs(segments) do
		if segment and segment:IsA("BasePart") and segment.Parent then
			-- Store original state
			frozen[i] = {
				part = segment,
				position = segment.Position,
				cframe = segment.CFrame,
				anchored = segment.Anchored,
				canCollide = segment.CanCollide
			}
			
			-- Freeze the segment
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanTouch = false
			segment.CanQuery = false
			
			-- Kill all velocity
			pcall(function()
				segment.AssemblyLinearVelocity = Vector3.zero
				segment.AssemblyAngularVelocity = Vector3.zero
				segment.Velocity = Vector3.zero
				segment.RotVelocity = Vector3.zero
			end)
			
			-- Disconnect any BodyMovers
			for _, obj in ipairs(segment:GetChildren()) do
				if obj:IsA("BodyMover") then
					obj:Destroy()
				end
			end
		end
	end
	
	-- Also freeze visual model
	local visualModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if visualModel then
		for _, part in ipairs(visualModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				pcall(function()
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end)
			end
		end
	end
	
	self.state.frozenSnakes[player] = frozen
	return frozen
end

function DeathSystem:AnimateCharacterDeath(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	-- Mark as dead
	rootPart:SetAttribute("Dead", true)
	
	-- Anchor character
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	
	-- Sink slightly
	rootPart.CFrame = rootPart.CFrame * CFrame.new(0, -10, 0)
	
	-- Fade out all parts
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			
			if descendant.Transparency < 1 then
				TweenService:Create(descendant, 
					TweenInfo.new(self.deathFadeTime, Enum.EasingStyle.Linear),
					{Transparency = 1}
				):Play()
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			TweenService:Create(descendant,
				TweenInfo.new(self.deathFadeTime, Enum.EasingStyle.Linear),
				{Transparency = 1}
			):Play()
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
end

function DeathSystem:SpawnDeathOrbs(player, segmentPositions, snakeLength)
	if not segmentPositions or #segmentPositions == 0 then
		warn("[DEATH] No segment positions for orb spawning")
		return
	end
	
	print("💎 [DEATH] Spawning orbs for", player.Name, "Length:", snakeLength, "Positions:", #segmentPositions)
	
	-- Calculate orb distribution
	local orbsPerSegment = 1 / 2.5
	local totalOrbs = math.clamp(math.floor(snakeLength * orbsPerSegment), 3, 40)
	
	-- Calculate orb value based on snake length
	local baseValue = 1
	if snakeLength <= 50 then
		baseValue = math.max(1, math.floor(snakeLength * 0.6 / totalOrbs))
	elseif snakeLength <= 200 then
		baseValue = math.max(1, math.floor(snakeLength * 0.45 / totalOrbs))
	elseif snakeLength <= 500 then
		baseValue = math.max(1, math.floor(snakeLength * 0.35 / totalOrbs))
	else
		baseValue = math.max(1, math.floor(math.min(snakeLength * 0.25, 200) / totalOrbs))
	end
	
	-- Spawn orbs along snake body
	task.spawn(function()
		task.wait(0.3) -- Small delay for death animation
		
		local spawnedOrbs = 0
		local skipInterval = math.max(1, math.floor(#segmentPositions / totalOrbs))
		
		for i = 1, #segmentPositions, skipInterval do
			if spawnedOrbs >= totalOrbs then break end
			
			local pos = segmentPositions[i]
			if pos then
				-- Add random spread
				local spread = Vector3.new(
					(math.random() - 0.5) * 6,
					0,
					(math.random() - 0.5) * 6
				)
				
				-- Extra spread for head area
				if i <= 5 then
					local angle = math.random() * math.pi * 2
					local distance = 10 + math.random() * 10
					spread = spread + Vector3.new(
						math.cos(angle) * distance,
						0,
						math.sin(angle) * distance
					)
				end
				
				local spawnPos = Vector3.new(
					pos.X + spread.X,
					self.orbSpawnHeight,
					pos.Z + spread.Z
				)
				
				local success, orb = pcall(function()
					return OrbUtils.spawnOrbAt(spawnPos, baseValue)
				end)
				
				if success and orb then
					orb.Name = "DeathOrb_" .. player.Name
					spawnedOrbs = spawnedOrbs + 1
				end
				
				-- Batch delay
				if spawnedOrbs % 5 == 0 then
					task.wait(0.02)
				end
			end
		end
		
		print("✅ [DEATH] Spawned", spawnedOrbs, "orbs for", player.Name)
	end)
end

function DeathSystem:ProcessPlayerDeath(player)
	local state = self.state:GetPlayerState(player)
	
	-- Prevent duplicate processing
	if state.processingDeath then
		print("⚠️ [DEATH] Already processing death for", player.Name)
		return
	end
	
	-- Check if recently died (within 2 seconds)
	if state.deathTimestamp and (tick() - state.deathTimestamp) < 2 then
		print("⚠️ [DEATH] Ignoring duplicate death for", player.Name)
		return
	end
	
	state.processingDeath = true
	self.state:SetPlayerDead(player)
	
	print("💀 [DEATH] Processing death for", player.Name)
	
	-- Get character and humanoid
	local character = player.Character
	if not character then
		state.processingDeath = false
		return
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		state.processingDeath = false
		return
	end
	
	-- Get snake data
	local snakeLength = 55
	if player:FindFirstChild("leaderstats") then
		local lengthValue = player.leaderstats:FindFirstChild("Length")
		if lengthValue then
			snakeLength = lengthValue.Value or 55
		end
	end
	
	-- Get and store segments
	local segments = self:GetSnakeSegments(player)
	local segmentPositions = {}
	
	if segments and #segments > 0 then
		for i, seg in ipairs(segments) do
			if seg and seg:IsA("BasePart") and seg.Parent then
				segmentPositions[i] = Vector3.new(seg.Position.X, seg.Position.Y, seg.Position.Z)
			end
		end
	end
	
	-- Clear attributes
	player:SetAttribute("MagnetRange", 1)
	player:SetAttribute("TempMagnetRange", 1)
	player:SetAttribute("ActiveMagnet", false)
	
	-- Disconnect camera
	self.state:DisconnectCamera(player)
	
	-- FREEZE SNAKE IMMEDIATELY
	self:FreezeSnake(player, segments)
	
	-- Animate character death
	self:AnimateCharacterDeath(character)
	
	-- SPAWN ORBS IMMEDIATELY (before revive check)
	self:SpawnDeathOrbs(player, segmentPositions, snakeLength)
	
	-- Handle revive
	self:HandleRevive(player, humanoid, character, snakeLength)
end

function DeathSystem:HandleRevive(player, humanoid, character, snakeLength)
	local reviveRemote = remotes:FindFirstChild("PromptRevive")
	if not reviveRemote then
		self:FinalizeDeath(player, humanoid)
		return
	end
	
	-- Send revive prompt
	reviveRemote:FireClient(player)
	print("📤 [DEATH] Revive prompt sent to", player.Name)
	
	local responseReceived = false
	local revived = false
	
	local connection = reviveRemote.OnServerEvent:Connect(function(plr, response)
		if plr == player and not responseReceived then
			responseReceived = true
			if response == "revive" then
				revived = true
			end
		end
	end)
	
	-- Wait for response (max 60 seconds)
	local timeout = 60
	local elapsed = 0
	
	while not responseReceived and elapsed < timeout do
		task.wait(0.1)
		elapsed = elapsed + 0.1
	end
	
	connection:Disconnect()
	
	if revived then
		self:ProcessRevive(player, character, snakeLength)
	else
		self:FinalizeDeath(player, humanoid)
	end
end

function DeathSystem:ProcessRevive(player, character, snakeLength)
	print("🎮 [DEATH] Processing revive for", player.Name)
	
	-- Set revive attributes
	player:SetAttribute("RevivingNow", true)
	player:SetAttribute("JustRevived", true)
	player:SetAttribute("NoReviveEffects", true)
	
	-- Get position
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local revivePos = rootPart and rootPart.Position or Vector3.new(0, 10, 0)
	if revivePos.Y < 5 then
		revivePos = Vector3.new(revivePos.X, 5, revivePos.Z)
	end
	
	-- Store revive data
	player:SetAttribute("RevivePosition", tostring(revivePos))
	player:SetAttribute("ReviveSnakeLength", snakeLength)
	
	-- Reset state
	self.state:ResetPlayer(player)
	
	-- Set invincibility
	self.state:SetInvincible(player, self.invincibilityDuration)
	
	-- Mark as no longer processing death
	local state = self.state:GetPlayerState(player)
	state.processingDeath = false
	
	-- Respawn
	player:LoadCharacter()
	
	-- Clear revive flags after load
	task.wait(2)
	player:SetAttribute("RevivingNow", false)
	player:SetAttribute("NoReviveEffects", false)
	player:SetAttribute("CameraLocked", false)
end

function DeathSystem:FinalizeDeath(player, humanoid)
	print("⚰️ [DEATH] Finalizing death for", player.Name)
	
	-- Destroy snake
	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance then
		if snakeInstance.destroy then
			pcall(function() snakeInstance:destroy() end)
		end
		_G.PlayerSnakes[player] = nil
	end
	
	-- Destroy visual model
	local visualModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if visualModel then
		visualModel:Destroy()
	end
	
	-- Clear state
	local state = self.state:GetPlayerState(player)
	state.processingDeath = false
	
	-- Kill humanoid
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
	
	-- Fire death event
	local deathEvent = ReplicatedStorage:FindFirstChild("PlayerDied")
	if deathEvent then
		deathEvent:Fire(player)
	end
	
	-- Cleanup after delay
	task.wait(5)
	self.state:ResetPlayer(player)
end

function DeathSystem:GetSnakeSegments(player)
	-- Try visual model first
	local visualModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if visualModel then
		local segments = {}
		local i = 0
		while true do
			local segmentName = i == 0 and "Segment0_Head" or ("Segment" .. i)
			local segment = visualModel:FindFirstChild(segmentName)
			if segment and segment:IsA("BasePart") then
				segments[#segments + 1] = segment
				i = i + 1
			else
				break
			end
		end
		if #segments > 0 then
			return segments
		end
	end
	
	-- Try global snake system
	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance and snakeInstance.segments then
		local segments = {}
		for _, seg in ipairs(snakeInstance.segments) do
			if seg and seg:IsA("BasePart") and seg.Parent then
				segments[#segments + 1] = seg
			end
		end
		if #segments > 0 then
			return segments
		end
	end
	
	return nil
end

-- Create death system instance
local Death = DeathSystem.new(State)

-- ==========================================
-- COLLISION DETECTION SYSTEM
-- ==========================================
local CollisionSystem = {}
CollisionSystem.__index = CollisionSystem

function CollisionSystem.new(stateManager, deathSystem)
	return setmetatable({
		state = stateManager,
		death = deathSystem,
		gridSize = 120,
		headCollisionDist = 3.5,
		bodyCollisionDist = 2.8,
		selfCollisionIgnore = 10,
		spatialGrid = {},
		segmentCache = {},
		cacheExpiry = 1.5
	}, CollisionSystem)
end

function CollisionSystem:GetPlayerHeads()
	local heads = {}
	
	for _, player in ipairs(Players:GetPlayers()) do
		if self.state:IsPlayerDead(player) then
			continue
		end
		
		if player.Character then
			-- Try snake model first
			local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
			if snakeModel then
				local head = snakeModel:FindFirstChild("Segment0_Head")
				if head and head:IsA("BasePart") and head.Parent then
					table.insert(heads, {player = player, part = head})
					continue
				end
			end
			
			-- Fallback to HumanoidRootPart
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Parent and not root:GetAttribute("Dead") then
				table.insert(heads, {player = player, part = root})
			end
		end
	end
	
	return heads
end

function CollisionSystem:GetAIHeads()
	local heads = {}
	
	if AISnakeModule._activeSnakes then
		for _, snake in pairs(AISnakeModule._activeSnakes) do
			if snake and snake._active and snake.HeadParts and snake.HeadParts.head then
				local head = snake.HeadParts.head
				if head and head.Parent then
					table.insert(heads, head)
				end
			end
		end
	end
	
	return heads
end

function CollisionSystem:GetSegments(player)
	-- Check cache
	local cached = self.segmentCache[player]
	if cached and (tick() - cached.timestamp) < self.cacheExpiry then
		return cached.segments
	end
	
	-- Get fresh segments
	local segments = self.death:GetSnakeSegments(player)
	
	-- Cache result
	if segments and #segments > 0 then
		self.segmentCache[player] = {
			segments = segments,
			timestamp = tick()
		}
	end
	
	return segments
end

function CollisionSystem:CheckCollision(headPos, targetPos, distance)
	local dist = (headPos - targetPos).Magnitude
	return dist < distance
end

function CollisionSystem:CheckBodyCollision(headPos, segments, ignoreFirst)
	if not segments or #segments == 0 then return false end
	
	local startIdx = ignoreFirst and self.selfCollisionIgnore + 1 or 1
	
	for i = startIdx, #segments do
		local segment = segments[i]
		if segment and segment:IsA("BasePart") and segment.Parent then
			if self:CheckCollision(headPos, segment.Position, self.bodyCollisionDist) then
				return true
			end
		end
	end
	
	return false
end

function CollisionSystem:CheckHeadToHeadCollision(headA, headB, velA, velB)
	if not self:CheckCollision(headA.Position, headB.Position, self.headCollisionDist) then
		return false, false
	end
	
	-- Calculate collision direction
	local dirAtoB = (headB.Position - headA.Position).Unit
	local dirBtoA = -dirAtoB
	
	-- Check velocities
	local dotA = velA:Dot(dirAtoB)
	local dotB = velB:Dot(dirBtoA)
	
	local aHitsB = dotA > 2
	local bHitsA = dotB > 2
	
	return aHitsB, bHitsA
end

function CollisionSystem:RunCollisionCheck()
	-- Clear segment cache periodically
	if math.random() < 0.1 then
		self.segmentCache = {}
	end
	
	local playerHeads = self:GetPlayerHeads()
	local aiHeads = self:GetAIHeads()
	
	-- Player vs AI Body
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part
		
		if self.state:IsInvincible(player) then
			continue
		end
		
		-- Check AI snake bodies
		if AISnakeModule._activeSnakes then
			for _, snake in pairs(AISnakeModule._activeSnakes) do
				if snake and snake._active and snake.Segments then
					if self:CheckBodyCollision(head.Position, snake.Segments, false) then
						self.death:ProcessPlayerDeath(player)
						break
					end
				end
			end
		end
	end
	
	-- Player vs Player Body
	for i, headDataA in ipairs(playerHeads) do
		local playerA = headDataA.player
		local headA = headDataA.part
		
		if self.state:IsInvincible(playerA) then
			continue
		end
		
		for j, headDataB in ipairs(playerHeads) do
			local playerB = headDataB.player
			local segmentsB = self:GetSegments(playerB)
			
			if segmentsB then
				local isSelf = (i == j)
				if self:CheckBodyCollision(headA.Position, segmentsB, isSelf) then
					self.death:ProcessPlayerDeath(playerA)
					break
				end
			end
		end
	end
	
	-- Head to Head Collisions
	for i = 1, #playerHeads - 1 do
		local dataA = playerHeads[i]
		local playerA = dataA.player
		local headA = dataA.part
		
		if self.state:IsInvincible(playerA) then
			continue
		end
		
		for j = i + 1, #playerHeads do
			local dataB = playerHeads[j]
			local playerB = dataB.player
			local headB = dataB.part
			
			if self.state:IsInvincible(playerB) then
				continue
			end
			
			local velA = headA.AssemblyLinearVelocity or Vector3.zero
			local velB = headB.AssemblyLinearVelocity or Vector3.zero
			
			local aHitsB, bHitsA = self:CheckHeadToHeadCollision(headA, headB, velA, velB)
			
			if aHitsB and bHitsA then
				-- Both hit each other
				self.death:ProcessPlayerDeath(playerA)
				task.wait(0.05)
				self.death:ProcessPlayerDeath(playerB)
			elseif aHitsB then
				self.death:ProcessPlayerDeath(playerA)
			elseif bHitsA then
				self.death:ProcessPlayerDeath(playerB)
			end
		end
	end
end

-- Create collision system instance
local Collision = CollisionSystem.new(State, Death)

-- ==========================================
-- PLAYER LIFECYCLE
-- ==========================================
local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		State:ResetPlayer(player)
		State:SetInvincible(player, 5)
		
		-- Wait for humanoid
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				State:SetPlayerDead(player)
			end)
		end
	end)
	
	player.AncestryChanged:Connect(function()
		if not player.Parent then
			State:ResetPlayer(player)
		end
	end)
end

-- Connect existing players
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- Connect new players
Players.PlayerAdded:Connect(onPlayerAdded)

-- ==========================================
-- MAIN COLLISION LOOP
-- ==========================================
local frameCount = 0
local COLLISION_CHECK_INTERVAL = 5 -- Check every 5 frames

RunService.Heartbeat:Connect(function()
	frameCount = frameCount + 1
	
	if frameCount % COLLISION_CHECK_INTERVAL == 0 then
		Collision:RunCollisionCheck()
	end
end)

-- ==========================================
-- DEBUG SYSTEM
-- ==========================================
local debugEnabled = false

local function toggleDebug()
	debugEnabled = not debugEnabled
	print("🔍 Debug mode:", debugEnabled and "ENABLED" or "DISABLED")
end

local debugValue = Instance.new("StringValue")
debugValue.Name = "ToggleCollisionDebug"
debugValue.Parent = workspace
debugValue.Changed:Connect(function()
	if debugValue.Value == "debug" then
		toggleDebug()
		debugValue.Value = ""
	end
end)

print("⚡ SnakeCollisionHandler V9.0 COMPLETE REVAMP")
print("✅ Professional state management system")
print("✅ Instant snake freeze on death")
print("✅ Clean death processing pipeline")
print("✅ Optimized collision detection")
print("✅ Proper revive handling")
print("🎮 Ready for production")