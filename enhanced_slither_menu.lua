--[[
BEAUTIFUL SLITHER.IO MENU V5.0 - ULTIMATE EDITION

- Ultra-modern glass morphism design with animations
- Enhanced username system like real slither.io
- Premium daily rewards with streak animations
- Advanced particle system with multiple effects
- Customizable color themes with live preview
- Responsive UI with smooth transitions
- Performance optimizations
- Achievement system
- Enhanced leaderboard with avatars
- Social features (friends, clans)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

-- Enhanced Configuration
local CONFIG = {
    MENU_VERSION = "5.0",
    DEFAULT_THEME = "neon_green",
    DEFAULT_USERNAME = "Player",
    MAX_USERNAME_LENGTH = 16,
    THEMES = {
        neon_green = {
            primary = Color3.fromRGB(0, 255, 127),
            secondary = Color3.fromRGB(46, 213, 115),
            accent = Color3.fromRGB(123, 237, 159),
            glow = Color3.fromRGB(0, 255, 0),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(11, 19, 43),
                Color3.fromRGB(28, 37, 65),
                Color3.fromRGB(58, 80, 107),
                Color3.fromRGB(91, 192, 190)
            }
        },
        cyber_blue = {
            primary = Color3.fromRGB(0, 184, 255),
            secondary = Color3.fromRGB(0, 144, 255),
            accent = Color3.fromRGB(100, 200, 255),
            glow = Color3.fromRGB(0, 100, 255),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(15, 23, 42),
                Color3.fromRGB(30, 41, 59),
                Color3.fromRGB(51, 65, 85),
                Color3.fromRGB(100, 116, 139)
            }
        },
        royal_purple = {
            primary = Color3.fromRGB(147, 51, 234),
            secondary = Color3.fromRGB(124, 58, 237),
            accent = Color3.fromRGB(167, 139, 250),
            glow = Color3.fromRGB(200, 100, 255),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(31, 25, 52),
                Color3.fromRGB(55, 48, 163),
                Color3.fromRGB(79, 70, 229),
                Color3.fromRGB(124, 58, 237)
            }
        },
        crimson_red = {
            primary = Color3.fromRGB(239, 68, 68),
            secondary = Color3.fromRGB(220, 38, 38),
            accent = Color3.fromRGB(252, 165, 165),
            glow = Color3.fromRGB(255, 0, 0),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(69, 10, 10),
                Color3.fromRGB(127, 29, 29),
                Color3.fromRGB(185, 28, 28),
                Color3.fromRGB(239, 68, 68)
            }
        },
        sunset_orange = {
            primary = Color3.fromRGB(251, 146, 60),
            secondary = Color3.fromRGB(249, 115, 22),
            accent = Color3.fromRGB(254, 215, 170),
            glow = Color3.fromRGB(255, 150, 0),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(69, 26, 3),
                Color3.fromRGB(124, 45, 18),
                Color3.fromRGB(194, 65, 12),
                Color3.fromRGB(251, 146, 60)
            }
        },
        cosmic_pink = {
            primary = Color3.fromRGB(236, 72, 153),
            secondary = Color3.fromRGB(219, 39, 119),
            accent = Color3.fromRGB(251, 207, 232),
            glow = Color3.fromRGB(255, 0, 150),
            text = Color3.fromRGB(255, 255, 255),
            background = {
                Color3.fromRGB(80, 7, 36),
                Color3.fromRGB(131, 24, 67),
                Color3.fromRGB(190, 24, 93),
                Color3.fromRGB(236, 72, 153)
            }
        }
    },
    PARTICLE_COUNT = 50,
    PARTICLE_TYPES = {"circle", "square", "triangle", "star", "hexagon", "snake"},
    MAX_FPS = 60,
    LEADERBOARD_REFRESH_RATE = 2,
    DAILY_REWARD_KEY = "SlitherIO_DailyReward_V5",
    SETTINGS_KEY = "SlitherIO_Settings_V5",
    STATS_KEY = "SlitherIO_Stats_V5",
    USERNAME_KEY = "SlitherIO_Username_V5",
    ACHIEVEMENTS_KEY = "SlitherIO_Achievements_V5",
    ACHIEVEMENT_LIST = {
        {id = "first_kill", name = "First Blood", desc = "Get your first kill", icon = "🗡️"},
        {id = "snake_10", name = "Growing Snake", desc = "Reach length 10", icon = "🐍"},
        {id = "snake_50", name = "Long Boy", desc = "Reach length 50", icon = "🐉"},
        {id = "snake_100", name = "Legendary Serpent", desc = "Reach length 100", icon = "👑"},
        {id = "survivor", name = "Survivor", desc = "Survive for 5 minutes", icon = "⏱️"},
        {id = "killer_5", name = "Snake Hunter", desc = "Get 5 kills in one game", icon = "💀"},
        {id = "killer_10", name = "Apex Predator", desc = "Get 10 kills in one game", icon = "🦾"},
        {id = "top_3", name = "Podium Finish", desc = "Reach top 3 on leaderboard", icon = "🥉"},
        {id = "champion", name = "Champion", desc = "Reach #1 on leaderboard", icon = "🏆"},
        {id = "streak_7", name = "Week Warrior", desc = "7 day login streak", icon = "🔥"}
    }
}

-- Enhanced tracking variables
local activeDeathHandler = nil
local currentMenu = nil
local isProcessingDeath = false
local currentTheme = CONFIG.DEFAULT_THEME
local currentUsername = CONFIG.DEFAULT_USERNAME
local playerStats = {
    highScore = 0,
    totalKills = 0,
    gamesPlayed = 0,
    longestSnake = 0,
    timeAlive = 0,
    totalScore = 0,
    avgScore = 0,
    bestKillStreak = 0,
    totalDeaths = 0
}
local dailyReward = {
    lastClaimed = 0,
    streak = 0,
    available = false,
    totalClaimed = 0
}
local settings = {
    graphicsMode = "High",
    soundEnabled = true,
    musicEnabled = true,
    particlesEnabled = true,
    showFPS = true,
    theme = CONFIG.DEFAULT_THEME,
    controlMode = "Mouse",
    username = CONFIG.DEFAULT_USERNAME,
    showGrid = true,
    reducedMotion = false,
    minimap = true
}
local achievements = {}
local menuSounds = {}

-- Preload assets and sounds
local function preloadAssets()
    local assets = {
        "rbxassetid://7072718362", -- Glow
        "rbxassetid://7072719338", -- Particle
        "rbxassetid://7072720023", -- Star
        "rbxassetid://7072725648", -- Circle
        "rbxassetid://6035067837", -- Button hover sound
        "rbxassetid://6035067839", -- Button click sound
        "rbxassetid://6035067841", -- Achievement unlock sound
        "rbxassetid://6035067843", -- Reward claim sound
    }
    
    ContentProvider:PreloadAsync(assets)
    
    -- Create menu sounds
    menuSounds.hover = Instance.new("Sound")
    menuSounds.hover.SoundId = "rbxassetid://6035067837"
    menuSounds.hover.Volume = 0.3
    menuSounds.hover.Parent = SoundService
    
    menuSounds.click = Instance.new("Sound")
    menuSounds.click.SoundId = "rbxassetid://6035067839"
    menuSounds.click.Volume = 0.4
    menuSounds.click.Parent = SoundService
    
    menuSounds.achievement = Instance.new("Sound")
    menuSounds.achievement.SoundId = "rbxassetid://6035067841"
    menuSounds.achievement.Volume = 0.5
    menuSounds.achievement.Parent = SoundService
    
    menuSounds.reward = Instance.new("Sound")
    menuSounds.reward.SoundId = "rbxassetid://6035067843"
    menuSounds.reward.Volume = 0.5
    menuSounds.reward.Parent = SoundService
end

-- Hide default Roblox UI
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- Save/Load functions for username
local function saveUsername()
    pcall(function()
        if writefile then
            writefile(CONFIG.USERNAME_KEY .. ".txt", currentUsername)
        end
        settings.username = currentUsername
    end)
end

local function loadUsername()
    pcall(function()
        if readfile and isfile and isfile(CONFIG.USERNAME_KEY .. ".txt") then
            currentUsername = readfile(CONFIG.USERNAME_KEY .. ".txt")
            settings.username = currentUsername
        end
    end)
end

-- Enhanced save/load functions
local function saveSettings()
    pcall(function()
        local encoded = HttpService:JSONEncode(settings)
        if writefile then
            writefile(CONFIG.SETTINGS_KEY .. ".json", encoded)
        end
    end)
end

local function loadSettings()
    pcall(function()
        if readfile and isfile and isfile(CONFIG.SETTINGS_KEY .. ".json") then
            local content = readfile(CONFIG.SETTINGS_KEY .. ".json")
            local decoded = HttpService:JSONDecode(content)
            
            for key, value in pairs(decoded) do
                settings[key] = value
            end
            
            currentTheme = settings.theme or CONFIG.DEFAULT_THEME
            currentUsername = settings.username or CONFIG.DEFAULT_USERNAME
        end
    end)
end

local function savePlayerStats()
    pcall(function()
        -- Calculate average score
        if playerStats.gamesPlayed > 0 then
            playerStats.avgScore = math.floor(playerStats.totalScore / playerStats.gamesPlayed)
        end
        
        local encoded = HttpService:JSONEncode(playerStats)
        if writefile then
            writefile(CONFIG.STATS_KEY .. ".json", encoded)
        end
    end)
end

local function loadPlayerStats()
    pcall(function()
        if readfile and isfile and isfile(CONFIG.STATS_KEY .. ".json") then
            local content = readfile(CONFIG.STATS_KEY .. ".json")
            local decoded = HttpService:JSONDecode(content)
            
            for key, value in pairs(decoded) do
                playerStats[key] = value
            end
        end
    end)
end

-- Achievement system
local function saveAchievements()
    pcall(function()
        local encoded = HttpService:JSONEncode(achievements)
        if writefile then
            writefile(CONFIG.ACHIEVEMENTS_KEY .. ".json", encoded)
        end
    end)
end

local function loadAchievements()
    pcall(function()
        if readfile and isfile and isfile(CONFIG.ACHIEVEMENTS_KEY .. ".json") then
            local content = readfile(CONFIG.ACHIEVEMENTS_KEY .. ".json")
            achievements = HttpService:JSONDecode(content)
        else
            -- Initialize achievements
            for _, achievement in ipairs(CONFIG.ACHIEVEMENT_LIST) do
                achievements[achievement.id] = {
                    unlocked = false,
                    unlockedAt = nil,
                    progress = 0
                }
            end
        end
    end)
end

local function unlockAchievement(achievementId, showNotification)
    if achievements[achievementId] and not achievements[achievementId].unlocked then
        achievements[achievementId].unlocked = true
        achievements[achievementId].unlockedAt = os.time()
        saveAchievements()
        
        if showNotification and menuSounds.achievement and settings.soundEnabled then
            menuSounds.achievement:Play()
        end
        
        return true
    end
    return false
end