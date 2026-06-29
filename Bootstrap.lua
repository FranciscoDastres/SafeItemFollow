local addonName, NS = ...

NS.ADDON_NAME = addonName
NS.VERSION = "0.1.0"
NS.DAY_SECONDS = 86400
NS.DEFAULT_PER_PAGE = 50

NS.Addon = LibStub("AceAddon-3.0"):NewAddon(
    "SafeItemFollow",
    "AceConsole-3.0"
)

NS.Store = nil
