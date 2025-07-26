-- Slither.io Orb Spawner Script - OPTIMIZED VERSION
-- Major performance improvements: reduced orb count, better LOD, efficient updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- PERFORMANCE SETTINGS - Significantly reduced for better FPS
local ORB_COUNT = 150 -- Reduced from 400-700
local RESPAWN_DELAY = 1 -- Slower respawn
local UPDATE_INTERVAL = 0.3 -- Less frequent updates
local UPGRADE_ORB_CHANCE = 0.02 -- Rare upgrade orbs

-- LOD Settings - Simplified for performance
local RENDER_DISTANCE = 200 -- Orbs become invisible beyond this
local COLLECTION_RANGE = 15 -- Max collection distance
local LOD_UPDATE_RATE = 0.5 -- Update visibility twice per second

-- Spatial grid for efficient collision detection
local GRID_SIZE = 100 -- Larger cells = fewer checks
local orbGrid = {}

-- Core helpers
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))
local SnakeUpgrades = require(ReplicatedStorage:WaitForChild("SnakeUpgrades"))

-- Create Orbs folder
local orbsFolder = workspace:FindFirstChild("Orbs")
if not orbsFolder then
	orbsFolder = Instance.new("Folder")
	orbsFolder.Name = "Orbs"
	orbsFolder.Parent = workspace
end

-- Lazy load AISnake to avoid circular dependency
local AISnakeModule
local function getAISnakeModule()
	if AISnakeModule then return AISnakeModule end
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("AISnake"))
	end)
	if ok then AISnakeModule = mod end
	return AISnakeModule
end

-- Create OrbCollected RemoteEvent
local OrbCollectedEvent = ReplicatedStorage:FindFirstChild("OrbCollected")
if not OrbCollectedEvent then
	OrbCollectedEvent = Instance.new("RemoteEvent")
	OrbCollectedEvent.Name = "OrbCollected"
	OrbCollectedEvent.Parent = ReplicatedStorage
end

-- State management
local orbs = {} -- All active orbs
local orbDebounce = {} -- Prevent double collection
local visibleOrbs = {} -- Track which orbs are visible
local orbPool = {} -- Reusable orb instances
local poolSize = 0

-- Forward declare
local attachOrbTouched

---------------------------------------------------------------------
-- Spatial Grid Functions - Optimized
---------------------------------------------------------------------
local function getGridKey(position)
	local x = math.floor(position.X / GRID_SIZE)
	local z = math.floor(position.Z / GRID_SIZE)
	return x .. "," .. z
end

local function addOrbToGrid(orb)
	local key = getGridKey(orb.Position)
	if not orbGrid[key] then
		orbGrid[key] = {}
	end
	orbGrid[key][orb] = true
end

local function removeOrbFromGrid(orb)
	local key = getGridKey(orb.Position)
	if orbGrid[key] then
		orbGrid[key][orb] = nil
		if next(orbGrid[key]) == nil then
			orbGrid[key] = nil
		end
	end
end

local function getOrbsInCell(x, z)
	local key = x .. "," .. z
	return orbGrid[key] or {}
end

---------------------------------------------------------------------
-- Get spawn area from map
---------------------------------------------------------------------
local function getOrbSpawnArea()
	local groundPart = workspace:FindFirstChild("SlitherIOGround")
	if groundPart and groundPart:IsA("BasePart") then
		local size = groundPart.Size
		local pos = groundPart.Position
		local halfX = size.X / 2 - 20
		local halfZ = size.Z / 2 - 20
		return {
			minX = pos.X - halfX,
			maxX = pos.X + halfX,
			minZ = pos.Z - halfZ,
			maxZ = pos.Z + halfZ,
			y = pos.Y + size.Y / 2 + 3
		}
	end
	return {minX = -600, maxX = 600, minZ = -600, maxZ = 600, y = 5}
end

---------------------------------------------------------------------
-- Efficient orb creation with pooling
---------------------------------------------------------------------
local function getOrCreateOrb()
	local orb
	
	-- Try to get from pool first
	if poolSize > 0 then
		orb = table.remove(orbPool)
		poolSize = poolSize - 1
		orb.Parent = orbsFolder
		return orb
	end
	
	-- Create new orb
	orb = Instance.new("Part")
	orb.Name = "Orb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2, 2, 2)
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanTouch = true
	orb.CanQuery = false -- Optimization: don't include in raycasts
	orb.Material = Enum.Material.Neon
	orb.TopSurface = Enum.SurfaceType.Smooth
	orb.BottomSurface = Enum.SurfaceType.Smooth
	
	local val = Instance.new("NumberValue")
	val.Name = "Value"
	val.Value = 5
	val.Parent = orb
	
	-- No PointLight - visual effects should be client-side
	
	return orb
end

local function returnOrbToPool(orb)
	if poolSize < 50 then -- Max pool size
		orb.Parent = nil
		orb.Transparency = 1
		table.insert(orbPool, orb)
		poolSize = poolSize + 1
	else
		orb:Destroy()
	end
end

---------------------------------------------------------------------
-- Simplified orb spawning
---------------------------------------------------------------------
local function spawnOrb()
	local area = getOrbSpawnArea()
	local orb = getOrCreateOrb()
	
	-- Random position
	orb.Position = Vector3.new(
		math.random(area.minX, area.maxX),
		area.y,
		math.random(area.minZ, area.maxZ)
	)
	
	-- Determine orb type
	if math.random() < UPGRADE_ORB_CHANCE then
		orb.Name = "UpgradeOrb"
		orb.Color = Color3.fromRGB(0, 150, 255)
		orb.Material = Enum.Material.ForceField
		orb.Size = Vector3.new(3, 3, 3)
		orb.Transparency = 0.3
		local val = orb:FindFirstChild("Value")
		if val then val.Value = 0 end
	else
		orb.Name = "Orb"
		orb.Color = Color3.fromRGB(255, 255, 0)
		orb.Material = Enum.Material.Neon
		orb.Size = Vector3.new(2, 2, 2)
		orb.Transparency = 0
		local val = orb:FindFirstChild("Value")
		if val then val.Value = 5 end
	end
	
	orb.Parent = orbsFolder
	table.insert(orbs, orb)
	addOrbToGrid(orb)
	attachOrbTouched(orb)
	
	-- Start invisible for LOD
	orb.Transparency = 1
	visibleOrbs[orb] = false
	
	return orb
end

---------------------------------------------------------------------
-- Death orbs - simplified
---------------------------------------------------------------------
local function spawnDeathOrbs(position, count)
	count = math.min(count, 20) -- Cap death orbs
	local spawned = {}
	
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local distance = math.random(5, 15)
		local offset = Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)
		
		local orb = getOrCreateOrb()
		orb.Name = "DeathOrb"
		orb.Color = Color3.fromRGB(255, 100, 100)
		orb.Size = Vector3.new(2.5, 2.5, 2.5)
		orb.Position = position + offset
		orb.Transparency = 0
		orb.Parent = orbsFolder
		
		local val = orb:FindFirstChild("Value")
		if val then val.Value = 3 end
		
		table.insert(orbs, orb)
		table.insert(spawned, orb)
		addOrbToGrid(orb)
		attachOrbTouched(orb)
		visibleOrbs[orb] = true
		
		-- Auto cleanup after 30 seconds
		Debris:AddItem(orb, 30)
	end
	
	return spawned
end

---------------------------------------------------------------------
-- Simplified collection system
---------------------------------------------------------------------
local function collectOrb(orb, collector, collectorType)
	if not orb or not orb.Parent or orbDebounce[orb] then return end
	orbDebounce[orb] = true
	
	-- Get orb value
	local valObj = orb:FindFirstChild("Value")
	local value = (valObj and valObj.Value) or 5
	local isUpgrade = orb.Name == "UpgradeOrb"
	
	-- Remove orb immediately
	local pos = orb.Position
	removeOrbFromGrid(orb)
	for i = #orbs, 1, -1 do
		if orbs[i] == orb then
			table.remove(orbs, i)
			break
		end
	end
	visibleOrbs[orb] = nil
	returnOrbToPool(orb)
	
	-- Apply effects
	task.defer(function()
		if collectorType == "player" then
			local player = collector
			if isUpgrade then
				-- Give upgrade
				local snakeInst = _G.PlayerSnakes and _G.PlayerSnakes[player]
				if snakeInst then
					SnakeUpgrades.GiveUpgrade(snakeInst)
				end
			else
				-- Grow snake
				local snakeInst = _G.PlayerSnakes and _G.PlayerSnakes[player]
				if not snakeInst and player.Character then
					local ref = player.Character:FindFirstChild("__SnakeInstance")
					if ref then snakeInst = ref.Value end
				end
				if snakeInst and snakeInst.grow then
					snakeInst:grow(value)
				end
			end
			
			-- Fire client event
			pcall(function()
				OrbCollectedEvent:FireClient(player, pos, orb.Name)
			end)
		else
			-- AI snake
			local ASM = getAISnakeModule()
			if ASM and ASM._activeSnakes then
				for _, snake in ASM._activeSnakes do
					if snake.HeadParts and snake.HeadParts.head == collector then
						if isUpgrade then
							SnakeUpgrades.GiveUpgrade(snake)
						else
							snake:grow(value)
						end
						break
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- Touch detection
---------------------------------------------------------------------
local function getPlayerFromPart(part)
	-- Check if it's a HumanoidRootPart
	local character = part.Parent
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return Players:GetPlayerFromCharacter(character)
		end
	end
	
	-- Check if it's a snake segment
	if part.Name == "SnakeHead" or part:GetAttribute("IsSnakeSegment") then
		local model = part.Parent
		while model do
			local userId = model:GetAttribute("OwnerUserId")
			if userId then
				for _, player in Players:GetPlayers() do
					if player.UserId == userId then
						return player
					end
				end
			end
			model = model.Parent
		end
	end
	
	return nil
end

local function getAISnakeFromPart(part)
	if part.Name == "AISnakeHead" then
		return part
	end
	
	local ASM = getAISnakeModule()
	if ASM and ASM._activeSnakes then
		for _, snake in ASM._activeSnakes do
			if snake.HeadParts and snake.HeadParts.head == part then
				return snake.HeadParts.head
			end
		end
	end
	
	return nil
end

attachOrbTouched = function(orb)
	orb.Touched:Connect(function(hit)
		if not orb.Parent or orbDebounce[orb] then return end
		
		-- Check player collision
		local player = getPlayerFromPart(hit)
		if player then
			-- Check spawn protection
			local spawnedBy = orb:GetAttribute("SpawnedByUserId")
			local spawnTime = orb:GetAttribute("SpawnTime")
			if spawnedBy == player.UserId and spawnTime and (tick() - spawnTime) < 5 then
				return
			end
			
			collectOrb(orb, player, "player")
			return
		end
		
		-- Check AI collision
		local aiHead = getAISnakeFromPart(hit)
		if aiHead then
			collectOrb(orb, aiHead, "ai")
		end
	end)
end

---------------------------------------------------------------------
-- Optimized LOD system - only update visible orbs near players
---------------------------------------------------------------------
local lastLODUpdate = 0
local function updateOrbVisibility()
	local now = tick()
	if now - lastLODUpdate < LOD_UPDATE_RATE then return end
	lastLODUpdate = now
	
	-- Get all viewer positions
	local viewers = {}
	
	-- Players
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(viewers, root.Position)
		end
	end
	
	-- AI snakes
	local ASM = getAISnakeModule()
	if ASM and ASM._activeSnakes then
		for _, snake in ASM._activeSnakes do
			if snake.HeadParts and snake.HeadParts.head then
				table.insert(viewers, snake.HeadParts.head.Position)
			end
		end
	end
	
	if #viewers == 0 then return end
	
	-- Update orb visibility based on distance
	for _, orb in ipairs(orbs) do
		if orb and orb.Parent then
			local orbPos = orb.Position
			local shouldBeVisible = false
			
			-- Check distance to nearest viewer
			for _, viewPos in ipairs(viewers) do
				local distance = (orbPos - viewPos).Magnitude
				if distance <= RENDER_DISTANCE then
					shouldBeVisible = true
					break
				end
			end
			
			-- Update visibility if changed
			if visibleOrbs[orb] ~= shouldBeVisible then
				visibleOrbs[orb] = shouldBeVisible
				orb.Transparency = shouldBeVisible and 0 or 1
			end
		end
	end
end

-- Run LOD updates
RunService.Heartbeat:Connect(updateOrbVisibility)

---------------------------------------------------------------------
-- Proximity collection system - simplified
---------------------------------------------------------------------
local function proximityCollectionLoop()
	while true do
		task.wait(0.2) -- Check 5 times per second
		
		-- Get all collectors
		local collectors = {}
		
		-- Players
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local magnetPower = (player:GetAttribute("MagnetRange") or 1) * 
				                   (player:GetAttribute("TempMagnetRange") or 1)
				table.insert(collectors, {
					position = root.Position,
					object = player,
					type = "player",
					range = COLLECTION_RANGE * magnetPower,
					magnetPower = magnetPower
				})
			end
		end
		
		-- AI snakes
		local ASM = getAISnakeModule()
		if ASM and ASM._activeSnakes then
			for _, snake in ASM._activeSnakes do
				if snake.HeadParts and snake.HeadParts.head then
					table.insert(collectors, {
						position = snake.HeadParts.head.Position,
						object = snake.HeadParts.head,
						type = "ai",
						range = COLLECTION_RANGE,
						magnetPower = 1
					})
				end
			end
		end
		
		-- Check collections
		for _, collector in ipairs(collectors) do
			local cellX = math.floor(collector.position.X / GRID_SIZE)
			local cellZ = math.floor(collector.position.Z / GRID_SIZE)
			
			-- Check nearby cells
			for dx = -1, 1 do
				for dz = -1, 1 do
					local cellOrbs = getOrbsInCell(cellX + dx, cellZ + dz)
					for orb, _ in pairs(cellOrbs) do
						if orb and orb.Parent and not orbDebounce[orb] then
							local distance = (orb.Position - collector.position).Magnitude
							
							-- Collection check
							if distance <= collector.range then
								-- Check spawn protection for players
								if collector.type == "player" then
									local spawnedBy = orb:GetAttribute("SpawnedByUserId")
									local spawnTime = orb:GetAttribute("SpawnTime")
									if spawnedBy == collector.object.UserId and 
									   spawnTime and (tick() - spawnTime) < 5 then
										continue
									end
								end
								
								collectOrb(orb, collector.object, collector.type)
							elseif collector.magnetPower > 1 and distance <= collector.range * 2 then
								-- Magnetic attraction (client should handle visual)
								local pullStrength = (collector.magnetPower - 1) * 0.2
								local direction = (collector.position - orb.Position).Unit
								orb.Position = orb.Position + direction * pullStrength
							end
						end
					end
				end
			end
		end
	end
end

-- Start proximity collection
task.spawn(proximityCollectionLoop)

---------------------------------------------------------------------
-- Orb spawning loop
---------------------------------------------------------------------
local function orbSpawnLoop()
	-- Initial spawn
	for i = 1, ORB_COUNT do
		spawnOrb()
		if i % 10 == 0 then
			task.wait() -- Prevent lag spike
		end
	end
	
	-- Maintain orb count
	while true do
		task.wait(RESPAWN_DELAY)
		
		-- Remove dead orbs
		for i = #orbs, 1, -1 do
			local orb = orbs[i]
			if not orb or not orb.Parent then
				table.remove(orbs, i)
				if orb then
					removeOrbFromGrid(orb)
					visibleOrbs[orb] = nil
				end
			end
		end
		
		-- Spawn new orbs
		local orbsToSpawn = ORB_COUNT - #orbs
		for i = 1, math.min(orbsToSpawn, 5) do -- Max 5 per cycle
			spawnOrb()
		end
	end
end

-- Start spawning
task.spawn(orbSpawnLoop)

---------------------------------------------------------------------
-- Module exports
---------------------------------------------------------------------
local OrbSpawner = {
	spawnDeathOrbsForSnake = spawnDeathOrbs,
	createSafeOrb = function(pos, val, name, color, mat)
		local orb = getOrCreateOrb()
		orb.Position = pos
		orb.Name = name or "Orb"
		orb.Color = color or Color3.fromRGB(255, 255, 0)
		orb.Material = mat or Enum.Material.Neon
		orb.Parent = orbsFolder
		local value = orb:FindFirstChild("Value")
		if value then value.Value = val or 5 end
		return orb
	end,
	registerExternalOrb = function(orb)
		if not orb or not orb.Parent then return end
		table.insert(orbs, orb)
		addOrbToGrid(orb)
		attachOrbTouched(orb)
		visibleOrbs[orb] = true
	end
}

-- Set the attachOrbTouched function for OrbUtils
OrbUtils.attachOrbTouched = attachOrbTouched

_G.OrbSpawner = OrbSpawner
print("OrbSpawner optimized - reduced lag, better performance")

return OrbSpawner