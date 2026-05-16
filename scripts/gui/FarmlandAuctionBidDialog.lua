FarmlandAuctionBidDialog = {}
local FarmlandAuctionBidDialog_mt = Class(FarmlandAuctionBidDialog, YesNoDialog)

local BID_DIALOG_MOD_DIR = g_currentModDirectory or ""

local function _fa_dbg(fmt, ...)
    if AuctionManager ~= nil and AuctionManager.DEBUG then
        local ok, msg = pcall(string.format, "[FarmlandAuctions] [BIDDIALOG] " .. tostring(fmt), ...)
        if ok then
            print(msg)
        else
            print("[FarmlandAuctions] [BIDDIALOG] " .. tostring(fmt))
        end
    end
end

local function nowHours()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then
        return 0
    end
    local dayMs = tonumber(env.dayTime or env:getEnvironmentTime() or 0) or 0
    return dayMs / 3600000 + (env.currentDay or 0) * 24
end

local function i18nText(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local txt = g_i18n:getText(key)
        if txt ~= nil and txt ~= "" and txt ~= key then
            return txt
        end
    end
    return fallback or key
end

local function getFarmDisplayName(farmId)
    farmId = tonumber(farmId or 0) or 0
    if farmId <= 0 then
        return "-"
    end

    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.name ~= nil and farm.name ~= "" then
            return tostring(farm.name)
        end
    end

    return "Farm " .. tostring(farmId)
end

function FarmlandAuctionBidDialog.new(target, custom_mt)
    local self = YesNoDialog.new(target, custom_mt or FarmlandAuctionBidDialog_mt)
    self.manager = nil
    self.minBidLevel = 1
    self.maxBidLevel = 10
    self.currentBidLevel = 1
    self.lastSliderState = nil
    self.bidLevelTexts = {}
    return self
end

function FarmlandAuctionBidDialog.register(modDir)
    if g_gui == nil then
        _fa_dbg("register failed: g_gui=nil")
        return false
    end

    local base = modDir or BID_DIALOG_MOD_DIR or ""
    local path = Utils.getFilename("gui/FarmlandAuctionBidDialog.xml", base)

    if not fileExists(path) then
        _fa_dbg("register abort: xml missing %s", tostring(path))
        return false
    end

    FarmlandAuctionBidDialog.INSTANCE = nil
    local dlg = FarmlandAuctionBidDialog.new()

    local ok, err = pcall(function()
        g_gui:loadGui(path, "FarmlandAuctionBidDialog", dlg)
    end)
    _fa_dbg("loadGui ok=%s err=%s", tostring(ok), tostring(err))

    if not ok then
        return false
    end

    FarmlandAuctionBidDialog.INSTANCE = dlg
    return true
end

function FarmlandAuctionBidDialog.show(manager)
    local dlg = FarmlandAuctionBidDialog.INSTANCE
    if dlg == nil or g_gui == nil then
        return false
    end

    dlg.manager = manager
    dlg.currentBidLevel = 1
    dlg.lastSliderState = nil

    local title = i18nText("fa_bid_title", "Auction")
    if dlg.dialogTitleElement ~= nil and dlg.dialogTitleElement.setText ~= nil then
        dlg.dialogTitleElement:setText(title)
    end

    local ok = pcall(function()
        g_gui:showDialog("FarmlandAuctionBidDialog")
    end)

    return ok == true
end

function FarmlandAuctionBidDialog:onCreate()
    FarmlandAuctionBidDialog:superClass().onCreate(self)
end

function FarmlandAuctionBidDialog:onOpen()
    FarmlandAuctionBidDialog:superClass().onOpen(self)
    self.currentBidLevel = 1
    self.lastSliderState = nil
    self:setupBidLevelSlider()
    self:updatePreview()
end

function FarmlandAuctionBidDialog:onClose()
    FarmlandAuctionBidDialog:superClass().onClose(self)
end

function FarmlandAuctionBidDialog:update(dt)
    FarmlandAuctionBidDialog:superClass().update(self, dt)

    local state = self:getSliderState()
    if state ~= self.lastSliderState then
        self.lastSliderState = state
        self:readBidLevelFromSlider()
        self:updatePreview()
    else
        -- Refresh time display every 100ms so it counts down live
        self._timeUpdateAccum = (self._timeUpdateAccum or 0) + dt
        if self._timeUpdateAccum >= 100 then
            self._timeUpdateAccum = 0
            local auction = self.manager ~= nil and self.manager.getCurrentAuction ~= nil and self.manager:getCurrentAuction() or nil
            if auction ~= nil then
                local endsIn = math.max(0, (tonumber(auction.endTime) or 0) - nowHours())
                local totalMins = math.max(0, math.floor(endsIn * 60 + 0.5))
                local h = math.floor(totalMins / 60)
                local m = totalMins - h * 60
                local timeStr = h > 0 and (tostring(h) .. "h " .. string.format("%02d", m) .. "m") or (tostring(m) .. "m")
                self:setTextSafe(self.endsValueText, timeStr)
            end
        end
    end
end

function FarmlandAuctionBidDialog:setTextSafe(element, text)
    if element ~= nil and element.setText ~= nil then
        element:setText(tostring(text or ""))
    end
end

function FarmlandAuctionBidDialog:setupBidLevelSlider()
    self.bidLevelTexts = {}

    for i = self.minBidLevel, self.maxBidLevel do
        table.insert(self.bidLevelTexts, tostring(i))
    end

    if self.bidStepsSlider ~= nil then
        if self.bidStepsSlider.setTexts ~= nil then
            self.bidStepsSlider:setTexts(self.bidLevelTexts)
        end

        if self.bidStepsSlider.setState ~= nil then
            self.bidStepsSlider:setState((self.currentBidLevel - self.minBidLevel) + 1, true)
        end
    end

    self.lastSliderState = self:getSliderState()
end

function FarmlandAuctionBidDialog:getSliderState()
    if self.bidStepsSlider ~= nil and self.bidStepsSlider.getState ~= nil then
        local state = self.bidStepsSlider:getState()
        if state ~= nil then
            return tonumber(state) or 1
        end
    end
    return 1
end

function FarmlandAuctionBidDialog:readBidLevelFromSlider()
    local state = self:getSliderState()
    local level = self.minBidLevel + state - 1
    level = math.max(self.minBidLevel, math.min(self.maxBidLevel, level))
    self.currentBidLevel = level
    return self.currentBidLevel
end

function FarmlandAuctionBidDialog:onBidStepsSliderChanged()
    self:readBidLevelFromSlider()
    self:updatePreview()
end

function FarmlandAuctionBidDialog:getSelectedBidLevel()
    return self:readBidLevelFromSlider()
end

function FarmlandAuctionBidDialog:onClickOk()
    local bidLevel = self:getSelectedBidLevel()
   -- print(string.format("[FarmlandAuctions] [BIDDIALOG] OK clicked bidLevel=%d manager=%s", tonumber(bidLevel or 0) or 0, tostring(self.manager ~= nil)))

    if self.manager ~= nil then
        if self.manager.requestBidLevel ~= nil then
            self.manager:requestBidLevel(bidLevel)
        elseif self.manager.requestBidSteps ~= nil then
            self.manager:requestBidSteps(bidLevel)
        else
          --  print("[FarmlandAuctions] [BIDDIALOG] OK clicked but manager has no bid request function")
        end
    else
      --  print("[FarmlandAuctions] [BIDDIALOG] OK clicked but manager=nil")
    end

    self:close()
end

function FarmlandAuctionBidDialog:onClickYes()
    self:onClickOk()
end

function FarmlandAuctionBidDialog:onClickOkay()
    self:onClickOk()
end

function FarmlandAuctionBidDialog:onYes()
    self:onClickOk()
end

function FarmlandAuctionBidDialog:onClickCancel()
    self:onClickBack()
end

function FarmlandAuctionBidDialog:onClickBack()
    self:close()
end


function FarmlandAuctionBidDialog:getHighestBidderName(auction)
    if auction == nil then
        return "-"
    end

    if auction.currentHighestIsNpc == true then
        local npcName = tostring(auction.currentHighestName or "")
        if npcName ~= "" then
            return npcName
        end
        return "NPC"
    end

    local highestFarmId = tonumber(auction.currentHighestFarmId or 0) or 0
    if highestFarmId > 0 then
        return getFarmDisplayName(highestFarmId)
    end

    return "-"
end

function FarmlandAuctionBidDialog:getLastBidderName(auction)
    if auction == nil then
        return "-"
    end

    if auction.lastBidderName ~= nil and tostring(auction.lastBidderName) ~= "" then
        return tostring(auction.lastBidderName)
    end

    local history = auction.bidHistory
    if history ~= nil and history[1] ~= nil then
        local entry = history[1]

        if entry.bidderName ~= nil and tostring(entry.bidderName) ~= "" then
            return tostring(entry.bidderName)
        end

        if entry.isNpc == true then
            local npcName = tostring(entry.npcName or entry.name or "")
            if npcName ~= "" then
                return npcName
            end
            return "NPC"
        end

        local farmId = tonumber(entry.farmId or 0) or 0
        if farmId > 0 then
            return getFarmDisplayName(farmId)
        end
    end

    return "-"
end

function FarmlandAuctionBidDialog:getBidPreviewValues(auction)
    local bidLevel = self.currentBidLevel or 1
    local currentPrice = tonumber(auction.currentPrice or 0) or 0
    local baseRaise = tonumber(auction.betStepSize or 0) or 0
    local raiseAmount = baseRaise * bidLevel
    local offeredBid = currentPrice + raiseAmount
    return bidLevel, currentPrice, baseRaise, raiseAmount, offeredBid
end

function FarmlandAuctionBidDialog:updatePreview()
    local auction = nil
    if self.manager ~= nil and self.manager.getCurrentAuction ~= nil then
        auction = self.manager:getCurrentAuction()
    end

    if auction == nil then
        self:setTextSafe(self.standardPriceValueText, "-")
        self:setTextSafe(self.startPriceValueText, "-")
        self:setTextSafe(self.highestValueText, "-")
        self:setTextSafe(self.currentValueText, "-")
        self:setTextSafe(self.raiseValueText, "-")
        self:setTextSafe(self.newBidValueText, "-")
        self:setTextSafe(self.endsValueText, "-")
        return
    end

    local _, currentPrice, _, raiseAmount, offeredBid = self:getBidPreviewValues(auction)
    local endsIn = math.max(0, (tonumber(auction.endTime) or 0) - nowHours())
    local standardPrice = tonumber(auction.originalPrice or 0) or 0
    local startPrice = tonumber(auction.normalPrice or 0) or 0

    self:setTextSafe(self.standardPriceValueText, g_i18n:formatMoney(standardPrice))
    self:setTextSafe(self.startPriceValueText, g_i18n:formatMoney(startPrice))
    self:setTextSafe(self.highestValueText, self:getHighestBidderName(auction))
    self:setTextSafe(self.currentValueText, g_i18n:formatMoney(currentPrice))
    self:setTextSafe(self.raiseValueText, g_i18n:formatMoney(raiseAmount))
    self:setTextSafe(self.newBidValueText, g_i18n:formatMoney(offeredBid))
    local totalMins = math.max(0, math.floor(endsIn * 60 + 0.5))
    local h = math.floor(totalMins / 60)
    local m = totalMins - h * 60
    local timeStr = h > 0 and (tostring(h) .. "h " .. string.format("%02d", m) .. "m") or (tostring(m) .. "m")
    self:setTextSafe(self.endsValueText, timeStr)
end