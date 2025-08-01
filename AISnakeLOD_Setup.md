# AISnake LOD System Setup Instructions

## Overview
The AISnake LOD (Level of Detail) system has been migrated from server-side to client-side to fix synchronization issues between snake heads, beams, and attachments. This resolves the issue where snake heads become transparent while eyes and beams remain visible.

## Installation Steps

### 1. Place ClientAISnakeLOD Module
- Copy the `ClientAISnakeLOD` module to `StarterPlayer.StarterPlayerScripts`
- This ensures the LOD system runs on each client

### 2. Update AISnake Module
- The `AISnake` module has been modified to remove server-side LOD calculations
- Ensure you're using the updated version that includes:
  - Removed `updateSegmentVisibility` function (now deprecated)
  - Removed `syncBeamVisibility` function (now deprecated)
  - Removed `applyLODToSegment` function (now deprecated)
  - Model attributes for client communication

### 3. No Additional Configuration Required
- The system automatically detects AI snakes in the workspace
- LOD calculations are performed based on each player's camera position
- All visual updates are atomic to prevent desynchronization

## Key Improvements

### 1. Eliminated Server-Client Desync
- Visual calculations now happen instantly on the client
- No 100-200ms network delay between updates
- All components update in the same frame

### 2. Fixed Beam Rendering Independence
- Beams are now properly synchronized with segment visibility
- Width properties are set to 0 when hiding beams completely
- Original beam widths are stored and restored

### 3. Atomic Visibility Updates
- All visual components (segments, beams, attachments, eyes) update together
- Single-frame updates prevent partial visibility states
- Smooth transitions between LOD levels

### 4. Performance Optimizations
- Client-side calculations reduce server load
- LOD updates only when camera distance changes significantly
- Efficient snake detection and caching

## Technical Details

### LOD Distance Thresholds
- **Near (< 200 studs)**: 100% of snake visible
- **Mid (200-400 studs)**: 70-80% of snake visible
- **Far (400-600 studs)**: 40-50% of snake visible
- **Minimal (600-800 studs)**: 20-30% of snake visible
- **Very Far (> 800 studs)**: 10-15% of snake visible

### Update Intervals
- Visibility checks: Every 5 frames
- Beam synchronization: Every 30 frames
- Snake detection: Every 60 frames (1 second)

### Visibility Features
- Progressive segment culling based on distance
- Smooth transparency transitions
- Eye visibility tied to head distance
- Glow effects scale with distance

## Troubleshooting

### Issue: Snakes not updating LOD
- Verify ClientAISnakeLOD is in StarterPlayer.StarterPlayerScripts
- Check console for "✅ ClientAISnakeLOD initialized" message
- Ensure AI snake models have proper naming (AISnakeModel_*)

### Issue: Beams still visible when head is transparent
- Verify you're using the updated AISnake module
- Check that beams are parented to AISnakeAttachmentPart
- Ensure beam Width0/Width1 attributes are being set

### Issue: Performance concerns
- Adjust VISIBILITY_CHECK_INTERVAL for less frequent updates
- Reduce RENDER_DISTANCE to cull distant snakes earlier
- Modify DYNAMIC_SEGMENT_LIMIT for fewer physical segments

## Migration Notes

### From Server-Side LOD
1. The following server-side functions are now deprecated:
   - `AISnake:updateSegmentVisibility()`
   - `AISnake:syncBeamVisibility()`
   - `AISnake:applyLODToSegment()`

2. LOD state variables have been removed:
   - `segmentVisibility`
   - `lodStates`
   - `visibleSegmentCount`
   - `forcedRenderSegments`

3. All segments now start fully visible
   - LOD is applied client-side after creation
   - No server-side transparency modifications

### Compatibility
- The system is backward compatible
- Deprecated functions exist but do nothing
- No changes required to AISnakeSpawner or other modules

## Benefits Summary

1. **Instant Response**: LOD updates happen immediately on each client
2. **Perfect Sync**: All visual components update atomically
3. **Better Performance**: Server freed from visual calculations
4. **Scalability**: Each client only processes snakes in view
5. **Smooth Transitions**: Interpolated visibility changes

The new client-side LOD system provides a much smoother and more reliable visual experience while reducing server load and eliminating the head/beam desynchronization issues.