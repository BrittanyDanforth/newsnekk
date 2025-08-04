--!strict
-- SnakeCollisionHandler V9.0 - Modernized Architecture (2025)
-- Implements: Trove pattern, modern spatial queries, client-server hybrid model
-- Follows 2025 Roblox best practices as outlined in the technical report

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

-- Type definitions for better code clarity and static analysis
type Player = Player
type BasePart = BasePart
type Vector3 = Vector3
type CFrame = CFrame

type SnakeSegment = {
    Part: BasePart,
    Position: Vector3,
    Index: number,
    IsVirtual: boolean?
}

type SnakeData = {
    Player: Player,
    Segments: {SnakeSegment},
    Length: number,
    LastUpdate: number,
    Trove: Trove,
    State: "alive" | "dying" | "dead"
}

type CollisionResult = {
    Hit: boolean,
    Target: Player | string, -- Player or "AI"
    Position: Vector3,
    Type: "head" | "body"
}

-- === MODULE IMPORTS ===
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Trove = require(Modules:WaitForChild("Trove"))
local SnakeConfig = require(Modules:WaitForChild("SnakeConfig"))
local OrbUtils = require(Modules:WaitForChild("OrbUtils"))

-- === MODERN CONSTANTS (Following 2025 standards) ===
local CONSTANTS = {
    -- Collision Detection
    SPATIAL_QUERY_RATE = 20, -- Hz, balanced for performance
    HEAD_COLLISION_RADIUS = 3.5,
    BODY_COLLISION_RADIUS = 2.8,
    SELF_COLLISION_IGNORE_COUNT = 10,
    
    -- Performance
    MAX_SEGMENTS_PER_QUERY = 300,
    SPATIAL_GRID_SIZE = 120,
    CACHE_LIFETIME = 1.5,
    
    -- Death & Respawn
    INVINCIBILITY_DURATION = 5,
    DEATH_ORB_SPAWN_DELAY = 0.5,
    REVIVE_TIMEOUT = 60,
    
    -- Network
    REPLICATION_RATE = 10, -- Hz
    NETWORK_COMPENSATION = 0.1
}

-- === REMOTE EVENTS (Secure communication) ===
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CollisionDetected = Remotes:WaitForChild("CollisionDetected")
local SnakeDied = Remotes:WaitForChild("SnakeDied")
local RequestRevive = Remotes:WaitForChild("RequestRevive")
local ReviveResponse = Remotes:WaitForChild("ReviveResponse")

-- === MAIN MODULE ===
local SnakeCollisionHandler = {}
SnakeCollisionHandler.__index = SnakeCollisionHandler

-- Private data storage (not using _G)
local ActiveSnakes: {[Player]: SnakeData} = {}
local DeathQueue: {{Player: Player, Timestamp: number}} = {}
local InvinciblePlayers: {[Player]: number} = {}
local CollisionCooldowns: {[Player]: number} = {}

-- === TROVE PATTERN IMPLEMENTATION ===
local function createSnakeTrove(): Trove
    return Trove.new()
end

-- === MODERN LIFECYCLE MANAGEMENT ===
function SnakeCollisionHandler:CreateSnake(player: Player): SnakeData
    -- Clean up any existing snake
    self:DestroySnake(player)
    
    local trove = createSnakeTrove()
    
    local snakeData: SnakeData = {
        Player = player,
        Segments = {},
        Length = SnakeConfig.StartingLength,
        LastUpdate = os.clock(),
        Trove = trove,
        State = "alive"
    }
    
    -- Set up collision detection with RunService (modern pattern)
    local collisionConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if snakeData.State == "alive" then
            self:CheckCollisions(player, deltaTime)
        end
    end)
    
    -- Add connection to Trove for automatic cleanup
    trove:Add(collisionConnection)
    
    -- Store in active snakes
    ActiveSnakes[player] = snakeData
    
    -- Set initial invincibility
    self:SetInvincible(player, CONSTANTS.INVINCIBILITY_DURATION)
    
    return snakeData
end

function SnakeCollisionHandler:DestroySnake(player: Player)
    local snakeData = ActiveSnakes[player]
    if not snakeData then return end
    
    -- Mark as dead
    snakeData.State = "dead"
    
    -- Use Trove to clean up ALL resources
    snakeData.Trove:Destroy()
    
    -- Clear from active snakes
    ActiveSnakes[player] = nil
    
    -- Clear other player-specific data
    InvinciblePlayers[player] = nil
    CollisionCooldowns[player] = nil
end

-- === MODERN COLLISION DETECTION (Spatial Queries) ===
function SnakeCollisionHandler:CheckCollisions(player: Player, deltaTime: number)
    local snakeData = ActiveSnakes[player]
    if not snakeData or snakeData.State ~= "alive" then return end
    
    -- Rate limiting
    local now = os.clock()
    local lastCheck = CollisionCooldowns[player] or 0
    if now - lastCheck < (1 / CONSTANTS.SPATIAL_QUERY_RATE) then
        return
    end
    CollisionCooldowns[player] = now
    
    -- Get snake head
    local head = self:GetSnakeHead(player)
    if not head then return end
    
    -- Skip if invincible
    if self:IsInvincible(player) then return end
    
    -- Perform spatial query
    local collisionResult = self:PerformSpatialQuery(head, player)
    
    if collisionResult.Hit then
        -- Client-server validation pattern
        self:ValidateAndProcessCollision(player, collisionResult)
    end
end

function SnakeCollisionHandler:PerformSpatialQuery(head: BasePart, player: Player): CollisionResult
    local headPos = head.Position
    
    -- Create OverlapParams for optimized queries
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {head.Parent}
    
    -- Query for nearby parts
    local parts = workspace:GetPartBoundsInBox(
        CFrame.new(headPos),
        Vector3.new(CONSTANTS.HEAD_COLLISION_RADIUS * 2, CONSTANTS.HEAD_COLLISION_RADIUS * 2, CONSTANTS.HEAD_COLLISION_RADIUS * 2),
        overlapParams
    )
    
    -- Check each part for collision
    for _, part in ipairs(parts) do
        local targetPlayer = self:GetPlayerFromPart(part)
        
        if targetPlayer and targetPlayer ~= player then
            local distance = (part.Position - headPos).Magnitude
            
            -- Head collision
            if part.Name == "SnakeHead" and distance < CONSTANTS.HEAD_COLLISION_RADIUS then
                return {
                    Hit = true,
                    Target = targetPlayer,
                    Position = part.Position,
                    Type = "head"
                }
            end
            
            -- Body collision
            if part.Name:match("^Segment") and distance < CONSTANTS.BODY_COLLISION_RADIUS then
                -- Check if it's self-collision
                local isSelfCollision = targetPlayer == player
                if isSelfCollision then
                    -- Extract segment index and ignore first N segments
                    local segmentIndex = tonumber(part.Name:match("Segment(%d+)")) or 0
                    if segmentIndex <= CONSTANTS.SELF_COLLISION_IGNORE_COUNT then
                        continue
                    end
                end
                
                return {
                    Hit = true,
                    Target = targetPlayer,
                    Position = part.Position,
                    Type = "body"
                }
            end
        end
    end
    
    return {Hit = false, Target = nil, Position = Vector3.zero, Type = "body"}
end

-- === CLIENT-SERVER VALIDATION ===
function SnakeCollisionHandler:ValidateAndProcessCollision(player: Player, collisionResult: CollisionResult)
    -- Server-side validation
    if not self:ValidateCollision(player, collisionResult) then
        return
    end
    
    -- Process based on collision type
    if collisionResult.Type == "head" then
        -- Head-to-head collision logic
        self:ProcessHeadCollision(player, collisionResult.Target)
    else
        -- Body collision - player dies
        self:QueueDeath(player)
    end
    
    -- Notify all clients for visual effects
    SnakeDied:FireAllClients(player, collisionResult.Position)
end

function SnakeCollisionHandler:ValidateCollision(player: Player, collisionResult: CollisionResult): boolean
    -- Sanity checks
    local snakeData = ActiveSnakes[player]
    if not snakeData or snakeData.State ~= "alive" then
        return false
    end
    
    -- Check if player is still alive
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end
    
    -- Validate position is reachable
    local head = self:GetSnakeHead(player)
    if head then
        local maxMovement = SnakeConfig.MaxSpeed * CONSTANTS.NETWORK_COMPENSATION
        local distance = (head.Position - collisionResult.Position).Magnitude
        if distance > maxMovement * 10 then -- Sanity check
            warn("Suspicious collision distance:", distance)
            return false
        end
    end
    
    return true
end

-- === DEATH SYSTEM WITH TROVE CLEANUP ===
function SnakeCollisionHandler:QueueDeath(player: Player)
    -- Prevent duplicate deaths
    for _, death in ipairs(DeathQueue) do
        if death.Player == player then
            return
        end
    end
    
    table.insert(DeathQueue, {
        Player = player,
        Timestamp = os.clock()
    })
end

function SnakeCollisionHandler:ProcessDeathQueue()
    while true do
        task.wait(0.1)
        
        if #DeathQueue > 0 then
            local death = table.remove(DeathQueue, 1)
            self:ProcessDeath(death.Player)
        end
    end
end

function SnakeCollisionHandler:ProcessDeath(player: Player)
    local snakeData = ActiveSnakes[player]
    if not snakeData or snakeData.State ~= "alive" then return end
    
    -- Mark as dying
    snakeData.State = "dying"
    
    -- Store segment positions for orb spawning
    local segmentPositions = {}
    for _, segment in ipairs(snakeData.Segments) do
        table.insert(segmentPositions, segment.Position)
    end
    
    -- Check for revive
    local hasRevive = self:CheckReviveAvailable(player)
    if hasRevive then
        local revived = self:PromptRevive(player)
        if revived then
            self:ProcessRevive(player)
            return
        end
    end
    
    -- Process actual death
    snakeData.State = "dead"
    
    -- Spawn death orbs
    self:SpawnDeathOrbs(segmentPositions, snakeData.Length)
    
    -- Clean up using Trove
    self:DestroySnake(player)
    
    -- Trigger respawn after delay
    task.wait(3)
    if player.Parent then
        player:LoadCharacter()
    end
end

-- === REVIVE SYSTEM ===
function SnakeCollisionHandler:CheckReviveAvailable(player: Player): boolean
    return player:GetAttribute("RevivesAvailable") > 0
end

function SnakeCollisionHandler:PromptRevive(player: Player): boolean
    -- Send revive prompt
    RequestRevive:FireClient(player)
    
    -- Wait for response with timeout
    local responded = false
    local revived = false
    
    local connection = ReviveResponse.OnServerEvent:Connect(function(respondingPlayer, response)
        if respondingPlayer == player then
            responded = true
            revived = response == "accept"
        end
    end)
    
    -- Add connection to player's Trove for cleanup
    local snakeData = ActiveSnakes[player]
    if snakeData then
        snakeData.Trove:Add(connection)
    end
    
    -- Wait for response with timeout
    local startTime = os.clock()
    while not responded and os.clock() - startTime < CONSTANTS.REVIVE_TIMEOUT do
        task.wait(0.1)
    end
    
    connection:Disconnect()
    
    return revived
end

function SnakeCollisionHandler:ProcessRevive(player: Player)
    local snakeData = ActiveSnakes[player]
    if not snakeData then return end
    
    -- Restore to alive state
    snakeData.State = "alive"
    
    -- Set invincibility
    self:SetInvincible(player, CONSTANTS.INVINCIBILITY_DURATION)
    
    -- Deduct revive
    local revivesLeft = player:GetAttribute("RevivesAvailable") - 1
    player:SetAttribute("RevivesAvailable", math.max(0, revivesLeft))
end

-- === INVINCIBILITY SYSTEM ===
function SnakeCollisionHandler:SetInvincible(player: Player, duration: number)
    InvinciblePlayers[player] = os.clock() + duration
end

function SnakeCollisionHandler:IsInvincible(player: Player): boolean
    local expireTime = InvinciblePlayers[player]
    if expireTime and os.clock() < expireTime then
        return true
    end
    
    -- Clean up expired invincibility
    if expireTime then
        InvinciblePlayers[player] = nil
    end
    
    -- Check for ghost mode
    return player:GetAttribute("ActiveGhostMode") == true
end

-- === HELPER FUNCTIONS ===
function SnakeCollisionHandler:GetSnakeHead(player: Player): BasePart?
    local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
    if snakeModel then
        return snakeModel:FindFirstChild("SnakeHead")
    end
    
    -- Fallback to character
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

function SnakeCollisionHandler:GetPlayerFromPart(part: BasePart): Player?
    -- Check if part belongs to a snake model
    local model = part.Parent
    if model and model.Name:match("^Snake_") then
        local playerName = model.Name:gsub("Snake_", "")
        return Players:FindFirstChild(playerName)
    end
    
    -- Check if part belongs to a character
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return Players:GetPlayerFromCharacter(model)
    end
    
    return nil
end

function SnakeCollisionHandler:SpawnDeathOrbs(positions: {Vector3}, snakeLength: number)
    -- Calculate orb distribution
    local totalOrbs = math.clamp(math.floor(snakeLength / 2.5), 3, 40)
    local orbValue = math.max(1, math.floor(snakeLength * 0.4 / totalOrbs))
    
    -- Spawn orbs with delay
    task.spawn(function()
        task.wait(CONSTANTS.DEATH_ORB_SPAWN_DELAY)
        
        local step = math.max(1, math.floor(#positions / totalOrbs))
        for i = 1, #positions, step do
            if i > totalOrbs then break end
            
            local position = positions[i]
            local offset = Vector3.new(
                math.random(-3, 3),
                0,
                math.random(-3, 3)
            )
            
            OrbUtils.SpawnOrb(position + offset, orbValue)
            
            if i % 5 == 0 then
                task.wait() -- Yield periodically
            end
        end
    end)
end

-- === HEAD-TO-HEAD COLLISION LOGIC ===
function SnakeCollisionHandler:ProcessHeadCollision(playerA: Player, playerB: Player)
    local headA = self:GetSnakeHead(playerA)
    local headB = self:GetSnakeHead(playerB)
    
    if not headA or not headB then return end
    
    -- Get velocities
    local velA = headA.AssemblyLinearVelocity
    local velB = headB.AssemblyLinearVelocity
    
    -- Calculate approach vectors
    local dirAtoB = (headB.Position - headA.Position).Unit
    local dirBtoA = -dirAtoB
    
    -- Check who's moving towards whom
    local approachA = velA:Dot(dirAtoB)
    local approachB = velB:Dot(dirBtoA)
    
    -- Determine winner
    if approachA > 2 and approachB <= 2 then
        self:QueueDeath(playerB)
    elseif approachB > 2 and approachA <= 2 then
        self:QueueDeath(playerA)
    elseif approachA > 2 and approachB > 2 then
        -- Both approaching - both die
        self:QueueDeath(playerA)
        self:QueueDeath(playerB)
    end
end

-- === INITIALIZATION ===
function SnakeCollisionHandler:Initialize()
    -- Set up player connections
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            -- Auto-create snake on spawn
            self:CreateSnake(player)
        end)
        
        player.CharacterRemoving:Connect(function()
            -- Clean up on character removal
            self:DestroySnake(player)
        end)
    end)
    
    -- Clean up on player leaving
    Players.PlayerRemoving:Connect(function(player)
        self:DestroySnake(player)
    end)
    
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            self:CreateSnake(player)
        end
    end
    
    -- Start death queue processor
    task.spawn(function()
        self:ProcessDeathQueue()
    end)
    
    -- Set up remote event security
    CollisionDetected.OnServerEvent:Connect(function(player, targetPlayer, position)
        -- Validate the collision report from client
        local result: CollisionResult = {
            Hit = true,
            Target = targetPlayer,
            Position = position,
            Type = "body"
        }
        
        -- Server validates before processing
        self:ValidateAndProcessCollision(player, result)
    end)
end

-- === MODULE EXPORT ===
return SnakeCollisionHandler