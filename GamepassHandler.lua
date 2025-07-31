--[[
	GAMEPASS HANDLER
	
	Handles all gamepass functionality and benefits:
	- Speed (2x speed multiplier)
	- Growth (2x growth multiplier)  
	- Coins (3x coin multiplier)
	- Magnet (attracts orbs)
	- Ghost Mode (temporary invincibility)
	- Revive (respawn with 50% length)
	- VIP (all benefits)
	- Pet Ally (AI companion)
	
	Also manages boost inventory system for consumable boosts.
--]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Gamepass IDs (replace with your actual gamepass IDs)
local GAMEPASS_IDS = {
	Speed = 123456789,
	Growth = 123456790,
	Coins = 123456791,
	Magnet = 123456792,
	GhostMode = 123456793,
	Revive = 123456794,
	VIP = 123456795,
	PetAlly = 123456796
}

-- Create remotes
local remotesFolder = ReplicatedStorage:WaitForChild("SnakeRemotes")

local checkGamepassRemote = remotesFolder:FindFirstChild("CheckGamepass") or Instance.new("RemoteFunction")
checkGamepassRemote.Name = "CheckGamepass"
checkGamepassRemote.Parent = remotesFolder

local gamepassPurchasedRemote = remotesFolder:FindFirstChild("GamepassPurchased") or Instance.new("RemoteEvent")
gamepassPurchasedRemote.Name = "GamepassPurchased"
gamepassPurchasedRemote.Parent = remotesFolder

local useBoostRemote = remotesFolder:FindFirstChild("UseBoost") or Instance.new("RemoteEvent")
useBoostRemote.Name = "UseBoost"
useBoostRemote.Parent = remotesFolder

local boostStatusRemote = remotesFolder:FindFirstChild("BoostStatus") or Instance.new("RemoteEvent")
boostStatusRemote.Name = "BoostStatus"
boostStatusRemote.Parent = remotesFolder

local toggleMagnetRemote = remotesFolder:FindFirstChild("ToggleMagnet") or Instance.new("RemoteEvent")
toggleMagnetRemote.Name = "ToggleMagnet"
toggleMagnetRemote.Parent = remotesFolder

local promptReviveRemote = remotesFolder:FindFirstChild("PromptRevive") or Instance.new("RemoteEvent")
promptReviveRemote.Name = "PromptRevive"
promptReviveRemote.Parent = remotesFolder

-- Cache for gamepass ownership
local gamepassCache = {}

-- Check if player owns gamepass
local function hasGamepass(player, gamepassName)
	local gamepassId = GAMEPASS_IDS[gamepassName]
	if not gamepassId then return false end
	
	-- Check cache first
	local cacheKey = player.UserId .. "_" .. gamepassName
	if gamepassCache[cacheKey] ~= nil then
		return gamepassCache[cacheKey]
	end
	
	-- Check ownership
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	
	if success then
		gamepassCache[cacheKey] = hasPass
		return hasPass
	end
	
	return false
end

-- Apply gamepass benefits
local function applyGamepassBenefits(player)
	-- Speed Gamepass
	if hasGamepass(player, "Speed") or hasGamepass(player, "VIP") then
		player:SetAttribute("SpeedMultiplier", 2)
		print(player.Name .. " has Speed gamepass - 2x speed!")
	else
		player:SetAttribute("SpeedMultiplier", 1)
	end
	
	-- Growth Gamepass
	if hasGamepass(player, "Growth") or hasGamepass(player, "VIP") then
		player:SetAttribute("GrowthMultiplier", 2)
		print(player.Name .. " has Growth gamepass - 2x growth!")
	else
		player:SetAttribute("GrowthMultiplier", 1)
	end
	
	-- Coins Gamepass
	if hasGamepass(player, "Coins") or hasGamepass(player, "VIP") then
		player:SetAttribute("CoinMultiplier", 3)
		print(player.Name .. " has Coins gamepass - 3x coins!")
	else
		player:SetAttribute("CoinMultiplier", 1)
	end
	
	-- Magnet Gamepass
	if hasGamepass(player, "Magnet") or hasGamepass(player, "VIP") then
		player:SetAttribute("HasMagnet", true)
		player:SetAttribute("MagnetRange", 50)
		print(player.Name .. " has Magnet gamepass!")
	else
		player:SetAttribute("HasMagnet", false)
		player:SetAttribute("MagnetRange", 0)
	end
	
	-- Ghost Mode Gamepass
	if hasGamepass(player, "GhostMode") or hasGamepass(player, "VIP") then
		player:SetAttribute("HasGhostMode", true)
		print(player.Name .. " has Ghost Mode gamepass!")
	else
		player:SetAttribute("HasGhostMode", false)
	end
	
	-- Revive Gamepass
	if hasGamepass(player, "Revive") or hasGamepass(player, "VIP") then
		player:SetAttribute("HasRevive", true)
		player:SetAttribute("RevivesAvailable", 3) -- 3 revives per life
		print(player.Name .. " has Revive gamepass - 3 revives!")
	else
		player:SetAttribute("HasRevive", false)
		player:SetAttribute("RevivesAvailable", 0)
	end
	
	-- VIP Gamepass
	if hasGamepass(player, "VIP") then
		player:SetAttribute("IsVIP", true)
		print(player.Name .. " is a VIP - All benefits active!")
		
		-- Give VIP boost inventory
		initializePlayerBoosts(player, true)
	else
		player:SetAttribute("IsVIP", false)
		initializePlayerBoosts(player, false)
	end
	
	-- Pet Ally Gamepass
	if hasGamepass(player, "PetAlly") or hasGamepass(player, "VIP") then
		player:SetAttribute("HasPetAlly", true)
		print(player.Name .. " has Pet Ally gamepass!")
		-- Pet creation handled elsewhere
	else
		player:SetAttribute("HasPetAlly", false)
	end
end

-- Boost inventory system
local playerBoosts = {}

local function initializePlayerBoosts(player, isVIP)
	playerBoosts[player] = {
		speedBoost = isVIP and 5 or 0,
		megaSpeed = isVIP and 3 or 0,
		growthBoost = isVIP and 5 or 0,
		ghostMode = isVIP and 3 or 0,
		magnet = isVIP and 5 or 0
	}
	
	-- Send initial boost status
	boostStatusRemote:FireClient(player, playerBoosts[player])
end

-- Use boost
local function useBoost(player, boostType)
	local boosts = playerBoosts[player]
	if not boosts then return end
	
	-- Check if player has boost
	if boosts[boostType] and boosts[boostType] > 0 then
		-- Check if boost is already active
		local attributeName = "Active" .. boostType:gsub("^%l", string.upper)
		if player:GetAttribute(attributeName) then
			return -- Already active
		end
		
		-- Consume boost
		boosts[boostType] = boosts[boostType] - 1
		
		-- Apply boost effect
		if boostType == "speedBoost" then
			player:SetAttribute("ActiveSpeedBoost", true)
			player:SetAttribute("SpeedMultiplier", (player:GetAttribute("SpeedMultiplier") or 1) * 2)
			
			-- Duration: 30 seconds
			task.wait(30)
			player:SetAttribute("ActiveSpeedBoost", false)
			applyGamepassBenefits(player) -- Reset to normal
			
		elseif boostType == "megaSpeed" then
			player:SetAttribute("ActiveMegaSpeed", true)
			player:SetAttribute("SpeedMultiplier", (player:GetAttribute("SpeedMultiplier") or 1) * 5)
			
			-- Duration: 15 seconds
			task.wait(15)
			player:SetAttribute("ActiveMegaSpeed", false)
			applyGamepassBenefits(player) -- Reset to normal
			
		elseif boostType == "growthBoost" then
			player:SetAttribute("ActiveGrowthBoost", true)
			player:SetAttribute("GrowthMultiplier", (player:GetAttribute("GrowthMultiplier") or 1) * 3)
			
			-- Duration: 45 seconds
			task.wait(45)
			player:SetAttribute("ActiveGrowthBoost", false)
			applyGamepassBenefits(player) -- Reset to normal
			
		elseif boostType == "ghostMode" then
			player:SetAttribute("ActiveGhostMode", true)
			
			-- Duration: 20 seconds
			task.wait(20)
			player:SetAttribute("ActiveGhostMode", false)
			
		elseif boostType == "magnet" then
			player:SetAttribute("ActiveMagnet", true)
			player:SetAttribute("MagnetRange", 100) -- Bigger range than passive
			
			-- Duration: 60 seconds
			task.wait(60)
			player:SetAttribute("ActiveMagnet", false)
			applyGamepassBenefits(player) -- Reset to normal
		end
		
		-- Update client
		boostStatusRemote:FireClient(player, boosts)
	end
end

-- Handle boost usage
useBoostRemote.OnServerEvent:Connect(function(player, boostType)
	task.spawn(function()
		useBoost(player, boostType)
	end)
end)

-- Magnet toggle for gamepass owners
toggleMagnetRemote.OnServerEvent:Connect(function(player)
	if player:GetAttribute("HasMagnet") then
		local isActive = player:GetAttribute("MagnetActive")
		player:SetAttribute("MagnetActive", not isActive)
	end
end)

-- Check gamepass function for client
checkGamepassRemote.OnServerInvoke = function(player, gamepassName)
	return hasGamepass(player, gamepassName)
end

-- Handle gamepass purchases
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if wasPurchased then
		-- Clear cache
		for name, id in pairs(GAMEPASS_IDS) do
			if id == gamepassId then
				local cacheKey = player.UserId .. "_" .. name
				gamepassCache[cacheKey] = true
				
				-- Reapply benefits
				applyGamepassBenefits(player)
				
				-- Notify client
				gamepassPurchasedRemote:FireClient(player, name)
				break
			end
		end
	end
end)

-- Revive handling
promptReviveRemote.OnServerEvent:Connect(function(player, useRevive)
	if useRevive and player:GetAttribute("HasRevive") and player:GetAttribute("RevivesAvailable") > 0 then
		-- Consume revive
		local revivesLeft = player:GetAttribute("RevivesAvailable") - 1
		player:SetAttribute("RevivesAvailable", revivesLeft)
		
		-- Mark as reviving
		player:SetAttribute("RevivingNow", true)
		player:SetAttribute("JustRevived", true)
		
		-- Respawn at death location
		local deathPosition = player:GetAttribute("DeathPosition")
		if deathPosition then
			-- Set spawn location before loading character
			local spawnLocation = Instance.new("SpawnLocation")
			spawnLocation.Position = deathPosition
			spawnLocation.Anchored = true
			spawnLocation.CanCollide = false
			spawnLocation.Transparency = 1
			spawnLocation.Parent = workspace
			
			-- Load character at death position directly
			player.RespawnLocation = spawnLocation
			player:LoadCharacter()
			
			-- Clean up spawn location after a delay
			task.wait(0.5)
			if spawnLocation and spawnLocation.Parent then
				spawnLocation:Destroy()
			end
			
			-- Wait for character to load
			local character = player.Character or player.CharacterAdded:Wait()
			local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
			
			-- Apply invincibility
			player:SetAttribute("ReviveInvincible", true)
			
			-- Visual effect
			local reviveEffect = Instance.new("Part")
			reviveEffect.Name = "ReviveEffect"
			reviveEffect.Size = Vector3.new(10, 10, 10)
			reviveEffect.Shape = Enum.PartType.Ball
			reviveEffect.Material = Enum.Material.ForceField
			reviveEffect.Color = Color3.fromRGB(76, 217, 100)
			reviveEffect.Transparency = 0.5
			reviveEffect.CanCollide = false
			reviveEffect.Anchored = true
			reviveEffect.Position = deathPosition
			reviveEffect.Parent = workspace
			
			-- Tween effect
			TweenService:Create(reviveEffect, TweenInfo.new(1), {
				Size = Vector3.new(30, 30, 30),
				Transparency = 1
			}):Play()
			
			Debris:AddItem(reviveEffect, 1)
			
			-- Remove invincibility after 3 seconds
			task.wait(3)
			player:SetAttribute("ReviveInvincible", false)
			player:SetAttribute("JustRevived", false)
		else
			-- Fallback to normal spawn
			player:LoadCharacter()
		end
	else
		-- Normal respawn
		player:LoadCharacter()
	end
end)

-- Player setup
Players.PlayerAdded:Connect(function(player)
	-- Initialize attributes
	player:SetAttribute("MagnetActive", false)
	player:SetAttribute("ActiveSpeedBoost", false)
	player:SetAttribute("ActiveMegaSpeed", false)
	player:SetAttribute("ActiveGrowthBoost", false)
	player:SetAttribute("ActiveGhostMode", false)
	player:SetAttribute("ActiveMagnet", false)
	player:SetAttribute("ReviveInvincible", false)
	player:SetAttribute("JustRevived", false)
	player:SetAttribute("RevivingNow", false)
	
	-- Apply gamepass benefits
	applyGamepassBenefits(player)
	
	-- Store death position on death
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		
		-- Check for revive gamepass and prompt on death
		humanoid.Died:Connect(function()
			-- Store death position
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				player:SetAttribute("DeathPosition", rootPart.Position)
			end
			
			-- Check for revives
			if player:GetAttribute("HasRevive") and player:GetAttribute("RevivesAvailable") > 0 then
				wait(0.5) -- Small delay to ensure death is processed
				promptReviveRemote:FireClient(player, player:GetAttribute("RevivesAvailable"))
			end
		end)
		
		-- Reset revives on fresh spawn (not revive)
		if not player:GetAttribute("JustRevived") then
			if player:GetAttribute("HasRevive") then
				player:SetAttribute("RevivesAvailable", 3)
			end
		end
	end)
end)

-- Cleanup on player leaving
Players.PlayerRemoving:Connect(function(player)
	playerBoosts[player] = nil
	-- Clear cache
	for key in pairs(gamepassCache) do
		if key:find(tostring(player.UserId)) then
			gamepassCache[key] = nil
		end
	end
end)

-- Studio testing override
if game:GetService("RunService"):IsStudio() then
	-- Override hasGamepass for testing
	local oldHasGamepass = hasGamepass
	hasGamepass = function(player, gamepassName)
		-- Enable all gamepasses in studio for testing
		return true
	end
	
	print("⚠️ Studio Mode: All gamepasses enabled for testing!")
end

print("✅ GamepassHandler loaded!")