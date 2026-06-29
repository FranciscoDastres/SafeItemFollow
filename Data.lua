local _, NS = ...

local Data = {}
NS.Data = Data

local DAY_SECONDS = NS.DAY_SECONDS or 86400

local function NormalizeItemID(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return math.floor(itemID)
end

local function EnsureRoot(root)
    root.realms = root.realms or {}
    return root
end

local function EnsureStore(store)
    store.items = store.items or {}
    return store
end

local function EnsureItem(store, itemID)
    itemID = NormalizeItemID(itemID)
    if not itemID then
        return nil
    end

    EnsureStore(store)
    store.items[itemID] = store.items[itemID] or { history = {} }
    store.items[itemID].history = store.items[itemID].history or {}
    return store.items[itemID]
end

function Data.NormalizeItemID(itemID)
    return NormalizeItemID(itemID)
end

function Data.ParseItemID(value)
    if type(value) == "number" then
        return NormalizeItemID(value)
    end

    value = tostring(value or "")
    return NormalizeItemID(value:match("item:(%d+)") or value:match("Hitem:(%d+)") or value:match("^(%d+)$"))
end

function Data.DayKey(timestamp)
    timestamp = tonumber(timestamp) or (type(time) == "function" and time()) or 0
    return math.floor(timestamp / DAY_SECONDS)
end

function Data.GetStore(root, realmKey)
    root = EnsureRoot(root or {})
    realmKey = tostring(realmKey or "Unknown-Neutral")
    root.realms[realmKey] = root.realms[realmKey] or { items = {} }
    return EnsureStore(root.realms[realmKey])
end

function Data.EnsureItem(store, itemID)
    return EnsureItem(store, itemID)
end

function Data.GetItem(store, itemID)
    itemID = NormalizeItemID(itemID)
    if not itemID or not store or not store.items then
        return nil
    end
    return store.items[itemID]
end

function Data.SetName(store, itemID, name)
    local item = EnsureItem(store, itemID)
    if item and name and name ~= "" then
        item.name = name
    end
end

function Data.SetVendor(store, itemID, vendorSell)
    local item = EnsureItem(store, itemID)
    vendorSell = tonumber(vendorSell)
    if item and vendorSell and vendorSell >= 0 then
        item.vendorSell = math.floor(vendorSell)
    end
end

function Data.SetWatched(store, itemID, watched)
    local item = EnsureItem(store, itemID)
    if item then
        item.watched = watched == true
    end
end

function Data.ToggleWatched(store, itemID)
    local item = EnsureItem(store, itemID)
    if not item then
        return false
    end
    item.watched = not item.watched
    return item.watched
end

function Data.GetWatched(store)
    local watched = {}
    if not store or not store.items then
        return watched
    end

    for itemID, item in pairs(store.items) do
        if item and item.watched then
            watched[#watched + 1] = tonumber(itemID)
        end
    end
    table.sort(watched)
    return watched
end

function Data.RecordScan(store, itemID, dayKey, summary)
    local item = EnsureItem(store, itemID)
    if not item or type(summary) ~= "table" then
        return nil
    end

    if summary.name then
        item.name = summary.name
    end
    if summary.vendorSell then
        Data.SetVendor(store, itemID, summary.vendorSell)
    end

    dayKey = tonumber(dayKey) or Data.DayKey()
    local minBuyout = tonumber(summary.minBuyout)
    local avgBuyout = tonumber(summary.avgBuyout or summary.minBuyout)
    local qty = tonumber(summary.qty) or 0

    if not minBuyout or minBuyout <= 0 or not avgBuyout or avgBuyout <= 0 then
        return nil
    end

    local key = tostring(math.floor(dayKey))
    local bucket = item.history[key]
    if not bucket then
        bucket = { minBuyout = math.floor(minBuyout), avgBuyout = math.floor(avgBuyout), qty = math.floor(qty), scans = 1 }
        item.history[key] = bucket
        return bucket
    end

    local scans = tonumber(bucket.scans) or 0
    local previousAvg = tonumber(bucket.avgBuyout) or avgBuyout
    bucket.avgBuyout = math.floor(((previousAvg * scans) + avgBuyout) / (scans + 1))
    bucket.minBuyout = math.min(tonumber(bucket.minBuyout) or minBuyout, math.floor(minBuyout))
    bucket.qty = math.floor(qty)
    bucket.scans = scans + 1
    return bucket
end

function Data.Purge(store, currentDayKey, retentionDays)
    if not store or not store.items then
        return
    end

    currentDayKey = tonumber(currentDayKey) or Data.DayKey()
    retentionDays = tonumber(retentionDays) or 30
    if retentionDays < 1 then
        retentionDays = 1
    end

    local oldestKept = math.floor(currentDayKey) - math.floor(retentionDays) + 1
    for _, item in pairs(store.items) do
        if item and item.history then
            for dayKey in pairs(item.history) do
                if tonumber(dayKey) and tonumber(dayKey) < oldestKept then
                    item.history[dayKey] = nil
                end
            end
        end
    end
end

function Data.GetHistory(store, itemID)
    local item = Data.GetItem(store, itemID)
    local history = {}
    if not item or not item.history then
        return history
    end

    for dayKey, bucket in pairs(item.history) do
        history[#history + 1] = {
            dayKey = tonumber(dayKey),
            minBuyout = tonumber(bucket.minBuyout) or 0,
            avgBuyout = tonumber(bucket.avgBuyout) or 0,
            qty = tonumber(bucket.qty) or 0,
            scans = tonumber(bucket.scans) or 0,
        }
    end

    table.sort(history, function(a, b) return a.dayKey < b.dayKey end)
    return history
end
