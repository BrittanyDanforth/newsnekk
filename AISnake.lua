-- === ENHANCED AI PERSONALITIES - STABLE & DISTINCT ===
AISnake.PersonalityTypes = {
	"Aggressor", "Scavenger", "Guardian", "Opportunist", "Hunter", "Nomad", "Shadow", "Berserker"
}

AISnake.PersonalityDefinitions = {
	Aggressor = {
		Type = "Aggressor",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.15,
		TurnBias = 0.03,
		BoostChance = 0.06,
		CombatRadius = 45,
		RandomTurnInterval = 5.0,
		OrbSeekRadius = 100,
		Description = "Balanced aggressor - hunts when advantageous",
		FleeThreshold = 20,  -- Length difference before fleeing
		AggressionLevel = 0.7,
		PatrolRadius = 200,
		MaxFleeTime = 3.0,  -- Maximum time to flee before doing something else
	},
	Scavenger = {
		Type = "Scavenger",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = true,
		SpeedMultiplier = 1.1,
		TurnBias = 0.05,
		BoostChance = 0.04,
		CombatRadius = 25,
		RandomTurnInterval = 4.0,
		OrbSeekRadius = 200,  -- Excellent orb vision
		Description = "Peaceful orb collector - avoids all conflict",
		FleeThreshold = 5,
		AggressionLevel = 0.0,
		PatrolRadius = 300,
		MaxFleeTime = 2.0,
	},
	Guardian = {
		Type = "Guardian",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.05,
		TurnBias = 0.02,
		BoostChance = 0.03,
		CombatRadius = 60,
		RandomTurnInterval = 6.0,
		OrbSeekRadius = 120,
		Description = "Territory defender - patrols specific areas",
		FleeThreshold = 30,
		AggressionLevel = 0.5,
		PatrolRadius = 150,  -- Stays in smaller area
		TerritoryCenter = Vector3.new(0, 0, 0),  -- Set randomly on spawn
		MaxFleeTime = 4.0,
	},
	Opportunist = {
		Type = "Opportunist",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.2,
		TurnBias = 0.04,
		BoostChance = 0.08,
		CombatRadius = 40,
		RandomTurnInterval = 3.5,
		OrbSeekRadius = 140,
		Description = "Smart fighter - only attacks smaller snakes",
		FleeThreshold = 0,  -- Never flees from equal/smaller
		AggressionLevel = 0.8,
		PatrolRadius = 250,
		OnlyAttackSmaller = true,
		MaxFleeTime = 2.5,
	},
	Hunter = {
		Type = "Hunter",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.18,
		TurnBias = 0.02,
		BoostChance = 0.07,
		CombatRadius = 50,
		RandomTurnInterval = 5.5,
		OrbSeekRadius = 130,
		Description = "Persistent hunter - tracks targets",
		FleeThreshold = 25,
		AggressionLevel = 0.75,
		PatrolRadius = 220,
		TrackingDuration = 10,  -- Seconds to track a target
		MaxFleeTime = 3.5,
	},
	Nomad = {
		Type = "Nomad",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.12,
		TurnBias = 0.06,
		BoostChance = 0.05,
		CombatRadius = 30,
		RandomTurnInterval = 2.5,  -- Frequent direction changes
		OrbSeekRadius = 160,
		Description = "Wanderer - explores the entire map",
		FleeThreshold = 10,
		AggressionLevel = 0.2,
		PatrolRadius = 400,  -- Roams widely
		ExplorationBias = 0.8,
		MaxFleeTime = 2.0,
	},
	Shadow = {
		Type = "Shadow",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.22,
		TurnBias = 0.01,
		BoostChance = 0.02,  -- Rarely boosts
		CombatRadius = 55,
		RandomTurnInterval = 8.0,
		OrbSeekRadius = 110,
		Description = "Stealthy assassin - strikes from behind",
		FleeThreshold = 15,
		AggressionLevel = 0.6,
		PatrolRadius = 180,
		PreferRearAttack = true,
		StalkDistance = 30,
		MaxFleeTime = 3.0,
	},
	Berserker = {
		Type = "Berserker",
		TargetPlayers = true,
		TargetOrbs = false,  -- Ignores orbs when hunting
		AvoidOthers = false,
		SpeedMultiplier = 1.25,
		TurnBias = 0.05,
		BoostChance = 0.12,  -- Boosts frequently
		CombatRadius = 35,
		RandomTurnInterval = 6.0,
		OrbSeekRadius = 50,  -- Poor orb vision
		Description = "Reckless fighter - all aggression",
		FleeThreshold = 40,  -- Only flees from much larger
		AggressionLevel = 1.0,
		PatrolRadius = 200,
		RageMode = true,  -- Gets faster when smaller
		MaxFleeTime = 2.0,
	},
}

-- === MUCH SMARTER AI BRAIN ===
function AISnake:_determineAction()
	local headPos = self.HeadParts.head.Position
	local p = self.Personality
	local now = tick()
	local state = "WANDER"
	local steer = self.Direction

	-- Clean up expired states
	if self.Avoiding and now > self.AvoidExpire then 
		self.Avoiding = false 
		self.FleeReason = ""
		self.FleeStartTime = nil
	end
	
	-- ANTI-STUCK: If fleeing for too long, force a state change
	if self.Avoiding and self.FleeStartTime then
		local fleeTime = now - self.FleeStartTime
		local maxFleeTime = p.MaxFleeTime or 3.0
		
		if fleeTime > maxFleeTime then
			-- Force stop fleeing and do something else
			self.Avoiding = false
			self.FleeReason = ""
			self.FleeStartTime = nil
			self.ForceWanderUntil = now + 2.0 -- Force wander for 2 seconds
			
			-- Pick a random direction away from threats
			local randomAngle = mathRandom() * 2 * mathPi
			self.TargetYaw = randomAngle
			self.Direction = Vector3new(mathSin(randomAngle), 0, mathCos(randomAngle))
		end
	end
	
	-- Force wander if stuck in flee loop
	if self.ForceWanderUntil and now < self.ForceWanderUntil then
		state = "WANDER"
		-- Continue in current direction with slight random turns
		if mathRandom() < 0.1 then
			self.TargetYaw = self.TargetYaw + mathRad(mathRandom(-30, 30))
		end
		steer = Vector3new(mathSin(self.TargetYaw), 0, mathCos(self.TargetYaw))
		return state, steer
	else
		self.ForceWanderUntil = nil
	end
	
	if self.isConfident and now > self.confidenceEndTime then
		self.isConfident = false
		if self.HeadParts and self.HeadParts.headOutline then
			self.HeadParts.headOutline.Color3 = Color3.fromRGB(255, 255, 255)
			self.HeadParts.headOutline.LineThickness = 0.1
			self.HeadParts.headOutline.Transparency = 1
		end
	end
	if self.TargetOrb and (not self.TargetOrb.Parent or now > self.TargetOrbExpire) then
		self.TargetOrb = nil
		AISnake._orbTargets[self] = nil
	end
	if self.TargetSnake and (not self.TargetSnake.part or not self.TargetSnake.part.Parent) then
		self.TargetSnake = nil
		self.trapPhase = 0
		self.isAmbushing = false
	end

	-- Priority 3: Threat assessment (SMARTER)
	local threats = self:findNearbyThreats()
	local shouldFlee = false
	local fleeReason = ""

	if #threats > 0 then
		local closestThreat = threats[1]
		
		-- HUGE SNAKE HANDLING - don't panic from massive snakes unless very close
		if closestThreat.enemyLength and closestThreat.enemyLength > 500 then
			-- Only flee from huge snakes if they're RIGHT on top of us
			if closestThreat.distance < 10 then
				shouldFlee = true
				fleeReason = "huge_snake_very_close"
			end
		else
			-- Normal threat handling for regular sized enemies
			if closestThreat.distance < 15 and closestThreat.lengthDiff > 5 then
				shouldFlee = true
				fleeReason = "immediate_danger"
			elseif closestThreat.distance < 25 and closestThreat.lengthDiff > 15 then
				shouldFlee = true
				fleeReason = "bigger_snake_nearby"
			elseif closestThreat.lengthDiff > 30 and closestThreat.distance < 40 then
				shouldFlee = true
				fleeReason = "giant_enemy"
			elseif #threats >= 2 and closestThreat.distance < 30 then
				shouldFlee = true
				fleeReason = "multiple_threats"
			elseif p.Type == "Scavenger" and closestThreat.lengthDiff > 0 and closestThreat.distance < 35 then
				shouldFlee = true
				fleeReason = "scavenger_instinct"
			end
		end

		-- Even aggressive types flee from much bigger snakes
		if shouldFlee and (p.Type == "Aggressor" or p.Type == "Hunter") then
			if closestThreat.lengthDiff < 10 and closestThreat.distance > 20 then
				shouldFlee = false
			end
		end
	end

	if shouldFlee or self.Avoiding then
		self.TargetSnake = nil
		self.TargetOrb = nil  -- Cancel orb seeking when fleeing

		local fleeDir = self:getSmartFleeDirection(threats)

		self.Avoiding = true
		self.AvoidDir = fleeDir
		self.AvoidExpire = now + 2.5
		
		-- Track when we started fleeing
		if shouldFlee and not self.FleeStartTime then
			self.FleeStartTime = now
		end
		
		if shouldFlee then self.FleeReason = fleeReason end
		return "FLEE", fleeDir
	else
		-- Reset flee timer when not fleeing
		self.FleeStartTime = nil
	end

	-- Priority 5: Wandering (SMARTER with anti-stuck)
	if state == "WANDER" then
		local mapCenter = Vector3new(0, headPos.Y, 0)
		local toCenter = mapCenter - headPos
		local distFromCenter = toCenter.Magnitude

		-- More varied wandering to prevent patterns
		local turnInterval = p.RandomTurnInterval * (0.5 + mathRandom() * 1.0) -- Add randomness
		if (now - (self.LastTurn or 0) > turnInterval) then
			local maxTurn = 60 -- Increased from 45 for more varied movement
			self.TargetYaw = self.TargetYaw + mathRad(mathRandom(-maxTurn, maxTurn))
			self.LastTurn = now
			
			-- Occasionally do a big turn to break patterns
			if mathRandom() < 0.1 then
				self.TargetYaw = self.TargetYaw + mathRad(mathRandom(-180, 180))
			end
		end

		local baseSteer = Vector3new(mathSin(self.TargetYaw), 0, mathCos(self.TargetYaw))

		return state, steer
	end

	return state, steer
end