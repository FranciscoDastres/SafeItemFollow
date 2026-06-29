local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local Core = {}
NS.Core = Core

local frame
local tabGroup
local eventFrame
local currentTab = "watchlist"
local selectedWatchID
local watchInput = ""
local lastMarketSummary = {}
local fullScanState
local retryToken = 0
local watchQueue = {}

local MAX_DISPLAY_ROWS = 100

local function GetAceGUI()
    return LibStub("AceGUI-3.0")
end

local function IsSupportedClient()
    if type(GetBuildInfo) ~= "function" then
        return true
    end

    local interfaceVersion = tonumber(select(4, GetBuildInfo()))
    if interfaceVersion == 20505 then
        return true
    end
    if interfaceVersion and interfaceVersion >= 50500 and interfaceVersion < 50600 then
        return true
    end

    if WOW_PROJECT_MISTS_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC then
        return true
    end
    if WOW_PROJECT_BURNING_CRUSADE_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
        return true
    end
    return false
end

local function Money(copper)
    if copper == nil then
        return "?"
    end
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

local function IsAuctionHouseOpen()
    return _G.AuctionFrame and _G.AuctionFrame.IsShown and _G.AuctionFrame:IsShown()
end

local function After(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    end
end

local function RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    elseif type(GetItemInfo) == "function" then
        GetItemInfo(itemID)
    end
end

local function GetItemInfoSafe(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    end
    if type(GetItemInfo) == "function" then
        return GetItemInfo(itemID)
    end
    return nil
end

local function GetItemNameAndVendor(itemID)
    local name, link, quality, itemLevel, reqLevel, class, subClass, maxStack, equipSlot, texture, vendorSell = GetItemInfoSafe(itemID)
    return name, link, vendorSell
end

local function PersistSummary(summary)
    if not NS.Store then
        return 0, 0
    end

    local dayKey = NS.Data.DayKey(NS.Config:GetServerTime())
    local auctionCount = 0
    local itemCount = 0

    for itemID, entry in pairs(summary or {}) do
        itemCount = itemCount + 1
        auctionCount = auctionCount + (tonumber(entry.listings) or 0)
        if entry.name then
            NS.Data.SetName(NS.Store, itemID, entry.name)
        end

        local name, link, vendorSell = GetItemNameAndVendor(itemID)
        if name then
            NS.Data.SetName(NS.Store, itemID, name)
        else
            RequestItem(itemID)
        end
        if vendorSell then
            NS.Data.SetVendor(NS.Store, itemID, vendorSell)
        end

        NS.Data.RecordScan(NS.Store, itemID, dayKey, entry)
    end

    NS.Data.Purge(NS.Store, dayKey, NS.Config:Settings().retentionDays)
    return auctionCount, itemCount
end

local function ScheduleRetry(callback)
    retryToken = retryToken + 1
    local token = retryToken
    After(0.25, function()
        if token == retryToken then
            callback()
        end
    end)
end

function Core:TrySendFullPage(page)
    if not NS.Scanner.scan then
        return false
    end

    if NS.Scanner:QueryFullPage(page) then
        return true
    end

    NS.Action:SetLabel(L.MSG_QUERY_THROTTLED)
    ScheduleRetry(function()
        Core:TrySendFullPage(page)
    end)
    return false
end

function Core:StartFullScan()
    if not IsAuctionHouseOpen() then
        Addon:Print(L.MSG_AH_REQUIRED)
        return
    end

    retryToken = retryToken + 1
    fullScanState = NS.ActionState:New():Begin(0)
    NS.Scanner:BeginFullScan()
    lastMarketSummary = {}
    Addon:Print(L.MSG_SCAN_STARTED)
    NS.Action:SetLabel(string.format(L.BTN_FULL_SCAN_RUNNING, 1))
    self:TrySendFullPage(0)
    self:RefreshActiveTab()
end

function Core:OnFullScanPage()
    local hasMore = NS.Scanner:IngestCurrentPage()
    local page = NS.Scanner.scan and NS.Scanner.scan.page or 0
    if fullScanState then
        fullScanState.page = page + 1
    end

    if hasMore then
        local nextPage = NS.Scanner.scan.nextPage
        NS.Action:SetLabel(string.format(L.BTN_FULL_SCAN_RUNNING, nextPage + 1))
        self:TrySendFullPage(nextPage)
        return
    end

    self:FinishFullScan()
end

function Core:FinishFullScan()
    local rows = NS.Scanner.scan and NS.Scanner.scan.rows or {}
    lastMarketSummary = NS.Rules.SummarizeListings(rows)
    local auctionCount, itemCount = PersistSummary(lastMarketSummary)

    if fullScanState then
        fullScanState:Finish()
    end
    NS.Scanner.scan = nil
    NS.Action:SetLabel(L.BTN_FULL_SCAN)
    Addon:Print(string.format(L.MSG_SCAN_DONE, auctionCount, itemCount))
    NS.Overlay:RefreshVisible()
    self:RefreshActiveTab()
end

function Core:AbortScans()
    local hadScan = NS.Scanner.scan ~= nil or #watchQueue > 0 or self.__activeWatchID ~= nil
    retryToken = retryToken + 1
    NS.Scanner:Abort()
    watchQueue = {}
    self.__activeWatchID = nil
    if fullScanState then
        fullScanState:Finish()
    end
    NS.Action:SetLabel(L.BTN_FULL_SCAN)
    if hadScan then
        Addon:Print(L.MSG_SCAN_ABORTED)
    end
end

function Core:QueueWatchlistScan()
    if not NS.Store or not IsAuctionHouseOpen() then
        return
    end

    watchQueue = NS.Data.GetWatched(NS.Store)
    self.__activeWatchID = nil
    self:PumpWatchQueue()
end

function Core:PumpWatchQueue()
    if self.__activeWatchID or #watchQueue == 0 or not IsAuctionHouseOpen() then
        return
    end

    local itemID = watchQueue[1]
    local item = NS.Data.GetItem(NS.Store, itemID)
    local name = item and item.name
    if not name then
        name = GetItemNameAndVendor(itemID)
    end

    if not name then
        RequestItem(itemID)
        ScheduleRetry(function()
            Core:PumpWatchQueue()
        end)
        return
    end

    if NS.Scanner:QueryItem(name) then
        self.__activeWatchID = itemID
    else
        ScheduleRetry(function()
            Core:PumpWatchQueue()
        end)
    end
end

function Core:RecordWatchlistPage()
    local itemID = self.__activeWatchID
    if not itemID then
        return false
    end

    local rows = NS.Scanner:ReadCurrentPage()
    local summary = NS.Rules.SummarizeListings(rows)
    local entry = summary[itemID]
    if entry then
        PersistSummary({ [itemID] = entry })
    end

    self.__activeWatchID = nil
    table.remove(watchQueue, 1)
    if #watchQueue > 0 then
        ScheduleRetry(function()
            Core:PumpWatchQueue()
        end)
    else
        self:RefreshActiveTab()
    end
    return true
end

function Core:OnListUpdated()
    if NS.Scanner.scan and NS.Scanner.scan.mode == "full" then
        self:OnFullScanPage()
    elseif self:RecordWatchlistPage() then
        NS.Overlay:RefreshVisible()
    else
        NS.Overlay:RefreshVisible()
    end
end

local function AddLabel(container, text, fullWidth)
    local AceGUI = GetAceGUI()
    local label = AceGUI:Create("Label")
    label:SetText(text)
    if fullWidth ~= false then
        label:SetFullWidth(true)
    end
    container:AddChild(label)
    return label
end

local function AddButton(container, text, width, callback)
    local AceGUI = GetAceGUI()
    local button = AceGUI:Create("Button")
    button:SetText(text)
    if width then
        button:SetWidth(width)
    end
    button:SetCallback("OnClick", callback)
    container:AddChild(button)
    return button
end

local function AddWatchItem(value)
    local itemID = NS.Data.ParseItemID(value)
    if not itemID then
        Addon:Print(L.MSG_INVALID_ITEM)
        return
    end

    local name, link, vendorSell = GetItemNameAndVendor(itemID)
    if name then
        NS.Data.SetName(NS.Store, itemID, name)
    else
        RequestItem(itemID)
    end
    if vendorSell then
        NS.Data.SetVendor(NS.Store, itemID, vendorSell)
    end
    NS.Data.SetWatched(NS.Store, itemID, true)
    selectedWatchID = itemID
    Addon:Print(string.format(L.MSG_WATCH_ADDED, itemID))
    Core:RefreshActiveTab()
end

local function RemoveWatchItem(itemID)
    NS.Data.SetWatched(NS.Store, itemID, false)
    if selectedWatchID == itemID then
        selectedWatchID = nil
    end
    Addon:Print(string.format(L.MSG_WATCH_REMOVED, itemID))
    Core:RefreshActiveTab()
end

local function QueryItemFromEntry(entry)
    if not IsAuctionHouseOpen() then
        Addon:Print(L.MSG_AH_REQUIRED)
        return
    end
    if not entry or not entry.name then
        return
    end
    if not NS.Scanner:QueryItem(entry.name) then
        Addon:Print(L.MSG_QUERY_THROTTLED)
    end
end

local function DrawHistory(container, itemID)
    local history = NS.Data.GetHistory(NS.Store, itemID)
    AddLabel(container, L.HISTORY_HEADER, true)
    if #history == 0 then
        AddLabel(container, L.HISTORY_EMPTY, true)
        return
    end

    for index = 1, #history do
        local point = history[index]
        AddLabel(container, string.format(
            "%s %d  %s %s  %s %s  %s %d",
            L.COL_DAY,
            point.dayKey,
            L.COL_MIN,
            Money(point.minBuyout),
            L.COL_AVG,
            Money(point.avgBuyout),
            L.COL_QTY,
            point.qty
        ), true)
    end
end

local function DrawWatchlist(container)
    local AceGUI = GetAceGUI()
    local inputGroup = AceGUI:Create("SimpleGroup")
    inputGroup:SetFullWidth(true)
    inputGroup:SetLayout("Flow")
    container:AddChild(inputGroup)

    local input = AceGUI:Create("EditBox")
    input:SetLabel(L.ADD_WATCH_LABEL)
    input:SetText(watchInput)
    input:SetFullWidth(false)
    input:SetWidth(260)
    input:SetCallback("OnTextChanged", function(_, _, text)
        watchInput = text or ""
    end)
    input:SetCallback("OnEnterPressed", function(_, _, text)
        watchInput = text or ""
        AddWatchItem(watchInput)
    end)
    inputGroup:AddChild(input)

    AddButton(inputGroup, L.BTN_ADD, 90, function()
        AddWatchItem(watchInput)
    end)

    local watched = NS.Data.GetWatched(NS.Store)
    if #watched == 0 then
        AddLabel(container, L.WATCHLIST_EMPTY, true)
        return
    end

    for index = 1, #watched do
        local itemID = watched[index]
        local item = NS.Data.GetItem(NS.Store, itemID)
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        container:AddChild(row)

        local label = AceGUI:Create("InteractiveLabel")
        label:SetText(((item and item.name) or ("item:" .. itemID)) .. "  (" .. itemID .. ")")
        label:SetWidth(260)
        label:SetCallback("OnClick", function()
            selectedWatchID = itemID
            Core:RefreshActiveTab()
        end)
        row:AddChild(label)

        AddButton(row, L.BTN_SCAN, 82, function()
            QueryItemFromEntry({ name = item and item.name })
        end)
        AddButton(row, L.BTN_REMOVE, 82, function()
            RemoveWatchItem(itemID)
        end)
    end

    if selectedWatchID then
        DrawHistory(container, selectedWatchID)
    end
end

local function DrawMarket(container)
    AddButton(container, L.BTN_FULL_SCAN, 130, function()
        Core:StartFullScan()
    end)

    local sorted = NS.Rules.SortSummaries(lastMarketSummary, "minBuyout", false)
    if #sorted == 0 then
        AddLabel(container, L.MARKET_EMPTY, true)
        return
    end

    local AceGUI = GetAceGUI()
    for index = 1, math.min(#sorted, MAX_DISPLAY_ROWS) do
        local entry = sorted[index].summary
        local itemID = sorted[index].itemID
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        container:AddChild(row)

        local text = string.format(
            "%s  %s %s  %s %s  %s %d",
            entry.name or ("item:" .. itemID),
            L.COL_MIN,
            Money(entry.minBuyout),
            L.COL_AVG,
            Money(entry.avgBuyout),
            L.COL_QTY,
            entry.qty
        )
        local label = AceGUI:Create("Label")
        label:SetText(text)
        label:SetWidth(430)
        row:AddChild(label)

        AddButton(row, L.BTN_WATCH, 75, function()
            NS.Data.SetWatched(NS.Store, itemID, true)
            selectedWatchID = itemID
            Core:RefreshActiveTab()
        end)
        AddButton(row, L.BTN_QUERY, 75, function()
            QueryItemFromEntry(entry)
        end)
    end
end

local function BuildFlipRows()
    local settings = NS.Config:Settings()
    local rows = {}
    for itemID, entry in pairs(lastMarketSummary or {}) do
        local item = NS.Data.GetItem(NS.Store, itemID)
        local vendorSell = item and item.vendorSell
        if vendorSell and NS.Rules.IsFlip(entry.minBuyout, vendorSell, settings.flipMargin) then
            rows[#rows + 1] = {
                itemID = itemID,
                entry = entry,
                vendorSell = vendorSell,
                gain = NS.Rules.FlipGain(entry.minBuyout, vendorSell, entry.qty),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.gain == b.gain then
            return (a.entry.name or "") < (b.entry.name or "")
        end
        return a.gain > b.gain
    end)
    return rows
end

local function DrawFlip(container)
    local flips = BuildFlipRows()
    if #flips == 0 then
        AddLabel(container, L.FLIP_EMPTY, true)
        return
    end

    local AceGUI = GetAceGUI()
    for index = 1, math.min(#flips, MAX_DISPLAY_ROWS) do
        local flip = flips[index]
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        container:AddChild(row)

        local label = AceGUI:Create("Label")
        label:SetWidth(470)
        label:SetText(string.format(
            "%s  buy %s  vendor %s  %s %s",
            flip.entry.name or ("item:" .. flip.itemID),
            Money(flip.entry.minBuyout),
            Money(flip.vendorSell),
            L.COL_GAIN,
            Money(flip.gain)
        ))
        row:AddChild(label)

        AddButton(row, L.BTN_WATCH, 75, function()
            NS.Data.SetWatched(NS.Store, flip.itemID, true)
            selectedWatchID = flip.itemID
            Core:RefreshActiveTab()
        end)
        AddButton(row, L.BTN_QUERY, 75, function()
            QueryItemFromEntry(flip.entry)
        end)
    end
end

function Core:RefreshActiveTab()
    if not tabGroup or not NS.Store then
        return
    end

    tabGroup:ReleaseChildren()
    if currentTab == "watchlist" then
        DrawWatchlist(tabGroup)
    elseif currentTab == "market" then
        DrawMarket(tabGroup)
    else
        DrawFlip(tabGroup)
    end
end

function Core:SelectTab(tab)
    currentTab = tab or "watchlist"
    self:RefreshActiveTab()
end

local function BuildFrame()
    local AceGUI = GetAceGUI()
    frame = AceGUI:Create("Frame")
    frame:SetTitle(L.WINDOW_TITLE)
    frame:SetLayout("Fill")
    frame:SetWidth(720)
    frame:SetHeight(520)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)

    tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetTabs({
        { text = L.TAB_WATCHLIST, value = "watchlist" },
        { text = L.TAB_MARKET, value = "market" },
        { text = L.TAB_FLIP, value = "flip" },
    })
    tabGroup:SetCallback("OnGroupSelected", function(_, _, tab)
        Core:SelectTab(tab)
    end)
    frame:AddChild(tabGroup)
    tabGroup:SelectTab(currentTab)
end

function Core:Show()
    if not frame then
        BuildFrame()
    end
    frame:Show()
    self:RefreshActiveTab()
end

function Core:Hide()
    if frame then
        frame:Hide()
    end
end

function Core:Toggle()
    if frame and frame.frame and frame.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Addon:HandleSlash(input)
    local command = tostring(input or ""):match("^%s*(.-)%s*$"):lower()
    if command == "config" or command == "options" then
        NS.Config:Open()
    elseif command == "scan" then
        NS.Core:StartFullScan()
    elseif command == "show" or command == "" then
        NS.Core:Show()
    elseif command == "hide" then
        NS.Core:Hide()
    else
        self:Print(L.MSG_HELP)
    end
end

function Addon:HandleEvent(event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        NS.Action:Initialize()
        NS.Overlay:RefreshVisible()
        if NS.Config:Settings().autoScanOnOpen then
            After(0.5, function()
                NS.Core:QueueWatchlistScan()
            end)
        end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        NS.Core:OnListUpdated()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        NS.Core:AbortScans()
        NS.Action:Hide()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if #watchQueue > 0 and not NS.Core.__activeWatchID then
            NS.Core:PumpWatchQueue()
        end
        NS.Core:RefreshActiveTab()
    end
end

function Addon:RegisterEvents()
    if eventFrame or type(CreateFrame) ~= "function" then
        return
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    eventFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        Addon:HandleEvent(event, ...)
    end)
end

function Addon:OnInitialize()
    NS.IsSupportedClient = IsSupportedClient()
    NS.Config:InitializeDatabase()
    NS.Config:RegisterOptions()
    NS.Tooltip:Initialize()
    NS.Overlay:Initialize()
    NS.MinimapButton:Initialize()
    self:RegisterEvents()
    self:RegisterChatCommand("safeitemfollow", "HandleSlash")
    self:RegisterChatCommand("sif", "HandleSlash")
end

function Addon:OnEnable()
    if not NS.IsSupportedClient then
        self:Print(L.MSG_UNSUPPORTED)
    end
end
