-- AISnake Module: SMOOTH AI MOVEMENT V4.0 - FIXED ERRATIC BEHAVIOR
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
local BRAIN_UPDATES_PER_FRAME = 1
local DEBUG_UPDATE_RATE = 5.0  -- Increased from 2.0 (debug less often)
local AI_HEIGHT = 5
local SEGMENT_UPDATE_SKIP = 2  -- Update every other segment for performance
local LONG_SNAKE_THRESHOLD = 100  -- Snakes longer than this use more aggressive optimization
local VERY_LONG_SNAKE_THRESHOLD = 300  -- Even more optimization for very long snakes
local AI_UPDATE_DISTANCE = 300  -- Increased from 200 - update AI within larger distance of players
local SEGMENT_POOL_MAX = 500  -- Increased pool size for better reuse
local RESPAWN_DELAY = 2.0  -- Add delay before respawning to prevent clustering

AISnake._activeSnakes = {}
AISnake._orbTargets = {}
AISnake._lastSpawnTime = 0  -- Track last spawn time