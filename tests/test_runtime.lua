SlashCmdList = {}

local namespace = {
    Addon = {
        prints = {},
    },
}

function namespace.Addon:Print(message)
    self.prints[#self.prints + 1] = tostring(message)
end

assert(loadfile("Locales.lua"))("SafeItemFollow", namespace)
assert(loadfile("Core.lua"))("SafeItemFollow", namespace)

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

equal(SLASH_SAFEITEMFOLLOW1, "/safeitemfollow", "native long slash")
equal(SLASH_SAFEITEMFOLLOW2, "/sif", "native short slash")
equal(type(SlashCmdList.SAFEITEMFOLLOW), "function", "native slash handler")

SlashCmdList.SAFEITEMFOLLOW("debug")
equal(namespace.Addon.prints[1], namespace.L.MSG_DEBUG_HEADER, "debug command prints status")

local beforeShow = #namespace.Addon.prints
SlashCmdList.SAFEITEMFOLLOW("")
equal(namespace.Addon.prints[beforeShow + 1], namespace.L.MSG_DEBUG_HEADER, "show command degrades to debug when AceGUI is missing")

print("SafeItemFollow runtime tests passed")
