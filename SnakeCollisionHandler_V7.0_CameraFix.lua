-- Add this code to your V7.0 SnakeCollisionHandler after line 890 (after the smooth death handling section)

-- CAMERA FIX: Stop camera movement when player dies
-- This should be added right after the "Smooth death handling" section around line 890

-- Add this right after the fade out effect (after the character parts are made invisible)
-- Around line 900, after the character fade out code:

-- CAMERA FIX: Lock camera when player dies
player:SetAttribute("CameraLocked", true)
print("📷 Camera locked for", player.Name)

-- The camera will automatically unlock when the player respawns because of the 
-- resetPlayerCollisionState function that's already in your V7.0 script

-- Also add this to the resetPlayerCollisionState function (around line 99):
-- player:SetAttribute("CameraLocked", false)