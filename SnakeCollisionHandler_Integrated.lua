--!strict
-- SnakeCollisionHandler V9.0 - Integrated with your existing systems
-- Modern collision detection using spatial queries
-- Drop-in replacement for your current SnakeCollisionHandler

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Your existing modules
local Trove = require(ReplicatedStorage:WaitForChild("Trove"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))
local OptimizedSnakeSystem = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystem"))

-- Check for optional modules
local VFXManager = ReplicatedStorage:FindFirstChild("VFXManager")
if VFXManager then VFXManager = require(VFXManager) end

local AISnake = ReplicatedStorage:FindFirstChild("AISnake")
if AISnake then AISnake = require(AISnake) end

-- Your existing events
local PlayerDied = ReplicatedStorage:WaitForChild("PlayerDied")
local SnakeCollision = ReplicatedStorage:WaitForChild("SnakeCollision")
local PlayVFX = ReplicatedStorage:WaitForChild("PlayVFX")

-- Module
local SnakeCollisionHandler = {}

-- Private storage (no more _G!)
local ActiveSnakes = {}
local DeathQueue = {}
local InvinciblePlayers = {}

-- Constants from your config (with fallbacks)
local HEAD_RADIUS = SnakeConfig.HeadRadius or 3.5
local BODY_RADIUS = SnakeConfig.BodyRadius or 2.8
local CHECK_RATE = 20 -- checks per second
local INVINCIBILITY_TIME = SnakeConfig.InvincibilityDuration or 5

-- Initialize collision checking for a player
function SnakeCollisionHandler:SetupPlayer(player)
    -- Clean up any old data
    if ActiveSnakes[player] then
        ActiveSnakes[player].Trove:Destroy()
    end
    
    -- Create new tracking with Trove
    local trove = Trove.new()
    ActiveSnakes[player] = {
        Trove = trove,
        LastCheck = 0,
        State = "alive"
    }
    
    -- Make them invincible on spawn
    InvinciblePlayers[player] = os.clock() + INVINCIBILITY_TIME
    
    -- Start collision checking
    local connection = RunService.Heartbeat:Connect(function()
        self:CheckCollisions(player)
    end)
    
    trove:Add(connection)
end

-- Remove player from collision system
function SnakeCollisionHandler:CleanupPlayer(player)
    if ActiveSnakes[player] then
        ActiveSnakes[player].Trove:Destroy()
        ActiveSnakes[player] = nil
    end
    InvinciblePlayers[player] = nil
end

-- Get the snake head (works with your OptimizedSnakeSystem)
function SnakeCollisionHandler:GetSnakeHead(player)
    -- Try OptimizedSnakeSystem first
    if OptimizedSnakeSystem.GetSnakeHead then
        local head = OptimizedSnakeSystem:GetSnakeHead(player)
        if head then return head end
    end
    
    -- Try your snake model naming patterns
    local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
    if snakeModel then
        -- Check various naming conventions
        local head = snakeModel:FindFirstChild("Head") or 
                    snakeModel:FindFirstChild("SnakeHead") or
                    snakeModel:FindFirstChild("Segment0_Head") or
                    snakeModel:FindFirstChild("Segment0") or
                    snakeModel:FindFirstChild("Segment_0")
        if head and head:IsA("BasePart") then 
            return head 
        end
    end
    
    -- Fallback to character
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Modern collision detection using spatial queries
function SnakeCollisionHandler:CheckCollisions(player)
    local data = ActiveSnakes[player]
    if not data or data.State ~= "alive" then return end
    
    -- Check if character exists and is alive
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    
    -- Rate limiting
    local now = os.clock()
    if now - data.LastCheck < (1/CHECK_RATE) then return end
    data.LastCheck = now
    
    -- Skip if invincible
    if InvinciblePlayers[player] and now < InvinciblePlayers[player] then
        return
    end
    
    -- Check for ghost mode or other invincibility
    if player:GetAttribute("ActiveGhostMode") or player:GetAttribute("Invincible") then
        return
    end
    
    -- Get head
    local head = self:GetSnakeHead(player)
    if not head then return end
    
    -- MODERN SPATIAL QUERY (replaces .Touched)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {head.Parent}
    
    local nearbyParts = workspace:GetPartBoundsInBox(
        CFrame.new(head.Position),
        Vector3.new(HEAD_RADIUS * 2, HEAD_RADIUS * 2, HEAD_RADIUS * 2),
        params
    )
    
    -- Check each nearby part
    for _, part in ipairs(nearbyParts) do
        if part.Name:match("Segment") or part.Name:match("Head") then
            local hit = self:ProcessPotentialHit(player, head, part)
            if hit then
                break -- Stop checking after first hit
            end
        end
    end
end

-- Process a potential collision
function SnakeCollisionHandler:ProcessPotentialHit(player, myHead, hitPart)
    local distance = (myHead.Position - hitPart.Position).Magnitude
    
    -- Get owner of the hit part
    local otherPlayer = self:GetPlayerFromPart(hitPart)
    
    -- Check for AI snake collision
    if not otherPlayer and AISnake and hitPart.Parent then
        if hitPart.Parent.Name:match("AISnake") or hitPart.Parent:GetAttribute("IsAISnake") then
            if distance < BODY_RADIUS then
                self:QueueDeath(player)
                
                -- Optional: destroy AI snake
                if hitPart.Parent:FindFirstChild("Destroy") then
                    hitPart.Parent:Destroy()
                end
                
                return true
            end
        end
    end
    
    if not otherPlayer or otherPlayer == player then
        -- Self-collision check
        if otherPlayer == player then
            local segNum = tonumber(hitPart.Name:match("Segment[%s_]*(%d+)")) or 0
            if segNum <= 10 then -- Ignore first 10 segments
                return false
            end
        else
            return false
        end
    end
    
    -- Check if other player is invincible
    if InvinciblePlayers[otherPlayer] and os.clock() < InvinciblePlayers[otherPlayer] then
        return false
    end
    
    -- Head collision
    if hitPart.Name:match("Head") or hitPart.Name:match("Segment[%s_]*0") then
        if distance < HEAD_RADIUS then
            self:HandleHeadCollision(player, otherPlayer)
            return true
        end
    end
    
    -- Body collision
    if distance < BODY_RADIUS then
        self:QueueDeath(player)
        
        -- Fire collision event for VFX
        if VFXManager then
            PlayVFX:FireAllClients("collision", myHead.Position)
        end
        
        -- Fire collision remote
        SnakeCollision:FireAllClients(player, otherPlayer, myHead.Position)
        
        return true
    end
    
    return false
end

-- Get player from a snake part
function SnakeCollisionHandler:GetPlayerFromPart(part)
    local model = part.Parent
    if not model then return nil end
    
    -- Check snake naming patterns
    if model.Name:match("^Snake_") then
        local playerName = model.Name:gsub("Snake_", "")
        return Players:FindFirstChild(playerName)
    end
    
    -- Check if it's a character
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return Players:GetPlayerFromCharacter(model)
    end
    
    -- Check for player attribute
    local playerAttr = model:GetAttribute("Player")
    if playerAttr and typeof(playerAttr) == "Instance" then
        return playerAttr
    end
    
    -- Check for player object value
    local playerValue = model:FindFirstChild("Player")
    if playerValue and playerValue:IsA("ObjectValue") and playerValue.Value then
        return playerValue.Value
    end
    
    return nil
end

-- Handle head-to-head collision
function SnakeCollisionHandler:HandleHeadCollision(playerA, playerB)
    local headA = self:GetSnakeHead(playerA)
    local headB = self:GetSnakeHead(playerB)
    
    if not headA or not headB then return end
    
    -- Check velocities to see who wins
    local velA = headA.AssemblyLinearVelocity or headA.Velocity or Vector3.zero
    local velB = headB.AssemblyLinearVelocity or headB.Velocity or Vector3.zero
    
    -- Calculate approach vectors
    local dirAtoB = (headB.Position - headA.Position).Unit
    local approachSpeedA = velA:Dot(dirAtoB)
    local approachSpeedB = velB:Dot(-dirAtoB)
    
    -- Determine winner based on approach speed
    if approachSpeedA > 2 and approachSpeedB <= 2 then
        self:QueueDeath(playerB)
    elseif approachSpeedB > 2 and approachSpeedA <= 2 then
        self:QueueDeath(playerA)
    else
        -- Both approaching or neither - both die
        self:QueueDeath(playerA)
        task.wait() -- Small delay
        self:QueueDeath(playerB)
    end
    
    -- VFX for head collision
    if VFXManager then
        local midPoint = (headA.Position + headB.Position) / 2
        PlayVFX:FireAllClients("headCollision", midPoint)
    end
end

-- Queue a player for death processing
function SnakeCollisionHandler:QueueDeath(player)
    -- Prevent duplicate deaths
    for _, death in ipairs(DeathQueue) do
        if death == player then return end
    end
    
    table.insert(DeathQueue, player)
end

-- Process deaths (runs continuously)
function SnakeCollisionHandler:ProcessDeaths()
    while true do
        task.wait(0.1)
        
        if #DeathQueue > 0 then
            local player = table.remove(DeathQueue, 1)
            
            local data = ActiveSnakes[player]
            if data and data.State == "alive" then
                data.State = "dead"
                
                -- Get snake length for orb spawning
                local length = 10
                if player:FindFirstChild("leaderstats") then
                    local lengthVal = player.leaderstats:FindFirstChild("Length") or
                                    player.leaderstats:FindFirstChild("Score") or
                                    player.leaderstats:FindFirstChild("Size")
                    if lengthVal then
                        length = lengthVal.Value
                    end
                end
                
                -- Check for revive (if your game supports it)
                local hasRevive = player:GetAttribute("HasRevive") and 
                                 player:GetAttribute("RevivesAvailable") and
                                 player:GetAttribute("RevivesAvailable") > 0
                
                if hasRevive then
                    -- You can add revive logic here if needed
                    -- For now, we'll proceed with normal death
                end
                
                -- Spawn orbs
                self:SpawnDeathOrbs(player, length)
                
                -- Fire your existing death event
                PlayerDied:Fire(player)
                
                -- Cleanup
                self:CleanupPlayer(player)
            end
        end
    end
end

-- Spawn orbs when snake dies
function SnakeCollisionHandler:SpawnDeathOrbs(player, snakeLength)
    local positions = {}
    
    -- Get segment positions from OptimizedSnakeSystem if available
    if OptimizedSnakeSystem.GetSnakeSegments then
        local segments = OptimizedSnakeSystem:GetSnakeSegments(player)
        if segments then
            for _, segment in ipairs(segments) do
                if segment.Position then
                    table.insert(positions, segment.Position)
                end
            end
        end
    end
    
    -- Fallback: get positions from workspace model
    if #positions == 0 then
        local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
        if snakeModel then
            for _, part in ipairs(snakeModel:GetChildren()) do
                if part:IsA("BasePart") and (part.Name:match("Segment") or part.Name:match("Head")) then
                    table.insert(positions, part.Position)
                end
            end
        end
    end
    
    -- If still no positions, use player position
    if #positions == 0 and player.Character then
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            positions[1] = root.Position
        end
    end
    
    -- Spawn orbs using your OrbUtils
    local orbCount = math.clamp(math.floor(snakeLength / 3), 3, 40)
    local orbValue = math.max(1, math.floor(snakeLength * 0.3 / orbCount))
    
    task.spawn(function()
        task.wait(0.5) -- Small delay for death animation
        
        local step = math.max(1, math.floor(#positions / orbCount))
        local orbsSpawned = 0
        
        for i = 1, #positions, step do
            if orbsSpawned >= orbCount then break end
            
            local pos = positions[i]
            if pos then
                -- Add slight randomization
                local offset = Vector3.new(
                    math.random(-2, 2),
                    0,
                    math.random(-2, 2)
                )
                
                -- Try different OrbUtils function names
                local success = false
                
                if OrbUtils.spawnOrbAt then
                    success = pcall(function()
                        OrbUtils.spawnOrbAt(pos + offset, orbValue)
                    end)
                elseif OrbUtils.SpawnOrb then
                    success = pcall(function()
                        OrbUtils.SpawnOrb(pos + offset, orbValue)
                    end)
                elseif OrbUtils.createOrb then
                    success = pcall(function()
                        OrbUtils.createOrb(pos + offset, orbValue)
                    end)
                end
                
                if success then
                    orbsSpawned = orbsSpawned + 1
                end
            end
            
            -- Yield periodically
            if i % 5 == 0 then
                task.wait()
            end
        end
    end)
end

-- Initialize the system
function SnakeCollisionHandler:Init()
    print("🐍 Modern Collision System Starting...")
    print("📦 Using modules:", {
        Trove = "✅",
        SnakeConfig = "✅", 
        OrbUtils = "✅",
        OptimizedSnakeSystem = "✅",
        VFXManager = VFXManager and "✅" or "❌",
        AISnake = AISnake and "✅" or "❌"
    })
    
    -- Player connections
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            -- Wait for snake to be set up by your existing systems
            task.wait(0.5)
            self:SetupPlayer(player)
        end)
        
        player.CharacterRemoving:Connect(function()
            self:CleanupPlayer(player)
        end)
    end)
    
    -- Cleanup on leave
    Players.PlayerRemoving:Connect(function(player)
        self:CleanupPlayer(player)
    end)
    
    -- Handle players already in game
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            self:SetupPlayer(player)
        end
    end
    
    -- Start death processor
    task.spawn(function()
        self:ProcessDeaths()
    end)
    
    -- Listen to your existing collision remote if it exists
    if SnakeCollision.OnServerEvent then
        SnakeCollision.OnServerEvent:Connect(function(player, targetPlayer, position)
            -- Validate the collision report from client
            if not player or not targetPlayer or not position then return end
            
            -- Basic sanity check
            local head = self:GetSnakeHead(player)
            if head and (head.Position - position).Magnitude < 50 then
                -- Process if reasonable
                local data = ActiveSnakes[player]
                if data and data.State == "alive" then
                    self:QueueDeath(player)
                end
            end
        end)
    end
    
    print("✅ Collision System Ready!")
    print("💡 Features: Spatial queries, Trove cleanup, Self-collision prevention")
end

-- Start it up!
SnakeCollisionHandler:Init()

return SnakeCollisionHandler