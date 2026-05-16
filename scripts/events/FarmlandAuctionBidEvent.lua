FarmlandAuctionBidEvent = {}
local FarmlandAuctionBidEvent_mt = Class(FarmlandAuctionBidEvent, Event)

InitEventClass(FarmlandAuctionBidEvent, "FarmlandAuctionBidEvent")

function FarmlandAuctionBidEvent.emptyNew()
    local self = Event.new(FarmlandAuctionBidEvent_mt)
    self._handled = false
    return self
end

function FarmlandAuctionBidEvent.new(steps, clientFarmId, farmlandId)
    local self = FarmlandAuctionBidEvent.emptyNew()
    self.steps = math.max(1, math.min(10, tonumber(steps) or 1))
    self.clientFarmId = math.max(0, tonumber(clientFarmId or 0) or 0)
    self.farmlandId = math.max(0, tonumber(farmlandId or 0) or 0)
    return self
end

function FarmlandAuctionBidEvent:readStream(streamId, connection)
    self.steps = streamReadUInt8(streamId) or 1
    self.clientFarmId = streamReadInt32(streamId) or 0
    self.farmlandId = streamReadInt32(streamId) or 0
    self:run(connection)
end

function FarmlandAuctionBidEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.steps or 1)
    streamWriteInt32(streamId, self.clientFarmId or 0)
    streamWriteInt32(streamId, self.farmlandId or 0)
end

function FarmlandAuctionBidEvent:run(connection)
    if self._handled == true then
        return
    end
    self._handled = true

    if g_server ~= nil and AuctionManager ~= nil and AuctionManager.onBidRequest ~= nil then
        AuctionManager:onBidRequest(connection, tonumber(self.steps) or 1, tonumber(self.clientFarmId) or 0, tonumber(self.farmlandId) or 0)
    end
end
