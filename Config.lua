local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local Config = {}
NS.Config = Config

local defaults = {
    global = {
        realms = {},
    },
    profile = {
        retentionDays = 30,
        flipMargin = 0,
        autoScanOnOpen = true,
        showTooltips = true,
        showOverlays = true,
        showMinimapButton = true,
    },
}

local function GetRealmNameSafe()
    if type(GetRealmName) == "function" then
        local realm = GetRealmName()
        if realm and realm ~= "" then
            return realm
        end
    end
    return "UnknownRealm"
end

local function GetFactionSafe()
    if type(UnitFactionGroup) == "function" then
        local faction = UnitFactionGroup("player")
        if faction and faction ~= "" then
            return faction
        end
    end
    return "Neutral"
end

local function RefreshStore()
    if not Addon.db then
        return
    end
    NS.Store = NS.Data.GetStore(Addon.db.global, Config:RealmKey())
end

local function NotifyChanged()
    RefreshStore()
    if NS.Overlay then
        NS.Overlay:RefreshVisible()
    end
    if NS.MinimapButton then
        NS.MinimapButton:Refresh()
    end
    if NS.Core then
        NS.Core:RefreshActiveTab()
    end
end

function Config:RealmKey()
    return GetRealmNameSafe() .. "-" .. GetFactionSafe()
end

function Config:Settings()
    if Addon.db and Addon.db.profile then
        return Addon.db.profile
    end
    return defaults.profile
end

function Config:InitializeDatabase()
    Addon.db = LibStub("AceDB-3.0"):New("SafeItemFollowDB", defaults, true)
    RefreshStore()
end

function Config:RegisterOptions()
    local options = {
        type = "group",
        name = L.CONFIG_NAME,
        args = {
            description = {
                type = "description",
                name = L.ADDON_DESCRIPTION,
                order = 1,
            },
            retentionDays = {
                type = "range",
                name = L.CONFIG_RETENTION,
                desc = L.CONFIG_RETENTION_DESC,
                order = 10,
                min = 1,
                max = 365,
                step = 1,
                get = function() return Config:Settings().retentionDays end,
                set = function(_, value)
                    Config:Settings().retentionDays = value
                    if NS.Store then
                        NS.Data.Purge(NS.Store, NS.Data.DayKey(Config:GetServerTime()), value)
                    end
                    NotifyChanged()
                end,
            },
            flipMargin = {
                type = "range",
                name = L.CONFIG_FLIP_MARGIN,
                desc = L.CONFIG_FLIP_MARGIN_DESC,
                order = 20,
                min = 0,
                max = 100000,
                step = 1,
                get = function() return Config:Settings().flipMargin end,
                set = function(_, value)
                    Config:Settings().flipMargin = value
                    NotifyChanged()
                end,
            },
            autoScanOnOpen = {
                type = "toggle",
                name = L.CONFIG_AUTO_SCAN,
                desc = L.CONFIG_AUTO_SCAN_DESC,
                order = 30,
                get = function() return Config:Settings().autoScanOnOpen end,
                set = function(_, value) Config:Settings().autoScanOnOpen = value end,
            },
            tooltips = {
                type = "toggle",
                name = L.CONFIG_TOOLTIPS,
                order = 40,
                get = function() return Config:Settings().showTooltips ~= false end,
                set = function(_, value) Config:Settings().showTooltips = value end,
            },
            overlays = {
                type = "toggle",
                name = L.CONFIG_OVERLAYS,
                order = 50,
                get = function() return Config:Settings().showOverlays ~= false end,
                set = function(_, value)
                    Config:Settings().showOverlays = value
                    NotifyChanged()
                end,
            },
            minimapButton = {
                type = "toggle",
                name = L.CONFIG_MINIMAP_BUTTON,
                order = 60,
                get = function() return Config:Settings().showMinimapButton ~= false end,
                set = function(_, value)
                    Config:Settings().showMinimapButton = value
                    NotifyChanged()
                end,
            },
        },
    }

    local profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(Addon.db)
    profileOptions.name = L.CONFIG_PROFILES
    profileOptions.order = 100
    options.args.profiles = profileOptions

    LibStub("AceConfig-3.0"):RegisterOptionsTable("SafeItemFollow", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SafeItemFollow", L.CONFIG_NAME)

    local function ProfileChanged()
        RefreshStore()
        NotifyChanged()
    end
    Addon.db.RegisterCallback(Addon, "OnProfileChanged", ProfileChanged)
    Addon.db.RegisterCallback(Addon, "OnProfileCopied", ProfileChanged)
    Addon.db.RegisterCallback(Addon, "OnProfileReset", ProfileChanged)
end

function Config:GetServerTime()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    if type(time) == "function" then
        return time()
    end
    return 0
end

function Config:Open()
    LibStub("AceConfigDialog-3.0"):Open("SafeItemFollow")
end
