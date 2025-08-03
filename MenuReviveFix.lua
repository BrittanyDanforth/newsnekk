-- MenuReviveFix - Client-side handler to prevent menu from showing during revives
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- Get remotes folder
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hideMenuRemote = remotes:WaitForChild("HideMenu", 5)

if hideMenuRemote then
	hideMenuRemote.OnClientEvent:Connect(function()
		print("📱 HideMenu event received - suppressing menu for revive")
		
		-- Find and destroy any existing menu
		local playerGui = LocalPlayer:WaitForChild("PlayerGui")
		local existingMenu = playerGui:FindFirstChild("SlitherIOMenu")
		if existingMenu then
			existingMenu:Destroy()
			print("✅ Menu destroyed for revive")
		end
		
		-- Also check for any menu frames
		for _, child in pairs(playerGui:GetChildren()) do
			if child.Name:match("Menu") or child.Name:match("menu") then
				child:Destroy()
			end
		end
	end)
	
	print("✅ MenuReviveFix loaded - will suppress menu during revives")
else
	warn("⚠️ HideMenu remote not found - menu may flash during revives")
end