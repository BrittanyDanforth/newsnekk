-- Test Module for AISnake LOD Fix
-- This module helps verify that the LOD system is working correctly

local TestAISnakeLOD = {}

-- Test function to verify segment and beam visibility sync
function TestAISnakeLOD:runVisibilityTest(aiSnake)
    print("\n=== AISnake LOD Test Results ===")
    
    if not aiSnake or not aiSnake._active then
        print("❌ No active AI snake to test")
        return false
    end
    
    local issues = {}
    local successes = {}
    
    -- Test 1: Check visibility state consistency
    print("\n📋 Test 1: Visibility State Consistency")
    local visibleCount = 0
    local culledCount = 0
    
    for i = 0, aiSnake.CurrentLength do
        if aiSnake.segmentVisibility[i] then
            visibleCount = visibleCount + 1
        else
            culledCount = culledCount + 1
        end
    end
    
    print(string.format("   Visible segments: %d", visibleCount))
    print(string.format("   Culled segments: %d", culledCount))
    print(string.format("   Total segments: %d", aiSnake.CurrentLength))
    
    if visibleCount + culledCount ~= aiSnake.CurrentLength + 1 then -- +1 for head (segment 0)
        table.insert(issues, "Visibility count mismatch")
    else
        table.insert(successes, "Visibility counts match")
    end
    
    -- Test 2: Check beam-segment sync
    print("\n📋 Test 2: Beam-Segment Synchronization")
    local beamIssues = 0
    
    for i = 0, math.min(aiSnake.CurrentLength - 1, 800) do
        local beam = aiSnake.Beams and aiSnake.Beams[i]
        if beam and beam.Parent then
            local seg1Visible = aiSnake.segmentVisibility[i] ~= false
            local seg2Visible = aiSnake.segmentVisibility[i + 1] ~= false
            local beamEnabled = beam.Enabled
            
            -- Beam should only be enabled if both segments are visible
            local shouldBeEnabled = seg1Visible and seg2Visible
            
            if beamEnabled ~= shouldBeEnabled then
                beamIssues = beamIssues + 1
                if beamIssues <= 5 then -- Only report first 5 issues
                    print(string.format("   ❌ Beam %d mismatch: enabled=%s, seg1=%s, seg2=%s", 
                        i, tostring(beamEnabled), tostring(seg1Visible), tostring(seg2Visible)))
                end
            end
        end
    end
    
    if beamIssues == 0 then
        table.insert(successes, "All beams correctly synced with segments")
        print("   ✅ All beams correctly synced!")
    else
        table.insert(issues, string.format("%d beams not synced properly", beamIssues))
        print(string.format("   ❌ Found %d beam sync issues", beamIssues))
    end
    
    -- Test 3: Check transparency consistency
    print("\n📋 Test 3: Transparency Consistency")
    local transparencyIssues = 0
    
    for i = 1, math.min(aiSnake.CurrentLength, 800) do
        local segment = aiSnake.Segments[i]
        if segment and segment.Parent then
            local isVisible = aiSnake.segmentVisibility[i]
            local transparency = segment.Transparency
            
            if isVisible and transparency >= 1 then
                transparencyIssues = transparencyIssues + 1
                if transparencyIssues <= 3 then
                    print(string.format("   ❌ Segment %d marked visible but fully transparent", i))
                end
            elseif not isVisible and transparency < 1 then
                transparencyIssues = transparencyIssues + 1
                if transparencyIssues <= 3 then
                    print(string.format("   ❌ Segment %d marked hidden but transparency=%f", i, transparency))
                end
            end
        end
    end
    
    if transparencyIssues == 0 then
        table.insert(successes, "Transparency values match visibility states")
        print("   ✅ All transparency values correct!")
    else
        table.insert(issues, string.format("%d transparency inconsistencies", transparencyIssues))
        print(string.format("   ❌ Found %d transparency issues", transparencyIssues))
    end
    
    -- Test 4: Check LOD distance logic
    print("\n📋 Test 4: LOD Distance Logic")
    local camera = workspace.CurrentCamera
    if camera then
        local cameraPos = camera.CFrame.Position
        local headDistance = (aiSnake.HeadParts.head.Position - cameraPos).Magnitude
        
        print(string.format("   Camera distance to head: %.1f studs", headDistance))
        print(string.format("   Visible segment count: %d", aiSnake.visibleSegmentCount or 0))
        
        -- Check if visible count makes sense for distance
        local expectedRange
        if headDistance < 200 then
            expectedRange = {0.9, 1.0}
        elseif headDistance < 400 then
            expectedRange = {0.7, 0.9}
        elseif headDistance < 600 then
            expectedRange = {0.5, 0.7}
        else
            expectedRange = {0.1, 0.5}
        end
        
        local visibleRatio = (aiSnake.visibleSegmentCount or 0) / aiSnake.CurrentLength
        if visibleRatio >= expectedRange[1] and visibleRatio <= expectedRange[2] then
            table.insert(successes, "LOD distance scaling is correct")
            print(string.format("   ✅ Visible ratio %.2f is within expected range", visibleRatio))
        else
            table.insert(issues, string.format("Visible ratio %.2f outside expected range [%.2f, %.2f]", 
                visibleRatio, expectedRange[1], expectedRange[2]))
            print(string.format("   ❌ Visible ratio %.2f outside expected range", visibleRatio))
        end
    end
    
    -- Summary
    print("\n📊 Test Summary:")
    print(string.format("   ✅ Passed: %d tests", #successes))
    print(string.format("   ❌ Failed: %d tests", #issues))
    
    if #issues == 0 then
        print("\n🎉 All LOD tests passed! The fix is working correctly.")
        return true
    else
        print("\n⚠️  Some LOD issues detected:")
        for _, issue in ipairs(issues) do
            print("   - " .. issue)
        end
        return false
    end
end

-- Visual debug overlay
function TestAISnakeLOD:createDebugOverlay(aiSnake)
    if not aiSnake or not aiSnake.HeadParts or not aiSnake.HeadParts.head then
        return
    end
    
    -- Create or update debug billboard
    local debugGui = aiSnake.HeadParts.head:FindFirstChild("LODDebugGUI") or Instance.new("BillboardGui")
    debugGui.Name = "LODDebugGUI"
    debugGui.Size = UDim2.new(0, 300, 0, 200)
    debugGui.StudsOffset = Vector3.new(0, 15, 0)
    debugGui.AlwaysOnTop = true
    debugGui.Parent = aiSnake.HeadParts.head
    
    local frame = debugGui:FindFirstChild("Frame") or Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.new(0, 1, 0)
    frame.Parent = debugGui
    
    local textLabel = frame:FindFirstChild("TextLabel") or Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -10, 1, -10)
    textLabel.Position = UDim2.new(0, 5, 0, 5)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Top
    textLabel.Parent = frame
    
    -- Update function
    local function updateDebug()
        if not aiSnake._active then
            debugGui:Destroy()
            return
        end
        
        local visibleSegs = 0
        local culledSegs = 0
        local beamsEnabled = 0
        
        for i = 0, aiSnake.CurrentLength do
            if aiSnake.segmentVisibility[i] then
                visibleSegs = visibleSegs + 1
            else
                culledSegs = culledSegs + 1
            end
        end
        
        for i = 0, math.min(aiSnake.CurrentLength - 1, 800) do
            local beam = aiSnake.Beams and aiSnake.Beams[i]
            if beam and beam.Parent and beam.Enabled then
                beamsEnabled = beamsEnabled + 1
            end
        end
        
        local camera = workspace.CurrentCamera
        local headDist = camera and (aiSnake.HeadParts.head.Position - camera.CFrame.Position).Magnitude or 0
        
        textLabel.Text = string.format(
            "LOD DEBUG\n" ..
            "Length: %d\n" ..
            "Visible: %d (%.0f%%)\n" ..
            "Culled: %d\n" ..
            "Beams: %d\n" ..
            "Head Dist: %.0f\n" ..
            "Visible Count: %d",
            aiSnake.CurrentLength,
            visibleSegs,
            (visibleSegs / (aiSnake.CurrentLength + 1)) * 100,
            culledSegs,
            beamsEnabled,
            headDist,
            aiSnake.visibleSegmentCount or 0
        )
    end
    
    -- Update loop
    spawn(function()
        while aiSnake._active and debugGui.Parent do
            updateDebug()
            wait(0.5)
        end
    end)
    
    return debugGui
end

-- Command to run test on all AI snakes
function TestAISnakeLOD:testAll()
    local AISnake = require(script.Parent:WaitForChild("AISnake"))
    
    print("\n🧪 Testing LOD on all active AI Snakes...")
    
    local testedCount = 0
    local passedCount = 0
    
    for _, snake in ipairs(AISnake._activeSnakes) do
        if snake._active then
            testedCount = testedCount + 1
            print(string.format("\n🐍 Testing snake %d (Length: %d)", testedCount, snake.CurrentLength))
            
            if self:runVisibilityTest(snake) then
                passedCount = passedCount + 1
            end
            
            -- Add debug overlay to first snake
            if testedCount == 1 then
                self:createDebugOverlay(snake)
            end
        end
    end
    
    print(string.format("\n\n🏁 FINAL RESULTS: %d/%d snakes passed all tests", passedCount, testedCount))
    
    if passedCount == testedCount and testedCount > 0 then
        print("✅ LOD system is working perfectly!")
    else
        print("⚠️  Some snakes have LOD issues that need fixing")
    end
end

return TestAISnakeLOD