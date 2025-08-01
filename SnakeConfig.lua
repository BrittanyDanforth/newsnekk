-- Global SnakeConfig for both Player and AI snakes
-- This is a ModuleScript inside ReplicatedStorage

return {
	-- SNAKE DIMENSIONS (V9 Compatible)
	HeadSize = Vector3.new(4.5, 4.5, 4.5),
	SegmentSize = Vector3.new(4, 4, 4),
	SegmentSpacing = 3.2, -- V9 uses this instead of SegmentGap
	
	-- BODY SETTINGS
	InitialLength = 105,
	MaxSegments = 2450,

	-- ENHANCED COLORS (Default skin - better green gradient)
	HeadColor = Color3.fromRGB(76, 217, 100),
	BodyColors = {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	},

	-- MOVEMENT SETTINGS
	FollowSpeed = 0.95,
	BoostFollowSpeed = 0.99,
	UpdateRate = 1,
	MinDistance = 0.02,
	PathSmoothness = 0.9,

	-- AI SPECIFIC SETTINGS
	BaseSpeed = 10,
	BoostSpeed = 24,
	TurnSpeed = 1.8,

	-- MATERIALS
	HeadMaterial = Enum.Material.Neon,
	BodyMaterial = Enum.Material.Neon,

	-- VISUAL ENHANCEMENTS
	GlowIntensity = 2,
	GlowRange = 6,
	LODDistance = 120, -- Level of detail distance

	-- GAMEPLAY SETTINGS
	OrbValue = 5,           -- Each orb gives 5 segments
	BoostDrainRate = 3,     -- Boost drains faster

	-- DEATH ORB VALUES (percentage of snake length returned as orbs)
	DeathOrbReturn = {
		small = 0.30,       -- Small snakes (< 100): return 30%
		medium = 0.25,      -- Medium snakes (100-200): return 25%
		large = 0.20,       -- Large snakes (200-500): return 20%
		huge = 0.15,        -- Huge snakes (500+): return 15%
		cap = 150           -- Max value from death orbs
	},

	-- LEGACY SUPPORT (for old code that might use these)
	SegmentGap = 3.0, -- Old name for spacing in path system
	SegmentColor = Color3.fromRGB(80, 200, 100), -- For SnakeMovement
}