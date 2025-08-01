-- AISnake Module: SMOOTH AI MOVEMENT V4.0 - FIXED ERRATIC BEHAVIOR
-- Completely redesigned AI brain for smooth, intelligent movement
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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
		-- AI Snakes can now pick up upgrade orbs
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
local MAX_AI_SNAKES = 10  -- Reduced from 14 for better performance
local SPATIAL_GRID_UPDATE_RATE = 1.0  -- Increased from 0.5 (update less often)
local BRAIN_UPDATES_PER_FRAME = 3  -- Update 3 snakes per frame to prevent freezing
local DEBUG_UPDATE_RATE = 5.0  -- Increased from 2.0 (debug less often)
local AI_HEIGHT = 5
local SEGMENT_UPDATE_SKIP = 2  -- Update every other segment for performance
local LONG_SNAKE_THRESHOLD = 100  -- Snakes longer than this use more aggressive optimization
local VERY_LONG_SNAKE_THRESHOLD = 300  -- Even more optimization for very long snakes
local AI_UPDATE_DISTANCE = 200  -- Only update AI within this distance of players
local SEGMENT_POOL_MAX = 500  -- Increased pool size for better reuse

-- LOD Constants (ENHANCED for progressive visibility like slither.io)
local VISIBILITY_CHECK_INTERVAL = 5  -- Check visibility every N frames
local RENDER_DISTANCE = 1000  -- Maximum render distance
local LOD_DISTANCE_NEAR = 200   -- Full snake visible
local LOD_DISTANCE_MID = 400    -- 70% of snake visible
local LOD_DISTANCE_FAR = 600    -- 40% of snake visible
local LOD_DISTANCE_MINIMAL = 800 -- 20% of snake visible (head + some body)
local BEAM_SYNC_INTERVAL = 3    -- Sync beams with parts every N frames
local FORCE_RENDER_SEGMENTS = 150  -- Always force render first N segments for nearby snakes
local MIN_VISIBLE_SEGMENTS = 10    -- Minimum segments to show even from far away
local MAX_VISIBLE_SEGMENTS = 2000  -- Maximum visible segments at once
local DYNAMIC_SEGMENT_LIMIT = 800  -- Initial physical segment creation limit

-- Progressive visibility percentages based on distance
local VISIBILITY_PERCENTAGES = {
	near = 1.0,      -- 100% of snake visible
	mid = 0.7,       -- 70% of snake visible
	far = 0.4,       -- 40% of snake visible
	minimal = 0.2,   -- 20% of snake visible
	veryFar = 0.1    -- 10% of snake visible (at least head + few segments)
}

-- Visual Constants from OptimizedSnakeSystem
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 2 -- Professional glow intensity
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 10 -- Optimal segments
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments
local VISUAL_SMOOTHING_FACTOR = 0.6 -- Higher = smoother transitions

-- Growth Animation Constants
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions
local GROWTH_PULSE_STRENGTH = 0.1 -- How much segments pulse when growing
local GROWTH_WAVE_SPEED = 10 -- Speed of growth wave effect

-- Professional Visual Enhancement Constants
local BEAM_TEXTURE_SPEED = 2 -- Flow animation speed for beams
local PARTICLE_VELOCITY_INHERITANCE = 0.7 -- Natural trailing behavior
local PARTICLE_DRAG = 3 -- Exponential velocity decay for boost effects
local BOOST_PARTICLE_SIZE = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0)
}
local MOBILE_PARTICLE_RATE = 100
local DESKTOP_PARTICLE_RATE = 200

-- Professional Texture Library
local BEAM_TEXTURES = {
	gradient = "rbxasset://textures/ui/LuaChat/9-slice/kit-modal-highlight.png",
	flow = "rbxasset://textures/ui/GuiImagePlaceholder.png", 
	energy = "rbxasset://textures/particles/sparkles_main.dds",
	smooth = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
}

AISnake._activeSnakes = {}
AISnake._orbTargets = {}

-- === SPATIAL GRID (unchanged) ===
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

-- === SEGMENT POOLING (shared with players) ===
local SegmentPool = {}
local PoolSize = 0
local MAX_POOL_SIZE = 1000 -- Increased pool size
local SEGMENT_PARENT = Workspace:FindFirstChild("AISegmentContainer") or Instance.new("Folder", Workspace)
SEGMENT_PARENT.Name = "AISegmentContainer"

local function resetSegment(segment, config)
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false  -- Only head needs touch
	segment.CanQuery = false  -- Segments don't need query
	segment.Transparency = 0
	segment.Size = config.SegmentSize
	segment.Material = config.BodyMaterial or Enum.Material.Neon
	segment.Shape = Enum.PartType.Ball
	segment.TopSurface = Enum.SurfaceType.Smooth
	segment.BottomSurface = Enum.SurfaceType.Smooth
	-- Don't set color here - let createSegment handle it
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

-- === HELPER FUNCTIONS (unchanged) ===
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