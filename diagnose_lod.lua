--[[
    LOD Diagnostic Script
    
    This script will help identify where the UserSettings error is coming from
    and verify that the LOD fix has been properly applied.
    
    Instructions:
    1. Run this as a Script in ServerScriptService
    2. Check the output for any issues
    3. The script will also attempt to patch any problematic code it finds
]]

local function diagnoseAndFix()
    print("=== LOD DIAGNOSTIC SCRIPT STARTING ===")
    
    -- Check if we're on server
    local RunService = game:GetService("RunService")
    if RunService:IsClient() then
        warn("This script should run on the server, not the client!")
        return
    end
    
    print("✓ Running on server")
    
    -- Try to find the AISnake module
    local function findAISnakeModule()
        -- Common locations to check
        local locations = {
            game.ServerScriptService,
            game.ServerStorage,
            game.ReplicatedStorage,
            workspace
        }
        
        for _, location in ipairs(locations) do
            local module = location:FindFirstChild("AISnake", true)
            if module and module:IsA("ModuleScript") then
                return module
            end
        end
        
        return nil
    end
    
    local aiSnakeModule = findAISnakeModule()
    if not aiSnakeModule then
        warn("✗ Could not find AISnake module!")
        print("Make sure the AISnake module is in ServerScriptService, ServerStorage, ReplicatedStorage, or Workspace")
        return
    end
    
    print("✓ Found AISnake module at:", aiSnakeModule:GetFullName())
    
    -- Check the module source for UserSettings
    local source = aiSnakeModule.Source
    if string.find(source, "UserSettings%(%)") then
        warn("✗ Found UserSettings reference in the module!")
        print("Attempting to auto-fix...")
        
        -- Replace the problematic code
        local fixedSource = string.gsub(source, 
            "local qualityFactor = UserSettings%(%)%.GameSettings%.SavedQualityLevel%.Value / 10",
            "local qualityFactor = 0.7 -- Fixed value, was using UserSettings which is client-only"
        )
        
        -- Also replace any beam quality calculations that use UserSettings
        fixedSource = string.gsub(fixedSource,
            "UserSettings%(%)%.GameSettings%.SavedQualityLevel%.Value",
            "7 -- Fixed value (was UserSettings)"
        )
        
        -- Try to update the module
        local success, err = pcall(function()
            aiSnakeModule.Source = fixedSource
        end)
        
        if success then
            print("✓ Successfully patched AISnake module!")
            print("The UserSettings references have been removed.")
        else
            warn("✗ Could not auto-patch the module:", err)
            print("You'll need to manually update the syncBeamVisibility function")
        end
    else
        print("✓ No UserSettings references found in the module source")
    end
    
    -- Test the module
    print("\nTesting module...")
    local success, result = pcall(function()
        return require(aiSnakeModule)
    end)
    
    if success then
        print("✓ Module loaded successfully!")
        
        -- Try to create a test instance
        if type(result) == "table" and result.new then
            local testSuccess, testErr = pcall(function()
                -- Mock required objects
                local mockHead = Instance.new("Part")
                mockHead.Name = "Head"
                mockHead.Parent = workspace
                
                local mockModel = Instance.new("Model")
                mockModel.Name = "TestSnake"
                mockModel.Parent = workspace
                
                -- Create test instance
                local testSnake = result.new(mockModel, mockHead, {
                    SnakeColor = Color3.new(1, 0, 0),
                    CurrentLength = 10,
                    OwnerName = "TestPlayer"
                })
                
                print("✓ Successfully created test AISnake instance!")
                
                -- Clean up
                wait(1)
                mockModel:Destroy()
                mockHead:Destroy()
            end)
            
            if not testSuccess then
                warn("✗ Error creating test instance:", testErr)
            end
        end
    else
        warn("✗ Error loading module:", result)
    end
    
    print("\n=== DIAGNOSTIC COMPLETE ===")
    print("\nIf you're still seeing UserSettings errors:")
    print("1. Make sure you've updated the AISnake module with the fixed code")
    print("2. Check for any other scripts that might be calling UserSettings")
    print("3. Restart Studio/republish the place to clear any cached code")
end

-- Run diagnostic
diagnoseAndFix()