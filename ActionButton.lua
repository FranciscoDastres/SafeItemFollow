local _, NS = ...
local L = NS.L

local ActionButton = {}
NS.ActionButton = ActionButton
NS.Action = ActionButton

local button

function ActionButton:SetLabel(text)
    if button and button.SetText then
        button:SetText(text)
    end
end

function ActionButton:SetEnabled(enabled)
    if not button then
        return
    end
    if enabled and button.Enable then
        button:Enable()
    elseif button.Disable then
        button:Disable()
    end
end

function ActionButton:RequestFullScan()
    if NS.Core and NS.Core.StartFullScan then
        NS.Core:StartFullScan()
    end
end

function ActionButton:Initialize()
    if button then
        button:Show()
        return
    end

    local parent = _G.AuctionFrame
    if not parent or type(CreateFrame) ~= "function" then
        return
    end

    button = CreateFrame("Button", "SafeItemFollowScanButton", parent, "UIPanelButtonTemplate")
    button:SetSize(124, 22)
    button:SetText(L.BTN_FULL_SCAN)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -178, -16)
    button:SetScript("OnClick", function()
        ActionButton:RequestFullScan()
    end)
end

function ActionButton:Hide()
    if button then
        button:Hide()
    end
end
