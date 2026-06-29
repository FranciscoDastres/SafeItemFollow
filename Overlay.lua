local _, NS = ...
local L = NS.L

local Overlay = {}
NS.Overlay = Overlay
local hooked = false

local function GetOffset()
    if type(FauxScrollFrame_GetOffset) == "function" and BrowseScrollFrame then
        return FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    end
    return 0
end

local function GetItemIDFromLink(index)
    if type(GetAuctionItemLink) == "function" then
        return NS.Data.ParseItemID(GetAuctionItemLink("list", index))
    end
    return nil
end

local function GetAuctionRow(index)
    if type(GetAuctionItemInfo) ~= "function" then
        return nil
    end

    local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice,
        bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID =
        GetAuctionItemInfo("list", index)

    itemID = tonumber(itemID) or GetItemIDFromLink(index)
    if not itemID then
        return nil
    end

    return {
        itemID = itemID,
        name = name,
        count = tonumber(count) or 1,
        buyout = tonumber(buyoutPrice) or 0,
        index = index,
    }
end

local function EnsureHighlight(button)
    if button.__SafeItemFollowHighlight then
        return button.__SafeItemFollowHighlight
    end

    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetColorTexture(0, 0, 0, 0)
    button.__SafeItemFollowHighlight = texture
    return texture
end

local function SetButtonNote(button, text)
    if button.__SafeItemFollowText then
        button.__SafeItemFollowText:SetText(text or "")
        return
    end
    if not button.CreateFontString then
        return
    end
    local note = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    note:SetTextColor(0.1, 1, 0.35)
    note:SetText(text or "")
    button.__SafeItemFollowText = note
end

function Overlay:RefreshVisible()
    self:TryHook()

    local settings = NS.Config and NS.Config:Settings()
    local enabled = settings and settings.showOverlays ~= false
    local visible = tonumber(NUM_BROWSE_TO_DISPLAY) or 8
    local offset = GetOffset()

    for displayIndex = 1, visible do
        local button = _G["BrowseButton" .. displayIndex]
        if button then
            local highlight = EnsureHighlight(button)
            highlight:Hide()
            SetButtonNote(button, "")

            if enabled and NS.Store then
                local row = GetAuctionRow(offset + displayIndex)
                local parsed = NS.Rules.ParseRow(row)
                if parsed then
                    local item = NS.Data.GetItem(NS.Store, parsed.itemID)
                    local history = NS.Data.GetHistory(NS.Store, parsed.itemID)
                    local isFlip = item and NS.Rules.IsFlip(parsed.perUnit, item.vendorSell, settings.flipMargin)
                    local isLow = NS.Rules.IsHistoricLow(parsed.perUnit, history)

                    if isFlip then
                        highlight:SetColorTexture(0.05, 0.70, 0.20, 0.22)
                        highlight:Show()
                        SetButtonNote(button, L.OVERLAY_FLIP)
                    elseif isLow and #history > 0 then
                        highlight:SetColorTexture(0.20, 0.55, 1.00, 0.18)
                        highlight:Show()
                        SetButtonNote(button, L.OVERLAY_LOW)
                    end
                end
            end
        end
    end
end

function Overlay:TryHook()
    if hooked then
        return
    end
    if type(hooksecurefunc) == "function" and type(_G.AuctionFrameBrowse_Update) == "function" then
        hooksecurefunc("AuctionFrameBrowse_Update", function()
            Overlay:RefreshVisible()
        end)
        hooked = true
    end
end

function Overlay:Initialize()
    self:TryHook()
end
