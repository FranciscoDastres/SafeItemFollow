local namespace = { DAY_SECONDS = 86400 }
assert(loadfile("Data.lua"))("SafeItemFollow", namespace)

local Data = namespace.Data

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

equal(Data.DayKey(0), 0, "epoch day")
equal(Data.DayKey(86400 * 3 + 42), 3, "floor day")
equal(Data.ParseItemID("|Hitem:12345::::::::|h[Test]|h"), 12345, "parse item link")
equal(Data.ParseItemID("678"), 678, "parse numeric id")

local root = {}
local store = Data.GetStore(root, "Realm-Alliance")
local other = Data.GetStore(root, "Realm-Horde")

Data.RecordScan(store, 1001, 10, { name = "Copper Ore", minBuyout = 100, avgBuyout = 140, qty = 8 })
Data.RecordScan(store, 1001, 10, { minBuyout = 90, avgBuyout = 160, qty = 12 })
Data.RecordScan(store, 1001, 11, { minBuyout = 120, avgBuyout = 180, qty = 3 })
Data.RecordScan(other, 1001, 10, { name = "Copper Ore", minBuyout = 500, avgBuyout = 500, qty = 1 })

local item = Data.GetItem(store, 1001)
equal(item.name, "Copper Ore", "records name")
equal(item.history["10"].minBuyout, 90, "keeps daily min")
equal(item.history["10"].avgBuyout, 150, "running average")
equal(item.history["10"].qty, 12, "latest daily qty")
equal(item.history["10"].scans, 2, "scan count")
equal(Data.GetItem(other, 1001).history["10"].minBuyout, 500, "realm separation")

Data.SetVendor(store, 1001, 25)
equal(Data.GetItem(store, 1001).vendorSell, 25, "vendor price")

Data.SetWatched(store, 1001, true)
Data.SetWatched(store, 2002, true)
local watched = Data.GetWatched(store)
equal(#watched, 2, "watched count")
equal(watched[1], 1001, "watched sorted")
Data.ToggleWatched(store, 1001)
equal(Data.GetItem(store, 1001).watched, false, "toggle watched")

local history = Data.GetHistory(store, 1001)
equal(#history, 2, "history length")
equal(history[1].dayKey, 10, "history sorted")
equal(history[2].dayKey, 11, "history sorted second")

Data.Purge(store, 11, 1)
history = Data.GetHistory(store, 1001)
equal(#history, 1, "purged old day")
equal(history[1].dayKey, 11, "kept current day")

print("SafeItemFollow data tests passed")
