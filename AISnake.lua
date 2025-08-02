-- AISnake Module: SMOOTH AI MOVEMENT V4.0 - FIXED ERRATIC BEHAVIOR
-- COLLISION DETECTION REMOVED - All collisions handled by SnakeCollisionHandler

local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local SpatialGrid = require(game.ServerScriptService:FindFirstChild("SpatialGrid") or game.ReplicatedStorage:FindFirstChild("SpatialGrid"))

-- Constants
local FORCE_RENDER_SEGMENTS = true  -- Forces segment updates for debugging
local MAX_PATH_ATTEMPTS = 3
local PHYSICS_STEP = 1/60 -- 60 Hz simulation
local AI_UPDATE_RATE = 0.1 -- AI decision making at 10 Hz
local VISUAL_UPDATE_RATE = 0.05 -- Visual updates at 20 Hz
local MAX_ORBS_PER_FRAME = 10 -- Limit orb processing per frame

-- Movement & Turning
local BASE_MOVE_SPEED = 45
local BOOST_SPEED_MULTIPLIER = 1.8
local TURN_SPEED_NORMAL = 4
local TURN_SPEED_BOOST = 3
local OBSTACLE_TURN_SPEED = 6
local SMOOTH_FACTOR = 0.15
local DIRECTION_SMOOTH_FACTOR = 0.3 -- Higher = smoother turns

-- Size & Growth
local BASE_SEGMENT_SIZE = 2.5
local MAX_SEGMENT_SIZE = 6
local SEGMENT_SPACING = 0.9
local HEAD_SIZE_MULTIPLIER = 1.3
local TAIL_SIZE_MULTIPLIER = 0.6
local GROWTH_CURVE_EXPONENT = 0.6

-- AI Brain Parameters
local ORB_DETECTION_BASE_RADIUS = 80
local ORB_CLOSE_RADIUS = 30
local DANGER_DETECTION_RADIUS = 60
local WALL_DETECTION_DISTANCE = 40
local BOOST_STAMINA_MAX = 100
local BOOST_STAMINA_DRAIN = 20
local BOOST_STAMINA_REGEN = 10
local MIN_BOOST_STAMINA = 25

-- Pathfinding Parameters
local WAYPOINT_REACHED_DISTANCE = 10
local PATH_RECOMPUTE_DISTANCE = 30
local OBSTACLE_CHECK_DISTANCE = 15

-- Death & Respawn
local DEATH_ORB_COUNT = 10
local RESPAWN_DELAY = 3
local DEATH_FADE_TIME = 0.5

-- AI Personality Types
local PersonalityTypes = {
    Aggressive = {
        orbSeekRadius = 120,
        dangerAvoidance = 0.6,
        boostAggressiveness = 0.8,
        turnPreference = 0.1
    },
    Cautious = {
        orbSeekRadius = 60,
        dangerAvoidance = 1.2,
        boostAggressiveness = 0.3,
        turnPreference = -0.1
    },
    Balanced = {
        orbSeekRadius = 80,
        dangerAvoidance = 1.0,
        boostAggressiveness = 0.5,
        turnPreference = 0
    }
}

-- Helper Functions
local function calculateGrowthFactor(length)
    local normalizedLength = math.min(length / 1000, 1)
    return 1 + (normalizedLength ^ GROWTH_CURVE_EXPONENT) * 2
end

local function getSegmentSize(segmentIndex, totalSegments, growthFactor)
    local baseSize = BASE_SEGMENT_SIZE * growthFactor
    local position = segmentIndex / math.max(totalSegments - 1, 1)
    
    if segmentIndex == 0 then
        return math.min(baseSize * HEAD_SIZE_MULTIPLIER, MAX_SEGMENT_SIZE)
    end
    
    local tailFactor = math.max(TAIL_SIZE_MULTIPLIER, 1 - position * 0.5)
    return math.min(baseSize * tailFactor, MAX_SEGMENT_SIZE)
end

local function createSegmentModel(size, index, aiSnakeModel)
    local segment = Instance.new("Part")
    segment.Name = "Segment" .. index .. (index == 0 and "_Head" or "")
    segment.Shape = Enum.PartType.Ball
    segment.Material = Enum.Material.Neon
    segment.TopSurface = Enum.SurfaceType.Smooth
    segment.BottomSurface = Enum.SurfaceType.Smooth
    segment.CanCollide = false
    segment.Massless = true
    segment.Size = Vector3.new(size, size, size)
    segment.CFrame = aiSnakeModel.PrimaryPart.CFrame
    segment.Parent = aiSnakeModel
    
    -- Configure based on segment type
    if index == 0 then
        -- Head configuration
        segment.Color = aiSnakeModel:GetAttribute("Color") or Color3.new(1, 0, 0)
        segment.Material = Enum.Material.Neon
        
        -- Head glow
        local glow = Instance.new("PointLight")
        glow.Brightness = 2
        glow.Range = size * 4
        glow.Color = segment.Color
        glow.Parent = segment
        
        -- Selection box for head outline
        local outline = Instance.new("SelectionBox")
        outline.Adornee = segment
        outline.Color3 = segment.Color
        outline.LineThickness = 0.1
        outline.Transparency = 0.3
        outline.Parent = segment
    else
        -- Body configuration
        segment.Color = aiSnakeModel:GetAttribute("Color") or Color3.new(0.8, 0, 0)
        segment.Material = Enum.Material.ForceField
        segment.Transparency = 0.1
    end
    
    return segment
end

local function setNetworkOwner(part, owner)
    if part and part:IsA("BasePart") and part:CanSetNetworkOwnership() then
        part:SetNetworkOwner(owner)
    end
end

-- AISnake Class
local AISnake = {}
AISnake.__index = AISnake

-- Segment Pool for performance
local SegmentPool = {
    available = {},
    inUse = {}
}

function SegmentPool:Get(size, index, aiSnakeModel)
    local segment = table.remove(self.available)
    if not segment then
        segment = createSegmentModel(size, index, aiSnakeModel)
    else
        -- Reconfigure existing segment
        segment.Size = Vector3.new(size, size, size)
        segment.Name = "Segment" .. index .. (index == 0 and "_Head" or "")
        segment.Parent = aiSnakeModel
        
        if index == 0 then
            segment.Color = aiSnakeModel:GetAttribute("Color") or Color3.new(1, 0, 0)
            segment.Material = Enum.Material.Neon
            segment.Transparency = 0
        else
            segment.Color = aiSnakeModel:GetAttribute("Color") or Color3.new(0.8, 0, 0)
            segment.Material = Enum.Material.ForceField
            segment.Transparency = 0.1
        end
    end
    
    self.inUse[segment] = true
    return segment
end

function SegmentPool:Return(segment)
    if self.inUse[segment] then
        self.inUse[segment] = nil
        segment.Parent = nil
        table.insert(self.available, segment)
    end
end

function SegmentPool:ReturnAll(segments)
    for _, segment in ipairs(segments) do
        self:Return(segment)
    end
end

-- Constructor
function AISnake.new(aiSnakeModel)
    local self = setmetatable({}, AISnake)
    
    -- Model reference
    self.model = aiSnakeModel
    self.humanoidRootPart = aiSnakeModel.PrimaryPart
    
    -- Initialize position if needed
    if self.humanoidRootPart.Position.Y < 0 then
        self.humanoidRootPart.Position = Vector3.new(
            math.random(-100, 100),
            10,
            math.random(-100, 100)
        )
    end
    
    -- Movement state
    self.position = self.humanoidRootPart.Position
    self.velocity = Vector3.new(0, 0, -1) * BASE_MOVE_SPEED
    self.direction = Vector3.new(0, 0, -1)
    self.smoothedDirection = self.direction
    self.targetDirection = self.direction
    self.speed = BASE_MOVE_SPEED
    self.isBoosting = false
    self.boostStamina = BOOST_STAMINA_MAX
    self.rotationOffset = CFrame.Angles(0, 0, 0)
    
    -- Snake state
    self.length = tonumber(aiSnakeModel:GetAttribute("Length")) or 50
    self.isAlive = true
    self.lastOrbCollection = 0
    self.orbsProcessedThisFrame = 0
    
    -- Visual state
    self.segments = {}
    self.segmentPositions = {}
    self.segmentRotations = {}
    self.trailLength = 0
    self.growthFactor = calculateGrowthFactor(self.length)
    
    -- AI Brain
    local personalities = {"Aggressive", "Cautious", "Balanced"}
    self.personality = PersonalityTypes[personalities[math.random(#personalities)]]
    self.currentPath = nil
    self.currentWaypointIndex = 1
    self.pathRecomputeTimer = 0
    self.stuckTimer = 0
    self.lastPosition = self.position
    self.avoidanceDirection = Vector3.new(0, 0, 0)
    
    -- Grid registration
    self.gridCell = nil
    self:updateGridPosition()
    
    -- Timers
    self.lastAIUpdate = 0
    self.lastVisualUpdate = 0
    self.physicsClock = 0
    
    -- Performance optimization
    self.updateCounter = 0
    self.skipFrames = 0
    
    -- Initialize visual
    self:initializeSegments()
    
    -- Set initial attributes
    aiSnakeModel:SetAttribute("Speed", self.speed)
    aiSnakeModel:SetAttribute("IsBoosting", false)
    
    return self
end

-- Grid Management
function AISnake:updateGridPosition()
    if SpatialGrid then
        local newCell = SpatialGrid.AddObject(self.model, self.position, "aisnake")
        if newCell ~= self.gridCell then
            if self.gridCell then
                SpatialGrid.RemoveObject(self.model, self.gridCell, "aisnake")
            end
            self.gridCell = newCell
        end
    end
end

-- Visual Management
function AISnake:initializeSegments()
    -- Clear existing segments
    for _, segment in ipairs(self.segments) do
        SegmentPool:Return(segment)
    end
    self.segments = {}
    self.segmentPositions = {}
    self.segmentRotations = {}
    
    -- Calculate segment count based on length
    local segmentCount = math.ceil(self.length / 10) + 5
    self.growthFactor = calculateGrowthFactor(self.length)
    
    -- Create segments
    for i = 0, segmentCount - 1 do
        local size = getSegmentSize(i, segmentCount, self.growthFactor)
        local segment = SegmentPool:Get(size, i, self.model)
        
        -- Position along initial direction
        local offset = self.direction * (i * SEGMENT_SPACING * self.growthFactor)
        segment.CFrame = CFrame.new(self.position - offset)
        
        table.insert(self.segments, segment)
        table.insert(self.segmentPositions, segment.Position)
        table.insert(self.segmentRotations, segment.CFrame)
        
        -- Set network ownership for smooth movement
        setNetworkOwner(segment, nil)
    end
    
    -- Tag head for collision detection
    if self.segments[1] then
        CollectionService:AddTag(self.segments[1], "SnakeHead")
        self.segments[1]:SetAttribute("OwnerType", "AI")
        self.segments[1]:SetAttribute("OwnerInstance", self.model)
    end
    
    -- Update model attribute
    self.model:SetAttribute("SegmentCount", #self.segments)
end

function AISnake:updateSegmentVisuals()
    if not self.isAlive or self.skipFrames > 0 then
        self.skipFrames = self.skipFrames - 1
        return
    end
    
    -- Only update if enough time has passed
    local now = tick()
    if now - self.lastVisualUpdate < VISUAL_UPDATE_RATE then
        return
    end
    self.lastVisualUpdate = now
    
    -- Update trail length
    self.trailLength = self.trailLength + self.velocity.Magnitude * VISUAL_UPDATE_RATE
    
    -- Update each segment
    for i, segment in ipairs(self.segments) do
        if i == 1 then
            -- Head follows position directly
            local targetCFrame = CFrame.lookAt(self.position, self.position + self.smoothedDirection)
            segment.CFrame = segment.CFrame:Lerp(targetCFrame, 0.5)
            self.segmentPositions[i] = segment.Position
            self.segmentRotations[i] = segment.CFrame
        else
            -- Body segments follow previous segment
            local targetPos = self.segmentPositions[i-1] - (self.segmentRotations[i-1].LookVector * SEGMENT_SPACING * self.growthFactor)
            local toTarget = targetPos - segment.Position
            
            if toTarget.Magnitude > 0.01 then
                local moveDistance = math.min(toTarget.Magnitude, self.speed * VISUAL_UPDATE_RATE * 2)
                local newPos = segment.Position + toTarget.Unit * moveDistance
                
                -- Smooth rotation to face previous segment
                local lookDir = (self.segmentPositions[i-1] - newPos).Unit
                if lookDir.Magnitude > 0 then
                    local targetCFrame = CFrame.lookAt(newPos, newPos + lookDir)
                    segment.CFrame = self.segmentRotations[i]:Lerp(targetCFrame, 0.3)
                    self.segmentPositions[i] = segment.Position
                    self.segmentRotations[i] = segment.CFrame
                end
            end
        end
    end
    
    -- Performance optimization: skip frames for distant AI
    local nearestPlayer = self:getNearestPlayer()
    if nearestPlayer then
        local distance = (nearestPlayer.Position - self.position).Magnitude
        self.skipFrames = math.floor(distance / 100) -- Skip more frames when farther away
    end
end

-- AI Brain Functions
function AISnake:getNearestPlayer()
    local nearestPlayer = nil
    local nearestDistance = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and player.Character.PrimaryPart then
            local distance = (player.Character.PrimaryPart.Position - self.position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = player.Character.PrimaryPart
            end
        end
    end
    
    return nearestPlayer
end

function AISnake:findNearestOrb()
    if not SpatialGrid then
        return nil
    end
    
    local searchRadius = self.personality.orbSeekRadius
    local nearbyOrbs = SpatialGrid.QueryRadius(self.position, searchRadius, "orb")
    
    if #nearbyOrbs == 0 then
        return nil
    end
    
    -- Find closest orb
    local nearestOrb = nil
    local nearestDistance = math.huge
    
    for _, orb in ipairs(nearbyOrbs) do
        if orb and orb.Parent then
            local distance = (orb.Position - self.position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestOrb = orb
            end
        end
    end
    
    return nearestOrb, nearestDistance
end

function AISnake:detectNearbyThreats()
    if not SpatialGrid then
        return {}
    end
    
    local threats = {}
    local searchRadius = DANGER_DETECTION_RADIUS
    
    -- Check for player snakes
    local nearbyPlayers = SpatialGrid.QueryRadius(self.position, searchRadius, "player")
    for _, playerPart in ipairs(nearbyPlayers) do
        if playerPart and playerPart.Parent then
            local distance = (playerPart.Position - self.position).Magnitude
            table.insert(threats, {
                position = playerPart.Position,
                distance = distance,
                type = "player",
                velocity = playerPart.AssemblyLinearVelocity or Vector3.new()
            })
        end
    end
    
    -- Check for other AI snakes
    local nearbyAI = SpatialGrid.QueryRadius(self.position, searchRadius, "aisnake")
    for _, aiModel in ipairs(nearbyAI) do
        if aiModel and aiModel ~= self.model and aiModel.PrimaryPart then
            local distance = (aiModel.PrimaryPart.Position - self.position).Magnitude
            table.insert(threats, {
                position = aiModel.PrimaryPart.Position,
                distance = distance,
                type = "ai",
                velocity = aiModel.PrimaryPart.AssemblyLinearVelocity or Vector3.new()
            })
        end
    end
    
    return threats
end

function AISnake:checkWallProximity()
    -- Simple boundary check
    local boundaries = {
        minX = -500, maxX = 500,
        minZ = -500, maxZ = 500
    }
    
    local wallThreats = {}
    
    -- Check each boundary
    if self.position.X - boundaries.minX < WALL_DETECTION_DISTANCE then
        table.insert(wallThreats, {
            normal = Vector3.new(1, 0, 0),
            distance = self.position.X - boundaries.minX
        })
    end
    if boundaries.maxX - self.position.X < WALL_DETECTION_DISTANCE then
        table.insert(wallThreats, {
            normal = Vector3.new(-1, 0, 0),
            distance = boundaries.maxX - self.position.X
        })
    end
    if self.position.Z - boundaries.minZ < WALL_DETECTION_DISTANCE then
        table.insert(wallThreats, {
            normal = Vector3.new(0, 0, 1),
            distance = self.position.Z - boundaries.minZ
        })
    end
    if boundaries.maxZ - self.position.Z < WALL_DETECTION_DISTANCE then
        table.insert(wallThreats, {
            normal = Vector3.new(0, 0, -1),
            distance = boundaries.maxZ - self.position.Z
        })
    end
    
    return wallThreats
end

function AISnake:computeAvoidanceVector(threats, walls)
    local avoidance = Vector3.new(0, 0, 0)
    
    -- Avoid threats
    for _, threat in ipairs(threats) do
        local toThreat = threat.position - self.position
        if toThreat.Magnitude > 0 then
            local avoidForce = -toThreat.Unit / math.max(threat.distance, 1)
            avoidance = avoidance + avoidForce * self.personality.dangerAvoidance
        end
    end
    
    -- Avoid walls
    for _, wall in ipairs(walls) do
        local avoidForce = wall.normal / math.max(wall.distance, 1)
        avoidance = avoidance + avoidForce * 2 -- Walls are high priority
    end
    
    return avoidance
end

function AISnake:generatePath(targetPosition)
    -- Simple pathfinding - for now just direct path with obstacle avoidance
    local path = {
        waypoints = {targetPosition},
        status = "Success"
    }
    
    -- Could integrate with Roblox PathfindingService here if needed
    return path
end

function AISnake:navigateToTarget(targetPosition)
    if not self.currentPath or (targetPosition - self.currentPath.waypoints[#self.currentPath.waypoints]).Magnitude > PATH_RECOMPUTE_DISTANCE then
        self.currentPath = self:generatePath(targetPosition)
        self.currentWaypointIndex = 1
    end
    
    if self.currentPath and self.currentPath.waypoints then
        local currentWaypoint = self.currentPath.waypoints[self.currentWaypointIndex]
        if currentWaypoint then
            local toWaypoint = currentWaypoint - self.position
            toWaypoint = Vector3.new(toWaypoint.X, 0, toWaypoint.Z) -- Keep on XZ plane
            
            if toWaypoint.Magnitude < WAYPOINT_REACHED_DISTANCE then
                self.currentWaypointIndex = self.currentWaypointIndex + 1
            end
            
            return toWaypoint.Unit
        end
    end
    
    return nil
end

function AISnake:determineAction()
    local now = tick()
    
    -- Only update AI decisions at specified rate
    if now - self.lastAIUpdate < AI_UPDATE_RATE then
        return
    end
    self.lastAIUpdate = now
    
    -- Check for nearby threats
    local threats = self:detectNearbyThreats()
    local walls = self:checkWallProximity()
    
    -- Compute avoidance if needed
    local avoidanceVector = self:computeAvoidanceVector(threats, walls)
    local hasImmediateDanger = avoidanceVector.Magnitude > 0.5
    
    -- Priority 1: Avoid immediate danger
    if hasImmediateDanger then
        self.targetDirection = avoidanceVector.Unit
        self.isBoosting = self.boostStamina > MIN_BOOST_STAMINA and self.personality.boostAggressiveness > 0.7
        return
    end
    
    -- Priority 2: Seek orbs
    local nearestOrb, orbDistance = self:findNearestOrb()
    if nearestOrb then
        local toOrb = nearestOrb.Position - self.position
        toOrb = Vector3.new(toOrb.X, 0, toOrb.Z)
        
        if toOrb.Magnitude > 0 then
            -- Navigate to orb
            local navigationDirection = self:navigateToTarget(nearestOrb.Position)
            if navigationDirection then
                self.targetDirection = navigationDirection
                
                -- Boost if orb is close and we have stamina
                if orbDistance < ORB_CLOSE_RADIUS and self.boostStamina > MIN_BOOST_STAMINA then
                    self.isBoosting = true
                else
                    self.isBoosting = false
                end
                return
            end
        end
    end
    
    -- Priority 3: Wander
    if math.random() < 0.05 then -- 5% chance to change direction
        local randomAngle = (math.random() - 0.5) * math.pi * 0.5
        self.targetDirection = CFrame.Angles(0, randomAngle, 0) * self.direction
    end
    
    self.isBoosting = false
end

-- Movement System
function AISnake:updateMovement(deltaTime)
    if not self.isAlive then
        return
    end
    
    -- Update physics clock
    self.physicsClock = self.physicsClock + deltaTime
    
    -- Physics update at fixed timestep
    while self.physicsClock >= PHYSICS_STEP do
        self.physicsClock = self.physicsClock - PHYSICS_STEP
        
        -- Make AI decisions
        self:determineAction()
        
        -- Smooth direction changes
        local turnSpeed = self.isBoosting and TURN_SPEED_BOOST or TURN_SPEED_NORMAL
        self.smoothedDirection = self.smoothedDirection:Lerp(self.targetDirection, turnSpeed * PHYSICS_STEP)
        self.smoothedDirection = self.smoothedDirection.Unit
        
        -- Update speed and stamina
        if self.isBoosting and self.boostStamina > 0 then
            self.speed = BASE_MOVE_SPEED * BOOST_SPEED_MULTIPLIER
            self.boostStamina = math.max(0, self.boostStamina - BOOST_STAMINA_DRAIN * PHYSICS_STEP)
        else
            self.speed = BASE_MOVE_SPEED
            self.boostStamina = math.min(BOOST_STAMINA_MAX, self.boostStamina + BOOST_STAMINA_REGEN * PHYSICS_STEP)
            self.isBoosting = false
        end
        
        -- Update velocity and position
        self.velocity = self.smoothedDirection * self.speed
        self.position = self.position + self.velocity * PHYSICS_STEP
        
        -- Keep on ground
        self.position = Vector3.new(self.position.X, 10, self.position.Z)
        
        -- Update HumanoidRootPart
        self.humanoidRootPart.CFrame = CFrame.lookAt(self.position, self.position + self.smoothedDirection)
        self.humanoidRootPart.AssemblyLinearVelocity = self.velocity
        
        -- Update attributes
        self.model:SetAttribute("Speed", self.speed)
        self.model:SetAttribute("IsBoosting", self.isBoosting)
        self.model:SetAttribute("Position", self.position)
        
        -- Update grid position
        self:updateGridPosition()
        
        -- Collect orbs
        self:collectNearbyOrbs()
        
        -- COLLISION DETECTION REMOVED - Handled by SnakeCollisionHandler
    end
    
    -- Visual update
    self:updateSegmentVisuals()
end

-- Orb Collection
function AISnake:collectNearbyOrbs()
    if not self.isAlive or not SpatialGrid then
        return
    end
    
    -- Limit orb processing per frame
    self.orbsProcessedThisFrame = 0
    
    -- Get head size for collection radius
    local headSize = getSegmentSize(0, #self.segments, self.growthFactor)
    local collectionRadius = headSize * 1.5
    
    -- Query nearby orbs
    local nearbyOrbs = SpatialGrid.QueryRadius(self.position, collectionRadius, "orb")
    
    for _, orb in ipairs(nearbyOrbs) do
        if self.orbsProcessedThisFrame >= MAX_ORBS_PER_FRAME then
            break
        end
        
        if orb and orb.Parent and (orb.Position - self.position).Magnitude <= collectionRadius then
            self.orbsProcessedThisFrame = self.orbsProcessedThisFrame + 1
            
            -- Award points
            local orbValue = orb:GetAttribute("Value") or 1
            self.length = self.length + orbValue
            self.model:SetAttribute("Length", self.length)
            
            -- Update growth
            local oldGrowthFactor = self.growthFactor
            self.growthFactor = calculateGrowthFactor(self.length)
            
            if self.growthFactor > oldGrowthFactor then
                self:adjustSegmentSizes()
            end
            
            -- Remove orb from grid
            SpatialGrid.RemoveObject(orb, nil, "orb")
            
            -- Destroy orb
            orb:Destroy()
        end
    end
end

function AISnake:adjustSegmentSizes()
    for i, segment in ipairs(self.segments) do
        local newSize = getSegmentSize(i - 1, #self.segments, self.growthFactor)
        TweenService:Create(segment, TweenInfo.new(0.3), {
            Size = Vector3.new(newSize, newSize, newSize)
        }):Play()
    end
    
    -- Check if we need more segments
    local targetSegmentCount = math.ceil(self.length / 10) + 5
    if targetSegmentCount > #self.segments then
        self:addSegment()
    end
end

function AISnake:addSegment()
    local index = #self.segments
    local size = getSegmentSize(index, #self.segments + 1, self.growthFactor)
    local segment = SegmentPool:Get(size, index, self.model)
    
    -- Position at end of snake
    local lastSegment = self.segments[#self.segments]
    if lastSegment then
        segment.CFrame = lastSegment.CFrame
        table.insert(self.segmentPositions, lastSegment.Position)
        table.insert(self.segmentRotations, lastSegment.CFrame)
    end
    
    table.insert(self.segments, segment)
    self.model:SetAttribute("SegmentCount", #self.segments)
end

-- Death Handling
function AISnake:die(killedBy)
    if not self.isAlive then
        return
    end
    
    self.isAlive = false
    self.model:SetAttribute("IsAlive", false)
    
    -- Spawn orbs
    local orbsToSpawn = math.min(DEATH_ORB_COUNT, math.floor(self.length / 10))
    for i = 1, orbsToSpawn do
        local randomOffset = Vector3.new(
            math.random(-20, 20),
            0,
            math.random(-20, 20)
        )
        local orbPosition = self.position + randomOffset
        
        -- Create orb (assuming orb spawning system exists)
        local orbSpawner = game.ServerScriptService:FindFirstChild("OrbSpawner")
        if orbSpawner and orbSpawner:FindFirstChild("SpawnOrb") then
            require(orbSpawner.SpawnOrb)(orbPosition, math.random(1, 3))
        end
    end
    
    -- Fade out effect
    for _, segment in ipairs(self.segments) do
        TweenService:Create(segment, TweenInfo.new(DEATH_FADE_TIME), {
            Transparency = 1,
            Size = segment.Size * 0.5
        }):Play()
    end
    
    -- Remove from grid
    if self.gridCell and SpatialGrid then
        SpatialGrid.RemoveObject(self.model, self.gridCell, "aisnake")
    end
    
    -- Schedule cleanup
    task.wait(DEATH_FADE_TIME)
    self:cleanup()
end

function AISnake:cleanup()
    -- Return segments to pool
    SegmentPool:ReturnAll(self.segments)
    self.segments = {}
    
    -- Respawn after delay
    task.wait(RESPAWN_DELAY)
    self:respawn()
end

function AISnake:respawn()
    -- Reset state
    self.position = Vector3.new(
        math.random(-300, 300),
        10,
        math.random(-300, 300)
    )
    self.humanoidRootPart.CFrame = CFrame.new(self.position)
    self.direction = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
    self.smoothedDirection = self.direction
    self.targetDirection = self.direction
    self.velocity = self.direction * BASE_MOVE_SPEED
    self.speed = BASE_MOVE_SPEED
    self.isBoosting = false
    self.boostStamina = BOOST_STAMINA_MAX
    self.length = 50
    self.isAlive = true
    self.growthFactor = calculateGrowthFactor(self.length)
    
    -- Reset attributes
    self.model:SetAttribute("Length", self.length)
    self.model:SetAttribute("IsAlive", true)
    self.model:SetAttribute("Speed", self.speed)
    self.model:SetAttribute("IsBoosting", false)
    
    -- Reinitialize visuals
    self:initializeSegments()
    
    -- Re-register with grid
    self:updateGridPosition()
end

-- Public Methods
function AISnake:update(deltaTime)
    if not self.isAlive then
        return
    end
    
    self:updateMovement(deltaTime)
end

function AISnake:destroy()
    -- Clean up
    SegmentPool:ReturnAll(self.segments)
    if self.gridCell and SpatialGrid then
        SpatialGrid.RemoveObject(self.model, self.gridCell, "aisnake")
    end
    self.model:Destroy()
end

return AISnake

print("✅ AISnake Module Loaded - Collision detection REMOVED (handled by SnakeCollisionHandler)")