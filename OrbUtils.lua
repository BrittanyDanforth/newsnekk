--!strict
-- OrbUtils - Utility module for spawning and managing collectible orbs
-- Follows modern patterns with proper cleanup and optimization

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Type definitions
type Vector3 = Vector3
type Color3 = Color3

type OrbData = {
    Value: number,
    Position: Vector3,
    Color: Color3,
    Size: number
}

local OrbUtils = {}

-- === CONSTANTS ===
local ORB_HEIGHT = 5 -- Height at which orbs spawn
local ORB_LIFETIME = 300 -- 5 minutes before despawn
local FLOAT_AMPLITUDE = 0.5 -- Bobbing motion amplitude
local FLOAT_SPEED = 2 -- Bobbing speed
local SPAWN_TWEEN_TIME = 0.5

-- Orb appearance by value
local ORB_APPEARANCES = {
    [1] = {color = Color3.fromRGB(100, 200, 100), size = 1},
    [5] = {color = Color3.fromRGB(100, 150, 255), size = 1.5},
    [10] = {color = Color3.fromRGB(255, 100, 255), size = 2},
    [50] = {color = Color3.fromRGB(255, 215, 0), size = 3}, -- Golden
}

-- === HELPER FUNCTIONS ===
local function getOrbAppearance(value: number)
    -- Find the appropriate appearance for the value
    local appearance = ORB_APPEARANCES[1] -- Default
    
    for orbValue, orbAppearance in pairs(ORB_APPEARANCES) do
        if value >= orbValue then
            appearance = orbAppearance
        end
    end
    
    return appearance
end

-- === PUBLIC API ===
function OrbUtils.SpawnOrb(position: Vector3, value: number): BasePart?
    -- Validate inputs
    if not position or not value or value <= 0 then
        warn("Invalid orb spawn parameters")
        return nil
    end
    
    -- Get appearance
    local appearance = getOrbAppearance(value)
    
    -- Create orb model
    local orb = Instance.new("Part")
    orb.Name = "Orb_" .. value
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Neon
    orb.TopSurface = Enum.SurfaceType.Smooth
    orb.BottomSurface = Enum.SurfaceType.Smooth
    orb.Size = Vector3.new(appearance.size, appearance.size, appearance.size)
    orb.Color = appearance.color
    orb.CanCollide = false
    orb.Anchored = true
    orb.Position = Vector3.new(position.X, ORB_HEIGHT, position.Z)
    
    -- Add value attribute
    orb:SetAttribute("OrbValue", value)
    orb:SetAttribute("SpawnTime", os.clock())
    
    -- Add light emission for visual appeal
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = 2
    pointLight.Range = appearance.size * 5
    pointLight.Color = appearance.color
    pointLight.Parent = orb
    
    -- Create selection box for better visibility
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = orb
    selectionBox.Color3 = appearance.color
    selectionBox.LineThickness = 0.1
    selectionBox.Transparency = 0.5
    selectionBox.Parent = orb
    
    -- Parent to workspace
    orb.Parent = workspace
    
    -- Spawn animation
    orb.Size = Vector3.zero
    orb.Transparency = 1
    
    local spawnTween = TweenService:Create(
        orb,
        TweenInfo.new(SPAWN_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(appearance.size, appearance.size, appearance.size),
            Transparency = 0
        }
    )
    
    spawnTween:Play()
    
    -- Add floating animation
    task.spawn(function()
        local startY = ORB_HEIGHT
        local startTime = os.clock()
        
        local connection
        connection = RunService.Heartbeat:Connect(function()
            if not orb.Parent then
                connection:Disconnect()
                return
            end
            
            local elapsed = os.clock() - startTime
            local offset = math.sin(elapsed * FLOAT_SPEED) * FLOAT_AMPLITUDE
            orb.Position = Vector3.new(orb.Position.X, startY + offset, orb.Position.Z)
            
            -- Gentle rotation
            orb.CFrame = orb.CFrame * CFrame.Angles(0, math.rad(1), 0)
        end)
        
        -- Store connection for cleanup
        orb:SetAttribute("FloatConnection", connection)
    end)
    
    -- Schedule automatic cleanup
    Debris:AddItem(orb, ORB_LIFETIME)
    
    return orb
end

function OrbUtils.SpawnOrbBatch(positions: {Vector3}, value: number): {BasePart}
    local orbs = {}
    
    for i, position in ipairs(positions) do
        -- Stagger spawning for performance
        if i % 5 == 0 then
            task.wait()
        end
        
        local orb = OrbUtils.SpawnOrb(position, value)
        if orb then
            table.insert(orbs, orb)
        end
    end
    
    return orbs
end

function OrbUtils.SpawnOrbPattern(center: Vector3, pattern: string, value: number, spacing: number): {BasePart}
    local positions = {}
    spacing = spacing or 5
    
    if pattern == "circle" then
        local radius = 10
        local count = 8
        for i = 1, count do
            local angle = (i - 1) * (2 * math.pi / count)
            local x = center.X + radius * math.cos(angle)
            local z = center.Z + radius * math.sin(angle)
            table.insert(positions, Vector3.new(x, center.Y, z))
        end
    elseif pattern == "line" then
        for i = -2, 2 do
            table.insert(positions, center + Vector3.new(i * spacing, 0, 0))
        end
    elseif pattern == "grid" then
        for x = -1, 1 do
            for z = -1, 1 do
                table.insert(positions, center + Vector3.new(x * spacing, 0, z * spacing))
            end
        end
    else
        -- Default single orb
        table.insert(positions, center)
    end
    
    return OrbUtils.SpawnOrbBatch(positions, value)
end

-- Cleanup function for proper resource management
function OrbUtils.CleanupOrb(orb: BasePart)
    if not orb or not orb.Parent then return end
    
    -- Disconnect floating animation
    local connection = orb:GetAttribute("FloatConnection")
    if connection and typeof(connection) == "RBXScriptConnection" then
        connection:Disconnect()
    end
    
    -- Fade out animation
    local fadeTween = TweenService:Create(
        orb,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        {
            Size = Vector3.zero,
            Transparency = 1
        }
    )
    
    fadeTween:Play()
    fadeTween.Completed:Connect(function()
        orb:Destroy()
    end)
end

-- Export with proper interface
return table.freeze(OrbUtils)