--[[
	GAMEPASS HANDLER
	Manages all gamepass functionality and benefits
--]]

-- Services
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Gamepass IDs
local GAMEPASS_IDS = {
	SpeedBoost = 123456789,      -- Replace with actual ID
	GrowthBoost = 123456790,     -- Replace with actual ID
	CoinMultiplier = 123456791,  -- Replace with actual ID
	Magnet = 123456792,          -- Replace with actual ID
	GhostMode = 123456793,       -- Replace with actual ID
	VIP = 123456794,             -- Replace with actual ID
	Revive = 123456795,          -- Replace with actual ID
	PetAlly = 123456796          -- Replace with actual ID
}

-- Studio testing overrides
local STUDIO_TESTING = game:GetService("RunService"):IsStudio()
local STUDIO_GAMEPASSES = {
	SpeedBoost = true,
	GrowthBoost = true,
	CoinMultiplier = true,
	Magnet = true,
	GhostMode = true,
	VIP = true,
	Revive = true,
	PetAlly = true
}

-- Boost inventory configuration
local BOOST_INVENTORY = {
	SpeedBoost = 5,      -- Start with 5 speed boosts
	MegaSpeed = 3,       -- Start with 3 mega speed boosts
	GrowthBoost = 5,     -- Start with 5 growth boosts
	GhostMode = 3,       -- Start with 3 ghost mode uses
	Magnet = 3           -- Start with 3 magnet uses
}

-- Cache for gamepass ownership
local gamepassCache = {}

-- Create/get remotes
local Events = ReplicatedStorage:WaitForChild("Events")

local checkGamepassRemote = Instance.new("RemoteFunction")
checkGamepassRemote.Name = "CheckGamepass"
checkGamepassRemote.Parent = Events

local gamepassPurchasedRemote = Instance.new("RemoteEvent")
gamepassPurchasedRemote.Name = "GamepassPurchased"
gamepassPurchasedRemote.Parent = Events

local useBoostRemote = Instance.new("RemoteEvent")
useBoostRemote.Name = "UseBoost"
useBoostRemote.Parent = Events

local boostStatusRemote = Instance.new("RemoteEvent")
boostStatusRemote.Name = "BoostStatus"
boostStatusRemote.Parent = Events

local toggleMagnetRemote = Instance.new("RemoteEvent")
toggleMagnetRemote.Name = "ToggleMagnet"
toggleMagnetRemote.Parent = Events

-- Check if player has gamepass
local function hasGamepass(player, gamepassName)
	-- Check cache first
	if gamepassCache[player.UserId] and gamepassCache[player.UserId][gamepassName] ~= nil then
		return gamepassCache[player.UserId][gamepassName]
	end
	
	-- Studio testing override
	if STUDIO_TESTING and STUDIO_GAMEPASSES[gamepassName] then
		if not gamepassCache[player.UserId] then
			gamepassCache[player.UserId] = {}
		end
		gamepassCache[player.UserId][gamepassName] = true
		return true
	end
	
	-- Check actual gamepass
	local gamepassId = GAMEPASS_IDS[gamepassName]
	if not gamepassId then
		warn("Invalid gamepass name:", gamepassName)
		return false
	end
	
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	
	if success then
		-- Cache result
		if not gamepassCache[player.UserId] then
			gamepassCache[player.UserId] = {}
		end
		gamepassCache[player.UserId][gamepassName] = hasPass
		return hasPass
	else
		warn("Failed to check gamepass:", gamepassName, "for", player.Name)
		return false
	end
end

-- Apply gamepass benefits
local function applyGamepassBenefits(player)
	-- Speed Boost
	if hasGamepass(player, "SpeedBoost") then
		player:SetAttribute("SpeedMultiplier", 1.25) -- 25% speed increase
	else
		player:SetAttribute("SpeedMultiplier", 1)
	end
	
	-- Growth Boost
	if hasGamepass(player, "GrowthBoost") then
		player:SetAttribute("GrowthMultiplier", 1.5) -- 50% more growth
	else
		player:SetAttribute("GrowthMultiplier", 1)
	end
	
	-- Coin Multiplier
	if hasGamepass(player, "CoinMultiplier") then
		player:SetAttribute("CoinMultiplier", 2) -- 2x coins
	else
		player:SetAttribute("CoinMultiplier", 1)
	end
	
	-- Magnet
	if hasGamepass(player, "Magnet") then
		player:SetAttribute("HasMagnet", true)
		player:SetAttribute("MagnetRange", 50) -- 50 stud magnet range
	else
		player:SetAttribute("HasMagnet", false)
		player:SetAttribute("MagnetRange", 0)
	end
	
	-- Ghost Mode
	if hasGamepass(player, "GhostMode") then
		player:SetAttribute("HasGhostMode", true)
	else
		player:SetAttribute("HasGhostMode", false)
	end
	
	-- VIP
	if hasGamepass(player, "VIP") then
		player:SetAttribute("IsVIP", true)
		-- VIP benefits can include:
		-- - Access to VIP skins
		-- - VIP chat tag
		-- - Bonus daily rewards
		-- - Exclusive emotes
	else
		player:SetAttribute("IsVIP", false)
	end
	
	-- Revive
	if hasGamepass(player, "Revive") then
		player:SetAttribute("HasRevive", true)
		player:SetAttribute("RevivesAvailable", 3) -- 3 revives per life
	else
		player:SetAttribute("HasRevive", false)
		player:SetAttribute("RevivesAvailable", 0)
	end
	
	-- Pet Ally
	if hasGamepass(player, "PetAlly") then
		player:SetAttribute("HasPetAlly", true)
		-- Pet functionality to be implemented
	else
		player:SetAttribute("HasPetAlly", false)
	end
end

-- Initialize player boosts
local function initializePlayerBoosts(player)
	-- Initialize boost inventory
	for boostType, count in pairs(BOOST_INVENTORY) do
		player:SetAttribute(boostType .. "Count", count)
	end
	
	-- Initialize active boost states
	player:SetAttribute("ActiveSpeedBoost", false)
	player:SetAttribute("ActiveMegaSpeed", false)
	player:SetAttribute("ActiveGrowthBoost", false)
	player:SetAttribute("ActiveGhostMode", false)
	player:SetAttribute("ActiveMagnet", false)
	
	-- Send initial inventory to client
	boostStatusRemote:FireClient(player, "inventory", BOOST_INVENTORY)
end

-- Use boost
local function useBoost(player, boostType)
	local countAttribute = boostType .. "Count"
	local activeAttribute = "Active" .. boostType
	
	local currentCount = player:GetAttribute(countAttribute) or 0
	local isActive = player:GetAttribute(activeAttribute) or false
	
	if currentCount > 0 and not isActive then
		-- Consume boost
		player:SetAttribute(countAttribute, currentCount - 1)
		player:SetAttribute(activeAttribute, true)
		
		-- Apply boost effects
		if boostType == "SpeedBoost" then
			-- 2x speed for 30 seconds
			local baseSpeed = player:GetAttribute("SpeedMultiplier") or 1
			player:SetAttribute("SpeedMultiplier", baseSpeed * 2)
			
			task.wait(30)
			
			player:SetAttribute("SpeedMultiplier", baseSpeed)
			player:SetAttribute(activeAttribute, false)
			
		elseif boostType == "MegaSpeed" then
			-- 3x speed for 20 seconds
			local baseSpeed = player:GetAttribute("SpeedMultiplier") or 1
			player:SetAttribute("SpeedMultiplier", baseSpeed * 3)
			
			task.wait(20)
			
			player:SetAttribute("SpeedMultiplier", baseSpeed)
			player:SetAttribute(activeAttribute, false)
			
		elseif boostType == "GrowthBoost" then
			-- 3x growth for 45 seconds
			local baseGrowth = player:GetAttribute("GrowthMultiplier") or 1
			player:SetAttribute("GrowthMultiplier", baseGrowth * 3)
			
			task.wait(45)
			
			player:SetAttribute("GrowthMultiplier", baseGrowth)
			player:SetAttribute(activeAttribute, false)
			
		elseif boostType == "GhostMode" then
			-- Invincibility for 15 seconds
			player:SetAttribute("ActiveGhostMode", true)
			
			task.wait(15)
			
			player:SetAttribute("ActiveGhostMode", false)
			
		elseif boostType == "Magnet" then
			-- Super magnet for 60 seconds
			player:SetAttribute("MagnetActive", true)
			player:SetAttribute("MagnetRange", 100) -- Increased range
			
			task.wait(60)
			
			if hasGamepass(player, "Magnet") then
				player:SetAttribute("MagnetRange", 50) -- Back to normal gamepass range
			else
				player:SetAttribute("MagnetRange", 0)
				player:SetAttribute("MagnetActive", false)
			end
		end
		
		-- Update client
		boostStatusRemote:FireClient(player, "used", boostType)
	end
end

-- Handle boost usage
useBoostRemote.OnServerEvent:Connect(function(player, boostType)
	-- Validate boost type
	if BOOST_INVENTORY[boostType] then
		-- Run in separate thread to not block
		task.spawn(function()
			useBoost(player, boostType)
		end)
	end
end)

-- Toggle magnet (for gamepass owners)
toggleMagnetRemote.OnServerEvent:Connect(function(player)
	if hasGamepass(player, "Magnet") then
		local currentState = player:GetAttribute("MagnetActive") or false
		player:SetAttribute("MagnetActive", not currentState)
		
		if not currentState then
			player:SetAttribute("MagnetRange", 50)
		else
			player:SetAttribute("MagnetRange", 0)
		end
	end
end)

-- Check gamepass remote function
checkGamepassRemote.OnServerInvoke = function(player, gamepassName)
	return hasGamepass(player, gamepassName)
end

-- Handle gamepass purchases
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if wasPurchased then
		-- Clear cache to force recheck
		if gamepassCache[player.UserId] then
			gamepassCache[player.UserId] = {}
		end
		
		-- Reapply benefits
		applyGamepassBenefits(player)
		
		-- Notify client
		gamepassPurchasedRemote:FireClient(player, gamepassId)
		
		-- Give immediate rewards based on gamepass
		for gamepassName, id in pairs(GAMEPASS_IDS) do
			if id == gamepassId then
				-- Special handling for certain gamepasses
				if gamepassName == "Revive" then
					player:SetAttribute("RevivesAvailable", 3)
				end
				break
			end
		end
	end
end)

-- Player setup
Players.PlayerAdded:Connect(function(player)
	-- Apply gamepass benefits
	applyGamepassBenefits(player)
	
	-- Initialize boosts
	initializePlayerBoosts(player)
	
	-- Handle character spawning for revive system
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		
		-- Reset revives on new life
		if hasGamepass(player, "Revive") then
			player:SetAttribute("RevivesAvailable", 3)
		end
		
		-- Clear any active boosts on spawn
		player:SetAttribute("ActiveSpeedBoost", false)
		player:SetAttribute("ActiveMegaSpeed", false) 
		player:SetAttribute("ActiveGrowthBoost", false)
		player:SetAttribute("ActiveGhostMode", false)
		
		-- Listen for death
		humanoid.Died:Connect(function()
			-- Store death info for revive
			player:SetAttribute("DeathPosition", character.HumanoidRootPart.Position)
			player:SetAttribute("ReviveSnakeLength", player:GetAttribute("SnakeLength") or 500)
			
			-- Clear magnet on death to prevent orb issues
			player:SetAttribute("MagnetActive", false)
			player:SetAttribute("MagnetRange", 0)
			
			-- Handle revive prompt
			if player:GetAttribute("HasRevive") and player:GetAttribute("RevivesAvailable") > 0 then
				wait(0.5) -- Small delay for death processing
				
				-- Prompt revive on client
				local promptReviveRemote = Events:FindFirstChild("PromptRevive")
				if promptReviveRemote then
					promptReviveRemote:FireClient(
						player, 
						player:GetAttribute("RevivesAvailable"),
						player:GetAttribute("ReviveSnakeLength")
					)
				end
			end
		end)
		
		-- Apply revive if flagged
		if player:GetAttribute("JustRevived") then
			player:SetAttribute("JustRevived", false)
			
			-- Teleport to death spot
			local deathPos = player:GetAttribute("DeathPosition")
			if deathPos then
				character:SetPrimaryPartCFrame(CFrame.new(deathPos))
			end
			
			-- Apply revive invincibility
			player:SetAttribute("ReviveInvincible", true)
			
			-- Visual effect
			local forcefield = Instance.new("ForceField")
			forcefield.Parent = character
			
			-- Remove invincibility after 5 seconds
			task.wait(5)
			
			player:SetAttribute("ReviveInvincible", false)
			if forcefield and forcefield.Parent then
				forcefield:Destroy()
			end
		end
	end)
end)

-- Cleanup on player leaving
Players.PlayerRemoving:Connect(function(player)
	-- Clear cache
	gamepassCache[player.UserId] = nil
end)

-- Handle revive response
local promptReviveRemote = Events:WaitForChild("PromptRevive")
promptReviveRemote.OnServerEvent:Connect(function(player, useRevive)
	if useRevive and player:GetAttribute("HasRevive") and player:GetAttribute("RevivesAvailable") > 0 then
		-- Consume revive
		local revivesLeft = player:GetAttribute("RevivesAvailable") - 1
		player:SetAttribute("RevivesAvailable", revivesLeft)
		
		-- Set revive flag
		player:SetAttribute("JustRevived", true)
		player:SetAttribute("RevivingNow", true)
		
		-- Respawn player
		player:LoadCharacter()
	else
		-- Normal respawn
		player:SetAttribute("JustRevived", false)
		player:SetAttribute("RevivingNow", false)
		player:LoadCharacter()
	end
end)

return {
	hasGamepass = hasGamepass,
	applyGamepassBenefits = applyGamepassBenefits
}