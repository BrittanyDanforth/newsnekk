--!strict
-- SnakeCollisionClient - Client-side prediction for responsive gameplay
-- Part of the hybrid client-server collision model (2025 best practices)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Type definitions
type Player = Player
type BasePart = BasePart
type Vector3 = Vector3

-- === CONSTANTS ===
local CONSTANTS = {
    PREDICTION_RATE = 60, -- Hz, matches typical frame rate
    COLLISION_RADIUS = 3.5,
    EFFECT_DURATION = 0.5,
    SOUND_VOLUME = 0.3
}

-- === REMOTE EVENTS ===
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CollisionDetected = Remotes:WaitForChild("CollisionDetected")
local SnakeDied = Remotes:WaitForChild("SnakeDied")

-- === LOCAL PLAYER ===
local LocalPlayer = Players.LocalPlayer

-- === EFFECTS MANAGEMENT ===
local EffectsModule = {}

function EffectsModule.PlayCollisionEffect(position: Vector3)
    -- Create impact particles
    local attachment = Instance.new("Attachment")
    attachment.Position = position
    attachment.Parent = workspace.Terrain
    
    local particle = Instance.new("ParticleEmitter")
    particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particle.Rate = 100
    particle.Lifetime = NumberRange.new(0.3, 0.5)
    particle.VelocityInheritance = 0
    particle.EmissionDirection = Enum.NormalId.Top
    particle.Speed = NumberRange.new(5, 10)
    particle.SpreadAngle = Vector2.new(360, 360)
    particle.Parent = attachment
    
    -- Stop emission after brief burst
    task.wait(0.1)
    particle.Enabled = false
    
    -- Clean up
    task.wait(1)
    attachment:Destroy()
end

function EffectsModule.PlayCollisionSound(position: Vector3)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxasset://sounds/impact_water_low.mp3"
    sound.Volume = CONSTANTS.SOUND_VOLUME
    sound.PlayOnRemove = false
    sound.Parent = workspace
    
    -- 3D sound positioning
    local attachment = Instance.new("Attachment")
    attachment.Position = position
    attachment.Parent = workspace.Terrain
    sound.Parent = attachment
    
    sound:Play()
    
    -- Clean up after sound finishes
    sound.Ended:Connect(function()
        attachment:Destroy()
    end)
end

function EffectsModule.PlayDeathEffect(position: Vector3)
    -- More dramatic effect for death
    local model = Instance.new("Model")
    model.Name = "DeathEffect"
    model.Parent = workspace
    
    -- Create expanding ring
    local ring = Instance.new("Part")
    ring.Name = "Ring"
    ring.Anchored = true
    ring.CanCollide = false
    ring.Material = Enum.Material.Neon
    ring.BrickColor = BrickColor.new("Really red")
    ring.Size = Vector3.new(1, 0.5, 1)
    ring.Position = position
    ring.Transparency = 0.5
    ring.Parent = model
    
    -- Create mesh
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Cylinder
    mesh.Parent = ring
    
    -- Tween the ring expansion
    local tween = TweenService:Create(
        ring,
        TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(30, 0.1, 30),
            Transparency = 1
        }
    )
    
    tween:Play()
    tween.Completed:Connect(function()
        model:Destroy()
    end)
    
    -- Add particles
    EffectsModule.PlayCollisionEffect(position)
end

-- === CLIENT PREDICTION MODULE ===
local ClientPrediction = {}
ClientPrediction.LastPredictionTime = 0
ClientPrediction.PredictedCollisions = {} -- Track what we've already predicted

function ClientPrediction.GetNearbySnakeParts(position: Vector3, radius: number): {BasePart}
    local parts = {}
    
    -- Use GetPartBoundsInRadius for efficient spatial query
    local region = Region3.new(
        position - Vector3.new(radius, radius, radius),
        position + Vector3.new(radius, radius, radius)
    )
    region = region:ExpandToGrid(4)
    
    for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(radius * 2, radius * 2, radius * 2))) do
        if part.Name:match("^Segment") or part.Name == "SnakeHead" then
            -- Verify it belongs to a snake
            local model = part.Parent
            if model and model.Name:match("^Snake_") then
                table.insert(parts, part)
            end
        end
    end
    
    return parts
end

function ClientPrediction.PredictCollision()
    -- Rate limiting
    local now = os.clock()
    if now - ClientPrediction.LastPredictionTime < (1 / CONSTANTS.PREDICTION_RATE) then
        return
    end
    ClientPrediction.LastPredictionTime = now
    
    -- Get local player's snake head
    local character = LocalPlayer.Character
    if not character then return end
    
    local snakeModel = workspace:FindFirstChild("Snake_" .. LocalPlayer.Name)
    local head = snakeModel and snakeModel:FindFirstChild("SnakeHead") or character:FindFirstChild("HumanoidRootPart")
    
    if not head then return end
    
    -- Check for nearby collisions
    local nearbyParts = ClientPrediction.GetNearbySnakeParts(head.Position, CONSTANTS.COLLISION_RADIUS)
    
    for _, part in ipairs(nearbyParts) do
        -- Skip our own parts
        if part.Parent == snakeModel or part.Parent == character then
            continue
        end
        
        local distance = (part.Position - head.Position).Magnitude
        if distance < CONSTANTS.COLLISION_RADIUS then
            -- Check if we've already predicted this collision recently
            local key = tostring(part) .. "_" .. math.floor(now)
            if ClientPrediction.PredictedCollisions[key] then
                continue
            end
            
            -- Mark as predicted
            ClientPrediction.PredictedCollisions[key] = true
            
            -- Clean up old predictions
            task.defer(function()
                task.wait(1)
                ClientPrediction.PredictedCollisions[key] = nil
            end)
            
            -- Play immediate feedback
            EffectsModule.PlayCollisionEffect(head.Position)
            EffectsModule.PlayCollisionSound(head.Position)
            
            -- Report to server for validation
            local targetPlayer = ClientPrediction.GetPlayerFromPart(part)
            if targetPlayer then
                CollisionDetected:FireServer(targetPlayer, head.Position)
            end
        end
    end
end

function ClientPrediction.GetPlayerFromPart(part: BasePart): Player?
    local model = part.Parent
    if model and model.Name:match("^Snake_") then
        local playerName = model.Name:gsub("Snake_", "")
        return Players:FindFirstChild(playerName)
    end
    return nil
end

-- === DEATH EFFECT HANDLER ===
SnakeDied.OnClientEvent:Connect(function(player: Player, position: Vector3)
    -- Play death effect for all players
    EffectsModule.PlayDeathEffect(position)
    
    -- Additional effects if it's the local player
    if player == LocalPlayer then
        -- Screen flash
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "DeathFlash"
        screenGui.Parent = LocalPlayer.PlayerGui
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.new(1, 0, 0)
        frame.BackgroundTransparency = 0.7
        frame.Parent = screenGui
        
        local tween = TweenService:Create(
            frame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad),
            {BackgroundTransparency = 1}
        )
        
        tween:Play()
        tween.Completed:Connect(function()
            screenGui:Destroy()
        end)
    end
end)

-- === INITIALIZATION ===
local function Initialize()
    -- Connect prediction to render stepped for maximum responsiveness
    RunService.RenderStepped:Connect(function()
        ClientPrediction.PredictCollision()
    end)
    
    -- Clean up prediction cache periodically
    task.spawn(function()
        while true do
            task.wait(10)
            -- Clear old predictions
            local now = os.clock()
            for key, _ in pairs(ClientPrediction.PredictedCollisions) do
                local timestamp = tonumber(key:match("_(%d+)$")) or 0
                if now - timestamp > 2 then
                    ClientPrediction.PredictedCollisions[key] = nil
                end
            end
        end
    end)
end

-- Start the client prediction system
Initialize()

print("✅ SnakeCollisionClient initialized - Client prediction active")