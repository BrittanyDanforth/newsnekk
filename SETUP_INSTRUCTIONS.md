# AI Snake Setup Instructions

## Overview
The AI Snake system consists of two main components:
1. **AISnake_Fixed.lua** - The main AI Snake module (goes in ReplicatedStorage)
2. **AISnakeSpawner.lua** - The spawner script (goes in ServerScriptService)

## Setup Steps

### 1. Place the AISnake Module
- Copy the contents of `AISnake_Fixed.lua`
- In Roblox Studio, create a new ModuleScript in ReplicatedStorage
- Name it exactly: `AISnake_Fixed`
- Paste the code into the module

### 2. Place the Spawner Script
- Copy the contents of `AISnakeSpawner.lua`
- In Roblox Studio, create a new Script in ServerScriptService
- Name it: `AISnakeSpawner` (or any name you prefer)
- Paste the code into the script

### 3. Required Dependencies
Make sure you have these modules in ReplicatedStorage:
- `SnakeConfig` - Configuration for snake appearance and behavior
- `OrbUtils` - Utilities for spawning orbs
- `SnakeUpgrades` (optional) - For upgrade orb functionality
- `AISnakeOrbPickup` (optional) - For additional orb pickup functionality

### 4. Required Workspace Objects
The AI snakes expect these objects in Workspace:
- `SlitherIOGround` - A part that defines the play area
- `OrbFolder` or `Orbs` - Folder containing orb objects (optional)

## Troubleshooting

### Snakes Not Spawning
1. Check the Output window for errors
2. Verify all required modules exist in ReplicatedStorage
3. Make sure the module is named exactly `AISnake_Fixed`
4. Check that `SlitherIOGround` exists in Workspace

### Performance Issues
1. Reduce `NUM_SNAKES` in the spawner script (default is 8)
2. Increase `INITIAL_SPAWN_DELAY` to space out spawns more
3. The system is optimized for up to 10 AI snakes

### AI Behavior
The AI snakes have 8 different personality types:
- **Aggressor** - Balanced fighter
- **Scavenger** - Peaceful orb collector
- **Guardian** - Territory defender
- **Opportunist** - Only attacks smaller snakes
- **Hunter** - Persistent tracker
- **Nomad** - Map explorer
- **Shadow** - Stealthy assassin
- **Berserker** - Reckless fighter

Each AI snake randomly selects a personality when spawned.

## Configuration

### In AISnakeSpawner.lua:
```lua
local NUM_SNAKES = 8          -- Number of AI snakes
local SPAWN_RADIUS = 250      -- Spawn area radius
local RESPAWN_DELAY = 5       -- Seconds before respawning
```

### In AISnake_Fixed.lua:
```lua
local MAX_AI_SNAKES = 10      -- Maximum AI snakes allowed
```

## Features
- Smooth, realistic snake movement
- Smart collision avoidance
- Boundary detection and avoidance
- Orb collection with growth
- Combat with players and other AI snakes
- Auto-respawning when killed
- 8 unique AI personalities
- Optimized performance