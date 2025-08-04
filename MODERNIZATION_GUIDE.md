# Snake Collision Handler Modernization Guide (2025)

## Overview

This guide documents the complete modernization of the SnakeCollisionHandler system, transforming it from a legacy implementation to a professional-grade system following 2025 Roblox development best practices.

## Key Architectural Changes

### 1. From Legacy APIs to Modern Standards

#### Before (Legacy):
```lua
wait(n)                      -- 30Hz scheduler, throttling issues
tick()                       -- Deprecated, client clock based
_G.PlayerSnakes             -- Global pollution
Event:connect()             -- Deprecated alias
while wait() do ... end     -- Frame-rate dependent
```

#### After (Modern):
```lua
task.wait(n)                -- Modern task scheduler
os.clock()                  -- High-precision CPU timer
local ActiveSnakes = {}     -- Module-scoped private data
Event:Connect()             -- PascalCase standard
RunService.Heartbeat        -- Frame-independent with deltaTime
```

### 2. From .Touched to Spatial Queries

#### Before (Unreliable):
```lua
part.Touched:Connect(function(hit)
    -- Deferred execution, unreliable for fast objects
    -- Can miss collisions entirely
end)
```

#### After (Professional):
```lua
function SnakeCollisionHandler:PerformSpatialQuery(head: BasePart, player: Player)
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local parts = workspace:GetPartBoundsInBox(
        CFrame.new(headPos),
        Vector3.new(radius * 2, radius * 2, radius * 2),
        overlapParams
    )
    -- Precise, volumetric hit detection
end
```

### 3. From Manual Cleanup to Trove Pattern

#### Before (Error-prone):
```lua
-- Manual cleanup scattered throughout code
connection:Disconnect()
part:Destroy()
-- Easy to miss items, causing memory leaks
```

#### After (Bulletproof):
```lua
local trove = Trove.new()
trove:Add(connection)
trove:Add(part)
trove:Add(customObject, "cleanup")

-- Single cleanup call handles everything
trove:Destroy()
```

### 4. From Naive Trust to Secure Hybrid Architecture

#### Before (Exploitable):
```lua
-- Client sends collision, server trusts it
RemoteEvent.OnServerEvent:Connect(function(player, hitData)
    -- Process collision without validation
    processCollision(hitData)
end)
```

#### After (Secure):
```lua
-- Client predicts for responsiveness
-- Server validates everything
function SnakeCollisionHandler:ValidateCollision(player: Player, collisionResult: CollisionResult)
    -- Sanity checks
    if not snakeData or snakeData.State ~= "alive" then
        return false
    end
    
    -- Physics validation
    local maxMovement = SnakeConfig.MaxSpeed * CONSTANTS.NETWORK_COMPENSATION
    if distance > maxMovement * 10 then
        warn("Suspicious collision distance")
        return false
    end
    
    return true
end
```

### 5. From Global State to Encapsulated Modules

#### Before (Unmaintainable):
```lua
_G.PlayerSnakes = {}
_G.CollisionData = {}
-- Any script can modify global state
```

#### After (Professional):
```lua
-- SnakeCollisionHandler.lua
local SnakeCollisionHandler = {}
local ActiveSnakes: {[Player]: SnakeData} = {} -- Private to module

-- Export only public API
return SnakeCollisionHandler
```

## Implementation Structure

### Server-Side Architecture

```
ServerScriptService/
├── SnakeGameServer.lua         -- Main initialization script
└── Modules/
    └── SnakeCollisionHandler.lua  -- Core collision module

ReplicatedStorage/
├── Modules/
│   ├── Trove.lua              -- Memory management utility
│   ├── SnakeConfig.lua        -- Game configuration
│   └── OrbUtils.lua           -- Orb spawning utilities
└── Remotes/
    ├── CollisionDetected      -- Client → Server collision report
    ├── SnakeDied             -- Server → All clients death notification
    ├── RequestRevive         -- Server → Client revive prompt
    └── ReviveResponse        -- Client → Server revive decision
```

### Client-Side Architecture

```
StarterPlayer/
└── StarterPlayerScripts/
    └── SnakeCollisionClient.lua  -- Client prediction system
```

## Core Features Implementation

### 1. Collision Detection System

- **Spatial Queries**: Uses `workspace:GetPartBoundsInBox()` for precise volumetric detection
- **Optimization**: OverlapParams filtering to reduce search space
- **Self-Collision Prevention**: Ignores first 10 segments to prevent false positives
- **Rate Limiting**: 20Hz server checks, 60Hz client prediction

### 2. Death & Cleanup Sequence

1. **State Management**: Three states - "alive", "dying", "dead"
2. **Revive System**: Integrated with proper state transitions
3. **Orb Spawning**: Calculated distribution based on snake length
4. **Trove Cleanup**: Guaranteed resource disposal

### 3. Client-Server Hybrid Model

- **Client**: Immediate visual/audio feedback via prediction
- **Server**: Authoritative validation and state changes
- **Network**: Optimized payload sizes, intent-based replication

## Performance Optimizations

### 1. Caching Strategy
- Player segment data cached for 1.5 seconds
- Spatial grid for large snakes (>200 segments)
- Frame-based collision cooldowns

### 2. Network Optimization
- Only snake head positions replicated
- Death events send minimal data (player + position)
- Client generates all visual effects locally

### 3. Memory Management
- Trove pattern prevents all memory leaks
- Automatic cleanup on player disconnect
- Periodic cache clearing

## Security Considerations

### 1. Input Validation
- All client reports validated server-side
- Physics-based sanity checks
- Rate limiting on remote events

### 2. State Authority
- Server maintains authoritative game state
- Client predictions never affect gameplay
- Exploit-resistant architecture

## Migration Guide

### For Existing Projects

1. **Replace Global Variables**:
   ```lua
   -- Old
   _G.PlayerSnakes[player] = snake
   
   -- New
   local ActiveSnakes = {}
   ActiveSnakes[player] = snakeData
   ```

2. **Update Event Connections**:
   ```lua
   -- Old
   part.Touched:connect(onTouch)
   
   -- New
   RunService.Heartbeat:Connect(function(dt)
       performSpatialQuery()
   end)
   ```

3. **Implement Trove Pattern**:
   ```lua
   -- Create Trove with snake
   local trove = Trove.new()
   snakeData.Trove = trove
   
   -- Add all resources
   trove:Add(connection)
   trove:Add(part)
   
   -- Clean up everything
   trove:Destroy()
   ```

## Testing Recommendations

### 1. Memory Leak Testing
- Monitor `gcinfo()` over extended sessions
- Verify cleanup after player disconnects
- Check for orphaned connections

### 2. Collision Accuracy
- Test high-speed collisions
- Verify self-collision prevention
- Validate head-to-head collision logic

### 3. Network Validation
- Test with simulated latency
- Attempt to send invalid collision data
- Verify server rejection of exploits

## Conclusion

This modernization transforms the SnakeCollisionHandler from a basic implementation into a robust, scalable system suitable for production games. By following 2025 best practices, the system is:

- **Secure**: Immune to common exploits
- **Performant**: Optimized for large-scale battles
- **Maintainable**: Clean architecture with clear separation of concerns
- **Reliable**: Guaranteed cleanup prevents memory leaks

The implementation serves as a template for professional Roblox development, demonstrating how to build systems that are both responsive for players and secure against exploitation.