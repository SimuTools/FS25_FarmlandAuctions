FarmlandAuctionAdminCmdEvent = {}
local FarmlandAuctionAdminCmdEvent_mt = Class(FarmlandAuctionAdminCmdEvent, Event)
InitEventClass(FarmlandAuctionAdminCmdEvent, "FarmlandAuctionAdminCmdEvent")

function FarmlandAuctionAdminCmdEvent.emptyNew()
    return Event.new(FarmlandAuctionAdminCmdEvent_mt)
end

function FarmlandAuctionAdminCmdEvent.new(cmd, arg1, arg2)
    local self = FarmlandAuctionAdminCmdEvent.emptyNew()
    self.cmd  = tostring(cmd  or "")
    self.arg1 = tostring(arg1 or "")
    self.arg2 = tostring(arg2 or "")
    return self
end

function FarmlandAuctionAdminCmdEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.cmd)
    streamWriteString(streamId, self.arg1)
    streamWriteString(streamId, self.arg2)
end

function FarmlandAuctionAdminCmdEvent:readStream(streamId, connection)
    self.cmd  = streamReadString(streamId)
    self.arg1 = streamReadString(streamId)
    self.arg2 = streamReadString(streamId)
    self:run(connection)
end

function FarmlandAuctionAdminCmdEvent:run(connection)
    if g_server == nil then return end
    if AuctionManager == nil then return end

    local result = "Unknown command."
    local cmd = self.cmd

    if     cmd == "faStartNow"         then result = AuctionManager:consoleStartNow()
    elseif cmd == "faEndNow"           then result = AuctionManager:consoleEndNow()
    elseif cmd == "faCancelAuction"    then result = AuctionManager:consoleCancelAuction()
    elseif cmd == "faStartAuction"     then result = AuctionManager:consoleStartAuction(self.arg1 ~= "" and self.arg1 or nil)
    elseif cmd == "faSetAuctionTime"   then result = AuctionManager:consoleSetAuctionTime(
            self.arg1 ~= "" and self.arg1 or nil,
            self.arg2 ~= "" and self.arg2 or nil)
    elseif cmd == "faSetStartInterval" then result = AuctionManager:consoleSetStartInterval(
            self.arg1 ~= "" and self.arg1 or nil,
            self.arg2 ~= "" and self.arg2 or nil)
    elseif cmd == "faSetAuctionOnly"   then result = AuctionManager:consoleSetAuctionOnly(
            self.arg1 ~= "" and self.arg1 or nil)
    end

    result = tostring(result or "Done.")
    print("[FarmlandAuctions] AdminCmd '" .. cmd .. "' result: " .. result)

    if connection ~= nil then
        local curAuction = AuctionManager:getCurrentAuction()
        local state = (curAuction ~= nil and curAuction.toState ~= nil)
            and curAuction:toState() or { farmlandId = 0 }

        -- Important for MP/admin clients:
        -- consoleSetAuctionOnly() already broadcasts the correct, stamped state to all clients.
        -- Without stamping this direct admin response as well, the admin client receives a second
        -- private sync with auctionOnlyPurchase=nil/false and the map buy button becomes visible again.
        if AuctionManager._stampSyncSettings ~= nil then
            state = AuctionManager:_stampSyncSettings(state)
        else
            state.auctionOnlyPurchase = AuctionManager.settings ~= nil
                and AuctionManager.settings.auctionOnlyPurchase == true
        end

        local n = nil
        if cmd ~= "faStartNow" and cmd ~= "faStartAuction" then
            n = { kind = "TEXT", farmId = 0, price = 0, npcName = "[FA] " .. result }
        end

        connection:sendEvent(FarmlandAuctionSyncEvent.new(state, n))
    end
end
