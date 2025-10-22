-- AISnake Module: FIXED VERSION - No more teleporting/dying/stretching bugs
-- Completely redesigned AI brain for smooth, intelligent movement
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Load the orb pickup module  
local AISnakeOrbPickup
pcall(function()
	local module = ReplicatedStorage:FindFirstChild("AISnakeOrbPickup") or game.ServerScriptService:FindFirstChild("AISnakeOrbPickup")
	if module then
		AISnakeOrbPickup = require(module)
	end
end)

-- Load SnakeUpgrades module for upgrade orbs
local SnakeUpgrades
pcall(function()
	local module = ReplicatedStorage:FindFirstChild("SnakeUpgrades")
	if module then
		SnakeUpgrades = require(module)
	end
end)

local Vector3new = Vector3.new
local CFramenew = CFrame.new
local CFramelookAt = CFrame.lookAt
local mathRad = math.rad
local mathRandom = math.random
local mathAtan2 = math.atan2
local mathPi = math.pi
local mathMin = math.min
local mathMax = math.max
local mathAbs = math.abs
local mathCeil = math.ceil
local mathExp = math.exp
local mathSin = math.sin
local mathCos = math.cos
local mathClamp = math.clamp
local mathFloor = math.floor
local mathSqrt = math.sqrt

local AISnake = {}
AISnake.__index = AISnake

-- === OPTIMIZED SETTINGS ===
local MAX_AI_SNAKES = 10
local SPATIAL_GRID_UPDATE_RATE = 1.0
local BRAIN_UPDATES_PER_FRAME = 1
local DEBUG_UPDATE_RATE = 5.0
local AI_HEIGHT = 5
local SEGMENT_UPDATE_SKIP = 2
local LONG_SNAKE_THRESHOLD = 100
local VERY_LONG_SNAKE_THRESHOLD = 300
local AI_UPDATE_DISTANCE = 200
local SEGMENT_POOL_MAX = 500

AISnake._activeSnakes = {}
AISnake._orbTargets = {}

-- === SPATIAL GRID ===
local SpatialGrid = {}
local gridGeneration = 0
local entityPositionCache = {}
local partSizeCache = {}
do
	local CELL_SIZE = 75
	local grid = {}
	local ground = Workspace:FindFirstChild("SlitherIOGround")
	local mapSize = ground and ground.Size or Vector3new(1000, 10, 1000)
	local minX, minZ = -mapSize.X / 2, -mapSize.Z / 2

	local function getCellCoords(position)
		local x = mathFloor((position.X - minX) / CELL_SIZE)
		local z = mathFloor((position.Z - minZ) / CELL_SIZE)
		return x, z
	end

	function SpatialGrid.Clear()
		grid = {}
	end

	function SpatialGrid.Insert(part, owner, type)
		if not part or not part.Parent then return end
		local x, z = getCellCoords(part.Position)
		if not grid[x] then
			grid[x] = {}
		end
		if not grid[x][z] then
			grid[x][z] = {}
		end
		table.insert(grid[x][z], {part = part, owner = owner, type = type})
	end

	function SpatialGrid.QueryRadius(position, radius)
		local results = {}
		local minX, minZ = getCellCoords(position - Vector3new(radius, 0, radius))
		local maxX, maxZ = getCellCoords(position + Vector3new(radius, 0, radius))

		for x = minX, maxX do
			if grid[x] then
				for z = minZ, maxZ do
					if grid[x][z] then
						for _, entity in grid[x][z] do
							if (entity.part.Position - position).Magnitude <= radius then
								table.insert(results, entity)
							end
						end
					end
				end
			end
		end
		return results
	end
end

-- === SEGMENT POOLING ===
local SegmentPool = {}
local PoolSize = 0
local MAX_POOL_SIZE = 1000
local SEGMENT_PARENT = Workspace:FindFirstChild("AISegmentContainer") or Instance.new("Folder", Workspace)
SEGMENT_PARENT.Name = "AISegmentContainer"

local function resetSegment(segment, config)
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false
	segment.CanQuery = false
	segment.Transparency = 0
	segment.Size = config.SegmentSize
	segment.Material = config.BodyMaterial or Enum.Material.Neon
	segment.Shape = Enum.PartType.Ball
	segment.TopSurface = Enum.SurfaceType.Smooth
	segment.BottomSurface = Enum.SurfaceType.Smooth
	segment.Color = config.BodyColors[1]
	segment.Name = "AISegment"

	-- Clean up children efficiently
	for _, child in segment:GetChildren() do
		if child:IsA("PointLight") or child:IsA("Attachment") then
			child:Destroy()
		end
	end
end

local function getSegment(config)
	if PoolSize > 0 then
		local segment = SegmentPool[PoolSize]
		SegmentPool[PoolSize] = nil
		PoolSize = PoolSize - 1
		resetSegment(segment, config)
		return segment
	else
		local segment = Instance.new("Part")
		resetSegment(segment, config)
		return segment
	end
end

local function returnSegment(segment)
	if not segment then return end

	-- Clean up all children first
	for _, child in ipairs(segment:GetChildren()) do
		child:Destroy()
	end

	-- If pool is full or segment is problematic, just destroy it
	if PoolSize >= MAX_POOL_SIZE then
		segment:Destroy()
		return
	end

	-- Reset segment properties
	segment.Transparency = 1
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.Anchored = true
	segment.Color = Color3.new()
	segment.Material = Enum.Material.Neon
	segment.Size = Vector3.new(3.5, 3.5, 4)

	-- Return to pool
	segment.Parent = SEGMENT_PARENT
	PoolSize = PoolSize + 1
	SegmentPool[PoolSize] = segment
end

-- === HELPER FUNCTIONS ===
local function getOrCreateSnakeModel(aiId)
	local modelName = "AISnakeModel_" .. tostring(aiId)
	local existing = Workspace:FindFirstChild(modelName)
	if existing and existing:IsA("Model") then
		return existing
	end
	local model = Instance.new("Model")
	model.Name = modelName
	model.Parent = Workspace
	return model
end

-- AI Snake color combinations
local AISnakeColors = {
	{
		-- Yellow (Classic smooth)
		HeadColor = Color3.fromRGB(255, 255, 102),
		BodyColors = {
			Color3.fromRGB(255, 255, 51), 
			Color3.fromRGB(255, 255, 102),
			Color3.fromRGB(255, 255, 153), 
			Color3.fromRGB(255, 255, 102), 
			Color3.fromRGB(255, 255, 51),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Green (Nature)
		HeadColor = Color3.fromRGB(102, 255, 102),
		BodyColors = {
			Color3.fromRGB(60, 180, 80),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(100, 220, 120),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(60, 180, 80),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Blue (Ocean)
		HeadColor = Color3.fromRGB(102, 178, 255),
		BodyColors = {
			Color3.fromRGB(51, 153, 255),
			Color3.fromRGB(102, 178, 255),
			Color3.fromRGB(153, 204, 255),
			Color3.fromRGB(102, 178, 255),
			Color3.fromRGB(51, 153, 255),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Orange (Sunset)
		HeadColor = Color3.fromRGB(255, 178, 102),
		BodyColors = {
			Color3.fromRGB(255, 153, 51),
			Color3.fromRGB(255, 178, 102),
			Color3.fromRGB(255, 204, 153),
			Color3.fromRGB(255, 178, 102),
			Color3.fromRGB(255, 153, 51),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	}
}

local function getRandomAIColor()
	-- 50% yellow, 50% others
	if math.random() < 0.5 then
		return AISnakeColors[1] -- Yellow
	else
		return AISnakeColors[math.random(2, #AISnakeColors)]
	end
end

local function deepCopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in orig do
			copy[orig_key] = deepCopy(orig_value)
		end
	else
		copy = orig
	end
	return copy
end

-- === VISUAL CREATION ===
local function createVisualHead(config, parentModel)
	local headPart = Instance.new("Part")
	headPart.Name = "AISnakeHead"
	headPart.Size = config.HeadSize
	headPart.Material = config.HeadMaterial
	headPart.Color = config.HeadColor
	headPart.Shape = Enum.PartType.Ball
	headPart.CanCollide = false
	headPart.CanTouch = true
	headPart.CanQuery = true
	headPart.Anchored = true
	headPart.TopSurface = Enum.SurfaceType.Smooth
	headPart.BottomSurface = Enum.SurfaceType.Smooth
	headPart.Parent = parentModel

	-- Make head invisible
	headPart.Transparency = 1

	local headLight = Instance.new("PointLight")
	headLight.Color = config.HeadColor
	headLight.Brightness = config.GlowIntensity + 2
	headLight.Range = config.GlowRange + 3
	headLight.Parent = headPart

	-- Eyes
	local leftEye = Instance.new("Part")
	leftEye.Name = "LeftEye"
	leftEye.Size = Vector3new(0.7, 0.7, 0.7)
	leftEye.Material = Enum.Material.Neon
	leftEye.Color = Color3.fromRGB(255, 255, 255)
	leftEye.Shape = Enum.PartType.Ball
	leftEye.CanCollide = false
	leftEye.Anchored = false
	leftEye.Parent = headPart

	local rightEye = Instance.new("Part")
	rightEye.Name = "RightEye"
	rightEye.Size = Vector3new(0.7, 0.7, 0.7)
	rightEye.Material = Enum.Material.Neon
	rightEye.Color = Color3.fromRGB(255, 255, 255)
	rightEye.Shape = Enum.PartType.Ball
	rightEye.CanCollide = false
	rightEye.Anchored = false
	rightEye.Parent = headPart

	local leftPupil = Instance.new("Part")
	leftPupil.Name = "LeftPupil"
	leftPupil.Size = Vector3new(0.3, 0.3, 0.3)
	leftPupil.Material = Enum.Material.Neon
	leftPupil.Color = Color3.fromRGB(0, 0, 0)
	leftPupil.Shape = Enum.PartType.Ball
	leftPupil.CanCollide = false
	leftPupil.Anchored = false
	leftPupil.Parent = leftEye

	local rightPupil = Instance.new("Part")
	rightPupil.Name = "RightPupil"
	rightPupil.Size = Vector3new(0.3, 0.3, 0.3)
	rightPupil.Material = Enum.Material.Neon
	rightPupil.Color = Color3.fromRGB(0, 0, 0)
	rightPupil.Shape = Enum.PartType.Ball
	rightPupil.CanCollide = false
	rightPupil.Anchored = false
	rightPupil.Parent = rightEye

	-- Position eyes
	leftEye.CFrame = headPart.CFrame * CFramenew(-0.6, 0.55, 0.8)
	rightEye.CFrame = headPart.CFrame * CFramenew(0.6, 0.55, 0.8)
	leftPupil.CFrame = leftEye.CFrame * CFramenew(0, 0, -0.25)
	rightPupil.CFrame = rightEye.CFrame * CFramenew(0, 0, -0.25)

	-- Weld eyes
	local leftEyeWeld = Instance.new("WeldConstraint")
	leftEyeWeld.Part0 = headPart
	leftEyeWeld.Part1 = leftEye
	leftEyeWeld.Parent = headPart

	local rightEyeWeld = Instance.new("WeldConstraint")
	rightEyeWeld.Part0 = headPart
	rightEyeWeld.Part1 = rightEye
	rightEyeWeld.Parent = headPart

	local leftPupilWeld = Instance.new("WeldConstraint")
	leftPupilWeld.Part0 = leftEye
	leftPupilWeld.Part1 = leftPupil
	leftPupilWeld.Parent = leftEye

	local rightPupilWeld = Instance.new("WeldConstraint")
	rightPupilWeld.Part0 = rightEye
	rightPupilWeld.Part1 = rightPupil
	rightPupilWeld.Parent = rightEye

	return {
		head = headPart,
		headLight = headLight,
		leftEye = leftEye,
		rightEye = rightEye,
		leftPupil = leftPupil,
		rightPupil = rightPupil,
		leftEyeWeld = leftEyeWeld,
		rightEyeWeld = rightEyeWeld,
		leftPupilWeld = leftPupilWeld,
		rightPupilWeld = rightPupilWeld,
	}
end

local function createSegment(index, position, color, config, parentModel, currentLength)
	local segment = getSegment(config)
	segment.Name = "AISegment" .. index

	-- Apply growth factor
	local growthFactor = 1
	if currentLength and currentLength > 200 then
		growthFactor = 1 + ((currentLength - 200) / 2800) * 1.0
	end

	segment.Size = config.SegmentSize * mathMin(growthFactor, 2.0)
	segment.Material = config.BodyMaterial or Enum.Material.Neon
	segment.Color = color
	segment.CFrame = CFramenew(position)
	segment.Parent = parentModel
	segment.Transparency = 0

	segment:SetAttribute("IsSnakeSegment", true)
	segment:SetAttribute("SegmentIndex", index)
	segment:SetAttribute("IsAISnake", true)

	-- Add glow to head segments
	if index <= 30 or index % 10 == 0 then
		local light = segment:FindFirstChild("Glow") or Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Range = config.GlowRange * 0.7
		light.Brightness = config.GlowIntensity * 0.8
		light.Enabled = true
		light.Parent = segment
	else
		local existingLight = segment:FindFirstChild("Glow")
		if existingLight then
			existingLight:Destroy()
		end
	end

	return segment
end

-- === HELPER FUNCTIONS ===
local function getPlayerLength(player)
	if not player or not player.Character then return 0 end
	local count = 0

	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance and snakeInstance.segments then
		return #snakeInstance.segments
	end

	for _, child in player.Character:GetChildren() do
		if child:IsA("BasePart") and child.Name:match("^Segment") then
			count = count + 1
		end
	end
	return count
end

local function getPlayerVelocity(player)
	if not player or not player.Character then return Vector3new(0, 0, 0) end
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:FindFirstChild("AssemblyLinearVelocity") then
		return rootPart.AssemblyLinearVelocity
	end
	return Vector3new(0, 0, 0)
end

-- Wall avoidance
local WALL_NAMES = {"SlitherIOWall_Left", "SlitherIOWall_Right", "SlitherIOWall_Top", "SlitherIOWall_Bottom"}
local wallParts = {}

task.spawn(function()
	task.wait(0.1)
	for _, wallName in WALL_NAMES do
		local wall = Workspace:FindFirstChild(wallName)
		if wall and wall:IsA("BasePart") then
			table.insert(wallParts, wall)
		end
	end
end)

-- Ground-based boundary detection with safe defaults
local MAP_BOUNDS = {
	minX = -350,
	maxX = 350,
	minZ = -350,
	maxZ = 350
}

-- Function to update bounds based on ground
local function updateMapBounds()
	local ground = Workspace:FindFirstChild("SlitherIOGround")
	if ground and ground:IsA("BasePart") then
		local halfSizeX = ground.Size.X / 2
		local halfSizeZ = ground.Size.Z / 2
		MAP_BOUNDS.minX = ground.Position.X - halfSizeX + 30
		MAP_BOUNDS.maxX = ground.Position.X + halfSizeX - 30
		MAP_BOUNDS.minZ = ground.Position.Z - halfSizeZ + 30
		MAP_BOUNDS.maxZ = ground.Position.Z + halfSizeZ - 30
		return true
	end
	return false
end

-- Initial bounds check
updateMapBounds()

local function getWallAvoidanceVector(headPos)
	local avoidVec = Vector3new(0, 0, 0)
	local avoidStrength = 0

	-- Check ground boundaries first
	local boundaryThreshold = 50
	local strongThreshold = 25

	-- Check X boundaries
	if headPos.X < MAP_BOUNDS.minX + boundaryThreshold then
		local dist = MAP_BOUNDS.minX - headPos.X + boundaryThreshold
		avoidVec = avoidVec + Vector3new(1, 0, 0) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	elseif headPos.X > MAP_BOUNDS.maxX - boundaryThreshold then
		local dist = headPos.X - MAP_BOUNDS.maxX + boundaryThreshold
		avoidVec = avoidVec + Vector3new(-1, 0, 0) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	end

	-- Check Z boundaries
	if headPos.Z < MAP_BOUNDS.minZ + boundaryThreshold then
		local dist = MAP_BOUNDS.minZ - headPos.Z + boundaryThreshold
		avoidVec = avoidVec + Vector3new(0, 0, 1) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	elseif headPos.Z > MAP_BOUNDS.maxZ - boundaryThreshold then
		local dist = headPos.Z - MAP_BOUNDS.maxZ + boundaryThreshold
		avoidVec = avoidVec + Vector3new(0, 0, -1) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	end

	if avoidStrength > 0 then
		return avoidVec.Unit * avoidStrength * 2, avoidStrength
	end

	return nil, 0
end

local function isPartsColliding(partA, partB)
	if not (partA and partA.Parent and partB and partB.Parent) then return false end
	local radiusA = (partA.Size.X + partA.Size.Y + partA.Size.Z) / 6
	local radiusB = (partB.Size.X + partB.Size.Y + partB.Size.Z) / 6
	local dist = (partA.Position - partB.Position).Magnitude
	return dist < (radiusA + radiusB) * 0.85
end

-- === AI PERSONALITIES ===
AISnake.PersonalityTypes = {
	"Aggressor", "Scavenger", "Guardian", "Opportunist", "Hunter", "Nomad", "Shadow", "Berserker"
}

AISnake.PersonalityDefinitions = {
	Aggressor = {
		Type = "Aggressor",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.15,
		TurnBias = 0.03,
		BoostChance = 0.06,
		CombatRadius = 45,
		RandomTurnInterval = 5.0,
		OrbSeekRadius = 100,
		Description = "Balanced aggressor - hunts when advantageous",
		FleeThreshold = 20,
		AggressionLevel = 0.7,
		PatrolRadius = 200,
	},
	Scavenger = {
		Type = "Scavenger",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = true,
		SpeedMultiplier = 1.1,
		TurnBias = 0.05,
		BoostChance = 0.04,
		CombatRadius = 25,
		RandomTurnInterval = 4.0,
		OrbSeekRadius = 200,
		Description = "Peaceful orb collector - avoids all conflict",
		FleeThreshold = 5,
		AggressionLevel = 0.0,
		PatrolRadius = 300,
	},
	Guardian = {
		Type = "Guardian",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.05,
		TurnBias = 0.02,
		BoostChance = 0.03,
		CombatRadius = 60,
		RandomTurnInterval = 6.0,
		OrbSeekRadius = 120,
		Description = "Territory defender - patrols specific areas",
		FleeThreshold = 30,
		AggressionLevel = 0.5,
		PatrolRadius = 150,
		TerritoryCenter = Vector3.new(0, 0, 0),
	},
	Opportunist = {
		Type = "Opportunist",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.2,
		TurnBias = 0.04,
		BoostChance = 0.08,
		CombatRadius = 40,
		RandomTurnInterval = 3.5,
		OrbSeekRadius = 140,
		Description = "Smart fighter - only attacks smaller snakes",
		FleeThreshold = 0,
		AggressionLevel = 0.8,
		PatrolRadius = 250,
		OnlyAttackSmaller = true,
	},
	Hunter = {
		Type = "Hunter",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.18,
		TurnBias = 0.02,
		BoostChance = 0.07,
		CombatRadius = 50,
		RandomTurnInterval = 5.5,
		OrbSeekRadius = 130,
		Description = "Persistent hunter - tracks targets",
		FleeThreshold = 25,
		AggressionLevel = 0.75,
		PatrolRadius = 220,
		TrackingDuration = 10,
	},
	Nomad = {
		Type = "Nomad",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.12,
		TurnBias = 0.06,
		BoostChance = 0.05,
		CombatRadius = 30,
		RandomTurnInterval = 2.5,
		OrbSeekRadius = 160,
		Description = "Wanderer - explores the entire map",
		FleeThreshold = 10,
		AggressionLevel = 0.2,
		PatrolRadius = 400,
		ExplorationBias = 0.8,
	},
	Shadow = {
		Type = "Shadow",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.22,
		TurnBias = 0.01,
		BoostChance = 0.02,
		CombatRadius = 55,
		RandomTurnInterval = 8.0,
		OrbSeekRadius = 110,
		Description = "Stealthy assassin - strikes from behind",
		FleeThreshold = 15,
		AggressionLevel = 0.6,
		PatrolRadius = 180,
		PreferRearAttack = true,
		StalkDistance = 30,
	},
	Berserker = {
		Type = "Berserker",
		TargetPlayers = true,
		TargetOrbs = false,
		AvoidOthers = false,
		SpeedMultiplier = 1.25,
		TurnBias = 0.05,
		BoostChance = 0.12,
		CombatRadius = 35,
		RandomTurnInterval = 6.0,
		OrbSeekRadius = 50,
		Description = "Reckless fighter - all aggression",
		FleeThreshold = 40,
		AggressionLevel = 1.0,
		PatrolRadius = 200,
		RageMode = true,
	},
}

-- === AI METHODS ===
function AISnake:findBestOrb()
	local minDist = self.Personality.OrbSeekRadius or 50
	local nearest = nil
	local headPos = self.HeadParts and self.HeadParts.head and self.HeadParts.head.Position or self.Position

	-- First check spatial grid for regular orbs
	local nearbyEntities = SpatialGrid.QueryRadius(headPos, minDist)

	-- Prioritize untargeted orbs
	local targetedOrbs = {}
	for ai, orb in AISnake._orbTargets do
		if ai ~= self and orb and orb.Parent then
			targetedOrbs[orb] = true
		end
	end

	-- Check upgrade orbs
	local orbFolder = Workspace:FindFirstChild("OrbFolder")
	if orbFolder then
		for _, orb in pairs(orbFolder:GetChildren()) do
			if orb:IsA("BasePart") and orb.Name == "UpgradeOrb" and not targetedOrbs[orb] then
				local dist = (orb.Position - headPos).Magnitude
				if dist < minDist then
					minDist = dist
					nearest = orb
				end
			end
		end
	end

	-- Check regular orbs
	if not nearest and #nearbyEntities > 0 then
		for _, entity in nearbyEntities do
			if entity.type == "ORB" and not targetedOrbs[entity.part] then
				local dist = (entity.part.Position - headPos).Magnitude
				if dist < minDist then
					minDist = dist
					nearest = entity.part
				end
			end
		end
	end

	return nearest, minDist
end

function AISnake:findNearestSnakeHead()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return nil, math.huge end
	local myPos = myHead.Position
	local minDist = math.huge
	local nearest = nil

	local nearbyEntities = SpatialGrid.QueryRadius(myPos, self.Personality.CombatRadius or 60)

	for _, entity in nearbyEntities do
		if entity.owner ~= self and (entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD") then
			local dist = (entity.part.Position - myPos).Magnitude
			if dist < minDist then
				minDist = dist
				if entity.type == "AI_HEAD" then
					nearest = {part = entity.part, isPlayer = false, snake = entity.owner}
				else
					nearest = {part = entity.part, isPlayer = true, player = entity.owner}
				end
			end
		end
	end
	return nearest, minDist
end

function AISnake:findNearbyThreats()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return {} end
	local myPos = myHead.Position
	local threats = {}

	local threatRadius = 80
	local nearbyEntities = SpatialGrid.QueryRadius(myPos, threatRadius)

	for _, entity in nearbyEntities do
		if entity.owner ~= self and (entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD") then
			local dist = (entity.part.Position - myPos).Magnitude
			local enemyLength = 0

			if entity.type == "AI_HEAD" then
				enemyLength = entity.owner.CurrentLength or 0
			else
				enemyLength = getPlayerLength(entity.owner)
			end

			local lengthDiff = enemyLength - self.CurrentLength
			local isThreat = false

			if lengthDiff > 20 or (dist < 20 and lengthDiff > 5) then
				isThreat = true
			end

			if isThreat then
				local threatLevel = mathMax(lengthDiff + 10, 5) / mathMax(dist, 1)
				table.insert(threats, {
					part = entity.part,
					position = entity.part.Position,
					isPlayer = entity.type == "PLAYER_HEAD",
					owner = entity.owner,
					distance = dist,
					threatLevel = threatLevel,
					lengthDiff = lengthDiff
				})
			end
		end
	end

	table.sort(threats, function(a, b) return a.threatLevel > b.threatLevel end)
	return threats
end

function AISnake:startBoost(duration)
	local now = tick()
	duration = duration or 1.5

	if self.Boosting and self.BoostEndTime > now + duration then
		return
	end

	self.Boosting = true
	self.IsBoosting = true
	self.BoostEndTime = now + duration
	self.BoostCooldown = self.BoostEndTime + mathRandom(15, 30) / 10
end

function AISnake:detectGiantSnakes()
	local myPos = self.Position
	local giants = {}

	for _, player in pairs(game.Players:GetPlayers()) do
		if player.Character then
			local length = getPlayerLength(player)
			if length > 300 then
				local head = player.Character:FindFirstChild("HumanoidRootPart")
				if head then
					local dist = (head.Position - myPos).Magnitude
					table.insert(giants, {
						player = player,
						length = length,
						distance = dist,
						position = head.Position
					})
				end
			end
		end
	end

	return giants
end

function AISnake:getFleeVector()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return Vector3new(0, 0, 1) end

	local headPos = myHead.Position
	local threats = self:findNearbyThreats()
	local wallVec, wallStrength = getWallAvoidanceVector(headPos)

	if #threats > 0 and not self.Boosting and mathRandom() < 0.3 then
		local closestThreat = threats[1]
		local boostDuration = 1.0

		if closestThreat.distance < 15 and closestThreat.lengthDiff > 30 then
			boostDuration = 1.5
		end

		self:startBoost(boostDuration)
	end

	local fleeDir = nil

	if #threats > 0 then
		local totalThreatVector = Vector3new(0, 0, 0)
		local totalWeight = 0

		for _, threat in threats do
			local threatPos = threat.part.Position
			local awayFromThreat = (headPos - threatPos).Unit
			local weight = 1 / mathMax(threat.distance, 1)
			totalThreatVector = totalThreatVector + awayFromThreat * weight
			totalWeight = totalWeight + weight
		end

		if totalWeight > 0 then
			fleeDir = (totalThreatVector / totalWeight).Unit

			local randomAngle = (math.random() - 0.5) * math.pi / 3
			local cosA = math.cos(randomAngle)
			local sinA = math.sin(randomAngle)
			fleeDir = Vector3new(
				fleeDir.X * cosA - fleeDir.Z * sinA,
				0,
				fleeDir.X * sinA + fleeDir.Z * cosA
			)
		end
	end

	if wallVec and wallStrength > 0.2 then
		if fleeDir then
			fleeDir = (fleeDir + wallVec.Unit * 2).Unit
		else
			fleeDir = wallVec.Unit
		end
	end

	if not fleeDir then
		local mapCenter = Vector3new(0, headPos.Y, 0)
		local toCenter = (mapCenter - headPos)
		local distFromCenter = toCenter.Magnitude

		if distFromCenter > 150 then
			fleeDir = toCenter.Unit
		else
			local randomAngle = mathRandom() * 2 * mathPi
			local randomDir = Vector3new(mathSin(randomAngle), 0, mathCos(randomAngle))
			if distFromCenter > 100 then
				fleeDir = (randomDir + toCenter.Unit * 0.5).Unit
			elseif distFromCenter > 60 then
				fleeDir = (randomDir + toCenter.Unit * 0.3).Unit
			else
				fleeDir = randomDir
			end
		end
	end

	local mapCenter = Vector3new(0, headPos.Y, 0)
	local distFromCenter = (mapCenter - headPos).Magnitude
	if distFromCenter > 180 and fleeDir then
		local toCenter = (mapCenter - headPos).Unit
		fleeDir = (fleeDir + toCenter * 0.4).Unit
	end

	return fleeDir
end

function AISnake:isPathSafe(targetPos, checkDistance)
	local myHead = self.HeadParts.head
	if not myHead then return false end

	local myPos = myHead.Position
	local toTarget = targetPos - myPos
	local distance = toTarget.Magnitude

	if distance < 0.1 then return true end

	local direction = toTarget.Unit
	local checkDist = mathMin(distance, checkDistance or 50)
	local stepSize = 5

	for d = stepSize, checkDist, stepSize do
		local checkPos = myPos + direction * d
		local nearbyEntities = SpatialGrid.QueryRadius(checkPos, 8)

		for _, entity in nearbyEntities do
			if entity.type == "AI_SEGMENT" or entity.type == "PLAYER_SEGMENT" then
				if entity.owner ~= self then
					return false
				end
			elseif entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD" then
				if entity.owner ~= self then
					local theirVel = entity.part.AssemblyLinearVelocity or Vector3.zero
					local timeToReach = d / self.Speed
					local theirFuturePos = entity.part.Position + theirVel * timeToReach

					if (checkPos - theirFuturePos).Magnitude < 10 then
						return false
					end
				end
			end
		end
	end

	return true
end

function AISnake:getSmartFleeDirection(threats)
	if not self.HeadParts or not self.HeadParts.head then
		return Vector3new(mathRandom(-1, 1), 0, mathRandom(-1, 1)).Unit
	end

	local myPos = self.HeadParts.head.Position
	local dangerVectors = {}

	for _, threat in ipairs(threats) do
		if threat.part and threat.part.Parent then
			local threatPos = threat.part.Position
			local awayFromThreat = (myPos - threatPos).Unit
			local weight = 1 / mathMax(threat.distance, 5)

			if threat.lengthDiff > 20 then
				weight = weight * 2
			end

			table.insert(dangerVectors, {
				direction = awayFromThreat,
				weight = weight
			})
		end
	end

	local fleeDir = Vector3.zero
	local totalWeight = 0

	for _, danger in ipairs(dangerVectors) do
		fleeDir = fleeDir + danger.direction * danger.weight
		totalWeight = totalWeight + danger.weight
	end

	local toCenter = Vector3new(0, myPos.Y, 0) - myPos
	local distFromCenter = toCenter.Magnitude
	if distFromCenter > 200 then
		local centerWeight = (distFromCenter - 200) / 100
		fleeDir = fleeDir + toCenter.Unit * centerWeight
		totalWeight = totalWeight + centerWeight
	end

	if totalWeight > 0 then
		fleeDir = (fleeDir / totalWeight).Unit

		if not self:isPathSafe(myPos + fleeDir * 30, 30) then
			local perpDir1 = Vector3new(-fleeDir.Z, 0, fleeDir.X)
			local perpDir2 = Vector3new(fleeDir.Z, 0, -fleeDir.X)

			if self:isPathSafe(myPos + perpDir1 * 30, 30) then
				fleeDir = perpDir1
			elseif self:isPathSafe(myPos + perpDir2 * 30, 30) then
				fleeDir = perpDir2
			end
		end

		return fleeDir
	end

	return toCenter.Unit
end

function AISnake:_determineAction()
	local headPos = self.HeadParts.head.Position
	local p = self.Personality
	local now = tick()
	local state = "WANDER"
	local steer = self.Direction

	-- Reset stuck behavior
	if self.State == self.LastState then
		self.StateTimer = (self.StateTimer or 0) + 0.1
		if self.StateTimer > 10 then -- Increased from 5 to 10 seconds
			self.TargetYaw = math.random() * 2 * math.pi
			self.State = "WANDER"
			self.StateTimer = 0
			self.LastPosition = nil
			self.StuckCounter = 0
		end
	else
		self.StateTimer = 0
	end
	self.LastState = self.State

	-- Clean up expired states
	if self.Avoiding and now > self.AvoidExpire then 
		self.Avoiding = false 
		self.FleeReason = ""
	end
	if self.isConfident and now > self.confidenceEndTime then
		self.isConfident = false
	end
	if self.TargetOrb and (not self.TargetOrb.Parent or now > self.TargetOrbExpire) then
		self.TargetOrb = nil
		AISnake._orbTargets[self] = nil
	end
	if self.TargetSnake and (not self.TargetSnake.part or not self.TargetSnake.part.Parent) then
		self.TargetSnake = nil
	end

	-- Priority 0: BOUNDARY AVOIDANCE
	local boundaryBuffer = 80
	local strongBuffer = 40
	local edgeSteer = nil
	local randomFactor = 0.3

	-- Check X boundaries
	if headPos.X > MAP_BOUNDS.maxX - boundaryBuffer then
		local strength = 1 - (MAP_BOUNDS.maxX - headPos.X) / boundaryBuffer
		edgeSteer = Vector3new(-1 + math.random() * randomFactor - randomFactor/2, 0, 0) * strength
	elseif headPos.X < MAP_BOUNDS.minX + boundaryBuffer then
		local strength = 1 - (headPos.X - MAP_BOUNDS.minX) / boundaryBuffer
		edgeSteer = Vector3new(1 + math.random() * randomFactor - randomFactor/2, 0, 0) * strength
	end

	-- Check Z boundaries
	if headPos.Z > MAP_BOUNDS.maxZ - boundaryBuffer then
		local strength = 1 - (MAP_BOUNDS.maxZ - headPos.Z) / boundaryBuffer
		local zSteer = Vector3new(0, 0, -1 + math.random() * randomFactor - randomFactor/2) * strength
		edgeSteer = edgeSteer and (edgeSteer + zSteer).Unit or zSteer
	elseif headPos.Z < MAP_BOUNDS.minZ + boundaryBuffer then
		local strength = 1 - (headPos.Z - MAP_BOUNDS.minZ) / boundaryBuffer
		local zSteer = Vector3new(0, 0, 1 + math.random() * randomFactor - randomFactor/2) * strength
		edgeSteer = edgeSteer and (edgeSteer + zSteer).Unit or zSteer
	end

	-- Strong boundary avoidance
	if edgeSteer and (
		headPos.X > MAP_BOUNDS.maxX - strongBuffer or 
			headPos.X < MAP_BOUNDS.minX + strongBuffer or
			headPos.Z > MAP_BOUNDS.maxZ - strongBuffer or 
			headPos.Z < MAP_BOUNDS.minZ + strongBuffer
		) then
		local randomAngle = mathRandom(-30, 30) * mathPi / 180
		local cosA = mathCos(randomAngle)
		local sinA = mathSin(randomAngle)
		local rotatedSteer = Vector3new(
			edgeSteer.X * cosA - edgeSteer.Z * sinA,
			0,
			edgeSteer.X * sinA + edgeSteer.Z * cosA
		)

		self.TargetSnake = nil
		self.TargetOrb = nil
		return "AVOID_BOUNDARY", rotatedSteer.Unit
	end

	-- Priority 1: Wall avoidance
	local wallVec, wallStrength = getWallAvoidanceVector(headPos)
	if wallVec and wallStrength > 0.3 then
		self.TargetSnake = nil
		return "AVOID_WALL", wallVec.Unit
	end

	-- Priority 2: COLLISION AVOIDANCE
	local lookAheadDist = self.Speed * 1.5
	local futurePos = headPos + self.Direction * lookAheadDist

	local nearbyDanger = SpatialGrid.QueryRadius(futurePos, 15)
	local collisionThreat = nil
	local minCollisionTime = math.huge

	for _, entity in nearbyDanger do
		if entity.owner ~= self and (entity.type:match("HEAD") or entity.type:match("SEGMENT")) then
			local theirPos = entity.part.Position
			local relPos = theirPos - headPos
			local relVel = self.Direction * self.Speed

			if entity.part.AssemblyLinearVelocity then
				relVel = relVel - entity.part.AssemblyLinearVelocity
			end

			local timeToCollision = relPos:Dot(relVel) / relVel:Dot(relVel)

			if timeToCollision > 0 and timeToCollision < 2 then
				local collisionPos = headPos + self.Direction * self.Speed * timeToCollision
				local theirFuturePos = theirPos

				if entity.part.AssemblyLinearVelocity then
					theirFuturePos = theirPos + entity.part.AssemblyLinearVelocity * timeToCollision
				end

				local collisionDist = (collisionPos - theirFuturePos).Magnitude

				if collisionDist < 8 and timeToCollision < minCollisionTime then
					minCollisionTime = timeToCollision
					collisionThreat = entity
				end
			end
		end
	end

	if collisionThreat and minCollisionTime < 1 then
		local threatPos = collisionThreat.part.Position
		local avoidDir = (headPos - threatPos).Unit
		local perpDir = Vector3new(-avoidDir.Z, 0, avoidDir.X)

		local leftClear = self:isPathSafe(headPos + perpDir * 20, 20)
		local rightClear = self:isPathSafe(headPos - perpDir * 20, 20)

		if leftClear and not rightClear then
			steer = perpDir
		elseif rightClear and not leftClear then
			steer = -perpDir
		else
			steer = avoidDir
		end

		self.TargetOrb = nil
		return "COLLISION_AVOID", steer
	end

	-- Priority 3: Threat assessment
	local threats = self:findNearbyThreats()
	local shouldFlee = false
	local fleeReason = ""

	local giants = self:detectGiantSnakes()
	if #giants > 0 then
		for _, giant in ipairs(giants) do
			if giant.distance < 150 then
				shouldFlee = true
				fleeReason = "giant_snake_detected"
				break
			end
		end
	end

	if #threats > 0 then
		local closestThreat = threats[1]

		if closestThreat.distance < 15 and closestThreat.lengthDiff > 5 then
			shouldFlee = true
			fleeReason = "immediate_danger"
		elseif closestThreat.distance < 25 and closestThreat.lengthDiff > 15 then
			shouldFlee = true
			fleeReason = "bigger_snake_nearby"
		elseif closestThreat.lengthDiff > 30 and closestThreat.distance < 40 then
			shouldFlee = true
			fleeReason = "giant_enemy"
		elseif #threats >= 2 and closestThreat.distance < 30 then
			shouldFlee = true
			fleeReason = "multiple_threats"
		end

		if closestThreat.owner and closestThreat.isPlayer then
			local playerLength = getPlayerLength(closestThreat.owner)
			if playerLength > 500 and closestThreat.distance < 200 then
				shouldFlee = true
				fleeReason = "massive_player_snake"
			end
		end

		if shouldFlee and (p.Type == "Aggressor" or p.Type == "Hunter") then
			if closestThreat.lengthDiff < 10 and closestThreat.distance > 20 then
				shouldFlee = false
			end
		end
	end

	if shouldFlee or self.Avoiding then
		self.TargetSnake = nil
		self.TargetOrb = nil

		local fleeDir = self:getSmartFleeDirection(threats)

		self.Avoiding = true
		self.AvoidDir = fleeDir
		self.AvoidExpire = now + 2.5
		if shouldFlee then self.FleeReason = fleeReason end
		return "FLEE", fleeDir
	end

	-- Priority 4: Smart orb seeking
	if p.TargetOrbs then
		if not self.TargetOrb or not self:isPathSafe(self.TargetOrb.Position) then
			local orb, dist = self:findBestOrb()

			if orb and dist < p.OrbSeekRadius * 1.5 and self:isPathSafe(orb.Position) then
				self.TargetOrb = orb
				self.TargetOrbExpire = now + mathRandom(50, 80) / 10
				AISnake._orbTargets[self] = orb
			else
				self.TargetOrb = nil
			end
		end

		if self.TargetOrb and self.TargetOrb.Parent then
			state = "SEEK_ORB"
			local toOrb = self.TargetOrb.Position - headPos
			local orbDist = toOrb.Magnitude

			if orbDist < 15 then
				steer = toOrb.Unit
			elseif orbDist < 30 then
				if not self:isPathSafe(self.TargetOrb.Position, 30) then
					self.TargetOrb = nil
					AISnake._orbTargets[self] = nil
				else
					steer = toOrb.Unit
				end
			else
				steer = toOrb.Unit
			end

			self.TargetSnake = nil
		end
	end

	-- Priority 5: Wandering
	if state == "WANDER" then
		local mapCenter = Vector3new(0, headPos.Y, 0)
		local toCenter = mapCenter - headPos
		local distFromCenter = toCenter.Magnitude

		if (now - (self.LastTurn or 0) > p.RandomTurnInterval) then
			local maxTurn = 45
			self.TargetYaw = self.TargetYaw + mathRad(mathRandom(-maxTurn, maxTurn))
			self.LastTurn = now
		end

		local baseSteer = Vector3new(mathSin(self.TargetYaw), 0, mathCos(self.TargetYaw))

		if not self:isPathSafe(headPos + baseSteer * 30, 30) then
			for i = 1, 8 do
				local testAngle = self.TargetYaw + (i * mathPi / 4)
				local testSteer = Vector3new(mathSin(testAngle), 0, mathCos(testAngle))
				if self:isPathSafe(headPos + testSteer * 30, 30) then
					baseSteer = testSteer
					self.TargetYaw = testAngle
					break
				end
			end
		end

		if distFromCenter > 250 then
			steer = toCenter.Unit
		elseif distFromCenter > 150 then
			local centerBias = toCenter.Unit * 0.7
			steer = (baseSteer + centerBias).Unit
		else
			steer = baseSteer
		end
	end

	return state, steer
end

function AISnake:updateBrain()
	if not self._active or not self.HeadParts or not self.HeadParts.head or not self.HeadParts.head.Parent then
		return
	end
	local state, steer = self:_determineAction()
	self.State = state
	self.SteerDirection = steer
end

-- === AI CONSTRUCTOR (FIXED) ===
function AISnake.new(startPosition)
	if #AISnake._activeSnakes >= MAX_AI_SNAKES then
		print("AI Snake limit reached:", MAX_AI_SNAKES)
		return nil
	end

	local self = setmetatable({}, AISnake)
	self.Config = deepCopy(SnakeConfig)

	-- Update map bounds
	updateMapBounds()

	-- Get random AI color
	local colorData = getRandomAIColor()
	self.Config.HeadColor = colorData.HeadColor
	self.Config.BodyColors = colorData.BodyColors
	self.Config.HeadMaterial = colorData.HeadMaterial
	self.Config.BodyMaterial = colorData.BodyMaterial

	self.Position = startPosition or Vector3new(0, 5, 0)
	self.Direction = Vector3new(0, 0, 1)
	self.Speed = self.Config.BaseSpeed or 10
	self.NormalSpeed = self.Config.BaseSpeed or 10
	self.BoostSpeed = self.Config.BoostSpeed or 24
	self.TurnSpeed = self.Config.TurnSpeed or 1.8
	self.RandomTurnInterval = 1.5
	self.LastTurn = tick()
	self.TargetYaw = 0
	self.CurrentYaw = 0

	self.FollowSpeed = self.Config.FollowSpeed or 0.95
	self.BoostFollowSpeed = self.Config.BoostFollowSpeed or 0.98
	self.SegmentSpacing = self.Config.SegmentSpacing or 2.2
	self.IsBoosting = false

	self.TargetOrb = nil
	self.TargetOrbExpire = 0

	self.State = "WANDER"
	self.SteerDirection = self.Direction
	self.Boosting = false
	self.BoostEndTime = 0
	self.BoostCooldown = 0
	self.TargetSnake = nil
	self.Avoiding = false
	self.AvoidExpire = 0
	self.AvoidDir = nil
	self.FleeReason = ""

	self.isConfident = false
	self.confidenceEndTime = 0
	self.circleAngle = mathRandom() * 2 * mathPi
	self.killCount = 0
	self.lastKillTime = 0

	-- Personality
	local pType = AISnake.PersonalityTypes[mathRandom(1, #AISnake.PersonalityTypes)]
	self.Personality = deepCopy(AISnake.PersonalityDefinitions[pType])
	self._personalityType = pType

	if self.Personality.Type == "Guardian" then
		local territoryAngle = mathRandom() * 2 * mathPi
		local territoryRadius = mathRandom(100, 200)
		self.Personality.TerritoryCenter = Vector3new(
			mathCos(territoryAngle) * territoryRadius,
			0,
			mathSin(territoryAngle) * territoryRadius
		)
	end

	self.Model = getOrCreateSnakeModel(tostring(self) .. "_" .. mathRandom(100000,999999))
	for _, obj in self.Model:GetChildren() do
		obj:Destroy()
	end

	self.RootPart = Instance.new("Part")
	self.RootPart.Name = "AISnakeRoot"
	self.RootPart.Size = Vector3new(2, 2, 2)
	self.RootPart.Anchored = true
	self.RootPart.CanCollide = false
	self.RootPart.Transparency = 1
	self.RootPart.Position = self.Position
	self.RootPart.Parent = self.Model

	self.HeadParts = createVisualHead(self.Config, self.Model)

	self.Segments = {}
	self.CurrentLength = self.Config.InitialLength

	-- FIXED: Proper position history initialization
	self.MaxHistorySize = mathCeil(self.Config.MaxSegments * 1.2) + 20
	self.PositionHistory = table.create(self.MaxHistorySize)
	self.HistoryHead = 1

	-- Initialize history with proper spread to prevent stretching
	for i = 1, self.MaxHistorySize do
		local historyOffset = self.Direction * (-i * 0.5)
		local historyPos = self.Position + historyOffset
		self.PositionHistory[i] = { position = historyPos, lookVector = self.Direction }
	end

	function self:addToHistory(data)
		self.PositionHistory[self.HistoryHead] = data
		self.HistoryHead = (self.HistoryHead % self.MaxHistorySize) + 1
	end

	function self:getFromHistory(stepsBack)
		local index = self.HistoryHead - stepsBack
		if index < 1 then
			index = index + self.MaxHistorySize
		end
		return self.PositionHistory[index]
	end

	-- FIXED: Create segments at proper positions
	for i = 1, self.CurrentLength do
		local segmentOffset = self.Direction * (-i * self.SegmentSpacing * 0.15)
		local pos = self.Position + segmentOffset
		local colorIndex = ((i - 1) % #self.Config.BodyColors) + 1
		local color = self.Config.BodyColors[colorIndex]
		local segment = createSegment(i, pos, color, self.Config, self.Model, i)
		self.Segments[i] = segment

		-- Start segments invisible
		segment.Transparency = 1
	end

	-- Make segments visible after initialization
	task.defer(function()
		task.wait(0.1)
		for _, segment in ipairs(self.Segments) do
			if segment and segment.Parent then
				segment.Transparency = 0
			end
		end
	end)

	table.insert(AISnake._activeSnakes, self)
	self._active = true

	-- Stuck detection
	self._lastPositions = {}
	self._stuckCheckTime = 0
	self._lastStuckCheck = tick()

	-- Spawn protection
	self._spawnProtection = tick() + 3  -- 3 second spawn protection

	return self
end

-- === OTHER METHODS ===
function AISnake:grow(amount)
	amount = amount or 5
	for i = 1, amount do
		if self.CurrentLength < self.Config.MaxSegments then
			self.CurrentLength = self.CurrentLength + 1
			local colorIndex = ((self.CurrentLength - 1) % #self.Config.BodyColors) + 1
			local color = self.Config.BodyColors[colorIndex]
			local lastSegment = self.Segments[#self.Segments]
			local newPos = lastSegment and lastSegment.Position or self.Position
			local segment = createSegment(self.CurrentLength, newPos, color, self.Config, self.Model, self.CurrentLength)
			self.Segments[self.CurrentLength] = segment

			segment.Transparency = 1
			segment.Size = Vector3new(0.1, 0.1, 0.1)

			local growthFactor = 1
			if self.CurrentLength > 200 then
				growthFactor = 1 + ((self.CurrentLength - 200) / 2800) * 1.0
			end
			local finalSize = self.Config.SegmentSize * mathMin(growthFactor, 2.0)

			task.spawn(function()
				if not segment or not segment.Parent then return end
				local growTime = 0.18
				local t = 0
				local startSize = Vector3new(0.1, 0.1, 0.1)
				while t < growTime do
					t = t + RunService.Heartbeat:Wait()
					if not segment or not segment.Parent then return end
					local alpha = mathMin(t / growTime, 1)
					segment.Size = startSize:Lerp(finalSize, alpha)
					segment.Transparency = 1 - alpha
				end
				if segment and segment.Parent then
					segment.Size = finalSize
					segment.Transparency = 0
				end
			end)
		end
	end
end

function AISnake:setConfidenceBuff()
	if not self._active then return end
	self.isConfident = true
	self.confidenceEndTime = tick() + 8
	self.killCount = self.killCount + 1
	self.lastKillTime = tick()
end

function AISnake:Destroy()
	if not self._active then return end
	self._active = false
	self._destroyed = true

	-- Untrack snake
	if AISnakeOrbPickup then
		pcall(function()
			AISnakeOrbPickup.UntrackSnake(self)
		end)
	end

	-- Remove from active list
	for i = #AISnake._activeSnakes, 1, -1 do
		if AISnake._activeSnakes[i] == self then
			table.remove(AISnake._activeSnakes, i)
			break
		end
	end
	AISnake._orbTargets[self] = nil

	-- Spawn orbs
	local orbSpawnData = {}
	if self.HeadParts and self.HeadParts.head and self.HeadParts.head.Parent then
		local head = self.HeadParts.head
		table.insert(orbSpawnData, {position = head.Position, size = 3.5, color = head.Color})
	end

	local ORB_SPAWN_DENSITY = 5
	for i = 1, #self.Segments do
		if i % ORB_SPAWN_DENSITY == 1 then
			local segment = self.Segments[i]
			if segment and segment.Parent then
				table.insert(orbSpawnData, {position = segment.Position, size = 1.8, color = segment.Color})
			end
		end
	end

	-- Spawn orbs
	task.spawn(function()
		if OrbUtils and OrbUtils.spawnOrb then
			for i = 1, #orbSpawnData do
				local data = orbSpawnData[i]
				pcall(function()
					OrbUtils.spawnOrb(data.position, data.size, data.color)
				end)
			end
		end
	end)

	-- Destroy segments
	for i = 1, #self.Segments do
		local segment = self.Segments[i]
		if segment then
			pcall(function()
				segment:Destroy()
			end)
		end
	end
	self.Segments = {}

	-- Destroy head parts
	if self.HeadParts then
		for name, part in pairs(self.HeadParts) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function()
					part:Destroy()
				end)
			end
		end
	end

	-- Destroy model
	if self.Model and self.Model.Parent then
		pcall(function()
			for _, descendant in ipairs(self.Model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant:Destroy()
				end
			end
			self.Model:Destroy()
		end)
	end

	-- Clear references
	self.Model = nil
	self.HeadParts = nil
	self.RootPart = nil
	self.Segments = nil
end

-- === SMOOTHER MOVEMENT (FIXED) ===
function AISnake:updateMovement(dt)
	if self._destroyed then return end

	if not self._active or not self.HeadParts or not self.HeadParts.head or not self.HeadParts.head.Parent then
		if self._active and not self._destroyed then 
			self:Destroy() 
		end
		return
	end

	local now = tick()
	local p = self.Personality
	local state = self.State
	local steer = self.SteerDirection

	-- SPAWN PROTECTION - Don't check boundaries for first few seconds
	local isSpawnProtected = now < (self._spawnProtection or 0)

	-- Validate position (unless spawn protected)
	if not isSpawnProtected then
		if self.Position.X < MAP_BOUNDS.minX - 10 or self.Position.X > MAP_BOUNDS.maxX + 10 or
			self.Position.Z < MAP_BOUNDS.minZ - 10 or self.Position.Z > MAP_BOUNDS.maxZ + 10 then
			-- Gentle repositioning instead of teleporting
			local safeX = mathClamp(self.Position.X, MAP_BOUNDS.minX + 50, MAP_BOUNDS.maxX - 50)
			local safeZ = mathClamp(self.Position.Z, MAP_BOUNDS.minZ + 50, MAP_BOUNDS.maxZ - 50)
			self.Position = Vector3new(safeX, self.Position.Y, safeZ)
			self.Direction = Vector3new(mathRandom() - 0.5, 0, mathRandom() - 0.5).Unit
			self.State = "WANDER"
			return
		end
	end

	-- Turning
	local forward = self.Direction
	local flatForward = Vector3new(forward.X, 0, forward.Z).Unit
	local flatSteer = Vector3new(steer.X, 0, steer.Z)
	local angle = 0
	if flatSteer.Magnitude > 0.01 then
		flatSteer = flatSteer.Unit
		angle = mathAtan2(flatSteer.X, flatSteer.Z) - mathAtan2(flatForward.X, flatForward.Z)
		if angle > mathPi then angle = angle - 2 * mathPi end
		if angle < -mathPi then angle = angle + 2 * mathPi end
	end
	local desiredYaw = self.CurrentYaw + angle
	self.TargetYaw = desiredYaw

	-- Turn speed
	local turnSpeed = self.TurnSpeed

	if state == "SEEK_ORB" and self.TargetOrb then
		local toOrb = (self.TargetOrb.Position - self.Position)
		local dist = toOrb.Magnitude
		if dist < 20 then
			turnSpeed = turnSpeed * 1.5
		end
	elseif state == "AVOID_WALL" then
		turnSpeed = turnSpeed * 1.3
	elseif state == "AVOID_BOUNDARY" then
		turnSpeed = turnSpeed * 2.5
	elseif state == "COLLISION_AVOID" then
		turnSpeed = turnSpeed * 3.0
	end

	if self.Boosting then
		turnSpeed = turnSpeed * 0.85
	end

	-- Apply turning
	local yawDiff = self.TargetYaw - self.CurrentYaw
	if yawDiff > mathPi then yawDiff = yawDiff - 2 * mathPi end
	if yawDiff < -mathPi then yawDiff = yawDiff + 2 * mathPi end

	local maxTurn = turnSpeed * dt
	yawDiff = mathClamp(yawDiff, -maxTurn, maxTurn)
	self.CurrentYaw = self.CurrentYaw + yawDiff

	self.Direction = Vector3new(mathSin(self.CurrentYaw), 0, mathCos(self.CurrentYaw))

	-- Movement variation
	if self.State == "WANDER" or self.State == "FLEE" then
		local wobbleTime = tick() * 2
		local wobbleAmount = 0.1
		local wobble = Vector3new(
			math.sin(wobbleTime) * wobbleAmount,
			0,
			math.cos(wobbleTime * 1.3) * wobbleAmount
		)
		self.Direction = (self.Direction + wobble).Unit
	end

	-- REMOVED: Emergency giant snake escape (causes teleporting)

	-- Boundary force (gentler, only when not spawn protected)
	if not isSpawnProtected then
		local lookAheadTime = 1.0
		local futurePos = self.Position + self.Direction * self.Speed * lookAheadTime

		local boundaryForce = Vector3new(0, 0, 0)
		local boundaryStrength = 0

		if futurePos.X > MAP_BOUNDS.maxX - 50 then
			local dist = MAP_BOUNDS.maxX - futurePos.X
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(-1, 0, 0)
		elseif futurePos.X < MAP_BOUNDS.minX + 50 then
			local dist = futurePos.X - MAP_BOUNDS.minX
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(1, 0, 0)
		end

		if futurePos.Z > MAP_BOUNDS.maxZ - 50 then
			local dist = MAP_BOUNDS.maxZ - futurePos.Z
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(0, 0, -1)
		elseif futurePos.Z < MAP_BOUNDS.minZ + 50 then
			local dist = futurePos.Z - MAP_BOUNDS.minZ
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(0, 0, 1)
		end

		if boundaryStrength > 0.1 then
			boundaryForce = boundaryForce.Unit
			self.Direction = (self.Direction * (1 - boundaryStrength) + boundaryForce * boundaryStrength).Unit
			if boundaryStrength > 0.5 then
				self.State = "AVOID_BOUNDARY"
				self.TargetOrb = nil
				self.TargetSnake = nil
			end
		end
	end

	-- Boost management
	if self.Boosting and now > self.BoostEndTime then
		self.Boosting = false
		self.IsBoosting = false
	end

	-- Smart boost usage
	if not self.Boosting and now > self.BoostCooldown then
		local shouldBoost = false
		local boostDuration = 1.2

		if state == "AVOID_WALL" then
			shouldBoost = true
			boostDuration = 0.8
		elseif state == "SEEK_ORB" then
			if mathRandom() < 0.02 then
				shouldBoost = true
				boostDuration = 0.5
			end
		elseif state == "FLEE" then
			if mathRandom() < 0.3 then
				shouldBoost = true
				boostDuration = 1.5
			end
		else
			if mathRandom() < (p.BoostChance or 0) * 0.3 then
				shouldBoost = true
			end
		end

		if shouldBoost then
			self:startBoost(boostDuration)
		end
	end

	-- Speed calculation
	local speedMultiplier = p.SpeedMultiplier or 1

	if self.Boosting then
		self.Speed = self.BoostSpeed * speedMultiplier
	else
		self.Speed = mathMax(self.NormalSpeed, self.NormalSpeed * speedMultiplier)
	end

	-- Position update (with clamping only when not spawn protected)
	local moveDistance = self.Speed * dt
	local newPosition = self.Position + self.Direction * moveDistance

	if not isSpawnProtected then
		local margin = 20
		local clampedX = mathClamp(newPosition.X, MAP_BOUNDS.minX + margin, MAP_BOUNDS.maxX - margin)
		local clampedZ = mathClamp(newPosition.Z, MAP_BOUNDS.minZ + margin, MAP_BOUNDS.maxZ - margin)

		if clampedX ~= newPosition.X or clampedZ ~= newPosition.Z then
			local escapeAngle = mathRandom() * mathPi - mathPi/2
			local currentAngle = mathAtan2(self.Direction.X, self.Direction.Z)
			local newAngle = currentAngle + escapeAngle

			self.Direction = Vector3new(mathSin(newAngle), 0, mathCos(newAngle))
			self.CurrentYaw = newAngle
			self.TargetYaw = newAngle

			self.TargetOrb = nil
			self.TargetSnake = nil
			self.State = "WANDER"
		end

		self.Position = Vector3new(clampedX, newPosition.Y, clampedZ)
	else
		self.Position = newPosition
	end

	-- REMOVED: Stuck detection that causes teleporting

	self.RootPart.Position = self.Position

	local headOffset = self.Direction * 1.5
	local newHeadPos = self.Position + headOffset
	self.HeadParts.head.CFrame = CFramelookAt(newHeadPos, newHeadPos + self.Direction)

	-- Keep head invisible
	if self.HeadParts.head.Transparency ~= 1 then
		self.HeadParts.head.Transparency = 1
	end

	-- Set velocity
	self.HeadParts.head.AssemblyLinearVelocity = self.Direction * self.Speed

	-- Orb pickup
	local headPos = self.HeadParts.head.Position
	local pickupRadius = 8

	local orbsToCheck = {}

	for _, obj in pairs(Workspace:GetChildren()) do
		if obj:IsA("BasePart") and (obj.Name == "Orb" or obj.Name == "UpgradeOrb" or obj.Name == "DeathOrb") then
			table.insert(orbsToCheck, obj)
		end
	end

	local orbFolder = Workspace:FindFirstChild("OrbFolder") or Workspace:FindFirstChild("Orbs")
	if orbFolder then
		for _, orb in pairs(orbFolder:GetChildren()) do
			if orb:IsA("BasePart") then
				table.insert(orbsToCheck, orb)
			end
		end
	end

	for _, orb in pairs(orbsToCheck) do
		if orb:IsA("BasePart") and orb.Parent then
			local dist = (orb.Position - headPos).Magnitude

			if dist <= pickupRadius then
				local isBeingCollected = orb:GetAttribute("BeingCollected")
				if isBeingCollected then
					continue
				end

				orb:SetAttribute("BeingCollected", true)

				local valueObj = orb:FindFirstChild("Value")
				local orbValue = valueObj and valueObj.Value or 1

				if orb.Name == "UpgradeOrb" then
					if SnakeUpgrades then
						print("🎯 AI Snake collecting upgrade orb!")
						SnakeUpgrades.GiveUpgrade(self)
					end
				else
					self:grow(orbValue)
				end

				orb:Destroy()
				break
			end
		end
	end

	-- History management
	local lastHistoryPoint = self:getFromHistory(1)
	local dist = (self.Position - lastHistoryPoint.position).Magnitude

	if dist > 0.02 then
		if dist > self.Config.SegmentSpacing * 0.7 then
			local isBoosting = self.Speed > 16
			local maxInterp = isBoosting and 6 or 3
			local numInterpolations = mathMin(mathFloor(dist / (self.Config.SegmentSpacing * 0.35)), maxInterp)
			for i = 1, numInterpolations do
				local fraction = i / (numInterpolations + 1)
				local interpPos = lastHistoryPoint.position:Lerp(self.Position, fraction)
				local interpLook = lastHistoryPoint.lookVector:Lerp(self.Direction, fraction).Unit
				self:addToHistory({ position = interpPos, lookVector = interpLook })
			end
		end
		self:addToHistory({ position = self.Position, lookVector = self.Direction })
	end

	-- Segment following
	local followSpeed = self.IsBoosting and self.BoostFollowSpeed or self.FollowSpeed

	self._segmentUpdateFrame = (self._segmentUpdateFrame or 0) + 1

	local segmentSkip = SEGMENT_UPDATE_SKIP
	if self.CurrentLength > VERY_LONG_SNAKE_THRESHOLD then
		segmentSkip = 2
	elseif self.CurrentLength > LONG_SNAKE_THRESHOLD then
		segmentSkip = 1
	end

	local updateOffset = self._segmentUpdateFrame % segmentSkip

	for i = 1 + updateOffset, self.CurrentLength, segmentSkip do
		local segment = self.Segments[i]
		if segment and segment.Parent then
			local delay = mathFloor(i * 1.2)
			local targetData = self:getFromHistory(delay)
			if targetData then
				local spacingMultiplier = 0.15
				if self.CurrentLength > 1500 then
					spacingMultiplier = 0.2
				end
				local segmentPos = targetData.position - targetData.lookVector * (self.Config.SegmentSpacing * spacingMultiplier)
				local currentSegmentPos = segment.Position

				if i > 1 then
					local prevSegment = self.Segments[i - 1]
					if prevSegment and prevSegment.Parent then
						local gap = (currentSegmentPos - prevSegment.Position).Magnitude
						if gap > self.Config.SegmentSpacing * 1.5 then
							local dir = (prevSegment.Position - currentSegmentPos).Unit
							segmentPos = prevSegment.Position - dir * self.Config.SegmentSpacing
						end
					end
				end

				local newPos = currentSegmentPos:Lerp(segmentPos, followSpeed)
				segment.CFrame = CFramenew(newPos)
			end
		end
	end

	-- Tail optimization for very long snakes
	if self.CurrentLength > VERY_LONG_SNAKE_THRESHOLD then
		if self._segmentUpdateFrame % 10 == 0 then
			local tailStart = mathFloor(self.CurrentLength * 0.7)
			for i = tailStart, self.CurrentLength, 10 do
				local segment = self.Segments[i]
				if segment and segment.Parent then
					local delay = mathFloor(i * 1.2)
					local targetData = self:getFromHistory(delay)
					if targetData then
						local spacingMultiplier = 0.15
						if self.CurrentLength > 1500 then
							spacingMultiplier = 0.2
						end
						local segmentPos = targetData.position - targetData.lookVector * (self.Config.SegmentSpacing * spacingMultiplier)

						if i > 300 then
							local prevSegment = self.Segments[i - 1]
							if prevSegment and prevSegment.Parent then
								local gap = (segment.Position - prevSegment.Position).Magnitude
								if gap > self.Config.SegmentSpacing * 1.5 then
									local dir = (prevSegment.Position - segment.Position).Unit
									segmentPos = prevSegment.Position - dir * self.Config.SegmentSpacing
								end
							end
						end

						segment.Position = segmentPos
					end
				end
			end
		end
	end

	-- FIXED: Less aggressive collision detection to prevent spam dying
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead or not myHead.Parent then return end

	-- Skip collision detection during spawn protection
	if isSpawnProtected then return end

	self._collisionCheckFrame = (self._collisionCheckFrame or 0) + 1
	if self._collisionCheckFrame % 6 ~= 0 then return end  -- Check even less often

	local searchRadius = 3.5
	local nearbyEntities = SpatialGrid.QueryRadius(myHead.Position, searchRadius)

	for _, data in nearbyEntities do
		local otherPart = data.part
		if otherPart == myHead then continue end

		if isPartsColliding(myHead, otherPart) then
			local otherOwner = data.owner

			-- Add double-check to prevent false positives
			if (myHead.Position - otherPart.Position).Magnitude > 5 then
				continue  -- Skip if distance is too far (false positive)
			end

			if data.type == "AI_HEAD" then
				if tostring(self) < tostring(otherOwner) then
					if self.CurrentLength > otherOwner.CurrentLength then
						otherOwner:Destroy()
						self:setConfidenceBuff()
					elseif otherOwner.CurrentLength > self.CurrentLength then
						self:Destroy()
						otherOwner:setConfidenceBuff()
					else
						otherOwner:Destroy()
						self:Destroy()
					end
				end
				return
			elseif data.type == "AI_SEGMENT" then
				if otherOwner ~= self then
					self:Destroy()
					otherOwner:setConfidenceBuff()
					return
				end
			elseif data.type == "PLAYER_HEAD" then
				if otherOwner.Character and otherOwner.Character:FindFirstChildOfClass("Humanoid") then
					otherOwner.Character:FindFirstChildOfClass("Humanoid").Health = 0
				end
				self:Destroy()
				return
			elseif data.type == "PLAYER_SEGMENT" then
				self:Destroy()
				return
			end
		end
	end
end

-- === UPDATE LOOPS ===
if AISnake._movementConnection then AISnake._movementConnection:Disconnect() end
if AISnake._brainConnection then AISnake._brainConnection:Disconnect() end

AISnake._movementConnection = RunService.Heartbeat:Connect(function(dt)
	local snakesToUpdate = {}
	for i = 1, #AISnake._activeSnakes do
		local snake = AISnake._activeSnakes[i]
		if snake and snake._active then
			table.insert(snakesToUpdate, snake)
		end
	end

	for i = 1, #snakesToUpdate do
		local snake = snakesToUpdate[i]
		if snake and snake._active then
			snake:updateMovement(dt)
		end
	end
end)

AISnake._brainUpdateIndex = 1
AISnake._spatialGridTimer = 0

AISnake._brainConnection = RunService.Stepped:Connect(function(time, deltaTime)
	AISnake._spatialGridTimer = AISnake._spatialGridTimer + deltaTime

	if AISnake._spatialGridTimer >= SPATIAL_GRID_UPDATE_RATE then
		AISnake._spatialGridTimer = 0

		SpatialGrid.Clear()

		for _, snake in AISnake._activeSnakes do
			if snake._active and snake.HeadParts and snake.HeadParts.head then
				SpatialGrid.Insert(snake.HeadParts.head, snake, "AI_HEAD")

				for i = 1, #snake.Segments, 4 do
					local segment = snake.Segments[i]
					if segment then
						SpatialGrid.Insert(segment, snake, "AI_SEGMENT")
					end
				end
			end
		end

		for _, player in Players:GetPlayers() do
			if player.Character then
				local head = player.Character:FindFirstChild("HumanoidRootPart")
				if head then
					SpatialGrid.Insert(head, player, "PLAYER_HEAD")
				end

				local segmentCount = 0
				for _, part in player.Character:GetChildren() do
					if part:IsA("BasePart") and part.Name:match("Segment") then
						segmentCount = segmentCount + 1
						if segmentCount % 4 == 1 then
							SpatialGrid.Insert(part, player, "PLAYER_SEGMENT")
						end
					end
				end
			end
		end

		for _, orb in OrbUtils.orbs do
			SpatialGrid.Insert(orb, orb, "ORB")
		end
	end 

	local snakes = AISnake._activeSnakes
	if #snakes == 0 then return end

	local nearestPlayerPos = nil
	local nearestDist = math.huge
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local pos = player.Character.HumanoidRootPart.Position
			if nearestPlayerPos == nil then
				nearestPlayerPos = pos
			end
		end
	end

	for i = 1, BRAIN_UPDATES_PER_FRAME do
		if AISnake._brainUpdateIndex > #snakes then
			AISnake._brainUpdateIndex = 1
		end

		local snake = snakes[AISnake._brainUpdateIndex]
		if snake and snake._active then
			local shouldUpdate = true
			if nearestPlayerPos and snake.Position then
				local dist = (snake.Position - nearestPlayerPos).Magnitude
				if dist > AI_UPDATE_DISTANCE then
					shouldUpdate = false
					if snake.HeadParts and snake.HeadParts.head then
						snake.HeadParts.head.CFrame = CFrame.new(snake.Position)
					end
				end
			end

			if shouldUpdate then
				snake:updateBrain()
			end
		end

		AISnake._brainUpdateIndex = AISnake._brainUpdateIndex + 1
	end
end)

return AISnake