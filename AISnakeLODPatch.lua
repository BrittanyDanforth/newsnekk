-- AISnake LOD Patch Instructions
-- This file shows exactly what to replace in your AISnake module

--[[
INSTRUCTIONS TO FIX LOD IN AISnake:

1. Find and REPLACE the updateSegmentVisibility function (around line 2500+)
2. Find and REPLACE the syncBeamVisibility function (around line 2600+)

The main issues fixed:
- Beam visibility now properly checks segmentVisibility states
- Transparency is calculated once in updateSegmentVisibility
- Beams are hidden when either connected segment is culled
- Smooth fade transitions at the tail
- Proper eye culling based on distance
]]

-- REPLACE THIS FUNCTION in AISnake:
function AISnake:updateSegmentVisibility(cameraPosition)
    if not cameraPosition or not self.HeadParts or not self.HeadParts.head then return end
    
    -- Calculate distance from camera to snake head
    local headDistance = (self.HeadParts.head.Position - cameraPosition).Magnitude
    
    -- Determine visibility range based on distance (FIXED percentages)
    local visibilityRange
    if headDistance < LOD_DISTANCE_NEAR then
        visibilityRange = 1.0  -- 100% visible
    elseif headDistance < LOD_DISTANCE_MID then
        visibilityRange = 0.85  -- 85% visible (was 0.8)
    elseif headDistance < LOD_DISTANCE_FAR then
        visibilityRange = 0.6   -- 60% visible (was 0.5)
    elseif headDistance < LOD_DISTANCE_MINIMAL then
        visibilityRange = 0.3   -- 30% visible
    else
        visibilityRange = 0.15  -- 15% visible
    end
    
    -- Calculate segments to show
    local segmentsToShow = math.max(
        MIN_VISIBLE_SEGMENTS,
        math.min(
            math.floor(self.CurrentLength * visibilityRange),
            DYNAMIC_SEGMENT_LIMIT,
            MAX_VISIBLE_SEGMENTS
        )
    )
    
    -- Always ensure head is visible
    if self.Segments[0] then
        self.segmentVisibility[0] = true
        self.lodStates[0] = "near"
        self.Segments[0].Transparency = 0
        self.Segments[0].CanTouch = true
        self.Segments[0].CanQuery = true
    end
    
    -- Update eye visibility (MORE AGGRESSIVE CULLING)
    if self.HeadParts then
        local eyeVisible = headDistance < 400  -- Was 600
        local eyeTrans = eyeVisible and 0 or 1
        
        if self.HeadParts.leftEye then
            self.HeadParts.leftEye.Transparency = eyeTrans
        end
        if self.HeadParts.rightEye then
            self.HeadParts.rightEye.Transparency = eyeTrans
        end
        if self.HeadParts.leftPupil then
            self.HeadParts.leftPupil.Transparency = eyeTrans
        end
        if self.HeadParts.rightPupil then
            self.HeadParts.rightPupil.Transparency = eyeTrans
        end
    end
    
    -- Update segment visibility and LOD states
    for i = 1, math.min(self.CurrentLength, DYNAMIC_SEGMENT_LIMIT) do
        local segment = self.Segments[i]
        
        if i <= segmentsToShow then
            -- Segment should be visible
            self.segmentVisibility[i] = true
            
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
                
                self.lodStates[i] = lodLevel
                
                -- Calculate base transparency
                local baseTransparency = 0
                if lodLevel == "mid" then
                    baseTransparency = 0.1
                elseif lodLevel == "far" then
                    baseTransparency = 0.2
                elseif lodLevel == "minimal" then
                    baseTransparency = 0.3
                end
                
                -- Apply fade at the tail (SMOOTHER FADE)
                local fadeStart = segmentsToShow * 0.7  -- Was 0.7
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
                
                -- Update glow (FIXED GLOW LOGIC)
                local glow = segment:FindFirstChild("Glow")
                if glow then
                    if lodLevel ~= "minimal" and self:shouldHaveGlow(i) then
                        glow.Enabled = true
                        local glowScale = math.max(0, 1 - (segmentDistance / LOD_DISTANCE_FAR))
                        glow.Brightness = GLOW_INTENSITY * glowScale * (1 - segment.Transparency)
                        glow.Range = GLOW_RANGE_BASE * glowScale * 0.8
                    else
                        glow.Enabled = false
                    end
                end
            end
        else
            -- Segment should be hidden
            self.segmentVisibility[i] = false
            self.lodStates[i] = "culled"
            
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
    self.visibleSegmentCount = segmentsToShow
end

-- REPLACE THIS FUNCTION in AISnake:
function AISnake:syncBeamVisibility()
    if not self.Beams then return end
    
    -- Update beams based on segment visibility (FIXED LOGIC)
    for i = 0, math.min(self.CurrentLength - 1, DYNAMIC_SEGMENT_LIMIT - 1) do
        local beam = self.Beams[i]
        if beam and beam.Parent then
            -- CHECK VISIBILITY STATES PROPERLY
            local seg1Visible = self.segmentVisibility[i] ~= false
            local seg2Visible = self.segmentVisibility[i + 1] ~= false
            
            -- Only show beam if BOTH segments are visible
            if seg1Visible and seg2Visible then
                local seg1 = self.Segments[i]
                local seg2 = self.Segments[i + 1]
                
                if seg1 and seg2 and seg1.Parent and seg2.Parent then
                    local trans1 = seg1.Transparency or 0
                    local trans2 = seg2.Transparency or 0
                    
                    -- Only show beam if segments aren't too transparent
                    if trans1 < 0.95 and trans2 < 0.95 then
                        beam.Enabled = true
                        
                        -- Smooth transparency for beams
                        local avgTrans = (trans1 + trans2) / 2
                        local beamTrans = math.min(0.9, avgTrans * 1.2)  -- Slightly more transparent
                        
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
                -- CRITICAL FIX: Hide beam if either segment is not visible
                beam.Enabled = false
            end
        end
    end
end