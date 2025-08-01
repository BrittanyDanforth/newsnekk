-- AISnake LOD Fix Module
-- This module provides a corrected LOD implementation that properly syncs segments and beams

local AISnakeLODFix = {}

-- LOD Constants (matching AISnake)
local VISIBILITY_CHECK_INTERVAL = 5
local RENDER_DISTANCE = 1000
local LOD_DISTANCE_NEAR = 200
local LOD_DISTANCE_MID = 400
local LOD_DISTANCE_FAR = 600
local LOD_DISTANCE_MINIMAL = 800
local BEAM_SYNC_INTERVAL = 3
local FORCE_RENDER_SEGMENTS = 150
local MIN_VISIBLE_SEGMENTS = 10
local MAX_VISIBLE_SEGMENTS = 2000
local DYNAMIC_SEGMENT_LIMIT = 800
local GLOW_INTENSITY = 2
local GLOW_RANGE_BASE = 15
local GLOW_FALLOFF_START = 50

-- Fixed visibility calculation
function AISnakeLODFix:updateSegmentVisibility(snake, cameraPosition)
    if not cameraPosition or not snake.HeadParts or not snake.HeadParts.head then return end
    
    -- Calculate distance from camera to snake head
    local headDistance = (snake.HeadParts.head.Position - cameraPosition).Magnitude
    
    -- Determine visibility range based on distance
    local visibilityRange
    if headDistance < LOD_DISTANCE_NEAR then
        visibilityRange = 1.0  -- 100% visible
    elseif headDistance < LOD_DISTANCE_MID then
        visibilityRange = 0.85  -- 85% visible
    elseif headDistance < LOD_DISTANCE_FAR then
        visibilityRange = 0.6   -- 60% visible
    elseif headDistance < LOD_DISTANCE_MINIMAL then
        visibilityRange = 0.3   -- 30% visible
    else
        visibilityRange = 0.15  -- 15% visible (at least head + some body)
    end
    
    -- Calculate segments to show
    local segmentsToShow = math.max(
        MIN_VISIBLE_SEGMENTS,
        math.min(
            math.floor(snake.CurrentLength * visibilityRange),
            DYNAMIC_SEGMENT_LIMIT,
            MAX_VISIBLE_SEGMENTS
        )
    )
    
    -- Always ensure head is visible
    if snake.Segments[0] then
        snake.segmentVisibility[0] = true
        snake.lodStates[0] = "near"
        snake.Segments[0].Transparency = 0
        snake.Segments[0].CanTouch = true
        snake.Segments[0].CanQuery = true
    end
    
    -- Update eye visibility
    if snake.HeadParts then
        local eyeVisible = headDistance < 400  -- More aggressive eye culling
        local eyeTrans = eyeVisible and 0 or 1
        
        if snake.HeadParts.leftEye then
            snake.HeadParts.leftEye.Transparency = eyeTrans
        end
        if snake.HeadParts.rightEye then
            snake.HeadParts.rightEye.Transparency = eyeTrans
        end
        if snake.HeadParts.leftPupil then
            snake.HeadParts.leftPupil.Transparency = eyeTrans
        end
        if snake.HeadParts.rightPupil then
            snake.HeadParts.rightPupil.Transparency = eyeTrans
        end
    end
    
    -- Update segment visibility and LOD states
    for i = 1, math.min(snake.CurrentLength, DYNAMIC_SEGMENT_LIMIT) do
        local segment = snake.Segments[i]
        
        if i <= segmentsToShow then
            -- Segment should be visible
            snake.segmentVisibility[i] = true
            
            if segment and segment.Parent then
                local segmentDistance = (segment.Position - cameraPosition).Magnitude
                
                -- Determine LOD level
                local lodLevel
                if i <= FORCE_RENDER_SEGMENTS and segmentDistance < LOD_DISTANCE_MID then
                    lodLevel = "near"
                elseif segmentDistance < LOD_DISTANCE_NEAR then
                    lodLevel = "near"
                elseif segmentDistance < LOD_DISTANCE_MID then
                    lodLevel = "mid"
                elseif segmentDistance < LOD_DISTANCE_FAR then
                    lodLevel = "far"
                else
                    lodLevel = "minimal"
                end
                
                snake.lodStates[i] = lodLevel
                
                -- Calculate base transparency
                local baseTransparency = 0
                if lodLevel == "mid" then
                    baseTransparency = 0.1
                elseif lodLevel == "far" then
                    baseTransparency = 0.2
                elseif lodLevel == "minimal" then
                    baseTransparency = 0.3
                end
                
                -- Apply fade at the tail
                local fadeStart = segmentsToShow * 0.7
                if i > fadeStart then
                    local fadeProgress = (i - fadeStart) / (segmentsToShow - fadeStart)
                    -- Smooth fade curve
                    fadeProgress = fadeProgress * fadeProgress
                    segment.Transparency = math.min(0.8, baseTransparency + fadeProgress * 0.5)
                else
                    segment.Transparency = baseTransparency
                end
                
                -- Update collision based on LOD and position
                if lodLevel == "near" and i <= 50 then
                    segment.CanTouch = true
                    segment.CanQuery = i <= 10
                else
                    segment.CanTouch = false
                    segment.CanQuery = false
                end
                
                -- Update glow
                local glow = segment:FindFirstChild("Glow")
                if glow then
                    if lodLevel ~= "minimal" and self:shouldHaveGlow(snake, i) then
                        glow.Enabled = true
                        local glowScale = 1 - (segmentDistance / LOD_DISTANCE_FAR)
                        glowScale = math.max(0, glowScale)
                        glow.Brightness = GLOW_INTENSITY * glowScale * (1 - segment.Transparency)
                        glow.Range = GLOW_RANGE_BASE * glowScale * 0.8
                    else
                        glow.Enabled = false
                    end
                end
            end
        else
            -- Segment should be hidden
            snake.segmentVisibility[i] = false
            snake.lodStates[i] = "culled"
            
            if segment and segment.Parent then
                segment.Transparency = 1
                segment.CanTouch = false
                segment.CanQuery = false
                
                local glow = segment:FindFirstChild("Glow")
                if glow then
                    glow.Enabled = false
                end
            end
        end
    end
    
    -- Update visible segment count
    snake.visibleSegmentCount = segmentsToShow
end

-- Fixed beam visibility sync
function AISnakeLODFix:syncBeamVisibility(snake)
    if not snake.Beams then return end
    
    -- Update beams based on segment visibility
    for i = 0, math.min(snake.CurrentLength - 1, DYNAMIC_SEGMENT_LIMIT - 1) do
        local beam = snake.Beams[i]
        if beam and beam.Parent then
            local seg1Visible = snake.segmentVisibility[i] ~= false
            local seg2Visible = snake.segmentVisibility[i + 1] ~= false
            
            -- Only show beam if BOTH segments are visible
            if seg1Visible and seg2Visible then
                local seg1 = snake.Segments[i]
                local seg2 = snake.Segments[i + 1]
                
                if seg1 and seg2 and seg1.Parent and seg2.Parent then
                    local trans1 = seg1.Transparency or 0
                    local trans2 = seg2.Transparency or 0
                    
                    -- Only show beam if segments aren't too transparent
                    if trans1 < 0.95 and trans2 < 0.95 then
                        beam.Enabled = true
                        
                        -- Smooth transparency for beams
                        local avgTrans = (trans1 + trans2) / 2
                        local beamTrans = math.min(0.9, avgTrans * 1.2)  -- Slightly more transparent than segments
                        
                        -- Create smooth transparency sequence
                        beam.Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, beamTrans),
                            NumberSequenceKeypoint.new(0.5, beamTrans),
                            NumberSequenceKeypoint.new(1, math.min(beamTrans + 0.1, 0.95))
                        })
                        
                        -- Adjust brightness based on visibility
                        beam.Brightness = math.max(0.3, 2 * (1 - avgTrans))
                    else
                        beam.Enabled = false
                    end
                else
                    beam.Enabled = false
                end
            else
                -- Hide beam if either segment is not visible
                beam.Enabled = false
            end
        end
    end
end

-- Helper function to determine glow
function AISnakeLODFix:shouldHaveGlow(snake, index)
    if index <= GLOW_FALLOFF_START then
        return true
    elseif index <= 100 then
        return index % 2 == 0
    elseif index <= 200 then
        return index % 3 == 0
    else
        return index % 5 == 0
    end
end

-- Apply LOD state to a segment (cleaner version)
function AISnakeLODFix:applyLODToSegment(snake, segment, lodLevel, index)
    if not segment or not segment.Parent then return end
    
    snake.lodStates[index] = lodLevel
    
    if lodLevel == "culled" then
        -- Completely hide culled segments
        segment.Transparency = 1
        segment.CanTouch = false
        segment.CanQuery = false
        snake.segmentVisibility[index] = false
        
        -- Disable glow
        local glow = segment:FindFirstChild("Glow")
        if glow then
            glow.Enabled = false
        end
    else
        -- Segment is visible at some LOD level
        snake.segmentVisibility[index] = true
        
        -- Note: Actual transparency is set by updateSegmentVisibility
        -- This just sets the collision properties
        if lodLevel == "near" and index <= 50 then
            segment.CanTouch = true
            segment.CanQuery = index <= 10
        else
            segment.CanTouch = false
            segment.CanQuery = false
        end
    end
end

return AISnakeLODFix