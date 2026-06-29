local _, NS = ...

local Scanner = {}
NS.Scanner = Scanner

Scanner.scan = nil
Scanner.lastQuery = nil

local function QueryAuctionItemsSafe(name, page, exactMatch)
    if type(QueryAuctionItems) ~= "function" then
        return false
    end

    QueryAuctionItems(name or "", nil, nil, nil, nil, nil, page or 0, false, nil, false, exactMatch == true)
    return true
end

local function GetAuctionItemLinkSafe(index)
    if type(GetAuctionItemLink) == "function" then
        return GetAuctionItemLink("list", index)
    end
    return nil
end

local function ParseItemIDFromLink(link)
    if not link then
        return nil
    end
    return tonumber(tostring(link):match("item:(%d+)"))
end

local function ReadAuctionInfo(index)
    if type(GetAuctionItemInfo) ~= "function" then
        return nil
    end

    local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice,
        bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID,
        hasAllInfo = GetAuctionItemInfo("list", index)

    local link = GetAuctionItemLinkSafe(index)
    itemID = tonumber(itemID) or ParseItemIDFromLink(link)

    return {
        itemID = itemID,
        name = name,
        count = tonumber(count) or 1,
        buyout = tonumber(buyoutPrice) or 0,
        minBid = minBid,
        bidAmount = bidAmount,
        quality = quality,
        index = index,
        link = link,
        hasAllInfo = hasAllInfo,
    }
end

function Scanner:BeginFullScan()
    self.scan = {
        active = true,
        mode = "full",
        page = 0,
        nextPage = 0,
        rows = {},
        total = nil,
        sentPage = nil,
    }
    return self.scan
end

function Scanner:IsActive()
    return self.scan and self.scan.active == true
end

function Scanner:Abort()
    if self.scan then
        self.scan.active = false
    end
    self.scan = nil
    self.lastQuery = nil
end

function Scanner:QueryFullPage(page)
    if not NS.Rules.CanQuery() then
        return false
    end

    if not self.scan then
        self:BeginFullScan()
    end

    page = tonumber(page) or 0
    if not QueryAuctionItemsSafe("", page, false) then
        return false
    end

    self.scan.page = page
    self.scan.sentPage = page
    self.lastQuery = { mode = "full", page = page }
    return true
end

function Scanner:QueryItem(name, exactMatch)
    if not name or name == "" or not NS.Rules.CanQuery() then
        return false
    end

    if not QueryAuctionItemsSafe(name, 0, exactMatch ~= false) then
        return false
    end

    self.lastQuery = { mode = "item", name = name, exactMatch = exactMatch ~= false }
    return true
end

function Scanner:ReadCurrentPage()
    local batchCount, totalCount = 0, 0
    if type(GetNumAuctionItems) == "function" then
        batchCount, totalCount = GetNumAuctionItems("list")
    end

    batchCount = tonumber(batchCount) or 0
    totalCount = tonumber(totalCount) or batchCount

    local rows = {}
    for index = 1, batchCount do
        local row = ReadAuctionInfo(index)
        if row and row.itemID then
            rows[#rows + 1] = row
        end
    end

    return rows, batchCount, totalCount
end

function Scanner:IngestCurrentPage()
    if not self.scan then
        return false, {}
    end

    local rows, batchCount, totalCount = self:ReadCurrentPage()
    for index = 1, #rows do
        self.scan.rows[#self.scan.rows + 1] = rows[index]
    end

    self.scan.total = totalCount
    local pageSize = NS.DEFAULT_PER_PAGE or 50
    local loadedThrough = ((self.scan.page or 0) + 1) * pageSize
    local hasMore
    if totalCount and totalCount > 0 then
        hasMore = loadedThrough < totalCount
    else
        hasMore = batchCount >= pageSize
    end

    self.scan.nextPage = (self.scan.page or 0) + 1
    if not hasMore then
        self.scan.active = false
    end

    return hasMore, rows
end
