-- AISnake LOD Debugger
-- Visual debugging tool to help diagnose LOD issues

local AISnakeLODDebugger = {}

-- Create debug UI for a snake
function AISnakeLODDebugger:createDebugUI(snake)
    if not snake.HeadParts or not snake.HeadParts.head then return end
    
    -- Create debug billboard
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "LODDebugUI"
    billboardGui.Size = UDim2.new(0, 200, 0, 150)
    billboardGui.StudsOffset = Vector3.new(0, 10, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = snake.HeadParts.head
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = billboardGui
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "DebugInfo"
    textLabel.Size = UDim2.new(1, -10, 1, -10)
    textLabel.Position = UDim2.new(0, 5, 0, 5)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextScaled = false
    textLabel.TextSize = 12
    textLabel.Font = Enum.Font.Code
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Top
    textLabel.Parent = frame
    
    snake._debugUI = billboardGui
    snake._debugLabel = textLabel
end

-- Update debug display
function AISnakeLODDebugger:updateDebugDisplay(snake)
    if not snake._debugLabel then return end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local cameraPos = camera.CFrame.Position
    local headDistance = (snake.HeadParts.head.Position - cameraPos).Magnitude
    
    -- Count visible segments
    local visibleCount = 0
    local nearCount = 0
    local midCount = 0
    local farCount = 0
    local culledCount = 0
    
    for i = 0, snake.CurrentLength do
        if snake.segmentVisibility[i] then
            visibleCount = visibleCount + 1
        end
        
        local lodState = snake.lodStates[i]
        if lodState == "near" then
            nearCount = nearCount + 1
        elseif lodState == "mid" then
            midCount = midCount + 1
        elseif lodState == "far" then
            farCount = farCount + 1
        elseif lodState == "culled" then
            culledCount = culledCount + 1
        end
    end
    
    -- Count visible beams
    local visibleBeams = 0
    local totalBeams = 0
    
    if snake.Beams then
        for i = 0, snake.CurrentLength - 1 do
            local beam = snake.Beams[i]
            if beam then
                totalBeams = totalBeams + 1
                if beam.Enabled then
                    visibleBeams = visibleBeams + 1
                end
            end
        end
    end
    
    -- Build debug text
    local debugText = string.format(
        "Length: %d\n" ..
        "Head Dist: %d\n" ..
        "Visible: %d/%d (%.1f%%)\n" ..
        "LOD: N:%d M:%d F:%d C:%d\n" ..
        "Beams: %d/%d\n" ..
        "Target Vis: %d",
        snake.CurrentLength,
        math.floor(headDistance),
        visibleCount,
        snake.CurrentLength,
        (visibleCount / snake.CurrentLength) * 100,
        nearCount,
        midCount,
        farCount,
        culledCount,
        visibleBeams,
        totalBeams,
        snake.visibleSegmentCount or 0
    )
    
    snake._debugLabel.Text = debugText
    
    -- Color code based on performance
    if culledCount > snake.CurrentLength * 0.8 then
        snake._debugLabel.TextColor3 = Color3.new(0, 1, 0) -- Green - good culling
    elseif culledCount > snake.CurrentLength * 0.5 then
        snake._debugLabel.TextColor3 = Color3.new(1, 1, 0) -- Yellow - moderate
    else
        snake._debugLabel.TextColor3 = Color3.new(1, 0.5, 0) -- Orange - low culling
    end
end

-- Visualize LOD states on segments
function AISnakeLODDebugger:visualizeLODStates(snake)
    for i = 0, math.min(snake.CurrentLength, 200) do -- Limit to first 200 for performance
        local segment = snake.Segments[i]
        if segment and segment.Parent then
            local lodState = snake.lodStates[i]
            
            -- Create or update debug sphere
            local debugSphere = segment:FindFirstChild("LODDebugSphere")
            if not debugSphere then
                debugSphere = Instance.new("SphereHandleAdornment")
                debugSphere.Name = "LODDebugSphere"
                debugSphere.Adornee = segment
                debugSphere.AlwaysOnTop = true
                debugSphere.ZIndex = 1
                debugSphere.Radius = segment.Size.X * 0.3
                debugSphere.Parent = segment
            end
            
            -- Color based on LOD state
            if lodState == "near" then
                debugSphere.Color3 = Color3.new(0, 1, 0) -- Green
                debugSphere.Transparency = 0.7
            elseif lodState == "mid" then
                debugSphere.Color3 = Color3.new(1, 1, 0) -- Yellow
                debugSphere.Transparency = 0.8
            elseif lodState == "far" then
                debugSphere.Color3 = Color3.new(1, 0.5, 0) -- Orange
                debugSphere.Transparency = 0.9
            elseif lodState == "culled" then
                debugSphere.Color3 = Color3.new(1, 0, 0) -- Red
                debugSphere.Transparency = 0.95
            end
            
            -- Hide debug sphere if segment is culled
            debugSphere.Visible = snake.segmentVisibility[i] ~= false
        end
    end
end

-- Check for LOD issues
function AISnakeLODDebugger:checkForIssues(snake)
    local issues = {}
    
    -- Check for beam/segment mismatch
    for i = 0, math.min(snake.CurrentLength - 1, 200) do
        local beam = snake.Beams and snake.Beams[i]
        local seg1 = snake.Segments[i]
        local seg2 = snake.Segments[i + 1]
        
        if beam and beam.Parent and beam.Enabled then
            -- Check if beam is visible but segments are not
            if (seg1 and seg1.Transparency >= 1) or (seg2 and seg2.Transparency >= 1) then
                table.insert(issues, {
                    type = "BEAM_SEGMENT_MISMATCH",
                    index = i,
                    message = string.format("Beam %d visible but connected segments are invisible", i)
                })
            end
            
            -- Check visibility state mismatch
            if snake.segmentVisibility[i] == false or snake.segmentVisibility[i + 1] == false then
                table.insert(issues, {
                    type = "VISIBILITY_STATE_MISMATCH",
                    index = i,
                    message = string.format("Beam %d visible but visibility state is false", i)
                })
            end
        end
    end
    
    -- Check for transparency issues
    for i = 0, math.min(snake.CurrentLength, 200) do
        local segment = snake.Segments[i]
        if segment and segment.Parent then
            local lodState = snake.lodStates[i]
            local visibility = snake.segmentVisibility[i]
            
            -- Check if culled but still visible
            if lodState == "culled" and segment.Transparency < 1 then
                table.insert(issues, {
                    type = "CULLED_BUT_VISIBLE",
                    index = i,
                    message = string.format("Segment %d is culled but transparency is %.2f", i, segment.Transparency)
                })
            end
            
            -- Check if visible but fully transparent
            if visibility and segment.Transparency >= 1 then
                table.insert(issues, {
                    type = "VISIBLE_BUT_TRANSPARENT",
                    index = i,
                    message = string.format("Segment %d marked visible but fully transparent", i)
                })
            end
        end
    end
    
    return issues
end

-- Enable debug mode for a snake
function AISnakeLODDebugger:enableDebug(snake)
    self:createDebugUI(snake)
    
    -- Create debug connection
    snake._debugConnection = game:GetService("RunService").Heartbeat:Connect(function()
        self:updateDebugDisplay(snake)
        
        -- Check for issues every 60 frames
        if not snake._debugIssueFrame then
            snake._debugIssueFrame = 0
        end
        snake._debugIssueFrame = snake._debugIssueFrame + 1
        
        if snake._debugIssueFrame >= 60 then
            snake._debugIssueFrame = 0
            local issues = self:checkForIssues(snake)
            if #issues > 0 then
                warn("LOD Issues detected for snake:")
                for _, issue in ipairs(issues) do
                    warn(" -", issue.message)
                end
            end
        end
    end)
end

-- Disable debug mode
function AISnakeLODDebugger:disableDebug(snake)
    if snake._debugUI then
        snake._debugUI:Destroy()
        snake._debugUI = nil
    end
    
    if snake._debugConnection then
        snake._debugConnection:Disconnect()
        snake._debugConnection = nil
    end
    
    -- Remove debug spheres
    for i = 0, snake.CurrentLength do
        local segment = snake.Segments[i]
        if segment and segment.Parent then
            local debugSphere = segment:FindFirstChild("LODDebugSphere")
            if debugSphere then
                debugSphere:Destroy()
            end
        end
    end
end

return AISnakeLODDebugger