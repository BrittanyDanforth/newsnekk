-- SnakeCollisionHandler V7.5 - ROBUST REVIVE & FAIR COLLISIONS
-- CRITICAL FIXES:
-- 1. COMPLETE HumanoidRootPart fix - Only uses visual snake head for collisions
-- 2. Fair head-to-head collisions with length-based tie-breaker
-- 3. Robust invincibility during respawn/revive with multiple checks
-- 4. Dynamic collision distance based on snake visual size
-- 5. Fixed player vs AI collisions to prevent mutual destruction
-- 6. Added recentlyKilled safeguard to prevent duplicate deaths

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

-- Load required modules
local SpatialGrid = require(game.ServerScriptService:FindFirstChild("SpatialGrid") or game.ReplicatedStorage:FindFirstChild("SpatialGrid"))

-- Constants
local DEPRECATED_HEAD_COLLISION_DISTANCE = 3.5 -- This is now dynamic based on visual size
local BODY_COLLISION_DISTANCE = 2.5
local INVINCIBILITY_DURATION = 3
local REVIVE_INVINCIBILITY_DURATION = 5
local AI_DEATH_ORB_COUNT = 10
local AI_DEATH_ORB_MIN_VALUE = 1
local AI_DEATH_ORB_MAX_VALUE = 3
local ORB_SPAWN_RADIUS = 20
local ORB_Y_POSITION = 5

-- Growth calculation from OptimizedSnakeSystem
local BASE_SIZE = 3.5
local MAX_SIZE_MULTIPLIER = 3.5
local GROWTH_CURVE_EXPONENT = 0.6

-- Tables to track states
local invinciblePlayers = {}
local deadPlayers = {}
local processingRevive = {}
local recentlyKilled = {} -- NEW: Prevents duplicate death processing

-- Function to calculate growth factor (from OptimizedSnakeSystem)
local function calculateGrowthFactor(length)
    local normalizedLength = math.min(length / 1000, 1)
    return 1 + (normalizedLength ^ GROWTH_CURVE_EXPONENT) * (MAX_SIZE_MULTIPLIER - 1)
end

-- Function to get snake visual size
local function getSnakeVisualSize(player)
    local length = player:GetAttribute("Length") or 100
    local growthFactor = calculateGrowthFactor(length)
    return BASE_SIZE * growthFactor * 1.2 -- 1.2 is head size multiplier
end

-- CRITICAL: Only get visual snake heads, never HumanoidRootPart
local function getPlayerHeads()
    local heads = {}
    local processedPlayers = {} -- Prevent duplicates
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and not processedPlayers[player] then
            -- ONLY look for visual snake head
            local snakeModel = player.Character:FindFirstChild("SnakeModel")
            if snakeModel then
                local visualHead = snakeModel:FindFirstChild("Segment0_Head")
                if visualHead then
                    table.insert(heads, {
                        part = visualHead,
                        player = player,
                        isAI = false,
                        character = player.Character
                    })
                    processedPlayers[player] = true
                end
            end
        end
    end
    
    -- Get AI snake heads
    for _, aiSnake in ipairs(CollectionService:GetTagged("AISnake")) do
        if aiSnake and aiSnake.Parent then
            local head = aiSnake:FindFirstChild("Segment0_Head")
            if head then
                table.insert(heads, {
                    part = head,
                    player = nil,
                    isAI = true,
                    aiModel = aiSnake,
                    character = aiSnake
                })
            end
        end
    end
    
    return heads
end

-- ROBUST INVINCIBILITY CHECK
local function isPlayerInvincible(player)
    if not player then return false end
    
    -- Check RevivingNow attribute
    if player:GetAttribute("RevivingNow") == true then
        return true
    end
    
    -- Check JustRevived attribute
    if player:GetAttribute("JustRevived") == true then
        return true
    end
    
    -- Check processingRevive table
    if processingRevive[player] then
        return true
    end
    
    -- Check invinciblePlayers table with timestamp
    if invinciblePlayers[player] and tick() < invinciblePlayers[player] then
        return true
    end
    
    -- Check ActiveGhostMode
    if player:GetAttribute("ActiveGhostMode") == true then
        return true
    end
    
    -- Check spawn time
    local spawnTime = player:GetAttribute("SpawnTime")
    if spawnTime and tick() - spawnTime < INVINCIBILITY_DURATION then
        return true
    end
    
    return false
end

-- Set player invincible
local function setPlayerInvincible(player, duration, reason)
    if player then
        invinciblePlayers[player] = tick() + duration
        print(string.format("✅ %s is now invincible for %d seconds (%s)", 
            player.Name, duration, reason or "unknown"))
    end
end

-- Get all snake segments (body parts)
local function getSnakeSegments(character)
    local segments = {}
    
    if character:FindFirstChild("SnakeModel") then
        -- Player snake
        for _, part in ipairs(character.SnakeModel:GetChildren()) do
            if part:IsA("BasePart") and part.Name:match("Segment") and part.Name ~= "Segment0_Head" then
                table.insert(segments, part)
            end
        end
    elseif character:GetAttribute("IsAISnake") then
        -- AI snake
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name:match("Segment") and part.Name ~= "Segment0_Head" then
                table.insert(segments, part)
            end
        end
    end
    
    return segments
end

-- Handle player death
local function handlePlayerDeath(player, killedBy)
    if deadPlayers[player] or recentlyKilled[player] then
        return -- Already dead or recently killed
    end
    
    -- Mark as recently killed to prevent duplicate processing
    recentlyKilled[player] = true
    task.wait(0.1) -- Brief cooldown
    recentlyKilled[player] = nil
    
    deadPlayers[player] = true
    
    -- Fire death event
    local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if remoteEvents then
        local snakeDeathEvent = remoteEvents:FindFirstChild("SnakeDeath")
        if snakeDeathEvent then
            snakeDeathEvent:FireClient(player, killedBy and killedBy.Name or "Unknown")
        end
    end
    
    print(string.format("💀 %s died to %s", 
        player.Name, killedBy and killedBy.Name or "collision"))
end

-- Handle AI death with orb spawning
local function handleAIDeath(aiModel, killedBy)
    if not aiModel or not aiModel.Parent then return end
    if recentlyKilled[aiModel] then return end
    
    -- Mark as recently killed
    recentlyKilled[aiModel] = true
    task.spawn(function()
        task.wait(0.1)
        recentlyKilled[aiModel] = nil
    end)
    
    -- Get AI position for orb spawning
    local position = aiModel.PrimaryPart and aiModel.PrimaryPart.Position or Vector3.new(0, 10, 0)
    local aiLength = aiModel:GetAttribute("Length") or 100
    
    -- Calculate orbs to spawn
    local orbCount = math.min(AI_DEATH_ORB_COUNT, math.floor(aiLength / 10))
    
    -- Spawn orbs
    task.spawn(function()
        for i = 1, orbCount do
            local angle = (i / orbCount) * math.pi * 2
            local offset = Vector3.new(
                math.cos(angle) * math.random() * ORB_SPAWN_RADIUS,
                0,
                math.sin(angle) * math.random() * ORB_SPAWN_RADIUS
            )
            local orbPosition = position + offset
            orbPosition = Vector3.new(orbPosition.X, ORB_Y_POSITION, orbPosition.Z)
            
            -- Create orb
            local orb = Instance.new("Part")
            orb.Name = "Orb"
            orb.Shape = Enum.PartType.Ball
            orb.Material = Enum.Material.Neon
            orb.Size = Vector3.new(2, 2, 2)
            orb.Position = orbPosition
            orb.CanCollide = false
            orb.Anchored = true
            
            -- Random color
            local colors = {
                Color3.new(1, 0, 0),    -- Red
                Color3.new(0, 1, 0),    -- Green
                Color3.new(0, 0, 1),    -- Blue
                Color3.new(1, 1, 0),    -- Yellow
                Color3.new(1, 0, 1),    -- Magenta
                Color3.new(0, 1, 1)     -- Cyan
            }
            orb.Color = colors[math.random(#colors)]
            
            -- Set orb value
            orb:SetAttribute("Value", math.random(AI_DEATH_ORB_MIN_VALUE, AI_DEATH_ORB_MAX_VALUE))
            orb:SetAttribute("OrbType", "normal")
            
            -- Add to workspace and spatial grid
            orb.Parent = workspace
            if SpatialGrid then
                SpatialGrid.AddObject(orb, orbPosition, "orb")
            end
            
            -- Add glow
            local pointLight = Instance.new("PointLight")
            pointLight.Brightness = 2
            pointLight.Range = 10
            pointLight.Color = orb.Color
            pointLight.Parent = orb
            
            -- Collection tag
            CollectionService:AddTag(orb, "Orb")
        end
    end)
    
    -- Destroy AI model
    aiModel:SetAttribute("IsAlive", false)
    
    -- Visual death effect
    for _, part in ipairs(aiModel:GetDescendants()) do
        if part:IsA("BasePart") then
            TweenService:Create(part, TweenInfo.new(0.5), {
                Transparency = 1,
                Size = part.Size * 0.5
            }):Play()
        end
    end
    
    -- Destroy after animation
    task.wait(0.5)
    aiModel:Destroy()
    
    print(string.format("🤖💀 AI Snake died to %s, spawned %d orbs", 
        killedBy and killedBy.Name or "collision", orbCount))
end

-- Queue deaths to handle them properly
local deathQueue = {}
local aiDeathQueue = {}

local function queuePlayerDeath(player, killedBy)
    if not deadPlayers[player] and not recentlyKilled[player] then
        table.insert(deathQueue, {player = player, killedBy = killedBy})
    end
end

local function queueAIDeath(aiModel, killedBy)
    if aiModel and aiModel.Parent and not recentlyKilled[aiModel] then
        table.insert(aiDeathQueue, {aiModel = aiModel, killedBy = killedBy})
    end
end

-- Process death queues
local function processDeathQueues()
    -- Process player deaths
    for _, death in ipairs(deathQueue) do
        if death.player and death.player.Parent then
            handlePlayerDeath(death.player, death.killedBy)
        end
    end
    deathQueue = {}
    
    -- Process AI deaths
    for _, death in ipairs(aiDeathQueue) do
        if death.aiModel and death.aiModel.Parent then
            handleAIDeath(death.aiModel, death.killedBy)
        end
    end
    aiDeathQueue = {}
end

-- Main collision detection
local collisionConnection
collisionConnection = RunService.Heartbeat:Connect(function()
    local activePlayerHeads = getPlayerHeads()
    
    -- Pre-filter invincible players
    local validHeads = {}
    for _, headData in ipairs(activePlayerHeads) do
        local shouldSkip = false
        
        if headData.isAI then
            -- AI snakes are never invincible
            shouldSkip = false
        else
            -- Check if player is invincible
            shouldSkip = isPlayerInvincible(headData.player)
        end
        
        if not shouldSkip then
            table.insert(validHeads, headData)
        end
    end
    
    -- Check head-to-body collisions
    for _, headData in ipairs(validHeads) do
        local head = headData.part
        local isAI = headData.isAI
        local owner = isAI and headData.aiModel or headData.player
        
        -- Check collision with all snake bodies
        for _, targetData in ipairs(activePlayerHeads) do
            if targetData ~= headData then
                local targetSegments = getSnakeSegments(targetData.character)
                
                -- Check if head hits any body segment
                for _, segment in ipairs(targetSegments) do
                    if (head.Position - segment.Position).Magnitude <= BODY_COLLISION_DISTANCE then
                        if isAI then
                            queueAIDeath(headData.aiModel, targetData.player)
                        else
                            queuePlayerDeath(headData.player, targetData.player)
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- DYNAMIC HEAD-TO-HEAD COLLISIONS (WITH GHOST MODE FIX)
    for i = 1, #validHeads do
        local headA = validHeads[i]
        
        for j = i + 1, #validHeads do
            local headB = validHeads[j]
            
            -- Skip if same entity
            if headA == headB or headA.character == headB.character then
                continue
            end
            
            -- Calculate dynamic collision distance based on visual size
            local sizeA = headA.isAI and 5 or getSnakeVisualSize(headA.player)
            local sizeB = headB.isAI and 5 or getSnakeVisualSize(headB.player)
            local dynamicCollisionDistance = (sizeA + sizeB) / 2
            
            local distance = (headA.part.Position - headB.part.Position).Magnitude
            
            if distance <= dynamicCollisionDistance then
                -- Get velocities for charge detection
                local velA = headA.part.AssemblyLinearVelocity or Vector3.new()
                local velB = headB.part.AssemblyLinearVelocity or Vector3.new()
                
                -- Calculate who's charging more aggressively
                local dirToB = (headB.part.Position - headA.part.Position).Unit
                local dirToA = -dirToB
                
                local chargeA = velA:Dot(dirToB)
                local chargeB = velB:Dot(dirToA)
                
                -- Get lengths for tie-breaker
                local lengthA = headA.isAI and (headA.aiModel:GetAttribute("Length") or 100) or (headA.player:GetAttribute("Length") or 100)
                local lengthB = headB.isAI and (headB.aiModel:GetAttribute("Length") or 100) or (headB.player:GetAttribute("Length") or 100)
                
                -- Handle different collision scenarios
                if headA.isAI and headB.isAI then
                    -- AI vs AI: Both die
                    queueAIDeath(headA.aiModel, headB.aiModel)
                    queueAIDeath(headB.aiModel, headA.aiModel)
                    print("🤖💥🤖 AI head-to-head collision - both died")
                    
                elseif not headA.isAI and not headB.isAI then
                    -- Player vs Player
                    local ghostModeA = headA.player:GetAttribute("ActiveGhostMode") == true
                    local ghostModeB = headB.player:GetAttribute("ActiveGhostMode") == true
                    
                    if ghostModeA or ghostModeB then
                        -- Ghost mode players can't kill or be killed
                        print("👻 Ghost mode collision ignored")
                    elseif math.abs(chargeA - chargeB) > 10 then
                        -- Clear aggressor wins
                        if chargeA > chargeB then
                            queuePlayerDeath(headB.player, headA.player)
                            print(string.format("💥 %s charged into %s - %s wins!", 
                                headA.player.Name, headB.player.Name, headA.player.Name))
                        else
                            queuePlayerDeath(headA.player, headB.player)
                            print(string.format("💥 %s charged into %s - %s wins!", 
                                headB.player.Name, headA.player.Name, headB.player.Name))
                        end
                    else
                        -- Similar charge - length wins
                        if lengthA > lengthB then
                            queuePlayerDeath(headB.player, headA.player)
                            print(string.format("💥 Head collision - %s (L:%d) beats %s (L:%d)", 
                                headA.player.Name, lengthA, headB.player.Name, lengthB))
                        elseif lengthB > lengthA then
                            queuePlayerDeath(headA.player, headB.player)
                            print(string.format("💥 Head collision - %s (L:%d) beats %s (L:%d)", 
                                headB.player.Name, lengthB, headA.player.Name, lengthA))
                        else
                            -- Equal length - both die
                            queuePlayerDeath(headA.player, headB.player)
                            queuePlayerDeath(headB.player, headA.player)
                            print("💥 Head collision - equal length, both die!")
                        end
                    end
                    
                else
                    -- Player vs AI
                    local playerHead = headA.isAI and headB or headA
                    local aiHead = headA.isAI and headA or headB
                    
                    if playerHead.player:GetAttribute("ActiveGhostMode") == true then
                        -- Ghost mode - no collision
                        print("👻 Ghost mode vs AI - no collision")
                    else
                        -- Use length-based tie-breaker
                        local playerLength = playerHead.player:GetAttribute("Length") or 100
                        local aiLength = aiHead.aiModel:GetAttribute("Length") or 100
                        
                        if playerLength >= aiLength then
                            -- Player wins or tie (player wins ties vs AI)
                            queueAIDeath(aiHead.aiModel, playerHead.player)
                            print(string.format("🎮 Player %s (L:%d) beats AI (L:%d)", 
                                playerHead.player.Name, playerLength, aiLength))
                        else
                            -- AI wins
                            queuePlayerDeath(playerHead.player, aiHead.aiModel)
                            print(string.format("🤖 AI (L:%d) beats player %s (L:%d)", 
                                aiLength, playerHead.player.Name, playerLength))
                        end
                    end
                end
            end
        end
    end
    
    -- Process all queued deaths
    processDeathQueues()
end)

-- HUMANOIDROOTPART SAFETY SYSTEM
task.spawn(function()
    while true do
        task.wait(0.1)
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                local snakeModel = player.Character:FindFirstChild("SnakeModel")
                
                if humanoidRootPart and snakeModel then
                    -- Move HumanoidRootPart far away and anchor it
                    humanoidRootPart.CFrame = CFrame.new(0, -5000, 0)
                    humanoidRootPart.Anchored = true
                    humanoidRootPart.CanCollide = false
                    humanoidRootPart.CanTouch = false
                    humanoidRootPart.CanQuery = false
                end
            end
        end
    end
end)

-- Handle player spawn/respawn
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Clear death/revive states
        deadPlayers[player] = nil
        processingRevive[player] = nil
        
        -- Set spawn time
        player:SetAttribute("SpawnTime", tick())
        
        -- Grant invincibility
        setPlayerInvincible(player, INVINCIBILITY_DURATION, "spawn")
        
        -- Clear any revive attributes
        player:SetAttribute("RevivingNow", false)
        player:SetAttribute("JustRevived", false)
    end)
    
    player.CharacterRemoving:Connect(function()
        deadPlayers[player] = nil
        invinciblePlayers[player] = nil
        processingRevive[player] = nil
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    deadPlayers[player] = nil
    invinciblePlayers[player] = nil
    processingRevive[player] = nil
    recentlyKilled[player] = nil
end)

-- Listen for revive events
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 5)
if remoteEvents then
    local reviveEvent = remoteEvents:FindFirstChild("RevivePlayer")
    if reviveEvent then
        reviveEvent.OnServerEvent:Connect(function(player)
            if player and player.Character then
                processingRevive[player] = true
                deadPlayers[player] = nil
                
                -- Set revive attributes
                player:SetAttribute("RevivingNow", true)
                player:SetAttribute("JustRevived", true)
                
                -- Grant extended invincibility
                setPlayerInvincible(player, REVIVE_INVINCIBILITY_DURATION, "revive")
                
                -- Clear revive state after delay
                task.wait(REVIVE_INVINCIBILITY_DURATION)
                processingRevive[player] = nil
                player:SetAttribute("RevivingNow", false)
                player:SetAttribute("JustRevived", false)
            end
        end)
    end
end

print("✅ SnakeCollisionHandler V7.4 - FAIR INVINCIBILITY & ORBS LOADED")
