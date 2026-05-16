FarmlandAuctionSyncEvent = {}
local FarmlandAuctionSyncEvent_mt = Class(FarmlandAuctionSyncEvent, Event)

InitEventClass(FarmlandAuctionSyncEvent, "FarmlandAuctionSyncEvent")

function FarmlandAuctionSyncEvent.emptyNew()
    local self = Event.new(FarmlandAuctionSyncEvent_mt)
    return self
end

function FarmlandAuctionSyncEvent.new(state, notification)
    local self = FarmlandAuctionSyncEvent.emptyNew()
    self.state = state
    self.notification = notification
    return self
end

local function _writeHistory(streamId, items)
    items = items or {}
    local count = math.min(#items, 4)
    streamWriteInt8(streamId, count)
    for i = 1, count do
        local item = items[i] or {}
        streamWriteInt32(streamId, item.farmId or 0)
        streamWriteBool(streamId, item.isNpc == true)
        streamWriteString(streamId, tostring(item.bidderName or ""))
        streamWriteFloat32(streamId, item.price or 0)
        streamWriteFloat32(streamId, item.time or 0)
    end
end

local function _readHistory(streamId)
    local items = {}
    local count = streamReadInt8(streamId)
    for i = 1, count do
        items[i] = {
            farmId = streamReadInt32(streamId),
            isNpc = streamReadBool(streamId),
            bidderName = streamReadString(streamId),
            price = streamReadFloat32(streamId),
            time = streamReadFloat32(streamId)
        }
    end
    return items
end

function FarmlandAuctionSyncEvent:writeStream(streamId, connection)
    local s = self.state or {}

    streamWriteInt32(streamId, s.farmlandId or 0)
    streamWriteString(streamId, s.name or "")

    streamWriteFloat32(streamId, s.startTime or 0)
    streamWriteFloat32(streamId, s.endTime or 0)
    streamWriteFloat32(streamId, s.originalPrice or s.maxPrice or s.normalPrice or 0)
    streamWriteFloat32(streamId, s.normalPrice or 0)
    streamWriteFloat32(streamId, s.currentPrice or 0)
    streamWriteFloat32(streamId, s.betStepSize or 1)
    streamWriteFloat32(streamId, s.maxPrice or 0)

    streamWriteInt32(streamId, s.currentHighestFarmId or 0)
    streamWriteBool(streamId, s.hasStarted == true)
    streamWriteBool(streamId, s.oneHourWarningSent == true)
    streamWriteBool(streamId, s.thirtyMinWarningSent == true)
    streamWriteBool(streamId, s.currentHighestIsNpc == true)
    streamWriteBool(streamId, s.hadPlayerBid == true)

    streamWriteFloat32(streamId, s.auctionStartPriceRatio or 0.62)
    streamWriteFloat32(streamId, s.betRatio or 0.035)
    streamWriteFloat32(streamId, s.lastBidTime or 0)
    streamWriteFloat32(streamId, s.nextNpcGlobalBidTime or 0)
    streamWriteInt8(streamId, s.softCloseExtensionCount or 0)

    streamWriteString(streamId, tostring(s.currentHighestName or ""))
    streamWriteString(streamId, tostring(s.auctionHouseName or ""))

    local fs = s.fieldStats or {}
    streamWriteInt8(streamId, fs.fieldCount or 0)
    streamWriteFloat32(streamId, fs.totalArea or 0)
    streamWriteBool(streamId, fs.hasFields == true)
    streamWriteString(streamId, tostring(fs.sizeClass or "medium"))

    _writeHistory(streamId, s.bidHistory)

    streamWriteBool(streamId, s.auctionOnlyPurchase == true)

    local hasN = self.notification ~= nil
    streamWriteBool(streamId, hasN)
    if hasN then
        streamWriteString(streamId, tostring(self.notification.kind or ""))
        streamWriteInt32(streamId, self.notification.farmId or 0)
        streamWriteFloat32(streamId, self.notification.price or 0)
        streamWriteString(streamId, tostring(self.notification.npcName or ""))
        streamWriteFloat32(streamId, self.notification.hours or 0)
        streamWriteInt8(streamId, self.notification.count or 0)
        streamWriteInt32(streamId, self.notification.farmlandId or 0)
    end
end

function FarmlandAuctionSyncEvent:readStream(streamId, connection)
    local s = {}

    s.farmlandId = streamReadInt32(streamId)
    s.name = streamReadString(streamId)

    s.startTime = streamReadFloat32(streamId)
    s.endTime = streamReadFloat32(streamId)
    s.originalPrice = streamReadFloat32(streamId)
    s.normalPrice = streamReadFloat32(streamId)
    s.currentPrice = streamReadFloat32(streamId)
    s.betStepSize = streamReadFloat32(streamId)
    s.maxPrice = streamReadFloat32(streamId)

    s.currentHighestFarmId = streamReadInt32(streamId)
    s.hasStarted = streamReadBool(streamId)
    s.oneHourWarningSent = streamReadBool(streamId)
    s.thirtyMinWarningSent = streamReadBool(streamId)
    s.currentHighestIsNpc = streamReadBool(streamId)
    s.hadPlayerBid = streamReadBool(streamId)

    s.auctionStartPriceRatio = streamReadFloat32(streamId)
    s.betRatio = streamReadFloat32(streamId)
    s.lastBidTime = streamReadFloat32(streamId)
    s.nextNpcGlobalBidTime = streamReadFloat32(streamId)
    s.softCloseExtensionCount = streamReadInt8(streamId)

    s.currentHighestName = streamReadString(streamId)
    s.auctionHouseName = streamReadString(streamId)

    s.fieldStats = {
        fieldCount = streamReadInt8(streamId),
        totalArea = streamReadFloat32(streamId),
        hasFields = streamReadBool(streamId),
        sizeClass = streamReadString(streamId)
    }

    s.bidHistory = _readHistory(streamId)
    s.auctionOnlyPurchase = streamReadBool(streamId)
    self.state = s

    local hasN = streamReadBool(streamId)
    if hasN then
        self.notification = {
            kind = streamReadString(streamId),
            farmId = streamReadInt32(streamId),
            price = streamReadFloat32(streamId),
            npcName = streamReadString(streamId),
            hours = streamReadFloat32(streamId),
            count = streamReadInt8(streamId),
            farmlandId = streamReadInt32(streamId)
        }
    else
        self.notification = nil
    end

    self:_handle(connection)
    self._handled = true
end

function FarmlandAuctionSyncEvent:_handle(connection)
    if AuctionManager ~= nil and AuctionManager.onSyncState ~= nil then
        AuctionManager:onSyncState(self.state, self.notification)
    end
end

function FarmlandAuctionSyncEvent:run(connection)
    if self._handled == true then
        return
    end
    self:_handle(connection)
    self._handled = true
end
