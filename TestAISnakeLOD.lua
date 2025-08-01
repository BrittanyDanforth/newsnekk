-- Test script to verify AISnake LOD is working
-- This can be run in ServerScriptService to check the LOD behavior

local AISnake = require(script.Parent.AISnake)

-- Create a test snake
local testSnake = AISnake.new({
    SkinIndex = 1,
    StartPosition = Vector3.new(0, 10, 0),
    InitialVelocity = Vector3.new(10, 0, 0),
    InitialLength = 50,
    PlayerName = "TestSnake",
    PersonalityType = "Explorer"
})

-- Monitor the snake's LOD behavior
local RunService = game:GetService("RunService")

local lastReport = 0
RunService.Heartbeat:Connect(function()
    local now = tick()
    
    -- Report every 5 seconds
    if now - lastReport > 5 then
        lastReport = now
        
        print("=== AISnake LOD Report ===")
        print("Current Length:", testSnake.CurrentLength)
        print("Visible Segments:", testSnake.visibleSegmentCount)
        print("Actual Segments Created:", testSnake.actualSegmentCount)
        
        -- Check beam visibility
        local enabledBeams = 0
        for i, beam in ipairs(testSnake.Beams) do
            if beam and beam.Parent and beam.Enabled then
                enabledBeams = enabledBeams + 1
            end
        end
        print("Enabled Beams:", enabledBeams)
        
        -- Check segment visibility
        local visibleSegments = 0
        for i, segment in ipairs(testSnake.Segments) do
            if segment and segment.Parent and segment.Transparency < 1 then
                visibleSegments = visibleSegments + 1
            end
        end
        print("Visible Segments (Transparency < 1):", visibleSegments)
        print("========================")
    end
end)

-- Keep the snake alive and moving
spawn(function()
    while testSnake.Alive do
        wait(0.1)
        -- The snake's AI should handle movement automatically
    end
    print("Test snake died")
end)

print("AISnake LOD test started - monitoring snake behavior...")