# Slither.io Revive System Setup Guide

## Overview
This revive system allows players to revive at 80% of their death length by using revives or purchasing them for 35 Robux.

## Setup Instructions

### 1. Create the Product in Roblox
1. Go to your game's page on Roblox
2. Click on "Store" → "Passes and Other Products" → "Developer Products"
3. Create a new Developer Product:
   - Name: "Revive"
   - Price: 35 Robux
   - Description: "Revive at 80% of your length!"
4. Copy the Product ID

### 2. Update the Scripts
1. In both `ReviveUI` and `SnakeDeathHandler`, replace `123456789` with your actual Product ID:
   ```lua
   REVIVE_PRODUCT_ID = YOUR_PRODUCT_ID_HERE
   ```

### 3. Script Placement
- `ReviveUI` → StarterPlayer > StarterPlayerScripts
- `SnakeDeathHandler` → ServerScriptService
- `SlitherIOMenu` → StarterPlayer > StarterPlayerScripts

### 4. How It Works

#### Death Flow:
1. Player dies → Snake length is captured
2. Server waits 0.5 seconds for death animation
3. ReviveUI appears showing:
   - "BRUH YOU DIED!"
   - "Your length: [death length]"
   - "Revive at [80% length] length!"
   - If has revives: "REVIVE" button
   - If no revives: "BUY REVIVE 35 🪙" button
4. 5 second timer to decide

#### Revive Options:
- **Has Revives**: Click "REVIVE" to respawn at 80% length
- **No Revives**: Click "BUY REVIVE 35" to purchase and auto-revive
- **Decline**: Click "RESPAWN" or let timer expire

#### Purchase Flow:
1. Click "BUY REVIVE 35"
2. Roblox purchase prompt appears
3. Timer pauses during purchase
4. If purchased: Auto-revives at 80% length
5. If cancelled: Timer resumes (3 seconds)

### 5. Testing
1. Set a test Product ID or use a test place
2. Give yourself a long snake (use admin commands)
3. Die and test the revive UI
4. Test both with and without revives

### 6. Important Notes
- The death handler needs to run AFTER the snake system initializes
- Make sure leaderstats with "Length" value exists
- The revive at 80% length is handled by setting `player:SetAttribute("ReviveLength", reviveLength)`
- Your snake spawning system should check for this attribute and set initial length accordingly

### 7. Integration with Snake System
When spawning a snake after revive, check for the ReviveLength attribute:

```lua
local function spawnSnake(player)
    local reviveLength = player:GetAttribute("ReviveLength")
    local initialLength = 10 -- default
    
    if reviveLength and reviveLength > 0 then
        initialLength = reviveLength
        player:SetAttribute("ReviveLength", 0) -- Clear after use
    end
    
    -- Create snake with initialLength
    local snake = SnakeSystem.createSnake(character, {
        InitialLength = initialLength,
        -- other config
    })
end
```

## Troubleshooting

### Length Not Showing:
- Check if leaderstats > Length exists
- Ensure SnakeDeathHandler is running
- Verify death length is being passed to ReviveUI

### Purchase Not Working:
- Verify Product ID is correct
- Check if product is active on Roblox
- Ensure MarketplaceService access is enabled

### Revive Not Working:
- Check RevivesAvailable attribute
- Verify PromptRevive RemoteEvent exists
- Check server console for errors