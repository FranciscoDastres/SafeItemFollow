local namespace = { DEFAULT_PER_PAGE = 2 }
assert(loadfile("Rules.lua"))("SafeItemFollow", namespace)
assert(loadfile("Scanner.lua"))("SafeItemFollow", namespace)

local Scanner = namespace.Scanner

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local currentPage = 0
local queries = {}
local canQuery = true
local pages = {
    [0] = {
        { name = "Copper Ore", count = 20, buyout = 2000, itemID = 1001 },
        { name = "Tin Ore", count = 10, buyout = 1500, itemID = 1002 },
    },
    [1] = {
        { name = "Silver Ore", count = 1, buyout = 3000, itemID = 1003 },
    },
}

CanSendAuctionQuery = function()
    return canQuery
end

QueryAuctionItems = function(name, minLevel, maxLevel, invTypeIndex, classIndex, subclassIndex, page, isUsable, qualityIndex, getAll, exactMatch)
    currentPage = page or 0
    queries[#queries + 1] = { name = name, page = currentPage, exactMatch = exactMatch }
end

GetNumAuctionItems = function(kind)
    equal(kind, "list", "auction list kind")
    local rows = pages[currentPage] or {}
    return #rows, 3
end

GetAuctionItemInfo = function(kind, index)
    equal(kind, "list", "auction info kind")
    local row = (pages[currentPage] or {})[index]
    if not row then
        return nil
    end
    return row.name, nil, row.count, nil, nil, nil, nil, nil, row.buyout, nil, nil, nil, nil, nil, nil, row.itemID, true
end

GetAuctionItemLink = function(kind, index)
    local row = (pages[currentPage] or {})[index]
    if not row then
        return nil
    end
    return "|Hitem:" .. row.itemID .. "::::::::|h[" .. row.name .. "]|h"
end

canQuery = false
Scanner:BeginFullScan()
equal(Scanner:QueryFullPage(0), false, "throttle blocks full page")
equal(#queries, 0, "no throttled query sent")

canQuery = true
equal(Scanner:QueryFullPage(0), true, "query first page")
equal(#queries, 1, "first query sent")
equal(queries[1].page, 0, "first page")

local hasMore, rows = Scanner:IngestCurrentPage()
equal(hasMore, true, "has second page")
equal(#rows, 2, "first page rows")
equal(#Scanner.scan.rows, 2, "stored first page")
equal(Scanner.scan.nextPage, 1, "next page")

equal(Scanner:QueryFullPage(Scanner.scan.nextPage), true, "query second page")
hasMore, rows = Scanner:IngestCurrentPage()
equal(hasMore, false, "last page")
equal(#rows, 1, "second page rows")
equal(#Scanner.scan.rows, 3, "stored all pages")
equal(Scanner.scan.active, false, "scan inactive after final page")

equal(Scanner:QueryItem("Copper Ore"), true, "directed query")
equal(queries[#queries].name, "Copper Ore", "directed query name")
equal(queries[#queries].page, 0, "directed query first page")
equal(queries[#queries].exactMatch, true, "directed exact match")

print("SafeItemFollow scanner tests passed")
