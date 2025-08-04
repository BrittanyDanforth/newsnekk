--!strict
-- SnakeConfig - Central configuration for the snake game
-- Following the principle of single source of truth for game constants

local SnakeConfig = {}

-- === SNAKE PROPERTIES ===
SnakeConfig.StartingLength = 10
SnakeConfig.MaxSpeed = 16 -- studs per second
SnakeConfig.TurnSpeed = 180 -- degrees per second
SnakeConfig.SegmentSpacing = 2.2 -- studs between segments
SnakeConfig.GrowthRate = 1 -- segments added per orb

-- === COLLISION SETTINGS ===
SnakeConfig.HeadRadius = 1.5
SnakeConfig.BodyRadius = 1.2
SnakeConfig.SelfCollisionGracePeriod = 3 -- seconds after spawn

-- === VISUAL SETTINGS ===
SnakeConfig.SegmentSize = Vector3.new(2, 1, 2)
SnakeConfig.HeadSize = Vector3.new(2.5, 1.5, 2.5)
SnakeConfig.DefaultColor = Color3.fromRGB(34, 139, 34) -- Forest green

-- === GAMEPLAY SETTINGS ===
SnakeConfig.OrbValue = {
    Small = 1,
    Medium = 5,
    Large = 10,
    Golden = 50
}

SnakeConfig.RespawnDelay = 3 -- seconds
SnakeConfig.InvincibilityDuration = 5 -- seconds after spawn

-- === PERFORMANCE SETTINGS ===
SnakeConfig.MaxSegmentsPerSnake = 1000
SnakeConfig.LODDistances = {
    High = 50,    -- Full detail
    Medium = 100, -- Reduced detail
    Low = 200     -- Minimal detail
}

-- === NETWORK SETTINGS ===
SnakeConfig.ReplicationRate = 10 -- Hz
SnakeConfig.InterpolationTime = 0.1 -- seconds

-- === VALIDATION FUNCTIONS ===
function SnakeConfig.ValidateLength(length: number): number
    return math.clamp(length, 1, SnakeConfig.MaxSegmentsPerSnake)
end

function SnakeConfig.GetOrbValueForLength(length: number): number
    -- Scale orb value based on snake length
    if length < 50 then
        return SnakeConfig.OrbValue.Small
    elseif length < 200 then
        return SnakeConfig.OrbValue.Medium
    elseif length < 500 then
        return SnakeConfig.OrbValue.Large
    else
        return SnakeConfig.OrbValue.Golden
    end
end

-- Make config read-only
return table.freeze(SnakeConfig)