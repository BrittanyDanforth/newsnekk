# Slither.io Revive System - Complete Setup Guide

## Overview
A complete revive system that:
- Saves revives permanently using DataStore
- Shows death length and revive at 80%
- One-button system (REVIVE button auto-purchases if needed)
- 35 Robux per revive

## Required Components

### 1. Scripts to Install

#### A. **ReviveUI** (Client-Side)
- **Location**: StarterPlayer → StarterPlayerScripts
- **Purpose**: Shows the revive UI when player dies
- **Features**: 
  - Shows "BRUH YOU DIED!" message
  - Displays death length and 80% revive length
  - Single REVIVE button that auto-purchases if no revives

#### B. **SnakeDeathHandler** (Server-Side)
- **Location**: ServerScriptService
- **Purpose**: Handles death detection, revive logic, and data persistence
- **Features**:
  - Detects player death and captures length
  - Manages revive inventory with DataStore
  - Processes Robux purchases
  - Handles respawn at 80% length

#### C. **SlitherIOMenu** (Client-Side)
- **Location**: StarterPlayer → StarterPlayerScripts
- **Purpose**: Main menu that waits 6 seconds after death before showing

### 2. Roblox Product Setup

1. Go to your game page on Roblox.com
2. Click **Configure Experience** → **Monetization** → **Developer Products**
3. Click **Create Product**
4. Fill in:
   - **Name**: Revive
   - **Price**: 35 Robux
   - **Description**: Revive at 80% of your length!
   - **Icon**: (optional)
5. Click **Create** and copy the Product ID
6. Replace `3356734577` with your Product ID in both scripts

### 3. Required Game Structure

Your game needs:
```
Players
└── Player
    └── leaderstats (Folder)
        └── Length (IntValue) - Current snake length

ReplicatedStorage
└── Remotes (Folder) - Created automatically
    └── PromptRevive (RemoteEvent) - Created automatically
```

### 4. DataStore Access

**IMPORTANT**: DataStores don't work in Studio by default!

To test in Studio:
1. Game Settings → Security → Enable Studio Access to API Services
2. Publish the game to test DataStore properly

## Installation Steps

### Step 1: Install All Scripts
1. Copy **ReviveUI** to StarterPlayer → StarterPlayerScripts
2. Copy **SnakeDeathHandler** to ServerScriptService
3. Make sure **SlitherIOMenu** is in StarterPlayer → StarterPlayerScripts

### Step 2: Update Product IDs
In both ReviveUI and SnakeDeathHandler, find and replace:
```lua
REVIVE_PRODUCT_ID = 3356734577
```
With your actual product ID.

### Step 3: Integration with Snake System

Your snake spawning system needs to check for revive length:

```lua
-- When creating a snake after respawn
local function createSnake(player, character)
    local reviveLength = player:GetAttribute("ReviveLength")
    local initialLength = 10 -- default starting length
    
    if reviveLength and reviveLength > 0 then
        initialLength = reviveLength
        player:SetAttribute("ReviveLength", 0) -- Clear after use
        print("Spawning with revive length:", initialLength)
    end
    
    -- Create your snake with initialLength
    local snake = SnakeSystem.createSnake(character, {
        InitialLength = initialLength,
        -- other config
    })
    
    -- Make sure leaderstats updates
    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        local lengthValue = leaderstats:FindFirstChild("Length")
        if lengthValue then
            lengthValue.Value = initialLength
        end
    end
end
```

### Step 4: Verify Installation

Run this check script in the command bar:

```lua
-- Check if everything is set up correctly
print("=== REVIVE SYSTEM CHECK ===")

-- Check RemoteEvents
local remotes = game.ReplicatedStorage:FindFirstChild("Remotes")
if remotes then
    print("✓ Remotes folder exists")
    if remotes:FindFirstChild("PromptRevive") then
        print("✓ PromptRevive RemoteEvent exists")
    else
        print("✗ PromptRevive RemoteEvent missing")
    end
else
    print("✗ Remotes folder missing")
end

-- Check Scripts
if game.ServerScriptService:FindFirstChild("SnakeDeathHandler") then
    print("✓ SnakeDeathHandler installed")
else
    print("✗ SnakeDeathHandler missing from ServerScriptService")
end

-- Check DataStore access
local success = pcall(function()
    game:GetService("DataStoreService"):GetDataStore("TestStore"):GetAsync("test")
end)
if success then
    print("✓ DataStore access enabled")
else
    print("✗ DataStore access disabled (Enable Studio API Services)")
end

print("=== END CHECK ===")
```

## How The System Works

### Death Flow:
1. **Player Dies** → SnakeDeathHandler captures death length
2. **Wait 0.5s** → Death animation plays
3. **Prompt Revive** → ReviveUI appears with:
   - "BRUH YOU DIED!"
   - "Your length: X"
   - "Revive at Y length! (80% of X)"
   - Shows revive count
4. **5 Second Timer** → Auto-declines if no action

### Revive Flow:
1. **Click REVIVE**:
   - **Has Revives**: Uses one, respawns at 80% length
   - **No Revives**: Opens Robux purchase prompt
2. **Purchase Success**: Grants revive and auto-uses it
3. **Purchase Cancel**: Timer resumes (3 seconds)

### Data Persistence:
- Revives saved to DataStore
- Survives server restarts
- Auto-saves every 30 seconds
- Saves on purchase/use/leave

## Troubleshooting

### "I have revives but didn't buy any"
- You might have test data from previous sessions
- DataStore persists between Studio sessions
- To reset: Use command bar with your UserId:
  ```lua
  game:GetService("DataStoreService"):GetDataStore("PlayerRevives"):RemoveAsync("Player_YOUR_USER_ID")
  ```

### "Purchase not working"
1. Check Product ID is correct
2. Ensure product is active on Roblox
3. Test in published game (not just Studio)
4. Check F9 console for errors

### "Length shows as 0"
1. Ensure leaderstats → Length exists
2. Check snake system updates Length value
3. Verify SnakeDeathHandler is running

### "Menu appears too fast after death"
- SlitherIOMenu should wait 6 seconds
- Check death handler in SlitherIOMenu

### "Revives not saving"
1. Enable Studio API Services for testing
2. Check DataStore isn't throwing errors
3. Publish game to test properly

## Console Messages to Expect

When working correctly, you'll see:
```
Snake Death Handler loaded with persistent revive storage!
Loaded X revives for [PlayerName]
Player [PlayerName] died with length: X
Player has X revives available
REVIVE PROMPT RECEIVED! Death length: X
```

## API Reference

### Player Attributes Set by System:
- `RevivesAvailable` - Number of revives owned
- `LastLength` - Length at death
- `DeathLength` - Same as LastLength
- `ReviveLength` - Length to spawn with after revive
- `JustRevived` - True when reviving
- `RevivingNow` - True during revive process
- `ReviveDeclined` - True if declined revive
- `ReviveTimerExpired` - True if timer ran out

### RemoteEvents:
- `PromptRevive:FireClient(player, deathLength)` - Show revive UI
- `PromptRevive:FireServer(response)` - Response: "revive" or "decline"