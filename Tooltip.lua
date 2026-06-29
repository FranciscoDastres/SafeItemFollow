local _, NS = ...
local L = NS.L

local Tooltip = {}
NS.Tooltip = Tooltip

local function Money(copper)
    if not copper then
        return "?"
    end
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

local function ExtractItemID(link)
    return NS.Data.ParseItemID(link)
end

local function AddHistoryLines(tooltip, itemID)
    if not NS.Store or not NS.Config or NS.Config:Settings().showTooltips == false then
        return
    end

    local history = NS.Data.GetHistory(NS.Store, itemID)
    if #history == 0 then
        return
    end

    local latest = history[#history]
    tooltip:AddLine(string.format(L.TOOLTIP_HISTORY, #history, Money(latest.minBuyout), Money(latest.avgBuyout)), 0.35, 0.85, 1.00)

    local item = NS.Data.GetItem(NS.Store, itemID)
    local settings = NS.Config:Settings()
    if item and item.vendorSell and NS.Rules.IsFlip(latest.minBuyout, item.vendorSell, settings.flipMargin) then
        tooltip:AddLine(string.format(L.TOOLTIP_VENDOR_FLIP, Money(latest.minBuyout), Money(item.vendorSell)), 0.10, 1.00, 0.35)
    end
end

function Tooltip:AddToTooltip(tooltip, itemID)
    if not tooltip or not itemID or tooltip.__SafeItemFollowItemID == itemID then
        return
    end
    tooltip.__SafeItemFollowItemID = itemID
    AddHistoryLines(tooltip, itemID)
    if tooltip.Show then
        tooltip:Show()
    end
end

local function OnTooltipSetItem(tooltip)
    if not tooltip or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    local itemID = ExtractItemID(link)
    Tooltip:AddToTooltip(tooltip, itemID)
end

local function OnTooltipCleared(tooltip)
    if tooltip then
        tooltip.__SafeItemFollowItemID = nil
    end
end

function Tooltip:Initialize()
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            local itemID = data and data.id
            if not itemID and tooltip and tooltip.GetItem then
                local _, link = tooltip:GetItem()
                itemID = ExtractItemID(link)
            end
            Tooltip:AddToTooltip(tooltip, itemID)
        end)
    end
end
