FarmlandAuctionsMapFrameExtension = {}

local function isBlockedFarmland(self)
    if self == nil or self.selectedFarmland == nil or AuctionManager == nil or AuctionManager.isFarmlandBlockedForStandardPurchase == nil then
        return false
    end

    local farmlandId = tonumber(self.selectedFarmland.id or 0) or 0
    if farmlandId == 0 then
        return false
    end

    return AuctionManager:isFarmlandBlockedForStandardPurchase(farmlandId) == true
end

local function setGuiElementVisible(element, visible)
    if element == nil then
        return
    end

    if element.setVisible ~= nil then
        element:setVisible(visible)
    elseif element.setVisibility ~= nil then
        element:setVisibility(visible)
    end

    if element.setDisabled ~= nil then
        element:setDisabled(not visible)
    end

    if element.setEnabled ~= nil then
        element:setEnabled(visible)
    end
end

local function setBuyActionHidden(self, hidden)
    if self == nil or self.contextActions == nil or InGameMenuMapFrame == nil or InGameMenuMapFrame.ACTIONS == nil then
        return
    end

    local buyActionId = InGameMenuMapFrame.ACTIONS.BUY_FARMLAND
    if buyActionId == nil then
        return
    end

    local action = self.contextActions[buyActionId]
    if action == nil then
        return
    end

    -- FS25 rebuilds/refreshes the map context actions often.  "isActive=false" only
    -- disables the action on some UI states, but the button can still stay visible.
    -- Therefore we also force all common visibility flags and known GUI element
    -- references to hidden while auction-only mode blocks standard purchases.
    action.isActive = not hidden
    action.active = not hidden
    action.visible = not hidden
    action.isVisible = not hidden
    action.forceHidden = hidden

    local visible = not hidden
    setGuiElementVisible(action, visible)
    setGuiElementVisible(action.element, visible)
    setGuiElementVisible(action.button, visible)
    setGuiElementVisible(action.buttonElement, visible)
    setGuiElementVisible(action.contextButton, visible)
    setGuiElementVisible(action.inputButton, visible)
    setGuiElementVisible(action.guiElement, visible)

    -- Some builds store the real button as a nested table value with a different
    -- field name. Keep this shallow and defensive to avoid touching unrelated UI.
    for _, value in pairs(action) do
        if type(value) == "table" and value ~= action then
            if value.setVisible ~= nil or value.setVisibility ~= nil or value.setDisabled ~= nil or value.setEnabled ~= nil then
                setGuiElementVisible(value, visible)
            end
        end
    end
end

function FarmlandAuctionsMapFrameExtension.setMapInputContext(self, superFunc, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)
    local blocked = isBlockedFarmland(self)
    if blocked then
        buyFarmlandActive = false
    end

    local result = superFunc(self, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)
    setBuyActionHidden(self, blocked)
    return result
end

function FarmlandAuctionsMapFrameExtension.updateContextActions(self, superFunc, ...)
    local result = superFunc(self, ...)
    setBuyActionHidden(self, isBlockedFarmland(self))
    return result
end

function FarmlandAuctionsMapFrameExtension.onClickBuyFarmland(self, superFunc, ...)
    if isBlockedFarmland(self) then
        setBuyActionHidden(self, true)
        return false
    end
    return superFunc(self, ...)
end

if InGameMenuMapFrame ~= nil then
    if InGameMenuMapFrame.setMapInputContext ~= nil then
        InGameMenuMapFrame.setMapInputContext = Utils.overwrittenFunction(InGameMenuMapFrame.setMapInputContext, FarmlandAuctionsMapFrameExtension.setMapInputContext)
    end

    if InGameMenuMapFrame.updateContextActions ~= nil then
        InGameMenuMapFrame.updateContextActions = Utils.overwrittenFunction(InGameMenuMapFrame.updateContextActions, FarmlandAuctionsMapFrameExtension.updateContextActions)
    end

    if InGameMenuMapFrame.onClickBuyFarmland ~= nil then
        InGameMenuMapFrame.onClickBuyFarmland = Utils.overwrittenFunction(InGameMenuMapFrame.onClickBuyFarmland, FarmlandAuctionsMapFrameExtension.onClickBuyFarmland)
    end
end
