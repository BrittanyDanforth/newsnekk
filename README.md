# NewSnekk - Slither.io Style Game

## Setup Instructions

### Important File Locations:

1. **ServerScriptService:**
   - `GamepassHandler` - Handles all gamepass logic
   - `OrbSpawner` - Spawns and manages orbs
   - `SnakeCollisionHandler.lua` - Handles snake collisions and death

2. **ReplicatedStorage:**
   - `InventoryUI` - The inventory system (ModuleScript)
   - `ShopUI` - Shop interface (ModuleScript)
   - `SnakeSkins` - Snake skin data (ModuleScript)
   - Other snake-related modules

3. **StarterPlayer > StarterPlayerScripts:**
   - `ReviveUI` - Shows revive prompt when you die (IMPORTANT!)
   - `SlitherIOMenu` - Main menu system
   - Other client scripts

### Gamepass Setup:

The Magnet gamepass (ID: 1335069823) is working. Other gamepass IDs need to be replaced in `GamepassHandler`:
- Replace placeholder IDs (123456789, etc.) with your real gamepass IDs
- The system supports: Lifeline Boost, Mega Speed, 2x Growth, 2x Coins, Magnet, Ghost Mode, VIP Access, Revive

### Features:

- **Magnet Gamepass**: 5x collection range with visual effects, can be toggled on/off in inventory
- **Inventory System**: Press 'I' to open, shows all owned skins, items, and gamepasses
- **Revive System**: If you have the Revive gamepass, you get a 5-second prompt to revive when you die

### Notes:

- Make sure `ReviveUI` is in StarterPlayerScripts for the revive prompt to work!
- The SlitherIOMenu will wait 6 seconds before showing if you have revives available
- Magnet visual effect shows as a purple ring on the ground around your snake
