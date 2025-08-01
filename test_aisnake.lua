-- Test script to verify AISnake module loads correctly
local function testAISnake()
    -- Mock required services and objects
    _G.game = {
        GetService = function(_, serviceName)
            if serviceName == "RunService" then
                return {
                    Heartbeat = {
                        Connect = function() return {Disconnect = function() end} end,
                        Wait = function() end
                    },
                    IsServer = function() return true end,
                    IsClient = function() return false end,
                    IsStudio = function() return false end
                }
            elseif serviceName == "Players" then
                return {
                    LocalPlayer = nil
                }
            elseif serviceName == "ReplicatedStorage" then
                return {
                    WaitForChild = function() return {} end,
                    FindFirstChild = function() return nil end
                }
            elseif serviceName == "Workspace" or serviceName == "workspace" then
                return {
                    CurrentCamera = {
                        CFrame = {
                            Position = {x = 0, y = 0, z = 0}
                        }
                    }
                }
            elseif serviceName == "TweenService" then
                return {
                    Create = function() return {Play = function() end} end
                }
            elseif serviceName == "UserInputService" then
                return {}
            end
            return {}
        end
    }
    
    _G.workspace = _G.game:GetService("Workspace")
    
    -- Try to load the module
    local success, result = pcall(function()
        return dofile("AISnake.lua")
    end)
    
    if success then
        print("✓ AISnake module loaded successfully!")
        print("✓ No UserSettings errors found")
    else
        print("✗ Error loading AISnake module:")
        print(result)
    end
end

testAISnake()