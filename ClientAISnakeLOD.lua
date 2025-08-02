-- ClientAISnakeLOD v3.0: Slither.io-inspired ultra-smooth LOD system
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Constants for smooth Slither.io-style LOD
local UPDATE_RATE = 30 -- 30 Hz updates for smooth transitions
local FADE_START_DISTANCE = 150 -- Start fading snake segments
local FADE_END_DISTANCE = 400 -- Fully fade distant segments
local OUTLINE_FADE_DISTANCE = 200 -- When to fade outline effects
local COMPRESSION_START = 100 -- Start compressing segments closer together
local MAX_COMPRESSION_RATIO = 0.3 -- Maximum segment compression
local MAX_VISIBLE_SNAKES = 20 -- Limit visible snakes for performance
local HEAD_ALWAYS_VISIBLE = true -- Always show snake heads
local MIN_SEGMENT_TRANSPARENCY = 0.1 -- Never fully hide segments
local MAX_SEGMENT_TRANSPARENCY = 0.95 -- Maximum fade

-- Visual quality settings
local GLOW_FADE_START = 100 -- Start fading glow effects
local BEAM_WIDTH_REDUCTION = 0.5 -- Reduce beam width at distance
local PARTICLE_DISABLE_DISTANCE = 150 -- Disable particles beyond this

-- Smooth transition parameters
local TRANSPARENCY_LERP_SPEED = 0.15 -- How fast transparency changes
local SIZE_LERP_SPEED = 0.1 -- How fast size changes
local VISIBILITY_CHECK_INTERVAL = 0.1 -- How often to check visibility

-- Performance settings
local MAX_SEGMENTS_PER_SNAKE = 200 -- Cap segments per snake
local SEGMENT_SKIP_DISTANCE = 300 -- Skip every other segment at distance
local FAR_SEGMENT_SKIP_RATIO = 3 -- Skip more segments when very far

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ClientSnake class for managing individual snake LOD
local ClientSnake = {}
ClientSnake.__index = ClientSnake

function ClientSnake.new(snakeModel)
    local self = setmetatable({}, ClientSnake)
    
    self.model = snakeModel
    self.segments = {}
    self.beams = {}
    self.lastUpdate = 0
    self.distance = 0
    self.isVisible = true
    self.compressionRatio = 1
    self.transparencyMultiplier = 0
    
    -- Cache all segments and beams
    for _, part in ipairs(snakeModel:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:match("Segment") then
            table.insert(self.segments, {
                part = part,
                originalSize = part.Size,
                originalTransparency = part.Transparency or 0,
                index = tonumber(part.Name:match("%d+")) or 0,
                glow = part:FindFirstChildOfClass("PointLight"),
                outline = part:FindFirstChildOfClass("SelectionBox"),
                particles = part:FindFirstChildOfClass("ParticleEmitter")
            })
        elseif part:IsA("Beam") then
            table.insert(self.beams, {
                beam = part,
                originalWidth0 = part.Width0,
                originalWidth1 = part.Width1,
                originalTransparency = part.Transparency
            })
        end
    end
    
    -- Sort segments by index for proper ordering
    table.sort(self.segments, function(a, b) return a.index < b.index end)
    
    return self
end

function ClientSnake:UpdateDistance()
    if not self.model.PrimaryPart then return end
    
    local headPos = self.model.PrimaryPart.Position
    local cameraPos = camera.CFrame.Position
    self.distance = (headPos - cameraPos).Magnitude
end

function ClientSnake:CalculateCompressionRatio()
    if self.distance < COMPRESSION_START then
        self.compressionRatio = 1
    else
        local compressionFactor = (self.distance - COMPRESSION_START) / (FADE_END_DISTANCE - COMPRESSION_START)
        self.compressionRatio = math.max(MAX_COMPRESSION_RATIO, 1 - compressionFactor)
    end
end

function ClientSnake:CalculateTransparency()
    if self.distance < FADE_START_DISTANCE then
        self.transparencyMultiplier = 0
    elseif self.distance > FADE_END_DISTANCE then
        self.transparencyMultiplier = MAX_SEGMENT_TRANSPARENCY
    else
        local fadeFactor = (self.distance - FADE_START_DISTANCE) / (FADE_END_DISTANCE - FADE_START_DISTANCE)
        self.transparencyMultiplier = fadeFactor * MAX_SEGMENT_TRANSPARENCY
    end
end

function ClientSnake:UpdateSegmentVisibility()
    local segmentSkip = 1
    
    -- Determine segment skip ratio based on distance
    if self.distance > SEGMENT_SKIP_DISTANCE then
        segmentSkip = math.floor(self.distance / 100)
        segmentSkip = math.min(segmentSkip, FAR_SEGMENT_SKIP_RATIO)
    end
    
    -- Update each segment
    for i, segmentData in ipairs(self.segments) do
        local shouldShow = true
        
        -- Always show head
        if segmentData.index > 0 then
            -- Skip segments based on distance
            if i % segmentSkip ~= 0 and self.distance > SEGMENT_SKIP_DISTANCE then
                shouldShow = false
            end
            
            -- Hide segments beyond max count
            if i > MAX_SEGMENTS_PER_SNAKE then
                shouldShow = false
            end
        end
        
        -- Apply visibility
        if shouldShow then
            self:UpdateSegmentVisuals(segmentData)
        else
            -- Hide segment
            segmentData.part.Transparency = 1
            if segmentData.glow then
                segmentData.glow.Enabled = false
            end
            if segmentData.outline then
                segmentData.outline.Visible = false
            end
            if segmentData.particles then
                segmentData.particles.Enabled = false
            end
        end
    end
    
    -- Update beams
    for _, beamData in ipairs(self.beams) do
        self:UpdateBeamVisuals(beamData)
    end
end

function ClientSnake:UpdateSegmentVisuals(segmentData)
    local part = segmentData.part
    
    -- Calculate target transparency
    local targetTransparency = segmentData.originalTransparency + self.transparencyMultiplier
    targetTransparency = math.min(targetTransparency, MAX_SEGMENT_TRANSPARENCY)
    
    -- Smooth transparency transition
    local currentTransparency = part.Transparency
    part.Transparency = currentTransparency + (targetTransparency - currentTransparency) * TRANSPARENCY_LERP_SPEED
    
    -- Update glow effects
    if segmentData.glow then
        if self.distance > GLOW_FADE_START then
            local glowFade = 1 - ((self.distance - GLOW_FADE_START) / (FADE_END_DISTANCE - GLOW_FADE_START))
            segmentData.glow.Brightness = segmentData.glow.Brightness * math.max(0.1, glowFade)
            segmentData.glow.Enabled = self.distance < PARTICLE_DISABLE_DISTANCE
        end
    end
    
    -- Update outline effects
    if segmentData.outline then
        if self.distance > OUTLINE_FADE_DISTANCE then
            segmentData.outline.Transparency = 0.8 + self.transparencyMultiplier * 0.2
        else
            segmentData.outline.Transparency = 0.3
        end
    end
    
    -- Disable particles at distance
    if segmentData.particles then
        segmentData.particles.Enabled = self.distance < PARTICLE_DISABLE_DISTANCE
    end
    
    -- Size compression for very distant segments (subtle effect)
    if segmentData.index > 0 and self.distance > COMPRESSION_START then
        local targetSize = segmentData.originalSize * (0.8 + 0.2 * self.compressionRatio)
        part.Size = part.Size:Lerp(targetSize, SIZE_LERP_SPEED)
    end
end

function ClientSnake:UpdateBeamVisuals(beamData)
    local beam = beamData.beam
    
    -- Fade beams with distance
    beam.Transparency = NumberSequence.new(math.min(0.9, beamData.originalTransparency + self.transparencyMultiplier))
    
    -- Reduce beam width at distance
    if self.distance > FADE_START_DISTANCE then
        local widthMultiplier = math.max(BEAM_WIDTH_REDUCTION, 1 - self.transparencyMultiplier)
        beam.Width0 = beamData.originalWidth0 * widthMultiplier
        beam.Width1 = beamData.originalWidth1 * widthMultiplier
    else
        beam.Width0 = beamData.originalWidth0
        beam.Width1 = beamData.originalWidth1
    end
    
    -- Disable beam texture scrolling at far distances for performance
    if self.distance > SEGMENT_SKIP_DISTANCE then
        beam.TextureSpeed = 0
    else
        beam.TextureSpeed = 2
    end
end

function ClientSnake:Update()
    local now = tick()
    if now - self.lastUpdate < VISIBILITY_CHECK_INTERVAL then
        return
    end
    self.lastUpdate = now
    
    self:UpdateDistance()
    self:CalculateCompressionRatio()
    self:CalculateTransparency()
    self:UpdateSegmentVisibility()
end

function ClientSnake:Destroy()
    -- Cleanup if needed
end

-- SnakeManager for managing all AI snakes
local SnakeManager = {
    snakes = {},
    updateQueue = {},
    lastFullUpdate = 0
}

function SnakeManager:AddSnake(snakeModel)
    if self.snakes[snakeModel] then return end
    
    local clientSnake = ClientSnake.new(snakeModel)
    self.snakes[snakeModel] = clientSnake
    
    -- Initial update
    clientSnake:Update()
end

function SnakeManager:RemoveSnake(snakeModel)
    local clientSnake = self.snakes[snakeModel]
    if clientSnake then
        clientSnake:Destroy()
        self.snakes[snakeModel] = nil
    end
end

function SnakeManager:GetVisibleSnakes()
    local visibleSnakes = {}
    
    for model, snake in pairs(self.snakes) do
        if model.Parent and snake.distance < FADE_END_DISTANCE * 1.5 then
            table.insert(visibleSnakes, {
                snake = snake,
                distance = snake.distance
            })
        end
    end
    
    -- Sort by distance
    table.sort(visibleSnakes, function(a, b) return a.distance < b.distance end)
    
    -- Limit to max visible
    local result = {}
    for i = 1, math.min(#visibleSnakes, MAX_VISIBLE_SNAKES) do
        table.insert(result, visibleSnakes[i].snake)
    end
    
    return result
end

function SnakeManager:Update()
    local now = tick()
    local deltaTime = now - self.lastFullUpdate
    
    -- Get visible snakes to update
    local visibleSnakes = self:GetVisibleSnakes()
    
    -- Update visible snakes with priority
    for i, snake in ipairs(visibleSnakes) do
        -- Higher priority (closer) snakes update more frequently
        local updateFrequency = i <= 5 and UPDATE_RATE or UPDATE_RATE / 2
        
        if now - snake.lastUpdate >= 1 / updateFrequency then
            snake:Update()
        end
    end
    
    self.lastFullUpdate = now
end

-- Initialize system
local function Initialize()
    -- Track existing AI snakes
    for _, model in ipairs(CollectionService:GetTagged("AISnake")) do
        SnakeManager:AddSnake(model)
    end
    
    -- Listen for new AI snakes
    CollectionService:GetInstanceAddedSignal("AISnake"):Connect(function(model)
        SnakeManager:AddSnake(model)
    end)
    
    -- Listen for removed AI snakes
    CollectionService:GetInstanceRemovedSignal("AISnake"):Connect(function(model)
        SnakeManager:RemoveSnake(model)
    end)
    
    -- Main update loop
    RunService.Heartbeat:Connect(function()
        SnakeManager:Update()
    end)
end

-- Start the system
Initialize()

print("🐍 ClientAISnakeLOD v3.0: Slither.io-style ultra-smooth LOD initialized!")