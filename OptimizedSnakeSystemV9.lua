-- Optimized Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING (FIXED GROWTH)
-- Perfect head-body integration with smooth growth transitions

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Performance Constants
local SEGMENT_UPDATE_RATE = 60
local NETWORK_UPDATE_RATE = 20
local MAX_SEGMENTS = 500
local SEGMENT_SPACING = 0.5 -- Tighter for seamless look
local HISTORY_SIZE = 2000
local GROWTH_CHECK_INTERVAL = 10

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 3 -- Consistent glow throughout
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 25 -- High quality curves
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper (reduced from part taper)
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local VISUAL_SMOOTHING_FACTOR = 0.6 -- Higher = smoother transitions

-- Growth Animation Constants (NEW)
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length (increased for smoother growth)
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions for smooth appearance
local GROWTH_PULSE_STRENGTH = 0.1 -- How much segments pulse when growing
local GROWTH_WAVE_SPEED = 10 -- Speed of growth wave effect

-- ... existing code ...

		-- All segments get glows now - no LOD
		local segmentGlow = Instance.new("PointLight")
		segmentGlow.Name = "Glow"
		segmentGlow.Brightness = GLOW_INTENSITY * 0.9 -- Slightly dimmer than head
		segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / segmentCount) * 0.1) -- Gradual range decrease
		segmentGlow.Color = segment.Color
		segmentGlow.Shadows = false
		segmentGlow.Parent = segment
		self.glows[i] = segmentGlow

		segment.Parent = self.model
		self.segments[i] = segment

-- ... existing code ...

		-- Add glow for all segments - no LOD
		local segmentGlow = Instance.new("PointLight")
		segmentGlow.Name = "Glow"
		segmentGlow.Brightness = GLOW_INTENSITY * 0.9
		segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / MAX_SEGMENTS) * 0.2)
		segmentGlow.Color = segment.Color
		segmentGlow.Shadows = false
		segmentGlow.Parent = segment
		self.glows[i] = segmentGlow

		segment.Parent = self.model
		self.segments[i] = segment

-- ... existing code ...