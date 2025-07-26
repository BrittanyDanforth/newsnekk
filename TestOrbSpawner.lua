-- Test script to verify OrbSpawner is working correctly
-- Place this in ServerScriptService to test

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for modules to load
wait(3)

-- Get OrbSpawner
local OrbSpawner = _G.OrbSpawner
if not OrbSpawner then
	warn("OrbSpawner not found in _G")
	return
end

-- Add debug commands
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		local msg = message:lower()
		
		if msg == "/orbstats" then
			-- Count orbs
			local totalOrbs = 0
			local visibleOrbs = 0
			local hiddenOrbs = 0
			local upgradeOrbs = 0
			
			for _, obj in pairs(workspace:GetDescendants()) do
				if obj:IsA("Part") and (obj.Name == "Orb" or obj.Name == "UpgradeOrb" or obj.Name == "DeathOrb") then
					totalOrbs = totalOrbs + 1
					
					if obj.Name == "UpgradeOrb" then
						upgradeOrbs = upgradeOrbs + 1
					end
					
					if obj.Transparency < 1 then
						visibleOrbs = visibleOrbs + 1
					else
						hiddenOrbs = hiddenOrbs + 1
					end
				end
			end
			
			print("=== ORB STATISTICS ===")
			print("Total Orbs:", totalOrbs)
			print("Visible Orbs:", visibleOrbs)
			print("Hidden Orbs:", hiddenOrbs)
			print("Upgrade Orbs:", upgradeOrbs)
			print("===================")
			
		elseif msg == "/spawndeathtest" then
			-- Test death orb spawning
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local pos = char.HumanoidRootPart.Position
				OrbSpawner.spawnDeathOrbsForSnake(pos, 20)
				print("Spawned 20 death orbs at player position")
			end
			
		elseif msg == "/clearorbs" then
			-- Clear all orbs for testing
			local cleared = 0
			for _, obj in pairs(workspace:GetDescendants()) do
				if obj:IsA("Part") and (obj.Name == "Orb" or obj.Name == "UpgradeOrb" or obj.Name == "DeathOrb") then
					obj:Destroy()
					cleared = cleared + 1
				end
			end
			print("Cleared", cleared, "orbs")
			
		elseif msg == "/orbdist" then
			-- Check orb distribution
			local gridCounts = {}
			local gridSize = 200 -- Check 200x200 stud areas
			
			for _, obj in pairs(workspace:GetDescendants()) do
				if obj:IsA("Part") and obj.Name == "Orb" then
					local gridX = math.floor(obj.Position.X / gridSize)
					local gridZ = math.floor(obj.Position.Z / gridSize)
					local key = gridX .. "," .. gridZ
					
					gridCounts[key] = (gridCounts[key] or 0) + 1
				end
			end
			
			print("=== ORB DISTRIBUTION ===")
			for key, count in pairs(gridCounts) do
				print("Grid", key, ":", count, "orbs")
			end
			print("=======================")
		end
	end)
end)

print("OrbSpawner test commands loaded. Use:")
print("/orbstats - Show orb statistics")
print("/spawndeathtest - Spawn death orbs at your position")
print("/clearorbs - Clear all orbs")
print("/orbdist - Check orb distribution across map")