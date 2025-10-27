# AISnake LOD Fix Instructions

## The Problem
Your AISnake module has a LOD (Level of Detail) issue where:
1. Body segments disappear but beams remain visible
2. There's a `UserSettings` error occurring on the server

## The Error
```
UserSettings is not a valid member of DataModel "nil"
```

This happens because `UserSettings()` is a client-only API that cannot be used on the server.

## The Solution

### Option 1: Quick Fix (Recommended)
1. Open your AISnake module in Roblox Studio
2. Press `Ctrl+F` (or `Cmd+F` on Mac) to open Find
3. Search for `UserSettings`
4. You should find code like this around line 3280 in the `syncBeamVisibility` function:
   ```lua
   local qualityFactor = UserSettings().GameSettings.SavedQualityLevel.Value / 10
   ```
5. Delete or comment out that line and replace it with:
   ```lua
   local qualityFactor = 0.7 -- Fixed value, was using UserSettings which is client-only
   ```

### Option 2: Use the Diagnostic Script
1. Copy the contents of `diagnose_lod.lua` 
2. Create a new Script in ServerScriptService
3. Paste the code and run it
4. It will automatically find and attempt to fix the issue

### Option 3: Full Function Replacement
Replace your entire `syncBeamVisibility` function with the one in `AISnake_FIXED.lua`

## Verification Steps
After applying the fix:

1. **Check for errors**: There should be no more UserSettings errors in the output
2. **Test LOD**: Move camera away from AI snakes - segments should disappear along with their beams
3. **Performance**: The game should run smoothly with proper LOD culling

## Additional Notes

- The fix replaces client-specific quality settings with a fixed quality factor
- Beam visibility is now properly synchronized with segment visibility
- The solution works on both client and server environments

## If Problems Persist

1. Make sure you saved the module after editing
2. Restart Roblox Studio to clear any cached code
3. Check if there are multiple copies of the AISnake module
4. Ensure you're editing the correct module that's actually being used
5. Look for other scripts that might be creating the UserSettings error

## What Changed

The main changes in the fixed version:
- Removed `UserSettings().GameSettings.SavedQualityLevel.Value` references
- Added proper bounds checking for segments and beams
- Ensured beams are disabled when their connected segments are hidden
- Simplified beam quality calculations to work on both client and server