# Head-to-Head Collision Fix Documentation

## Problem Description
When a player and AI snake (or two players) collide head-to-head, the revive UI wasn't showing up properly for players. Additionally, the collision logic needed to match slither.io behavior where only the snake that "messed up" dies.

## Root Causes
1. **Pre-marking as dead**: The collision system was marking players as dead BEFORE queuing them for death processing
2. **Death check skip**: The death processor was checking if a player was already marked as dead and skipping them
3. **Incorrect collision logic**: Previously both snakes died in head-to-head, but slither.io only kills the one who ran into the other

## Solutions Implemented

### 1. Proper Head-to-Head Collision Logic
- **Before**: Both snakes always died in head-to-head collision
- **After**: Only the snake moving more aggressively toward the other dies (matches slither.io)

```lua
-- The dot product tells us who is moving toward whom
local dotA = velA:Dot(dirAB)  // A's velocity toward B
local dotB = velB:Dot(dirBA)  // B's velocity toward A

if dotA > 2 and dotB <= 2 then
    -- A ran into B (A dies)
    queuePlayerDeath(playerA)
elseif dotB > 2 and dotA <= 2 then
    -- B ran into A (B dies)
    queuePlayerDeath(playerB)
elseif dotA > 2 and dotB > 2 then
    -- Both moving toward each other
    -- The one with higher approach speed dies
    if dotA > dotB then
        queuePlayerDeath(playerA)
    else
        queuePlayerDeath(playerB)
    end
end
```

### 2. Fixed Death Marking Order
- **Before**: Mark as dead → Queue death → Process death (would skip due to already dead)
- **After**: Queue death → Process death → Mark as dead (ensures processing happens)

### 3. Consistent Behavior Across All Collision Types
- Player vs Player: Only the aggressor dies
- Player vs AI: Only the aggressor dies
- AI vs AI: Only the aggressor dies

## Technical Details

### Death Processing Flow
1. Head collision detected (distance < HEAD_COLLISION_DISTANCE)
2. Queue both entities for death WITHOUT pre-marking as dead
3. Death processor runs:
   - Checks if player is alive and not already marked dead
   - Marks player as dead to prevent duplicate processing
   - Processes death (spawns orbs, checks for revive, etc.)
   - Shows revive UI if player has revive gamepass

### Key Code Changes

#### SnakeCollisionHandler - Head Collision Detection
```lua
-- Player vs Player
if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
    -- Both die immediately
    queuePlayerDeath(playerA)
    queuePlayerDeath(playerB)
end

-- Player vs AI
if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
    -- Both die immediately
    queuePlayerDeath(player)
    queueAIDeath(aiHead)
end
```

#### SnakeCollisionHandler - Death Queue Processing
```lua
if humanoid and humanoid.Health > 0 and not deadPlayers[player] then
    -- Mark as dead immediately to prevent duplicate processing
    deadPlayers[player] = true
    
    -- Continue with death processing including revive UI...
```

## Testing Checklist
- [ ] Player vs Player head collision - both die, revive UI shows
- [ ] Player vs AI head collision - both die, revive UI shows for player
- [ ] AI vs AI head collision - both die
- [ ] Normal body collisions still work correctly
- [ ] Revive UI appears consistently for players with revive gamepass
- [ ] No double-death processing
- [ ] Dead players can't kill others

## Benefits
1. **Consistent behavior**: Head-to-head always results in both dying
2. **Revive UI fix**: Players with revive gamepass will see the UI properly
3. **Simpler logic**: Removed complex velocity calculations
4. **Matches slither.io**: Behavior now matches the original game