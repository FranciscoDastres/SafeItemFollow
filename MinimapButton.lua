local _, NS = ...
local L = NS.L

local MinimapButton = {}
NS.MinimapButton = MinimapButton

local button

local function IsShownInProfile()
    return not NS.Config or NS.Config:Settings().showMinimapButton ~= false
end

local function SetTooltip(owner)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_TITLE, 0.35, 0.85, 1.00)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_RIGHT, 0.85, 0.85, 0.85)
    GameTooltip:Show()
end

function MinimapButton:Refresh()
    if not button then
        return
    end
    if IsShownInProfile() then
        button:Show()
    else
        button:Hide()
    end
end

function MinimapButton:Initialize()
    if button or not Minimap or type(CreateFrame) ~= "function" then
        return
    end

    button = CreateFrame("Button", "SafeItemFollowMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -2, -2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 1, 1)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            NS.Config:Open()
        elseif NS.Core then
            NS.Core:Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self) SetTooltip(self) end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    self:Refresh()
end
