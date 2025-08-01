-- AISnake LOD System Fix
-- This module contains the corrected LOD implementation

local AISnakeLOD = {}

-- LOD Constants (matching your original)
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

-- Fixed visibility percentages with better falloff
local VISIBILITY_PERCENTAGES = {
    near = 1.0,      -- 100% visible
    mid = 0.85,      -- 85% visible (less aggressive)
    far = 0.6,       -- 60% visible
    minimal = 0.3,   -- 30% visible
    veryFar = 0.15   -- 15% visible
}

-- Calculate segment visibility percentage based on distance
function AISnakeLOD:getVisibilityPercentage(distance)
    if distance < LOD_DISTANCE_NEAR then
        return VISIBILITY_PERCENTAGES.near
    elseif distance < LOD_DISTANCE_MID then
        return VISIBILITY_PERCENTAGES.mid
    elseif distance < LOD_DISTANCE_FAR then
        return VISIBILITY_PERCENTAGES.far
    elseif distance < LOD_DISTANCE_MINIMAL then
        return VISIBILITY_PERCENTAGES.minimal
    else
        return VISIBILITY_PERCENTAGES.veryFar
    end
end

-- Calculate how many segments should be visible
function AISnakeLOD:calculateVisibleSegments(snake, cameraPosition)
    if not cameraPosition or not snake.HeadParts or not snake.HeadParts.head then
        return MIN_VISIBLE_SEGMENTS
    end
    
    local headDistance = (snake.HeadParts.head.Position - cameraPosition).Magnitude
    local visibilityPercent = self:getVisibilityPercentage(headDistance)
    
    -- Calculate base visible segments
    local visibleCount = math.floor(snake.CurrentLength * visibilityPercent)
    
    -- Apply constraints
    visibleCount = math.max(MIN_VISIBLE_SEGMENTS, visibleCount)
    visibleCount = math.min(visibleCount, MAX_VISIBLE_SEGMENTS, DYNAMIC_SEGMENT_LIMIT)
    
    -- Ensure we always show at least the head + some body
    if visibleCount < 15 and snake.CurrentLength >= 15 then
        visibleCount = 15
    end
    
    return visibleCount
end

-- Check if segment should have glow
function AISnakeLOD:shouldHaveGlow(index, lodState)
    -- No glow for culled or far segments
    if lodState == "culled" or lodState == "far" then
        return false
    end
    
    if index <= GLOW_FALLOFF_START then
        return lodState == "near" -- Only near segments get full glow
    elseif index <= 100 then
        return lodState == "near" and index % 2 == 0
    elseif index <= 200 then
        return lodState == "near" and index % 3 == 0
    else
        return false -- No glow for distant segments
    end
end

-- Main visibility update function (FIXED)
function AISnakeLOD:updateSegmentVisibility(snake, cameraPosition)
    if not cameraPosition or not snake.HeadParts or not snake.HeadParts.head then
        return
    end
    
    -- Calculate how many segments should be visible
    local segmentsToShow = self:calculateVisibleSegments(snake, cameraPosition)
    snake.visibleSegmentCount = segmentsToShow
    
    -- Initialize visibility states if needed
    if not snake.segmentVisibility then
        snake.segmentVisibility = {}
    end
    if not snake.lodStates then
        snake.lodStates = {}
    end
    
    -- Update head (always visible)
    if snake.Segments[0] then
        snake.lodStates[0] = "near"
        snake.segmentVisibility[0] = true
        snake.Segments[0].Transparency = 0
        local headGlow = snake.Segments[0]:FindFirstChild("Glow")
        if headGlow then
            headGlow.Enabled = true
            headGlow.Brightness = GLOW_INTENSITY
        end
    end
    
    -- Calculate head distance for overall LOD decisions
    local headDistance = (snake.HeadParts.head.Position - cameraPosition).Magnitude
    
    -- Update each segment's visibility
    for i = 1, snake.CurrentLength do
        local segment = snake.Segments[i]
        
        if i <= segmentsToShow then
            -- This segment should be visible
            if segment and segment.Parent then
                -- Calculate segment-specific distance
                local segmentDistance = (segment.Position - cameraPosition).Magnitude
                
                -- Determine LOD level
                local lodState
                if i <= FORCE_RENDER_SEGMENTS and segmentDistance < LOD_DISTANCE_FAR then
                    lodState = "near" -- Force render segments always near quality when in range
                elseif segmentDistance < LOD_DISTANCE_NEAR then
                    lodState = "near"
                elseif segmentDistance < LOD_DISTANCE_MID then
                    lodState = "mid"
                elseif segmentDistance < LOD_DISTANCE_FAR then
                    lodState = "far"
                else
                    lodState = "minimal"
                end
                
                -- Store LOD state
                snake.lodStates[i] = lodState
                snake.segmentVisibility[i] = true
                
                -- Calculate transparency based on position in snake and distance
                local baseTransparency = 0
                
                -- Distance-based transparency
                if headDistance > 600 then
                    baseTransparency = 0.2
                elseif headDistance > 400 then
                    baseTransparency = 0.1
                end
                
                -- Fade near the end of visible segments
                local fadeStart = segmentsToShow * 0.8
                if i > fadeStart then
                    local fadeProgress = (i - fadeStart) / (segmentsToShow - fadeStart)
                    baseTransparency = math.min(0.8, baseTransparency + fadeProgress * 0.6)
                end
                
                -- Apply transparency
                segment.Transparency = baseTransparency
                
                -- Update collision properties based on LOD
                if lodState == "near" and i <= 50 then
                    segment.CanTouch = true
                    segment.CanQuery = i <= 10
                else
                    segment.CanTouch = false
                    segment.CanQuery = false
                end
                
                -- Update glow
                local glow = segment:FindFirstChild("Glow")
                if glow then
                    if self:shouldHaveGlow(i, lodState) then
                        glow.Enabled = true
                        glow.Brightness = GLOW_INTENSITY * (1 - baseTransparency)
                        glow.Range = GLOW_RANGE_BASE * (1 - i / math.min(200, snake.CurrentLength) * 0.5)
                    else
                        glow.Enabled = false
                    end
                end
            else
                -- Segment doesn't exist yet, mark as not visible
                snake.segmentVisibility[i] = false
                snake.lodStates[i] = "culled"
            end
        else
            -- This segment should be hidden
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
    
    -- Update eyes based on distance
    if snake.HeadParts then
        local eyeVisible = headDistance < 400 -- Closer threshold for eyes
        local eyeTransparency = eyeVisible and 0 or 1
        
        if snake.HeadParts.leftEye then
            snake.HeadParts.leftEye.Transparency = eyeTransparency
        end
        if snake.HeadParts.rightEye then
            snake.HeadParts.rightEye.Transparency = eyeTransparency
        end
        if snake.HeadParts.leftPupil then
            snake.HeadParts.leftPupil.Transparency = eyeTransparency
        end
        if snake.HeadParts.rightPupil then
            snake.HeadParts.rightPupil.Transparency = eyeTransparency
        end
    end
end

-- Sync beam visibility (FIXED to properly match segment visibility)
function AISnakeLOD:syncBeamVisibility(snake)
    if not snake.Beams then return end
    
    -- Update beams based on segment visibility
    for i = 0, math.min(snake.CurrentLength - 1, DYNAMIC_SEGMENT_LIMIT - 1) do
        local beam = snake.Beams[i]
        if beam and beam.Parent then
            -- Check both connected segments
            local seg1Visible = snake.segmentVisibility[i] == true
            local seg2Visible = snake.segmentVisibility[i + 1] == true
            local seg1 = snake.Segments[i]
            local seg2 = snake.Segments[i + 1]
            
            -- Beam should only be visible if both segments are visible and exist
            if seg1Visible and seg2Visible and seg1 and seg2 and seg1.Parent and seg2.Parent then
                -- Check segment transparencies
                local trans1 = seg1.Transparency or 1
                local trans2 = seg2.Transparency or 1
                
                -- Only show beam if segments are reasonably visible
                if trans1 < 0.95 and trans2 < 0.95 then
                    beam.Enabled = true
                    
                    -- Calculate beam transparency based on segment transparencies
                    local avgTrans = (trans1 + trans2) / 2
                    -- Make beams slightly more transparent than segments
                    local beamTrans = math.min(0.9, avgTrans + 0.05)
                    
                    beam.Transparency = NumberSequence.new{
                        NumberSequenceKeypoint.new(0, beamTrans),
                        NumberSequenceKeypoint.new(0.5, beamTrans),
                        NumberSequenceKeypoint.new(1, math.min(0.95, beamTrans + 0.05))
                    }
                    
                    -- Adjust brightness based on visibility
                    beam.Brightness = math.max(0.5, 2 * (1 - avgTrans))
                else
                    beam.Enabled = false
                end
            else
                beam.Enabled = false
            end
        end
    end
end

-- Apply LOD to a single segment (cleaner implementation)
function AISnakeLOD:applyLODToSegment(segment, lodState, index, visibility)
    if not segment or not segment.Parent then return end
    
    -- Apply visibility
    if visibility then
        -- Segment is visible at some LOD level
        if lodState == "culled" then
            segment.Transparency = 1
            segment.CanTouch = false
            segment.CanQuery = false
        else
            -- Collision only for near segments in first 50
            segment.CanTouch = (lodState == "near" and index <= 50)
            segment.CanQuery = (lodState == "near" and index <= 10)
        end
    else
        -- Segment is not visible
        segment.Transparency = 1
        segment.CanTouch = false
        segment.CanQuery = false
    end
end

-- Helper to ensure segments are created when needed
function AISnakeLOD:ensureSegmentExists(snake, index)
    -- Don't create beyond limits
    if index > DYNAMIC_SEGMENT_LIMIT or index > snake.CurrentLength then
        return nil
    end
    
    local segment = snake.Segments[index]
    if segment and segment.Parent then
        return segment
    end
    
    -- Segment creation would happen here in the main snake code
    -- This is just a placeholder
    return nil
end

return AISnakeLOD