# Script Placement Guide for Slither.io

## Server Scripts (ServerScriptService)
These scripts run on the server and handle game logic:

- `SnakeCollisionHandler.lua` - Handles all collision detection between snakes
- `AISnake.lua` - AI snake logic and movement
- `AISnakeSpawner.lua` - Spawns AI snakes
- `OrbSpawner.lua` - Spawns orbs on the map
- `SnakeNetworkHandler.lua` - Handles network communication
- `GamepassHandler.lua` - Manages gamepass purchases
- `LeaderboardManager.lua` - Updates leaderboard
- `SlitherIOMapBuilder.lua` - Creates the game map
- `SnakeSystemIntegration.lua` - Integrates all snake systems

## Client Scripts (StarterPlayer > StarterPlayerScripts)
These scripts run on each player's client:

- `ClientAISnakeLOD.lua` - Manages AI snake visibility for performance
- `OptimizedSnakeSystem.lua` - Visual snake rendering system
- `CameraController.lua` - Controls camera movement
- `MobileHUD.lua` - Mobile controls interface
- `SlitherIOMenu.lua` - Main menu interface
- `ShopUI.lua` - Shop interface
- `RewardUI.lua` - Reward notifications
- `OrbClientGraphics.lua` - Orb visual effects
- `VFXManager.lua` - Visual effects manager

## Shared Scripts (ReplicatedStorage)
These can be accessed by both server and client:

- `SnakeConfig.lua` - Game configuration
- `OrbUtils.lua` - Orb utility functions
- `SnakeUpgrades.lua` - Upgrade definitions
- `SnakeSkins.lua` - Skin system
- `SnakeSkinsData.lua` - Skin data
- `UnifiedSkinSystem.lua` - Skin management
- `ShopItems.lua` - Shop item definitions

## Character Scripts (StarterPlayer > StarterCharacterScripts)
These run when a player's character spawns:

- `CleanCharacterSetup.lua` - Prepares character for snake
- `SnakeMovement.lua` - Player snake controls

## Key Points:
1. **SnakeCollisionHandler.lua** must be in ServerScriptService
2. **ClientAISnakeLOD.lua** must be in StarterPlayerScripts
3. The collision detection from AISnake has been removed - all collisions are handled by SnakeCollisionHandler
4. Make sure all scripts have the `.lua` extension when placing them in Roblox Studio