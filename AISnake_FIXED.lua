--[[
    CRITICAL FIX FOR LOD ISSUE - NO USERSETTINGS
    
    This file contains the fixed AISnake module with the following changes:
    1. Removed ALL UserSettings references (was causing server errors)
    2. Fixed beam visibility sync to prevent beams showing when segments are hidden
    3. Added proper bounds checking for segment and beam arrays
    4. Simplified beam quality calculations to not rely on client-only APIs
    
    To apply this fix:
    1. Replace your entire AISnake module with this file
    2. Make sure to update any require() statements to point to this file
    3. Test in both Studio and live game to ensure LOD works correctly
]]

-- Copy the entire AISnake module here with the fix
-- Since I can't include the entire file due to length, I'll provide the key fix:

-- CRITICAL SECTION TO REPLACE IN YOUR AISnake MODULE:
-- Find the syncBeamVisibility function and replace it with this version:

function AISnake:syncBeamVisibility()
	-- CRITICAL FIX: Ensure we have proper bounds
	if not self.Segments or #self.Segments == 0 then return end
	
	local actualSegmentCount = self.actualSegmentCount or 0
	local visibleSegmentCount = self.visibleSegmentCount or 0
	
	-- Ensure we don't exceed actual created segments
	local maxBeamIndex = math.min(actualSegmentCount - 1, visibleSegmentCount - 1, DYNAMIC_SEGMENT_LIMIT - 1)
	if maxBeamIndex < 0 then return end
	
	-- Get camera for distance calculations (works on both client and server)
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or (self.Head and self.Head.Position)
	
	-- First pass: Disable ALL beams by default
	for i = 0, #self.Beams do
		local beam = self.Beams[i]
		if beam and beam.Parent then
			beam.Enabled = false
		end
	end
	
	-- Second pass: Enable only beams that should be visible
	for i = 0, maxBeamIndex do
		local beam = self.Beams[i]
		if not beam or not beam.Parent then continue end
		
		-- CRITICAL: Segments are 0-indexed, beams connect i to i+1
		local seg1Index = i
		local seg2Index = i + 1
		
		-- Check bounds
		if seg1Index > actualSegmentCount or seg2Index > actualSegmentCount then
			continue
		end
		
		local seg1 = self.Segments[seg1Index]
		local seg2 = self.Segments[seg2Index]
		
		-- CRITICAL: Both segments must exist and be parented
		if not seg1 or not seg2 or not seg1.Parent or not seg2.Parent then
			continue
		end
		
		-- Check if both segments are within visible range
		if seg1Index >= visibleSegmentCount or seg2Index >= visibleSegmentCount then
			continue
		end
		
		-- Check segment visibility states
		local vis1 = self.segmentVisibility[seg1Index] ~= false
		local vis2 = self.segmentVisibility[seg2Index] ~= false
		
		if not vis1 or not vis2 then
			continue
		end
		
		-- Get segment transparencies
		local trans1 = seg1.Transparency or 1
		local trans2 = seg2.Transparency or 1
		
		-- Only show beam if BOTH segments are sufficiently visible
		if trans1 < 0.95 and trans2 < 0.95 then
			beam.Enabled = true
			
			-- FIXED: Simple distance-based quality WITHOUT UserSettings
			if cameraPos then
				local distance = (seg1.Position - cameraPos).Magnitude
				local qualityScalar = math.clamp(1 - (distance / 1000), 0.2, 1)
				
				-- Apply beam segments
				local desiredSegments = beam:GetAttribute("DesiredSegments") or BEAM_SEGMENTS
				beam.Segments = math.max(MIN_BEAM_SEGMENTS or 2, math.ceil(desiredSegments * qualityScalar))
			else
				beam.Segments = BEAM_SEGMENTS
			end
			
			-- Synchronized transparency
			local avgTransparency = (trans1 + trans2) / 2
			local beamTransparency = math.min(avgTransparency + 0.05, 0.9)
			
			beam.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0, beamTransparency),
				NumberSequenceKeypoint.new(0.5, beamTransparency),
				NumberSequenceKeypoint.new(1, math.min(beamTransparency + 0.1, 0.95))
			}
			beam.Brightness = math.max(0.5, 2 * (1 - avgTransparency))
		end
	end
	
	-- Handle overlap beams with same strict logic
	for key, beam in pairs(self.Beams) do
		if type(key) == "string" and beam and beam.Parent then
			if string.find(key, "overlap") then
				beam.Enabled = false -- Default to disabled
				
				local index = tonumber(string.match(key, "%d+"))
				if index and index > 0 and index <= actualSegmentCount and index < visibleSegmentCount then
					local seg = self.Segments[index]
					if seg and seg.Parent then
						local segVis = self.segmentVisibility[index] ~= false
						local segTrans = seg.Transparency or 1
						
						if segVis and segTrans < 0.7 then
							beam.Enabled = true
							beam.Transparency = NumberSequence.new(math.min(segTrans + 0.3, 0.9))
						end
					end
				end
			end
		end
	end
end