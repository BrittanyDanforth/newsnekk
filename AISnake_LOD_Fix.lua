-- AISnake LOD Fix - Replace these sections in your AISnake module

-- Fixed updateSegmentVisibility function
function AISnake:updateSegmentVisibility(cameraPosition)
	if not cameraPosition then return end

	-- Calculate distance from camera to snake head
	local headDistance = (self.HeadParts.head.Position - cameraPosition).Magnitude

	-- Determine how many segments to show based on distance
	local segmentsToShow
	if headDistance < 200 then
		segmentsToShow = self.CurrentLength  -- Show all
	elseif headDistance < 400 then
		segmentsToShow = math.floor(self.CurrentLength * 0.8)  -- 80%
	elseif headDistance < 600 then
		segmentsToShow = math.floor(self.CurrentLength * 0.5)  -- 50%
	elseif headDistance < 800 then
		segmentsToShow = math.max(30, math.floor(self.CurrentLength * 0.3))  -- 30% but at least 30
	else
		segmentsToShow = math.max(15, math.floor(self.CurrentLength * 0.15))  -- 15% but at least 15
	end

	-- Clamp to limits
	segmentsToShow = math.min(segmentsToShow, self.CurrentLength, DYNAMIC_SEGMENT_LIMIT)

	-- Always show head at full quality
	if self.Segments[0] then
		self:applyLODToSegment(self.Segments[0], "near", 0)
		self.Segments[0].Transparency = 0  -- Head always fully opaque
	end

	-- Update eye visibility based on head distance
	if self.HeadParts then
		local eyeVisible = headDistance < 600  -- Hide eyes when far away
		if self.HeadParts.leftEye then
			self.HeadParts.leftEye.Transparency = eyeVisible and 0 or 1
		end
		if self.HeadParts.rightEye then
			self.HeadParts.rightEye.Transparency = eyeVisible and 0 or 1
		end
		if self.HeadParts.leftPupil then
			self.HeadParts.leftPupil.Transparency = eyeVisible and 0 or 1
		end
		if self.HeadParts.rightPupil then
			self.HeadParts.rightPupil.Transparency = eyeVisible and 0 or 1
		end
	end

	-- Update segments continuously from head
	for i = 1, self.CurrentLength do
		local segment = self.Segments[i]

		if i <= segmentsToShow then
			-- This segment should be visible
			if segment and segment.Parent then
				-- Calculate segment-specific distance
				local segmentDistance = (segment.Position - cameraPosition).Magnitude

				-- Determine LOD level
				local lodLevel
				if segmentDistance < LOD_DISTANCE_NEAR then
					lodLevel = "near"
				elseif segmentDistance < LOD_DISTANCE_MID then
					lodLevel = "mid"
				else
					lodLevel = "far"
				end

				self:applyLODToSegment(segment, lodLevel, i)

				-- Calculate transparency
				local baseTransparency = 0
				if headDistance < 200 then
					baseTransparency = 0
				elseif headDistance < 400 then
					baseTransparency = 0.1
				elseif headDistance < 600 then
					baseTransparency = 0.2
				else
					baseTransparency = 0.3
				end

				-- Fade out segments near the cutoff point
				local fadeStart = segmentsToShow * 0.8  -- Start fading at 80%
				if i > fadeStart and i < segmentsToShow then
					-- Gradual fade for last 20% of visible segments
					local fadeProgress = (i - fadeStart) / (segmentsToShow - fadeStart)
					segment.Transparency = math.min(0.7, baseTransparency + fadeProgress * 0.4)
				else
					segment.Transparency = baseTransparency
				end

				-- Update glow based on distance and visibility
				local glow = segment:FindFirstChild("Glow")
				if glow then
					if headDistance < 600 and self:shouldHaveGlow(i) then
						-- Scale down glow with distance
						local glowScale = math.max(0, 1 - (headDistance / 600))
						glow.Enabled = true
						glow.Brightness = GLOW_INTENSITY * glowScale * (1 - segment.Transparency)
						glow.Range = GLOW_RANGE_BASE * glowScale
					else
						glow.Enabled = false
					end
				end
			else
				-- Segment doesn't exist yet, mark as invisible
				self.segmentVisibility[i] = false
			end
		else
			-- This segment should be completely hidden
			if segment and segment.Parent then
				self:applyLODToSegment(segment, "culled", i)
			end
			self.segmentVisibility[i] = false
		end
	end

	-- Store visible count
	self.visibleSegmentCount = segmentsToShow
end

-- Fixed syncBeamVisibility function
function AISnake:syncBeamVisibility()
	-- CRITICAL: Only update beams for segments that actually exist
	local maxBeamIndex = math.min(self.actualSegmentCount or self.CurrentLength, DYNAMIC_SEGMENT_LIMIT) - 1
	
	-- Update main beams based on segment visibility
	for i = 0, maxBeamIndex do
		local beam = self.Beams[i]
		if beam and beam.Parent then
			local seg1 = self.Segments[i]
			local seg2 = self.Segments[i + 1]

			-- Check if both segments exist and are visible
			if seg1 and seg2 and seg1.Parent and seg2.Parent then
				-- Check visibility states
				local vis1 = self.segmentVisibility[i] ~= false
				local vis2 = self.segmentVisibility[i + 1] ~= false
				
				-- Only show beam if both segments are visible
				if vis1 and vis2 and i < self.visibleSegmentCount then
					-- Get segment transparencies
					local trans1 = seg1.Transparency or 0
					local trans2 = seg2.Transparency or 0

					-- Show beam only if segments are visible enough
					if trans1 < 0.95 and trans2 < 0.95 then
						beam.Enabled = true

						-- Calculate beam transparency based on segment transparency
						local avgTransparency = (trans1 + trans2) / 2
						local beamTransparency = math.min(avgTransparency + 0.05, 0.9)
						
						beam.Transparency = NumberSequence.new{
							NumberSequenceKeypoint.new(0, beamTransparency),
							NumberSequenceKeypoint.new(0.5, beamTransparency),
							NumberSequenceKeypoint.new(1, math.min(beamTransparency + 0.1, 0.95))
						}
						beam.Brightness = math.max(0.5, 2 * (1 - avgTransparency))
					else
						-- Hide beam if segments are too transparent
						beam.Enabled = false
					end
				else
					-- Hide beam if segments aren't visible
					beam.Enabled = false
				end
			else
				-- Hide beam if segments don't exist
				beam.Enabled = false
			end
		end
	end

	-- Disable all beams beyond the actual segment count
	for i = maxBeamIndex + 1, #self.Beams do
		local beam = self.Beams[i]
		if beam and beam.Parent then
			beam.Enabled = false
		end
	end
end

-- Fixed applyLODToSegment function
function AISnake:applyLODToSegment(segment, lodLevel, index)
	if not segment or not segment.Parent then return end

	-- Store LOD state
	self.lodStates[index] = lodLevel

	if lodLevel == "culled" then
		-- Completely hide culled segments
		segment.Transparency = 1
		segment.CanTouch = false
		segment.CanQuery = false

		-- Disable glow
		local glow = segment:FindFirstChild("Glow")
		if glow then
			glow.Enabled = false
		end

		self.segmentVisibility[index] = false
	else
		-- Segment is visible at some level
		-- Collision only for near segments in the first 50
		if lodLevel == "near" and index <= 50 then
			segment.CanTouch = true
			segment.CanQuery = index <= 10
		else
			segment.CanTouch = false
			segment.CanQuery = false
		end

		self.segmentVisibility[index] = true
		
		-- Don't set transparency here - let updateSegmentVisibility handle it
	end
end

-- Fixed ensureSegmentExists function
function AISnake:ensureSegmentExists(index)
	if index > DYNAMIC_SEGMENT_LIMIT or index > self.CurrentLength then
		return nil
	end

	local segment = self.Segments[index]
	if segment and segment.Parent then
		return segment
	end

	-- Don't create segments beyond visible count + buffer
	if index > self.visibleSegmentCount + 50 then
		return nil
	end

	-- Create segment on demand
	local delay = mathFloor(index * 1.2)
	local targetData = self:getFromHistory(delay)
	if not targetData then
		return nil
	end

	local color = self:getSegmentColor(index)
	segment = createSegment(index, targetData.position, color, self.Config, self.Model, self.CurrentLength)

	-- Apply proper size
	local currentBaseSize = BASE_SIZE * self.growthFactor
	local segmentSize = self:getSegmentSize(index, currentBaseSize)
	segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

	-- CRITICAL: Apply LOD immediately based on camera distance
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position
	if cameraPos then
		local lodLevel = self:calculateLODLevel(index, cameraPos)
		self:applyLODToSegment(segment, lodLevel, index)
		
		-- If segment is culled, don't show it
		if lodLevel == "culled" then
			segment.Transparency = 1
		end
	else
		-- If no camera, hide segment
		segment.Transparency = 1
		self.segmentVisibility[index] = false
	end

	self.Segments[index] = segment

	-- Create attachment if needed
	if not self.Attachments[index] and self.AttachmentPart then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. index
		attachment.Parent = self.AttachmentPart
		attachment.WorldPosition = segment.Position
		self.Attachments[index] = attachment
	end

	-- Create beam to previous segment if needed
	if index > 0 and not self.Beams[index - 1] and self.Attachments[index - 1] and self.Attachments[index] then
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. (index - 1)
		beam.Attachment0 = self.Attachments[index - 1]
		beam.Attachment1 = self.Attachments[index]

		-- Beam properties
		local beamWidth = self:getBeamWidth(index - 1, currentBaseSize)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = BEAM_TEXTURES.gradient
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.TextureSpeed = BEAM_TEXTURE_SPEED
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.Transparency = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1)
		}
		beam.Color = ColorSequence.new(color)

		beam.Parent = self.AttachmentPart
		self.Beams[index - 1] = beam

		-- Apply visibility immediately based on segment visibility
		if self.segmentVisibility[index] == false or self.segmentVisibility[index - 1] == false then
			beam.Enabled = false
		end
	end

	-- Update actual segment count
	self.actualSegmentCount = math.max(self.actualSegmentCount or 0, index)

	return segment
end

-- Add this helper function to clean up invisible segments periodically
function AISnake:cleanupInvisibleSegments()
	-- Only run cleanup every 60 frames
	self._cleanupFrame = (self._cleanupFrame or 0) + 1
	if self._cleanupFrame % 60 ~= 0 then return end
	
	-- Don't cleanup segments that are close to visible range
	local cleanupThreshold = self.visibleSegmentCount + 100
	
	for i = cleanupThreshold, #self.Segments do
		local segment = self.Segments[i]
		if segment and segment.Parent then
			-- Return segment to pool
			returnSegment(segment)
			self.Segments[i] = nil
			
			-- Disable associated beam
			local beam = self.Beams[i - 1]
			if beam then
				beam.Enabled = false
			end
		end
	end
end