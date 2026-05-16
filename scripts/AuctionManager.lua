AuctionManager = AuctionManager or {}

local MOD_NAME = g_currentModName or "FS25_FarmlandAuctions"
local MOD_DIR = g_currentModDirectory or ""
AuctionManager.DEBUG = false
AuctionManager.NPC_BIDDING = true
AuctionManager.PLAYER_BID_COOLDOWN_MS = 3000
AuctionManager.ACTION_BID = "FARMLAND_AUCTION_BID"
AuctionManager.SETTINGS_DIR = "modSettings/FS25_FarmlandAuctions"
AuctionManager.SETTINGS_FILE = AuctionManager.SETTINGS_DIR .. "/settings.xml"
AuctionManager.settings = {
    npcBiddingEnabled = true,
    auctionOnlyPurchase = false,
    auctionDurationMinHours = 24,
    auctionDurationMaxHours = 120,
    startDelayMinHours = 4,
    startDelayMaxHours = 18
}


print(string.format("[FarmlandAuctions] AuctionManager.lua LOADED (mod=%s)", tostring(MOD_NAME)))

local function dbg(fmt, ...)
    if AuctionManager.DEBUG then
        local ok, msg = pcall(string.format, "[FarmlandAuctions] " .. tostring(fmt), ...)
        if ok then print(msg) else print("[FarmlandAuctions] " .. tostring(fmt)) end
    end
end

local function i18nText(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local candidates = {
            {key, MOD_NAME},
            {key, g_currentModName},
            {key, nil}
        }

        for _, c in ipairs(candidates) do
            local ok, t
            if c[2] ~= nil and c[2] ~= "" then
                ok, t = pcall(g_i18n.getText, g_i18n, c[1], c[2])
            else
                ok, t = pcall(g_i18n.getText, g_i18n, c[1])
            end

            if ok and t ~= nil and t ~= "" and t ~= key then
                return t
            end
        end
    end

    return fallback or key
end

local function isServer()
    return g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer()
end

local function isClient()
    return g_currentMission ~= nil and g_currentMission.getIsClient ~= nil and g_currentMission:getIsClient()
end

local function nowHours()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return 0 end
    local dayMs = tonumber(env.dayTime or env:getEnvironmentTime() or 0) or 0
    return dayMs / 3600000 + (env.currentDay or 0) * 24
end

local function farmlandWord()
    if g_i18n ~= nil and g_i18n.getLanguageShort ~= nil then
        local ok, s = pcall(g_i18n.getLanguageShort, g_i18n)
        if ok and tostring(s) == "de" then return "Ackerland" end
    end
    return "Farmland"
end


local function formatFarmlandName(fid)
    return string.format("%s %d", farmlandWord(), tonumber(fid) or 0)
end

local function formatRemainingTimeShort(hours)
    hours = tonumber(hours) or 0
    local totalMinutes = math.max(0, math.floor(hours * 60 + 0.5))
    local h = math.floor(totalMinutes / 60)
    local m = totalMinutes - h * 60
    if h > 0 then
        return tostring(h) .. "h " .. string.format("%02d", m) .. "m"
    end
    return tostring(m) .. "m"
end

local function getFarmIdFromUser(user, connection)
    local farmId = 0

    local function readNumber(value)
        local n = tonumber(value or 0) or 0
        if n > 0 then
            farmId = n
            return true
        end
        return false
    end

    local function readFarmObject(farm)
        if farm == nil then return false end
        if readNumber(farm.farmId) then return true end
        if readNumber(farm.farmID) then return true end
        if readNumber(farm.id) then return true end
        return false
    end

    if user ~= nil then
        if type(user.getFarmId) == "function" then
            local ok, value = pcall(user.getFarmId, user)
            if ok and readNumber(value) then return farmId end
        end
        if type(user.getFarmID) == "function" then
            local ok, value = pcall(user.getFarmID, user)
            if ok and readNumber(value) then return farmId end
        end

        if readNumber(user.farmId) then return farmId end
        if readNumber(user.farmID) then return farmId end

        if type(user.getFarm) == "function" then
            local ok, farm = pcall(user.getFarm, user)
            if ok and readFarmObject(farm) then return farmId end
        end

        if readFarmObject(user.farm) then return farmId end

        if type(user.getId) == "function" and g_farmManager ~= nil and type(g_farmManager.getFarmByUserId) == "function" then
            local okUserId, userId = pcall(user.getId, user)
            if okUserId then
                local okFarm, farm = pcall(g_farmManager.getFarmByUserId, g_farmManager, userId)
                if okFarm and readFarmObject(farm) then return farmId end
            end
        end
    end

    if connection ~= nil then
        if type(connection.getFarmId) == "function" then
            local ok, value = pcall(connection.getFarmId, connection)
            if ok and readNumber(value) then return farmId end
        end
        if type(connection.getFarmID) == "function" then
            local ok, value = pcall(connection.getFarmID, connection)
            if ok and readNumber(value) then return farmId end
        end
        if type(connection.getPlayer) == "function" then
            local ok, player = pcall(connection.getPlayer, connection)
            if ok and player ~= nil then
                if readNumber(player.farmId) then return farmId end
                if player.user ~= nil and player.user ~= user then
                    local f = getFarmIdFromUser(player.user, nil)
                    if f > 0 then return f end
                end
            end
        end

        if readNumber(connection.farmId) then return farmId end
        if readNumber(connection.farmID) then return farmId end
        if connection.player ~= nil and readNumber(connection.player.farmId) then return farmId end
        if connection.user ~= nil and connection.user ~= user then
            local f = getFarmIdFromUser(connection.user, nil)
            if f > 0 then return f end
        end
    end

    return farmId
end

local function getLocalFarmIdSafe()
    local function readNumber(value)
        local n = tonumber(value or 0) or 0
        if n > 0 then return n end
        return 0
    end

    local function readFarmObject(farm)
        if farm == nil then return 0 end
        return readNumber(farm.farmId) > 0 and readNumber(farm.farmId)
            or readNumber(farm.farmID) > 0 and readNumber(farm.farmID)
            or readNumber(farm.id)
    end

 
    if g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" then
        local ok, value = pcall(g_currentMission.getFarmId, g_currentMission)
        local n = ok and readNumber(value) or 0
        if n > 0 then return n end
    end

    if g_currentMission ~= nil then
        local n = readNumber(g_currentMission.farmId)
        if n > 0 then return n end

        if g_currentMission.player ~= nil then
            n = readNumber(g_currentMission.player.farmId)
            if n > 0 then return n end
            n = readNumber(g_currentMission.player.farmID)
            if n > 0 then return n end
        end

        if g_currentMission.controlledVehicle ~= nil then
            local v = g_currentMission.controlledVehicle
            if type(v.getActiveFarm) == "function" then
                local ok, value = pcall(v.getActiveFarm, v)
                n = ok and readNumber(value) or 0
                if n > 0 then return n end
            end
            if type(v.getOwnerFarmId) == "function" then
                local ok, value = pcall(v.getOwnerFarmId, v)
                n = ok and readNumber(value) or 0
                if n > 0 then return n end
            end
        end

        if g_currentMission.missionInfo ~= nil then
            n = readNumber(g_currentMission.missionInfo.playerFarmId)
            if n > 0 then return n end
        end
    end

    if g_localPlayer ~= nil then
        local n = readNumber(g_localPlayer.farmId)
        if n > 0 then return n end
        n = readNumber(g_localPlayer.farmID)
        if n > 0 then return n end
    end


    if g_farmManager ~= nil and g_farmManager.getFarms ~= nil then
        local ok, farms = pcall(g_farmManager.getFarms, g_farmManager)
        if ok and farms ~= nil then
            for _, farm in pairs(farms) do
                local n = readFarmObject(farm)
                if n > 0 and n ~= FarmlandManager.SPECTATOR_FARM_ID then
                    return n
                end
            end
        end
    end

    return 0
end

local function getFarmDisplayNameSafe(farmId)
    farmId = tonumber(farmId or 0) or 0
    if farmId <= 0 then
        return nil
    end

    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local ok, farm = pcall(g_farmManager.getFarmById, g_farmManager, farmId)
        if ok and farm ~= nil and farm.name ~= nil and tostring(farm.name) ~= "" then
            return tostring(farm.name)
        end
    end

    return i18nText("Farm", "Farm") .. tostring(farmId)
end

local function ensureAuctionOriginalPrice(auction)
    if auction == nil or g_farmlandManager == nil then
        return
    end

    local farmlandId = tonumber(auction.farmlandId or 0) or 0
    if farmlandId == 0 then
        return
    end

    local farmland = g_farmlandManager:getFarmlandById(farmlandId)
    if farmland == nil then
        return
    end

    local originalPrice = math.max(
        tonumber(auction.originalPrice or 0) or 0,
        tonumber(auction.maxPrice or 0) or 0,
        tonumber(farmland.faOriginalPrice or 0) or 0,
        tonumber(farmland.price or 0) or 0
    )

    if originalPrice > 0 then
        auction.originalPrice = originalPrice
        auction.maxPrice = math.max(originalPrice, tonumber(auction.maxPrice or 0) or 0)
        farmland.faOriginalPrice = originalPrice
    end
end

function bidderDisplayNameFromNotification(n)
    if n == nil then return "" end
    if n.kind == "NPC_HIGHEST" then
        return tostring(n.npcName or "NPC")
    end
    if n.kind == "FARM_HIGHEST" then
        return i18nText("Farm", "Farm") .. " " .. tostring(n.farmId or 0)
    end
    return ""
end

local function getPlayerFarmlandId()
    local fm = g_farmlandManager
    if fm == nil then return 0 end

    local x, z
    local m = g_currentMission

    local function useNode(node)
        if node ~= nil then
            local px, _, pz = getWorldTranslation(node)
            x, z = tonumber(px) or 0, tonumber(pz) or 0
            return true
        end
        return false
    end

    if m ~= nil and m.controlledVehicle ~= nil and m.controlledVehicle.rootNode ~= nil then
        useNode(m.controlledVehicle.rootNode)
    end

    if (x == nil or z == nil or (x == 0 and z == 0)) and m ~= nil and m.player ~= nil and m.player.rootNode ~= nil then
        useNode(m.player.rootNode)
    end

    if (x == nil or z == nil or (x == 0 and z == 0)) and g_localPlayer ~= nil and g_localPlayer.rootNode ~= nil then
        useNode(g_localPlayer.rootNode)
    end

    if x == nil or z == nil then
        return 0
    end

    local fid = 0
    if fm.getFarmlandAtWorldPosition ~= nil then
        local f = fm:getFarmlandAtWorldPosition(x, z)
        if f ~= nil and f.id ~= nil then
            fid = tonumber(f.id) or 0
        end
    end
    if fid == 0 and fm.getFarmlandIdAtWorldPosition ~= nil then
        fid = tonumber(fm:getFarmlandIdAtWorldPosition(x, z) or 0) or 0
    end

    return fid
end

local function isAuctionRunning(auction)
    if auction == nil then return false end
    local fid = tonumber(auction.farmlandId or 0) or 0
    if fid == 0 then return false end

    local hasStarted = auction.hasStarted
    local startTime = tonumber(auction.startTime or 0) or 0

    if hasStarted == true or hasStarted == 1 or hasStarted == "1" or hasStarted == "true" then
        return true
    end
    if startTime > 0 and nowHours() >= startTime then
        return true
    end
    return false
end

local unownedFarmlandIds = {}
local currentAuction = nil
local _buyableOriginalState = {}
local _buyableAppliedState = {}

local _purchaseHooksInstalled = false

local function getFarmlandOwnerSafe(farmlandId)
    if g_farmlandManager == nil then
        return 0
    end
    return tonumber(g_farmlandManager:getFarmlandOwner(tonumber(farmlandId) or 0) or 0) or 0
end

function AuctionManager:isFarmlandBlockedForStandardPurchase(farmlandId)
    farmlandId = tonumber(farmlandId) or 0
    if farmlandId == 0 then
        return false
    end

    local ownerId = getFarmlandOwnerSafe(farmlandId)
    if ownerId ~= FarmlandManager.NO_OWNER_FARM_ID and ownerId ~= FarmlandManager.NOT_BUYABLE_FARM_ID then
        return false
    end

    if currentAuction ~= nil then
        local activeAuctionFarmlandId = tonumber(currentAuction.farmlandId or 0) or 0
        if activeAuctionFarmlandId ~= 0 and farmlandId == activeAuctionFarmlandId then
            return true
        end
    end

    if self.settings ~= nil and self.settings.auctionOnlyPurchase == true then
        return true
    end

    return false
end

function AuctionManager:installPurchaseHooks()
    if _purchaseHooksInstalled then
        return
    end

    local function overwriteMethod(tbl, methodName, func)
        if tbl ~= nil and tbl[methodName] ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
            tbl[methodName] = Utils.overwrittenFunction(tbl[methodName], func)
            return true
        end
        return false
    end

    local hooked = false

    local function resolveFarmlandId(a, b)
        local idA = tonumber(a) or 0
        local idB = tonumber(b) or 0
        local hasA = idA ~= 0 and g_farmlandManager ~= nil and g_farmlandManager:getFarmlandById(idA) ~= nil
        local hasB = idB ~= 0 and g_farmlandManager ~= nil and g_farmlandManager:getFarmlandById(idB) ~= nil

        if hasA and not hasB then
            return idA
        end
        if hasB and not hasA then
            return idB
        end
        if hasA then
            return idA
        end
        return idB
    end

    local function canBuyOverride(selfObj, superFunc, a, b, ...)
        local farmlandId = resolveFarmlandId(a, b)
        local result = superFunc(selfObj, a, b, ...)
        if AuctionManager:isFarmlandBlockedForStandardPurchase(farmlandId) then
            return false
        end
        return result
    end

    local function buyOverride(selfObj, superFunc, a, b, ...)
        local farmlandId = resolveFarmlandId(a, b)
        if AuctionManager:isFarmlandBlockedForStandardPurchase(farmlandId) then
            return false
        end
        return superFunc(selfObj, a, b, ...)
    end

    if FarmlandManager ~= nil then
        hooked = overwriteMethod(FarmlandManager, 'canFarmBuyFarmland', canBuyOverride) or hooked
        hooked = overwriteMethod(FarmlandManager, 'getCanFarmBuyFarmland', canBuyOverride) or hooked
        hooked = overwriteMethod(FarmlandManager, 'canBuyFarmland', canBuyOverride) or hooked
        hooked = overwriteMethod(FarmlandManager, 'getCanBuyFarmland', canBuyOverride) or hooked
        hooked = overwriteMethod(FarmlandManager, 'buyFarmland', buyOverride) or hooked
    end

    _purchaseHooksInstalled = true
    print(string.format('[FarmlandAuctions] Purchase hooks installed=%s', tostring(hooked)))
end


local function getModSettingsRootDir()
    local base = getUserProfileAppPath and getUserProfileAppPath() or ""
    if base == nil or base == "" then
        return nil
    end
    return base .. AuctionManager.SETTINGS_DIR
end

local function getModSettingsFilePath()
    local dir = getModSettingsRootDir()
    if dir == nil then
        return nil
    end
    return dir .. "/settings.xml"
end

local function getFarmlandBuyableState(farmland)
    if farmland == nil then
        return nil, nil
    end
    if farmland.isBuyable ~= nil then
        return farmland.isBuyable == true, "isBuyable"
    end
    if farmland.buyable ~= nil then
        return farmland.buyable == true, "buyable"
    end
    if farmland.canBeBought ~= nil then
        return farmland.canBeBought == true, "canBeBought"
    end
    return nil, nil
end

local function setFarmlandBuyableState(farmland, state)
    if farmland == nil then
        return false
    end

    local value = state == true
    local changed = false

    if farmland.isBuyable ~= nil then
        farmland.isBuyable = value
        changed = true
    end
    if farmland.buyable ~= nil then
        farmland.buyable = value
        changed = true
    end
    if farmland.canBeBought ~= nil then
        farmland.canBeBought = value
        changed = true
    end

    return changed
end

function AuctionManager:loadSettings()
    local path = getModSettingsFilePath()
    self.settings = self.settings or {}
    self.settings.npcBiddingEnabled = true
    self.settings.auctionOnlyPurchase = false
    self.settings.auctionDurationMinHours = 24
    self.settings.auctionDurationMaxHours = 120
    self.settings.startDelayMinHours = 4
    self.settings.startDelayMaxHours = 18

    if path == nil or not fileExists(path) then
        self:saveSettings()
        AuctionManager.NPC_BIDDING = self.settings.npcBiddingEnabled == true
        return
    end

    local xml = loadXMLFile("faSettingsXml", path)
    if xml ~= nil and xml ~= 0 then
        local npcEnabled = getXMLBool(xml, "settings#npcBiddingEnabled")
        local auctionOnly = getXMLBool(xml, "settings#auctionOnlyPurchase")
        local minHours = getXMLInt(xml, "settings#auctionDurationMinHours")
        local maxHours = getXMLInt(xml, "settings#auctionDurationMaxHours")
        local startDelayMin = getXMLInt(xml, "settings#startDelayMinHours")
        local startDelayMax = getXMLInt(xml, "settings#startDelayMaxHours")

        if npcEnabled ~= nil then
            self.settings.npcBiddingEnabled = npcEnabled == true
        end
        if auctionOnly ~= nil then
            self.settings.auctionOnlyPurchase = auctionOnly == true
        end
        if minHours ~= nil then
            self.settings.auctionDurationMinHours = math.max(1, tonumber(minHours) or 24)
        end
        if maxHours ~= nil then
            self.settings.auctionDurationMaxHours = math.max(self.settings.auctionDurationMinHours, tonumber(maxHours) or 120)
        end
        if startDelayMin ~= nil then
            self.settings.startDelayMinHours = math.max(1, tonumber(startDelayMin) or 4)
        end
        if startDelayMax ~= nil then
            self.settings.startDelayMaxHours = math.max(self.settings.startDelayMinHours, tonumber(startDelayMax) or 18)
        end

        delete(xml)
    end

    AuctionManager.NPC_BIDDING = self.settings.npcBiddingEnabled == true
end

function AuctionManager:saveSettings()
    local path = getModSettingsFilePath()
    if path == nil then
        return false
    end

    local dir = getModSettingsRootDir()
    if dir ~= nil and createFolder ~= nil then
        createFolder(dir)
    end

    local xml = createXMLFile("faSettingsXml", path, "settings")
    if xml == nil or xml == 0 then
        return false
    end

    local minHours = 24
    local maxHours = 120
    local startDelayMin = 4
    local startDelayMax = 18
    if self.settings ~= nil then
        minHours = math.max(1, tonumber(self.settings.auctionDurationMinHours) or 24)
        maxHours = math.max(minHours, tonumber(self.settings.auctionDurationMaxHours) or 120)
        self.settings.auctionDurationMinHours = minHours
        self.settings.auctionDurationMaxHours = maxHours
        startDelayMin = math.max(1, tonumber(self.settings.startDelayMinHours) or 4)
        startDelayMax = math.max(startDelayMin, tonumber(self.settings.startDelayMaxHours) or 18)
        self.settings.startDelayMinHours = startDelayMin
        self.settings.startDelayMaxHours = startDelayMax
    end

    setXMLBool(xml, "settings#npcBiddingEnabled", self.settings ~= nil and self.settings.npcBiddingEnabled == true)
    setXMLBool(xml, "settings#auctionOnlyPurchase", self.settings ~= nil and self.settings.auctionOnlyPurchase == true)
    setXMLInt(xml, "settings#auctionDurationMinHours", minHours)
    setXMLInt(xml, "settings#auctionDurationMaxHours", maxHours)
    setXMLInt(xml, "settings#startDelayMinHours", startDelayMin)
    setXMLInt(xml, "settings#startDelayMaxHours", startDelayMax)
    saveXMLFile(xml)
    delete(xml)

    return true
end

function AuctionManager:restoreBuyableStates()
    local farmlands = g_farmlandManager and g_farmlandManager:getFarmlands() or nil
    if farmlands == nil then
        return
    end

    for farmlandId, data in pairs(_buyableOriginalState) do
        local farmland = farmlands[tonumber(farmlandId) or 0]
        if farmland ~= nil and data ~= nil then
            setFarmlandBuyableState(farmland, data.value == true)
        end
    end

    _buyableOriginalState = {}
    _buyableAppliedState = {}
end

function AuctionManager:applyFarmlandPurchaseRules()
    local farmlands = g_farmlandManager and g_farmlandManager:getFarmlands() or nil
    if farmlands == nil then
        return
    end

    local auctionOnly = self.settings ~= nil and self.settings.auctionOnlyPurchase == true
    local activeAuctionFarmlandId = 0

    if currentAuction ~= nil and isAuctionRunning(currentAuction) then
        activeAuctionFarmlandId = tonumber(currentAuction.farmlandId or 0) or 0
    end

    local desired = {}

    for id, farmland in pairs(farmlands) do
        local farmlandId = tonumber(id) or 0
        local ownerId = tonumber(g_farmlandManager:getFarmlandOwner(farmlandId) or 0) or 0
        local currentValue, key = getFarmlandBuyableState(farmland)

        if key ~= nil and ownerId == FarmlandManager.NO_OWNER_FARM_ID then
            local forceDisabled = false

            if activeAuctionFarmlandId ~= 0 and farmlandId == activeAuctionFarmlandId then
                forceDisabled = true
            elseif auctionOnly then
                forceDisabled = true
            end

            if forceDisabled then
                desired[farmlandId] = false
                if _buyableOriginalState[farmlandId] == nil then
                    _buyableOriginalState[farmlandId] = { value = currentValue == true }
                end
            elseif _buyableOriginalState[farmlandId] ~= nil then
                desired[farmlandId] = _buyableOriginalState[farmlandId].value == true
            end
        elseif _buyableOriginalState[farmlandId] ~= nil then
            desired[farmlandId] = _buyableOriginalState[farmlandId].value == true
        end
    end

    for farmlandId, state in pairs(desired) do
        local farmland = farmlands[tonumber(farmlandId) or 0]
        if farmland ~= nil then
            local currentValue = ({getFarmlandBuyableState(farmland)})[1]
            if currentValue ~= state or _buyableAppliedState[farmlandId] ~= state then
                setFarmlandBuyableState(farmland, state)
                _buyableAppliedState[farmlandId] = state
            end

            if _buyableOriginalState[farmlandId] ~= nil and state == (_buyableOriginalState[farmlandId].value == true) then
                _buyableOriginalState[farmlandId] = nil
                _buyableAppliedState[farmlandId] = nil
            end
        end
    end
end

function AuctionManager:getAuctionDurationRangeHours()
    local minHours = 24
    local maxHours = 120

    if self.settings ~= nil then
        minHours = math.max(1, tonumber(self.settings.auctionDurationMinHours) or minHours)
        maxHours = math.max(minHours, tonumber(self.settings.auctionDurationMaxHours) or maxHours)
    end

    return minHours, maxHours
end

function AuctionManager:getRandomAuctionDurationHours()
    local minHours, maxHours = self:getAuctionDurationRangeHours()
    if minHours >= maxHours then
        return minHours
    end
    return math.random(minHours, maxHours)
end

function AuctionManager:getCurrentAuction()
    return currentAuction
end

local isInitialized = false
local savePath = nil

local dirtyState = false
local lastSyncMs = 0
local _joinSyncMs = 0
local _lastKnownClientCount = -1
local _didStartNotify = false
local _bidCooldownUntilByFarm = {}
local _localOneHourWarningByFarmland = {}
local _localThirtyMinuteWarningByFarmland = {}

local _lastNoticeKey = ""
local _lastNoticeMs = 0
local function shouldEmit(key)
    local t = g_time or 0
    if key == _lastNoticeKey and (t - (_lastNoticeMs or 0)) < 1500 then
        return false
    end
    _lastNoticeKey = key
    _lastNoticeMs = t
    return true
end


local function showLocalEndWarnings(auction)
    if isServer() then
        return
    end

    if not isClient() or auction == nil or auction.hasStarted ~= true or g_currentMission == nil then
        return
    end

    local fid = tonumber(auction.farmlandId or 0) or 0
    if fid <= 0 then
        return
    end

    local remaining = math.max(0, tonumber(auction:remainingTimeHours()) or 0)
    if remaining <= 0 then
        return
    end

    if remaining <= 1 and _localOneHourWarningByFarmland[fid] ~= true then
        _localOneHourWarningByFarmland[fid] = true
        if shouldEmit("warn1hLocal:" .. tostring(fid)) then
            g_currentMission:addIngameNotification({1, 0.84, 0, 1}, i18nText("EndInOneHour", "The auction ends in one hour!"), MOD_NAME)
        end
    end

    if remaining <= 0.5 and _localThirtyMinuteWarningByFarmland[fid] ~= true then
        _localThirtyMinuteWarningByFarmland[fid] = true
        if shouldEmit("warn30mLocal:" .. tostring(fid)) then
            g_currentMission:addIngameNotification({1, 0.84, 0, 1}, i18nText("EndInThirtyMinutes", "The auction ends in 30 minutes!"), MOD_NAME)
        end
    end
end

local function makeAuctionStartedNotification(auction)
    if auction == nil then
        return nil
    end

    local hoursLeft = math.max(0, (tonumber(auction.endTime or 0) or 0) - nowHours())
    return {
        kind = "AUCTION_STARTED",
        farmlandId = tonumber(auction.farmlandId or 0) or 0,
        price = tonumber(auction.currentPrice or auction.normalPrice or 0) or 0,
        hours = hoursLeft,
        npcName = tostring(auction.name or formatFarmlandName(auction.farmlandId or 0)),
        count = 0,
        farmId = 0
    }
end

local function formatAuctionStartedMessage(n)
    local name = tostring(n and n.npcName or "")
    if name == "" then
        name = formatFarmlandName(n and n.farmlandId or 0)
    end

    local hoursLeft = tonumber(n and n.hours or 0) or 0
    return i18nText("NewAuction", "New auction:")
        .. " "
        .. name
        .. " "
        .. i18nText("EndsLess", "ends in")
        .. " "
        .. formatRemainingTimeShort(hoursLeft)
end

AuctionManager._fa_actionEventId = AuctionManager._fa_actionEventId or nil
AuctionManager._fa_lastActive   = AuctionManager._fa_lastActive   or false
AuctionManager._fa_registered   = AuctionManager._fa_registered   or false

local _ringHotspots = {}
local _ringFarmlandId = 0
local _ringMs = 0
local _ringOn = true
local _ringIntervalMs = 450

local _ringPendingFarmlandId = 0
local _ringBuildPending = false
local _ringLastPostponePrintMs = 0
local _ringRetryMs = 0

local function updateRingBlink(dt)
    if _ringFarmlandId == 0 or _ringHotspots == nil or #_ringHotspots == 0 then
        return
    end

    _ringMs = (_ringMs or 0) + (dt or 0)
    if _ringMs < (_ringIntervalMs or 450) then
        return
    end

    _ringMs = 0
    _ringOn = not _ringOn

    local r, g, b, a = 1.00, 0.55, 0.00, 1.0

    if currentAuction ~= nil and tonumber(currentAuction.farmlandId or 0) == tonumber(_ringFarmlandId or 0) then
        local playerFarmId = 0
        if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
            playerFarmId = tonumber(g_localPlayer.farmId) or 0
        elseif g_currentMission ~= nil and g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
            playerFarmId = tonumber(g_currentMission.player.farmId) or 0
        end

        local playerHasBid = false
        if playerFarmId > 0 and currentAuction.bidHistory ~= nil then
            for i = 1, #currentAuction.bidHistory do
                local item = currentAuction.bidHistory[i]
                if item ~= nil and (tonumber(item.farmId or 0) or 0) == playerFarmId then
                    playerHasBid = true
                    break
                end
            end
        end

        local highestFarmId = tonumber(currentAuction.currentHighestFarmId or 0) or 0

        if playerFarmId > 0 and highestFarmId == playerFarmId then
            r, g, b, a = 0.15, 0.95, 0.20, 1.0
        elseif playerHasBid then
            r, g, b, a = 1.00, 0.10, 0.10, 1.0
        else
            r, g, b, a = 1.00, 0.55, 0.00, 1.0
        end
    end

    for i = 1, #_ringHotspots do
        local hs = _ringHotspots[i]
        if hs ~= nil then
            if hs.setVisible ~= nil then
                hs:setVisible(_ringOn)
            end
            if hs.setColor ~= nil then
                hs:setColor(r, g, b, a)
            end
        end
    end
end

function setRingTargetFarmland(farmlandId)
    farmlandId = tonumber(farmlandId) or 0

    local function removeAllHotspots()
        if g_currentMission ~= nil and g_currentMission.removeMapHotspot ~= nil then
            for i = #_ringHotspots, 1, -1 do
                local hs = _ringHotspots[i]
                if hs ~= nil then
                    pcall(function() g_currentMission:removeMapHotspot(hs) end)
                end
                table.remove(_ringHotspots, i)
            end
        else
            for i = #_ringHotspots, 1, -1 do
                table.remove(_ringHotspots, i)
            end
        end
    end

    local function canBuildNow()
        if g_currentMission == nil or g_currentMission.addMapHotspot == nil then return false end
        if MapHotspot == nil then return false end
        if g_farmlandManager == nil then return false end
        if g_farmlandManager.getFarmlandAtWorldPosition == nil and g_farmlandManager.getFarmlandIdAtWorldPosition == nil then return false end
        return true
    end

    local function fidAt(x, z)
        local fm = g_farmlandManager
        if fm == nil then return 0 end

        if fm.getFarmlandAtWorldPosition ~= nil then
            local f = fm:getFarmlandAtWorldPosition(x, z)
            if f ~= nil and f.id ~= nil then
                return tonumber(f.id) or 0
            end
        end

        if fm.getFarmlandIdAtWorldPosition ~= nil then
            return tonumber(fm:getFarmlandIdAtWorldPosition(x, z) or 0) or 0
        end

        return 0
    end

    if farmlandId == 0 then
        removeAllHotspots()
        _ringFarmlandId = 0
        _ringPendingFarmlandId = 0
        _ringBuildPending = false
        _ringMs = 0
        _ringOn = true
        return
    end

    if _ringFarmlandId == farmlandId and #_ringHotspots > 0 then
        return
    end

    if not canBuildNow() then
        _ringPendingFarmlandId = farmlandId
        _ringBuildPending = true

        local nowMs = g_time or 0
        if AuctionManager.DEBUG and (nowMs - (_ringLastPostponePrintMs or 0)) > 1500 then
            _ringLastPostponePrintMs = nowMs
            print(string.format("[FarmlandAuctions] [BLINK] postpone ring build farmlandId=%d", farmlandId))
        end
        return
    end

    removeAllHotspots()
    _ringFarmlandId = farmlandId
    _ringPendingFarmlandId = 0
    _ringBuildPending = false
    _ringMs = 0
    _ringOn = true

    local seeds = {}

    local terrainSize = 2048
    if g_currentMission ~= nil and g_currentMission.terrainSize ~= nil then
        terrainSize = tonumber(g_currentMission.terrainSize) or terrainSize
    elseif getTerrainSize ~= nil and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
        local ok, size = pcall(getTerrainSize, g_currentMission.terrainRootNode)
        if ok and size ~= nil then
            terrainSize = tonumber(size) or terrainSize
        end
    end

    local halfSize = terrainSize * 0.5
    local CELL = terrainSize >= 4096 and 12.0 or 8.0
    local SEED_SCAN_STEP = math.max(18.0, CELL * 3.0)
    local MAX_CELLS = terrainSize >= 4096 and 140000 or 90000
    local MAX_QUEUE = MAX_CELLS + 25000
    local MIN_POINT_DIST = CELL * 1.8
    local MAX_POINTS = terrainSize >= 4096 and 120 or 96

    if g_fieldManager ~= nil and g_fieldManager.fields ~= nil then
        for _, field in pairs(g_fieldManager.fields) do
            local ffid = 0
            if field ~= nil then
                if field.farmland ~= nil and field.farmland.id ~= nil then
                    ffid = tonumber(field.farmland.id) or 0
                elseif field.farmlandId ~= nil then
                    ffid = tonumber(field.farmlandId) or 0
                end
            end

            if ffid == farmlandId and field ~= nil and field.getCenterOfFieldWorldPosition ~= nil then
                local sx, sz = field:getCenterOfFieldWorldPosition()
                sx, sz = tonumber(sx) or 0, tonumber(sz) or 0
                if sx ~= 0 or sz ~= 0 then
                    seeds[#seeds + 1] = { x = sx, z = sz }
                end
            end
        end
    end

    local function cellKey(ix, iz)
        return tostring(ix) .. ":" .. tostring(iz)
    end

    local function cellCenter(ix, iz)
        return (ix + 0.5) * CELL, (iz + 0.5) * CELL
    end

    local function toCell(v)
        return math.floor(v / CELL)
    end

    local function findSeedByScan()
        for x = -halfSize, halfSize, SEED_SCAN_STEP do
            for z = -halfSize, halfSize, SEED_SCAN_STEP do
                if fidAt(x, z) == farmlandId then
                    return x, z
                end
            end
        end

        local finerStep = math.max(CELL, 10.0)
        for x = -halfSize, halfSize, finerStep do
            for z = -halfSize, halfSize, finerStep do
                if fidAt(x, z) == farmlandId then
                    return x, z
                end
            end
        end

        return nil, nil
    end

    if #seeds == 0 then
        local sx, sz = findSeedByScan()
        if sx ~= nil and sz ~= nil then
            seeds[#seeds + 1] = { x = sx, z = sz }
        end
    end

    local function floodFrom(seedX, seedZ)
        local startIX = toCell(seedX)
        local startIZ = toCell(seedZ)

        local bestIX = startIX
        local bestIZ = startIZ
        local found = false
        for radius = 0, 4 do
            if found then break end
            for dx = -radius, radius do
                for dz = -radius, radius do
                    local ix = startIX + dx
                    local iz = startIZ + dz
                    local testX, testZ = cellCenter(ix, iz)
                    if fidAt(testX, testZ) == farmlandId then
                        bestIX = ix
                        bestIZ = iz
                        found = true
                        break
                    end
                end
                if found then break end
            end
        end

        if not found then
            return nil
        end

        local qx, qz = {}, {}
        local qh, qt = 1, 0
        local visited = {}
        local cells = {}
        local count = 0

        local function push(ix, iz)
            local k = cellKey(ix, iz)
            if visited[k] then return end
            visited[k] = true
            qt = qt + 1
            if qt > MAX_QUEUE then return end
            qx[qt] = ix
            qz[qt] = iz
        end

        push(bestIX, bestIZ)

        while qh <= qt do
            local ix = qx[qh]
            local iz = qz[qh]
            qh = qh + 1

            local cx, cz = cellCenter(ix, iz)
            if fidAt(cx, cz) == farmlandId then
                local k = cellKey(ix, iz)
                if cells[k] == nil then
                    cells[k] = { ix = ix, iz = iz, x = cx, z = cz }
                    count = count + 1
                    if count > MAX_CELLS then break end
                end

                push(ix + 1, iz)
                push(ix - 1, iz)
                push(ix, iz + 1)
                push(ix, iz - 1)
            end
        end

        return { cells = cells, count = count }
    end

    local farmlandCells = {}
    local farmlandCellCount = 0

    local function mergeComponent(comp)
        if comp == nil or comp.cells == nil then
            return
        end
        for k, cell in pairs(comp.cells) do
            if farmlandCells[k] == nil then
                farmlandCells[k] = cell
                farmlandCellCount = farmlandCellCount + 1
            end
        end
    end

    for i = 1, #seeds do
        local s = seeds[i]
        mergeComponent(floodFrom(s.x, s.z))
    end

    if farmlandCellCount < 8 then
        for x = -halfSize, halfSize, CELL do
            for z = -halfSize, halfSize, CELL do
                if fidAt(x, z) == farmlandId then
                    local ix = toCell(x)
                    local iz = toCell(z)
                    local k = cellKey(ix, iz)
                    if farmlandCells[k] == nil then
                        local cx, cz = cellCenter(ix, iz)
                        farmlandCells[k] = { ix = ix, iz = iz, x = cx, z = cz }
                        farmlandCellCount = farmlandCellCount + 1
                        if farmlandCellCount >= MAX_CELLS then
                            break
                        end
                    end
                end
            end
            if farmlandCellCount >= MAX_CELLS then
                break
            end
        end
    end

    if farmlandCellCount < 3 then
        print(string.format("[FarmlandAuctions] [BLINK] ERROR: farmland scan empty farmlandId=%d", farmlandId))
        return
    end

    local function hasCell(ix, iz)
        return farmlandCells[cellKey(ix, iz)] ~= nil
    end

    local edges = {}
    local adjacency = {}

    local function vertexKey(x, z)
        return tostring(x) .. ":" .. tostring(z)
    end

    local function addAdj(a, b)
        adjacency[a] = adjacency[a] or {}
        adjacency[a][#adjacency[a] + 1] = b
    end

    local function addEdge(x1, z1, x2, z2)
        local a = vertexKey(x1, z1)
        local b = vertexKey(x2, z2)
        local edgeKey = a < b and (a .. "|" .. b) or (b .. "|" .. a)
        if edges[edgeKey] ~= nil then
            return
        end

        edges[edgeKey] = {
            a = a,
            b = b,
            x1 = x1 * CELL,
            z1 = z1 * CELL,
            x2 = x2 * CELL,
            z2 = z2 * CELL
        }

        addAdj(a, b)
        addAdj(b, a)
    end

    for _, c in pairs(farmlandCells) do
        local ix, iz = c.ix, c.iz

        if not hasCell(ix, iz - 1) then addEdge(ix, iz, ix + 1, iz) end
        if not hasCell(ix + 1, iz) then addEdge(ix + 1, iz, ix + 1, iz + 1) end
        if not hasCell(ix, iz + 1) then addEdge(ix + 1, iz + 1, ix, iz + 1) end
        if not hasCell(ix - 1, iz) then addEdge(ix, iz + 1, ix, iz) end
    end

    local edgeCount = 0
    for _ in pairs(edges) do
        edgeCount = edgeCount + 1
    end

    if edgeCount < 3 then
        print(string.format("[FarmlandAuctions] [BLINK] ERROR: boundary edge graph too small farmlandId=%d", farmlandId))
        return
    end

    local visitedEdges = {}
    local loops = {}

    local function makeEdgeVisitKey(a, b)
        return a < b and (a .. "|" .. b) or (b .. "|" .. a)
    end

    local function parseVertex(v)
        local sx, sz = string.match(v, "([^:]+):([^:]+)")
        return (tonumber(sx) or 0) * CELL, (tonumber(sz) or 0) * CELL
    end

    local function traceLoop(startVertex, nextVertex)
        local loop = {}
        local prev = startVertex
        local current = nextVertex
        local sx, sz = parseVertex(startVertex)
        loop[#loop + 1] = { x = sx, z = sz }

        local guard = 0
        while current ~= nil and guard < 300000 do
            guard = guard + 1
            local cx, cz = parseVertex(current)
            loop[#loop + 1] = { x = cx, z = cz }

            visitedEdges[makeEdgeVisitKey(prev, current)] = true
            local neighbors = adjacency[current] or {}
            local candidate = nil

            for i = 1, #neighbors do
                local n = neighbors[i]
                if n ~= prev then
                    local visitKey = makeEdgeVisitKey(current, n)
                    if not visitedEdges[visitKey] or n == startVertex then
                        candidate = n
                        break
                    end
                end
            end

            if candidate == nil then
                for i = 1, #neighbors do
                    local n = neighbors[i]
                    if n == startVertex then
                        candidate = n
                        break
                    end
                end
            end

            if candidate == nil then
                break
            end

            if candidate == startVertex then
                visitedEdges[makeEdgeVisitKey(current, candidate)] = true
                break
            end

            prev, current = current, candidate
        end

        return loop
    end

    for vertex, neighbors in pairs(adjacency) do
        for i = 1, #neighbors do
            local neighbor = neighbors[i]
            local visitKey = makeEdgeVisitKey(vertex, neighbor)
            if not visitedEdges[visitKey] then
                local loop = traceLoop(vertex, neighbor)
                if loop ~= nil and #loop >= 4 then
                    loops[#loops + 1] = loop
                end
            end
        end
    end

    if #loops == 0 then
        print(string.format("[FarmlandAuctions] [BLINK] ERROR: no boundary loops farmlandId=%d", farmlandId))
        return
    end

    local function loopPerimeter(loop)
        local total = 0
        if loop == nil or #loop < 2 then
            return total
        end
        for i = 1, #loop do
            local a = loop[i]
            local b = loop[(i % #loop) + 1]
            local dx = (b.x or 0) - (a.x or 0)
            local dz = (b.z or 0) - (a.z or 0)
            total = total + math.sqrt(dx * dx + dz * dz)
        end
        return total
    end

    table.sort(loops, function(a, b)
        return loopPerimeter(a) > loopPerimeter(b)
    end)

    local function loopArea(loop)
        local area = 0
        if loop == nil or #loop < 3 then
            return 0
        end
        for i = 1, #loop do
            local a = loop[i]
            local b = loop[(i % #loop) + 1]
            area = area + ((a.x or 0) * (b.z or 0) - (b.x or 0) * (a.z or 0))
        end
        return math.abs(area) * 0.5
    end

    local filteredLoops = {}
    local totalPerimeter = 0
    local mainArea = loopArea(loops[1])
    for i = 1, #loops do
        local loop = loops[i]
        local perimeter = loopPerimeter(loop)
        local area = loopArea(loop)
        if perimeter >= CELL * 6 and (i == 1 or area >= math.max(CELL * CELL * 6, mainArea * 0.015)) then
            filteredLoops[#filteredLoops + 1] = loop
            totalPerimeter = totalPerimeter + perimeter
        end
    end
    loops = filteredLoops

    if #loops == 0 then
        print(string.format("[FarmlandAuctions] [BLINK] ERROR: no usable boundary loops farmlandId=%d", farmlandId))
        return
    end

    local samplePoints = {}
    local sampleKeys = {}

    local function addSamplePoint(x, z)
        local k = string.format("%d:%d", math.floor(x / math.max(1, CELL * 0.7)), math.floor(z / math.max(1, CELL * 0.7)))
        if sampleKeys[k] then
            return
        end
        sampleKeys[k] = true
        samplePoints[#samplePoints + 1] = { x = x, z = z }
    end

    local function sampleLoop(loop, targetSpacing, pointBudget)
        if loop == nil or #loop < 2 or pointBudget <= 0 then
            return
        end

        local perimeter = loopPerimeter(loop)
        if perimeter <= 0 then
            return
        end

        local spacing = math.max(targetSpacing, perimeter / math.max(1, pointBudget))
        local placed = 0
        local distanceToNext = 0

        for i = 1, #loop do
            if placed >= pointBudget then
                break
            end

            local a = loop[i]
            local b = loop[(i % #loop) + 1]
            local dx = (b.x or 0) - (a.x or 0)
            local dz = (b.z or 0) - (a.z or 0)
            local segLen = math.sqrt(dx * dx + dz * dz)

            if segLen > 0 then
                local traveled = distanceToNext
                while traveled <= segLen and placed < pointBudget do
                    local t = traveled / segLen
                    addSamplePoint(a.x + dx * t, a.z + dz * t)
                    placed = placed + 1
                    traveled = traveled + spacing
                end
                distanceToNext = traveled - segLen
            end
        end
    end

    local remainingBudget = MAX_POINTS
    for i = 1, #loops do
        local perimeter = loopPerimeter(loops[i])
        local budget = math.max(8, math.floor(MAX_POINTS * (perimeter / math.max(1, totalPerimeter)) + 0.5))
        if i == #loops then
            budget = remainingBudget
        else
            budget = math.min(budget, remainingBudget - math.max(0, (#loops - i) * 6))
        end
        budget = math.max(0, math.min(budget, remainingBudget))
        remainingBudget = remainingBudget - budget
        sampleLoop(loops[i], MIN_POINT_DIST, budget)
    end

    if #samplePoints < 4 then
        local mainLoop = loops[1]
        if mainLoop ~= nil then
            for i = 1, #mainLoop do
                addSamplePoint(mainLoop[i].x, mainLoop[i].z)
                if #samplePoints >= MAX_POINTS then
                    break
                end
            end
        end
    end

    table.sort(samplePoints, function(a, b)
        if a.x == b.x then
            return a.z < b.z
        end
        return a.x < b.x
    end)
    local r, g, b, a = 1.00, 0.55, 0.00, 1
    if currentAuction ~= nil and tonumber(currentAuction.farmlandId or 0) == farmlandId then
        local playerFarmId = 0
        if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
            playerFarmId = tonumber(g_localPlayer.farmId) or 0
        elseif g_currentMission ~= nil and g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
            playerFarmId = tonumber(g_currentMission.player.farmId) or 0
        end

        local playerHasBid = false
        if playerFarmId > 0 and currentAuction.bidHistory ~= nil then
            for i = 1, #currentAuction.bidHistory do
                local item = currentAuction.bidHistory[i]
                if item ~= nil and (tonumber(item.farmId or 0) or 0) == playerFarmId then
                    playerHasBid = true
                    break
                end
            end
        end

        local highestFarmId = tonumber(currentAuction.currentHighestFarmId or 0) or 0

        if playerFarmId > 0 and highestFarmId == playerFarmId then
            r, g, b, a = 0.15, 0.95, 0.20, 1
        elseif playerHasBid then
            r, g, b, a = 1.00, 0.10, 0.10, 1
        else
            r, g, b, a = 1.00, 0.55, 0.00, 1
        end
    end

    local scale = 2.5
    local w0, h0 = getNormalizedScreenValues(36, 36)

    for i = 1, #samplePoints do
        local hs = MapHotspot.new()
        hs.width  = w0 * scale
        hs.height = h0 * scale

        if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
            hs.icon = g_overlayManager:createOverlay("mapHotspots.other", 0, 0, hs.width, hs.height)
        end

        if hs.setWorldPosition ~= nil then hs:setWorldPosition(samplePoints[i].x, samplePoints[i].z) end
        if hs.setColor ~= nil then hs:setColor(r, g, b, a) end
        if hs.setVisible ~= nil then hs:setVisible(true) end

        g_currentMission:addMapHotspot(hs)
        _ringHotspots[#_ringHotspots + 1] = hs
    end

    if AuctionManager.DEBUG then
        print(string.format("[FarmlandAuctions] [BLINK] ring built farmlandId=%d points=%d loops=%d cell=%.1fm", farmlandId, #samplePoints, #loops, CELL))
    end
end

local function _sendAdminCmd(cmd, arg1, arg2)
    if g_client == nil then
        print("[FA] _sendAdminCmd: g_client is nil, cannot send " .. tostring(cmd))
        return nil
    end
    if not (g_currentMission and g_currentMission.isMasterUser) then
        return "[FA] Permission denied. Must be logged in as admin."
    end
    print("[FA] _sendAdminCmd: sending " .. tostring(cmd))
    g_client:getServerConnection():sendEvent(FarmlandAuctionAdminCmdEvent.new(cmd, arg1, arg2))
    return "[FA] Command sent to server: " .. tostring(cmd)
end

function AuctionManager:_registerConsoleCmdOnce()
    if self._consoleRegistered then return end
    self._consoleRegistered = true

    if addConsoleCommand ~= nil then
        addConsoleCommand("faStartNow",        "FarmlandAuctions: start current/next auction immediately (admin).",        "consoleStartNow",        self)
        addConsoleCommand("faEndNow",          "FarmlandAuctions: end current auction immediately (admin).",               "consoleEndNow",          self)
        addConsoleCommand("faCancelAuction",   "FarmlandAuctions: cancel current auction without selling (admin).",        "consoleCancelAuction",   self)
        addConsoleCommand("faStartAuction",    "FarmlandAuctions: start auction for a specific farmlandId (admin).",       "consoleStartAuction",    self)
        addConsoleCommand("faSetAuctionTime",  "FarmlandAuctions: set min/max auction duration hours (admin).",            "consoleSetAuctionTime",  self)
        addConsoleCommand("faSetStartInterval","FarmlandAuctions: set min/max hours until next auction starts (admin).",   "consoleSetStartInterval",self)
        addConsoleCommand("faSetAuctionOnly",  "FarmlandAuctions: toggle auction-only purchase mode on/off (admin).",      "consoleSetAuctionOnly",  self)
        print("[FarmlandAuctions] Console commands registered (faStartNow, faEndNow, faCancelAuction, faStartAuction, faSetAuctionTime, faSetStartInterval, faSetAuctionOnly)")
    end
end

function AuctionManager:consoleStartNow()
    if not isServer() then
        return _sendAdminCmd("faStartNow") or "Server or admin only."
    end

    if not isInitialized then
        return "Not initialized yet."
    end

    local now = nowHours()

    if currentAuction ~= nil then
        ensureAuctionOriginalPrice(currentAuction)

        local oldStartTime = tonumber(currentAuction.startTime or now) or now
        local oldEndTime = tonumber(currentAuction.endTime or (oldStartTime + 24)) or (oldStartTime + 24)
        local duration = math.max(24, oldEndTime - oldStartTime)
        local shift = now - oldStartTime

        currentAuction.startTime = now
        currentAuction.endTime = now + duration
        currentAuction.hasStarted = true
        currentAuction.oneHourWarningSent = false
        currentAuction.thirtyMinWarningSent = false
        currentAuction.lastBidTime = 0

        local firstNpc = nil

        if currentAuction.npcBidders ~= nil then
            for i = 1, #currentAuction.npcBidders do
                local npc = currentAuction.npcBidders[i]
                if npc ~= nil then
                    if npc.bidSlots ~= nil then
                        for j = 1, #npc.bidSlots do
                            npc.bidSlots[j] = (tonumber(npc.bidSlots[j]) or oldStartTime) + shift
                        end
                        table.sort(npc.bidSlots)
                    end

                    npc.forcedReaction = false

                    if npc.active ~= false then
                        if firstNpc == nil or (tonumber(npc.maxBid or 0) or 0) > (tonumber(firstNpc.maxBid or 0) or 0) then
                            firstNpc = npc
                        end
                    end
                end
            end
        end

        local firstNpcDue = now + 0.002

        if firstNpc ~= nil then
            firstNpc.nextBidTime = firstNpcDue
            firstNpc.forcedReaction = true

            if firstNpc.bidSlots ~= nil and #firstNpc.bidSlots > 0 then
                firstNpc.bidSlots[1] = firstNpcDue
                table.sort(firstNpc.bidSlots)
            end
        end

        currentAuction.nextNpcGlobalBidTime = firstNpcDue

        _didStartNotify = true
        dirtyState = true
        self:broadcastSync(makeAuctionStartedNotification(currentAuction))

        print(string.format(
            "[FarmlandAuctions] Auction forced to start now: farmlandId=%d shift=%.2fh firstNpcDue=%.3f newEnd=%.2f",
            tonumber(currentAuction.farmlandId or 0) or 0,
            tonumber(shift or 0) or 0,
            tonumber(currentAuction.nextNpcGlobalBidTime or now) or 0,
            tonumber(currentAuction.endTime or 0) or 0
        ))

        return "Auction started now."
    end

    self:updateUnownedFarmlands()
    if #unownedFarmlandIds <= 0 then
        return "No buyable unowned farmlands found."
    end

    local farmlandId = tonumber(unownedFarmlandIds[math.random(#unownedFarmlandIds)]) or 0
    if farmlandId == 0 then
        return "No valid farmland found."
    end

    local ok, msg = self:_createAuctionForFarmlandNow(farmlandId)
    if ok then
        return "New auction created and started now."
    end
    return msg
end

function AuctionManager:consoleEndNow()
    if not isServer() then
        return _sendAdminCmd("faEndNow") or "Server or admin only."
    end

    if currentAuction == nil then
        return "No active auction."
    end

    if currentAuction.hasStarted ~= true then
        local farmlandId = tonumber(currentAuction.farmlandId or 0) or 0
        currentAuction = nil
        _didStartNotify = false
        dirtyState = true
        self:applyFarmlandPurchaseRules()
        self:broadcastSync(nil)
        return "Scheduled auction cleared for farmland " .. tostring(farmlandId) .. "."
    end

    currentAuction.endTime = nowHours()

    local notification = currentAuction:auctionEndedServer()

    self:updateUnownedFarmlands()
    if #unownedFarmlandIds > 0 then
        local nextId = unownedFarmlandIds[math.random(#unownedFarmlandIds)]
        self:generateNextAuction(nextId)
    else
        currentAuction = nil
    end

    dirtyState = true
    self:applyFarmlandPurchaseRules()
    self:broadcastSync(notification)
    return "Auction ended now."
end

function AuctionManager:_createAuctionForFarmlandNow(farmlandId)
    farmlandId = tonumber(farmlandId) or 0
    if farmlandId == 0 then
        return false, "Invalid farmlandId."
    end
    if g_farmlandManager == nil then
        return false, "Farmland manager not ready."
    end

    local farmland = g_farmlandManager:getFarmlandById(farmlandId)
    if farmland == nil then
        return false, "Farmland not found."
    end

    local ownerId = tonumber(g_farmlandManager:getFarmlandOwner(farmlandId) or 0) or 0
    if ownerId ~= FarmlandManager.NO_OWNER_FARM_ID then
        return false, "Farmland is already owned or blocked."
    end

    local now = nowHours()
    local durationHours = self:getRandomAuctionDurationHours()
    local auctionName = formatFarmlandName(farmlandId)

    currentAuction = Auction.newServer(farmlandId, auctionName, now, now + durationHours)
    ensureAuctionOriginalPrice(currentAuction)
    currentAuction.hasStarted = true
    currentAuction.startTime = now
    currentAuction.endTime = now + durationHours
    currentAuction.lastBidTime = 0

    local firstNpcDue = now + 0.002
    local firstNpc = nil

    if currentAuction.npcBidders ~= nil then
        for i = 1, #currentAuction.npcBidders do
            local npc = currentAuction.npcBidders[i]
            if npc ~= nil and npc.active ~= false then
                if firstNpc == nil or (tonumber(npc.maxBid or 0) or 0) > (tonumber(firstNpc.maxBid or 0) or 0) then
                    firstNpc = npc
                end
            end
        end
    end

    if firstNpc ~= nil then
        firstNpc.nextBidTime = firstNpcDue
        firstNpc.forcedReaction = true

        if firstNpc.bidSlots ~= nil and #firstNpc.bidSlots > 0 then
            firstNpc.bidSlots[1] = firstNpcDue
            table.sort(firstNpc.bidSlots)
        end
    end

    currentAuction.nextNpcGlobalBidTime = firstNpcDue

    _didStartNotify = true
    dirtyState = true
    self:applyFarmlandPurchaseRules()
    self:broadcastSync(makeAuctionStartedNotification(currentAuction))

    print(string.format(
        "[FarmlandAuctions] StartAuction created: farmlandId=%d name='%s' duration=%dh firstNpcDue=%.3f",
        tonumber(farmlandId) or 0,
        tostring(auctionName),
        tonumber(durationHours) or 0,
        tonumber(firstNpcDue) or 0
    ))

    return true, "Auction started for farmland " .. tostring(farmlandId) .. "."
end

function AuctionManager:consoleCancelAuction()
    if not isServer() then
        return _sendAdminCmd("faCancelAuction") or "Server or admin only."
    end

    if currentAuction == nil then
        return "No active or scheduled auction."
    end

    local farmlandId = tonumber(currentAuction.farmlandId or 0) or 0
    local farmland = g_farmlandManager ~= nil and g_farmlandManager:getFarmlandById(farmlandId) or nil
    if farmland ~= nil then
        farmland.price = currentAuction.originalPrice or currentAuction.normalPrice or farmland.price
    end

    local hadStarted = currentAuction.hasStarted == true

    currentAuction = nil
    _didStartNotify = false
    dirtyState = true
    self:applyFarmlandPurchaseRules()
    self:broadcastSync(nil)

    if hadStarted then
        return "Auction cancelled for farmland " .. tostring(farmlandId) .. "."
    end

    return "Scheduled auction cancelled for farmland " .. tostring(farmlandId) .. "."
end

function AuctionManager:consoleStartAuction(farmlandId)
    if not isServer() then
        return _sendAdminCmd("faStartAuction", farmlandId) or "Server or admin only."
    end

    if currentAuction ~= nil and currentAuction.hasStarted == true then
        return "There is already an active auction. Use faCancelAuction or faEndNow first."
    end

    if currentAuction ~= nil and currentAuction.hasStarted ~= true then
        currentAuction = nil
        _didStartNotify = false
    end

    local ok, msg = self:_createAuctionForFarmlandNow(farmlandId)
    return msg
end

function AuctionManager:consoleSetAuctionTime(minHours, maxHours)
    if not isServer() then
        return _sendAdminCmd("faSetAuctionTime", minHours, maxHours) or "Server or admin only."
    end

    minHours = tonumber(minHours)
    maxHours = tonumber(maxHours)

    if minHours == nil or maxHours == nil then
        local curMin, curMax = self:getAuctionDurationRangeHours()
        return string.format("Usage: faSetAuctionTime <minHours> <maxHours> | current=%dh-%dh", curMin, curMax)
    end

    minHours = math.max(1, math.floor(minHours))
    maxHours = math.max(minHours, math.floor(maxHours))

    self.settings = self.settings or {}
    self.settings.auctionDurationMinHours = minHours
    self.settings.auctionDurationMaxHours = maxHours
    self:saveSettings()

    return string.format("Auction duration updated to %dh-%dh.", minHours, maxHours)
end

function AuctionManager:consoleSetStartInterval(minHours, maxHours)
    if not isServer() then
        return _sendAdminCmd("faSetStartInterval", minHours, maxHours) or "Server or admin only."
    end

    minHours = tonumber(minHours)
    maxHours = tonumber(maxHours)

    if minHours == nil or maxHours == nil then
        local curMin = math.max(1, tonumber(self.settings and self.settings.startDelayMinHours) or 4)
        local curMax = math.max(curMin, tonumber(self.settings and self.settings.startDelayMaxHours) or 18)
        return string.format("Usage: faSetStartInterval <minHours> <maxHours> | current=%dh-%dh", curMin, curMax)
    end

    minHours = math.max(1, math.floor(minHours))
    maxHours = math.max(minHours, math.floor(maxHours))

    self.settings = self.settings or {}
    self.settings.startDelayMinHours = minHours
    self.settings.startDelayMaxHours = maxHours
    self:saveSettings()

    return string.format("Start interval updated to %dh-%dh (takes effect for next auction).", minHours, maxHours)
end

function AuctionManager:consoleSetAuctionOnly(value)
    if not isServer() then
        return _sendAdminCmd("faSetAuctionOnly", value) or "Server or admin only."
    end

    self.settings = self.settings or {}
    local current = self.settings.auctionOnlyPurchase == true

    if value == nil or value == "" then
        self.settings.auctionOnlyPurchase = not current
    elseif value == "1" or value == "true" or value == "on" then
        self.settings.auctionOnlyPurchase = true
    elseif value == "0" or value == "false" or value == "off" then
        self.settings.auctionOnlyPurchase = false
    else
        return string.format("Usage: faSetAuctionOnly [on/off/1/0] | current=%s", tostring(current))
    end

    self:saveSettings()
    self:applyFarmlandPurchaseRules()

    if isServer() and g_server ~= nil then
        local syncState = self:_stampSyncSettings((currentAuction and currentAuction:toState()) or {farmlandId=0})
        if g_server.getClientConnections ~= nil then
            for _, conn in ipairs(g_server:getClientConnections()) do
                if conn ~= nil then
                    conn:sendEvent(FarmlandAuctionSyncEvent.new(syncState, nil))
                end
            end
        else
            g_server:broadcastEvent(FarmlandAuctionSyncEvent.new(syncState, nil), false)
        end
    end

    local state = self.settings.auctionOnlyPurchase and "ON" or "OFF"
    return string.format("Auction-only purchase mode: %s.", state)
end

function AuctionManager:_registerBidActionOnce()
    if self._fa_registered == true then return end
    if g_inputBinding == nil then return end

    local a = InputAction and InputAction[AuctionManager.ACTION_BID] or nil
    if a == nil then
        print("[FarmlandAuctions] WARN: InputAction[FARMLAND_AUCTION_BID] is nil")
        return
    end

    local ok, r1, r2 = pcall(function()
        return g_inputBinding:registerActionEvent(a, self, AuctionManager.onActionBid, false, true, false, true, nil, true)
    end)
    if not ok then
        ok, r1, r2 = pcall(function()
            return g_inputBinding:registerActionEvent(a, self, AuctionManager.onActionBid, false, true, false, true, nil)
        end)
    end

    local id = r2
    if id == nil then id = r1 end

    self._fa_actionEventId = id
    self._fa_registered = (id ~= nil)

    -- print(string.format("[FarmlandAuctions] [INPUT] registerActionEvent ok=%s id=%s", tostring(ok), tostring(id)))

    if id ~= nil then
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventActive(id, false)

        if g_inputBinding.requestActionEventUpdate ~= nil then
            g_inputBinding:requestActionEventUpdate()
        end
    end
end

function AuctionManager:_updateBidActionUI(running, auctionFid)
    if g_inputBinding == nil or self._fa_actionEventId == nil then return end

    local playerFid = getPlayerFarmlandId()
    local active = (running and auctionFid ~= 0 and playerFid ~= 0 and playerFid == auctionFid)

    if active ~= self._fa_lastActive then
        self._fa_lastActive = active

        g_inputBinding:setActionEventActive(self._fa_actionEventId, active)
        g_inputBinding:setActionEventTextVisibility(self._fa_actionEventId, false)

        if g_inputBinding.requestActionEventUpdate ~= nil then
            g_inputBinding:requestActionEventUpdate()
        end

        dbg("[INPUT] active=%s running=%s playerFid=%d auctionFid=%d id=%s",
            tostring(active), tostring(running), tonumber(playerFid or 0), tonumber(auctionFid or 0), tostring(self._fa_actionEventId))
    end
end

function AuctionManager:_getBidCooldownRemainingMs(farmId)
    local nowMs = g_time or 0
    local untilMs = tonumber(_bidCooldownUntilByFarm[farmId] or 0) or 0
    return math.max(0, untilMs - nowMs)
end

function AuctionManager:_setBidCooldown(farmId)
    if farmId == nil or farmId == 0 then return end
    _bidCooldownUntilByFarm[farmId] = (g_time or 0) + (AuctionManager.PLAYER_BID_COOLDOWN_MS or 3000)
end

function AuctionManager:_notifyOutbidFarm(outbid)
    if outbid == nil or (tonumber(outbid.farmId or 0) or 0) <= 0 then
        return
    end

    local newName = ""
    if outbid.newIsNpc then
        newName = tostring(outbid.newName or "NPC")
    else
        newName = tostring(outbid.newName or "")
        if newName == "" then
            newName = getFarmDisplayNameSafe(outbid.newFarmId) or (i18nText("Farm", "Farm") .. tostring(outbid.newFarmId or 0))
        end
    end

    local msg = i18nText("OutbidBy", "You have been outbid by")
        .. " " .. newName .. " "
        .. i18nText("HighestBidder", "is highest bidder with")
        .. " " .. g_i18n:formatMoney(outbid.price or 0)

    self:sendNotificationToFarm(outbid.farmId, msg, {1, 0.35, 0.2, 1})
end

function AuctionManager:_handleBidResult(farmId, ok, notification, outbid, extraNotification, targetConnection)
    if ok then
        self:_setBidCooldown(farmId)
        dirtyState = true
        if outbid ~= nil then
            self:_notifyOutbidFarm(outbid)
        end
        self:broadcastSync(notification)
        if extraNotification ~= nil then
            self:broadcastSync(extraNotification)
        end
        return true
    end

    local cooldownMs = self:_getBidCooldownRemainingMs(farmId)
    if cooldownMs > 0 then
        local secs = math.max(1, math.ceil(cooldownMs / 1000))
        local msg = i18nText("BidCooldown", "Please wait before placing the next bid.")
            .. " (" .. tostring(secs) .. "s)"
        if targetConnection ~= nil then
            self:sendNotificationToConnection(targetConnection, msg, {1, 0.84, 0, 1})
        else
            self:sendNotificationToFarm(farmId, msg, {1, 0.84, 0, 1})
        end
        return false
    end

    local kind = notification ~= nil and notification.kind or nil
    local msg

    if kind == "MAX_PRICE_REACHED" then
        msg = i18nText("AuctionMaxPriceReached", "No more bids possible for this auction.")
    elseif kind == "INVALID_FARM" then
        msg = i18nText("AuctionBidInvalidFarm", "Your farm cannot bid on this auction.")
    else
        msg = i18nText("NotEnoughMoney", "Not enough money to bid.")
    end

    if targetConnection ~= nil then
        self:sendNotificationToConnection(targetConnection, msg, {1, 0.84, 0, 1})
    else
        self:sendNotificationToFarm(farmId, msg, {1, 0.84, 0, 1})
    end
    return false
end

function AuctionManager:_serverPlaceBidSteps(farmId, steps, targetConnection)
    if currentAuction == nil or not currentAuction.hasStarted then
       -- print("[FarmlandAuctions] [BID] abort: _serverPlaceBidSteps without running auction")
        return
    end

    steps = math.max(1, math.min(10, tonumber(steps) or 1))
    farmId = tonumber(farmId or 0) or 0
    if farmId <= 0 then
        print("[FarmlandAuctions] [BID] abort: farmId missing")
        return
    end

    local bidderName = getFarmDisplayNameSafe(farmId)
    local cooldownMs = self:_getBidCooldownRemainingMs(farmId)
    if cooldownMs > 0 then
        local secs = math.max(1, math.ceil(cooldownMs / 1000))
        local msg = i18nText("BidCooldown", "Please wait before placing the next bid.")
            .. " (" .. tostring(secs) .. "s)"
        if targetConnection ~= nil then
            self:sendNotificationToConnection(targetConnection, msg, {1, 0.84, 0, 1})
        else
            self:sendNotificationToFarm(farmId, msg, {1, 0.84, 0, 1})
        end
        return
    end

    for _ = 1, steps do
        if currentAuction == nil then break end
        local ok, notification, outbid, extraNotification = currentAuction:placeBidServer(farmId, bidderName)
        if not self:_handleBidResult(farmId, ok, notification, outbid, extraNotification, targetConnection) then
            break
        end
    end
end

function AuctionManager:requestBidSteps(steps)
    steps = math.max(1, math.min(10, tonumber(steps) or 1))

    local clientFarmId = getLocalFarmIdSafe()
    local auctionFarmlandId = tonumber(currentAuction and currentAuction.farmlandId or 0) or 0

    -- print(string.format("[FarmlandAuctions] [BID] OK clicked/requestBidSteps steps=%d clientFarmId=%d auctionFarmlandId=%d isServer=%s isClient=%s",
        -- tonumber(steps or 0) or 0,
        -- tonumber(clientFarmId or 0) or 0,
        -- tonumber(auctionFarmlandId or 0) or 0,
        -- tostring(isServer()),
        -- tostring(isClient())))

    if isServer() then

        self:_serverPlaceBidSteps(clientFarmId, steps)
    else
        local conn = nil
        if g_client ~= nil and g_client.getServerConnection ~= nil then
            conn = g_client:getServerConnection()
        end

        if conn ~= nil and conn.sendEvent ~= nil then
            conn:sendEvent(FarmlandAuctionBidEvent.new(steps, clientFarmId, auctionFarmlandId))
          --  print("[FarmlandAuctions] [BID] bid event sent to server")
        else
           -- print("[FarmlandAuctions] [BID] abort: client has no server connection")
        end
    end
end

function AuctionManager:requestBidLevel(steps)
    self:requestBidSteps(steps)
end

function AuctionManager:_tryOpenBidDialog(source)
    local nowMs = g_time or 0
    if (nowMs - (self._fa_lastOpenRequestMs or 0)) < 250 then
        return true
    end
    self._fa_lastOpenRequestMs = nowMs

    if currentAuction == nil then
        print("[FarmlandAuctions] [BID] abort: currentAuction=nil")
        return false
    end

    local auctionFid = tonumber(currentAuction.farmlandId or 0) or 0
    if auctionFid == 0 then
        print("[FarmlandAuctions] [BID] abort: auctionFid=0")
        return false
    end

    if not isAuctionRunning(currentAuction) then
        print("[FarmlandAuctions] [BID] abort: auction not running")
        return false
    end

    local pf = getPlayerFarmlandId()
    if pf == 0 or pf ~= auctionFid then
        print(string.format("[FarmlandAuctions] [BID] abort: playerFid=%d != auctionFid=%d", pf, auctionFid))
        return false
    end

    local opened = false

    if g_gui ~= nil and FarmlandAuctionBidDialog ~= nil and FarmlandAuctionBidDialog.register ~= nil then
        local modDir = MOD_DIR
        if modDir == nil or modDir == "" then
            modDir = g_currentModDirectory or ""
        end

        local ok = FarmlandAuctionBidDialog.register(modDir)
        if ok and FarmlandAuctionBidDialog.show ~= nil then
            opened = (FarmlandAuctionBidDialog.show(self) == true)
        end
    end

    if not opened then
      --  print(string.format("[FarmlandAuctions] [GUI] could not open bid dialog source=%s", tostring(source or "unknown")))
    end

    return opened
end

function AuctionManager:onActionBid(actionName, inputValue, callbackState, isAnalog)
    self:_tryOpenBidDialog("action")
end

function AuctionManager:updateUnownedFarmlands()
    unownedFarmlandIds = {}

    local farmlands = g_farmlandManager and g_farmlandManager:getFarmlands() or {}
    for id, farmland in pairs(farmlands) do
        local farmlandId = tonumber(id) or 0
        local ownerId = tonumber(g_farmlandManager:getFarmlandOwner(farmlandId) or 0) or 0
        local price = 0
        local isBuyable = true

        if farmland ~= nil and farmland.price ~= nil then
            price = tonumber(farmland.price) or 0
        end

        if farmland ~= nil then
            local currentBuyable = getFarmlandBuyableState(farmland)
            if currentBuyable ~= nil then
                isBuyable = currentBuyable == true
            end
        end

        if _buyableOriginalState[farmlandId] ~= nil then
            isBuyable = _buyableOriginalState[farmlandId].value == true
        end

        if ownerId == FarmlandManager.NO_OWNER_FARM_ID and price > 0 and isBuyable then
            unownedFarmlandIds[#unownedFarmlandIds + 1] = farmlandId
        end
    end

    dbg("Unowned buyable farmland count=%d", #unownedFarmlandIds)
end

function AuctionManager:onBidRequest(connection, steps, clientFarmId, requestedFarmlandId)
    if not isServer() then return end

   -- print(string.format("[FarmlandAuctions] [BID] server received bid event steps=%d clientFarmId=%d requestedFarmlandId=%d", tonumber(steps or 0) or 0, tonumber(clientFarmId or 0) or 0, tonumber(requestedFarmlandId or 0) or 0))

    if currentAuction == nil or not currentAuction.hasStarted then
        print("[FarmlandAuctions] [BID] abort: no running auction on server")
        return
    end

    local auctionFarmlandId = tonumber(currentAuction.farmlandId or 0) or 0
    requestedFarmlandId = tonumber(requestedFarmlandId or 0) or 0
    if requestedFarmlandId > 0 and auctionFarmlandId > 0 and requestedFarmlandId ~= auctionFarmlandId then
        print(string.format("[FarmlandAuctions] [BID] abort: client requested farmlandId=%d but current auction is farmlandId=%d", requestedFarmlandId, auctionFarmlandId))
        return
    end

    local user = nil
    if g_currentMission ~= nil and g_currentMission.userManager ~= nil and g_currentMission.userManager.getUserByConnection ~= nil then
        local ok, result = pcall(g_currentMission.userManager.getUserByConnection, g_currentMission.userManager, connection)
        if ok then
            user = result
        end
    end

    local farmId = getFarmIdFromUser(user, connection)
    if farmId <= 0 then
        farmId = tonumber(clientFarmId or 0) or 0
    end

    if farmId <= 0 then
        print("[FarmlandAuctions] [BID] abort: could not resolve farmId from client connection or event payload")
        return
    end

  --  print(string.format("[FarmlandAuctions] [BID] server resolved farmId=%d", tonumber(farmId or 0) or 0))

    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local ok, farm = pcall(g_farmManager.getFarmById, g_farmManager, farmId)
        if not ok or farm == nil then
            print(string.format("[FarmlandAuctions] [BID] abort: invalid farmId=%d", farmId))
            return
        end
    end

    self:_serverPlaceBidSteps(farmId, steps, connection)
end

function AuctionManager:sendNotificationToConnection(connection, msg, color)
    if msg == nil or msg == "" then
        return false
    end

    if connection ~= nil and connection.sendEvent ~= nil then
        local state = (currentAuction ~= nil and currentAuction.toState ~= nil) and currentAuction:toState() or {farmlandId = 0}
        state = self:_stampSyncSettings(state)
        local n = { kind = "TEXT", farmId = 0, price = 0, npcName = tostring(msg) }
        connection:sendEvent(FarmlandAuctionSyncEvent.new(state, n))
        return true
    end

    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(color or {1, 0.84, 0, 1}, tostring(msg), MOD_NAME)
        return true
    end

    return false
end

function AuctionManager:sendNotificationToFarm(farmId, msg, color)
    farmId = tonumber(farmId or 0) or 0
    if farmId <= 0 or msg == nil or msg == "" then
        return
    end

    local shownLocal = false

    if g_localPlayer ~= nil and tonumber(g_localPlayer.farmId or 0) == farmId then
        if g_currentMission ~= nil then
            g_currentMission:addIngameNotification(color or {1, 1, 1, 1}, tostring(msg), MOD_NAME)
            shownLocal = true
        end
    elseif g_currentMission ~= nil and g_currentMission.player ~= nil and tonumber(g_currentMission.player.farmId or 0) == farmId then
        g_currentMission:addIngameNotification(color or {1, 1, 1, 1}, tostring(msg), MOD_NAME)
        shownLocal = true
    end

    if g_server ~= nil and g_server.getClientConnections ~= nil and g_currentMission ~= nil and g_currentMission.userManager ~= nil then
        for _, conn in ipairs(g_server:getClientConnections()) do
            local user = nil
            if g_currentMission.userManager.getUserByConnection ~= nil then
                local ok, result = pcall(g_currentMission.userManager.getUserByConnection, g_currentMission.userManager, conn)
                if ok then
                    user = result
                end
            end

            if getFarmIdFromUser(user, conn) == farmId and conn ~= nil and conn.sendEvent ~= nil then
                local n = { kind="TEXT", farmId=farmId, price=0, npcName=tostring(msg) }
                conn:sendEvent(FarmlandAuctionSyncEvent.new(self:_stampSyncSettings((currentAuction and currentAuction:toState()) or {farmlandId=0}), n))
            end
        end
    end

    if AuctionManager.DEBUG then
        print(string.format(
            "[FarmlandAuctions] [OUTBID_NOTIFY] farmId=%d localShown=%s msg='%s'",
            farmId,
            tostring(shownLocal),
            tostring(msg)
        ))
    end
end

function AuctionManager:onSyncState(state, notification)
    if not isServer() then
        if state ~= nil then
            self.settings = self.settings or {}
            self.settings.auctionOnlyPurchase = state.auctionOnlyPurchase == true
        end

        if state ~= nil and (state.farmlandId or 0) ~= 0 then
            currentAuction = Auction.newClientFromState(state)
        else
            currentAuction = nil
        end
    end

    if isClient() then
        if currentAuction ~= nil and isAuctionRunning(currentAuction) then
            local fid = tonumber(currentAuction.farmlandId or 0) or 0
            if fid ~= 0 then
                setRingTargetFarmland(fid)
            end
        else
            setRingTargetFarmland(0)
        end
    end

    if notification ~= nil then
        self:showNotification(notification)
    end
end

function AuctionManager:showNotification(n)
    if g_currentMission == nil or n == nil then return end

    if n.kind == "AUCTION_STARTED" then
        local fid = tonumber(n.farmlandId or 0) or 0
        if fid > 0 then
            _localOneHourWarningByFarmland[fid] = nil
            _localThirtyMinuteWarningByFarmland[fid] = nil
        end
        local key = "start:" .. tostring(n.farmlandId or 0)
        if shouldEmit(key) then
            g_currentMission:addIngameNotification({0, 1, 0, 1}, formatAuctionStartedMessage(n), MOD_NAME)
        end

    elseif n.kind == "FARM_HIGHEST" then
        local displayName = tostring(n.npcName or "")
        if displayName == "" then
            displayName = getFarmDisplayNameSafe(n.farmId) or (i18nText("Farm", "Farm") .. tostring(n.farmId))
        end
        local txt = displayName
            .. " " .. i18nText("HighestBidder", "is highest bidder with")
            .. " " .. g_i18n:formatMoney(n.price)
        g_currentMission:addIngameNotification({1, 0.84, 0, 1}, txt, MOD_NAME)

    elseif n.kind == "NPC_HIGHEST" then
        local npcName = n.npcName or "NPC"
        local txt = tostring(npcName)
            .. " " .. i18nText("HighestBidder", "is highest bidder with")
            .. " " .. g_i18n:formatMoney(n.price)
        g_currentMission:addIngameNotification({1, 0.3, 0.3, 1}, txt, MOD_NAME)

    elseif n.kind == "SOLD_TO_FARM" then
        local txt = i18nText("Sold", "Land sold:")
            .. " " .. g_i18n:formatMoney(n.price)
        g_currentMission:addIngameNotification({0.4, 1, 0.4, 1}, txt, MOD_NAME)

 
        local winFarmId  = tonumber(n.farmId or 0) or 0
        local soldFid    = tonumber(n.farmlandId or 0) or 0
        if winFarmId > 0 and soldFid > 0 and g_farmlandManager ~= nil then
            local prevOwner = tonumber(g_farmlandManager:getFarmlandOwner(soldFid) or 0) or 0
            g_farmlandManager:setLandOwnership(soldFid, winFarmId)
            if g_messageCenter ~= nil then
                if prevOwner ~= FarmlandManager.NO_OWNER_FARM_ID then
                    g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, prevOwner)
                end
                g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, winFarmId)
            end
        end

    elseif n.kind == "NOT_SOLD" then
        local txt = i18nText("NotSold", "Auction ended without a buyer.")
        g_currentMission:addIngameNotification({1, 0.84, 0, 1}, txt, MOD_NAME)

    elseif n.kind == "SOFT_CLOSE_EXTENDED" then
        local mins = math.max(1, math.floor(((tonumber(n.hours) or 0) * 60) + 0.5))
        local txt = i18nText("SoftCloseExtended", "Auction extended by")
            .. " " .. tostring(mins) .. " "
            .. i18nText("Minutes", "minutes.")
        g_currentMission:addIngameNotification({0.65, 0.9, 1, 1}, txt, MOD_NAME)

    elseif n.kind == "TEXT" then
        g_currentMission:addIngameNotification({1,0.84,0,1}, tostring(n.npcName or ""), MOD_NAME)
    end
end

function AuctionManager:broadcastText(msg, color, key)
    if key ~= nil and not shouldEmit(key) then return end

    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(color or {1,1,1,1}, msg, MOD_NAME)
    end

    if g_server ~= nil and g_server.getClientConnections ~= nil then
        for _, conn in ipairs(g_server:getClientConnections()) do
            local n = { kind="TEXT", farmId=0, price=0, npcName=msg }
            conn:sendEvent(FarmlandAuctionSyncEvent.new(self:_stampSyncSettings((currentAuction and currentAuction:toState()) or {farmlandId=0}), n))
        end
    end
end

function AuctionManager:_stampSyncSettings(state)
    state = state or {farmlandId = 0}
    state.auctionOnlyPurchase = self.settings ~= nil and self.settings.auctionOnlyPurchase == true
    return state
end

function AuctionManager:_getCurrentSyncState()
    local state
    if currentAuction ~= nil then
        state = currentAuction:toState()
    else
        state = { farmlandId = 0 }
    end

    return self:_stampSyncSettings(state)
end

function AuctionManager:broadcastSync(notification)
    -- Important for MP late joiners: auctionOnlyPurchase is a global setting and
    -- must be synced even when there is currently no active auction.  Older
    -- builds returned early when currentAuction was nil, which left newly joined
    -- clients with the default false value until faSetAuctionOnly was executed
    -- again.
    local state = self:_getCurrentSyncState()

    if isClient() then
        self:onSyncState(state, notification)
    end

    if g_server == nil then
        return
    end

    local sent = 0
    if g_server.getClientConnections ~= nil then
        for _, conn in ipairs(g_server:getClientConnections()) do
            if conn ~= nil then
                conn:sendEvent(FarmlandAuctionSyncEvent.new(state, notification))
                sent = sent + 1
            end
        end
    else
        g_server:broadcastEvent(FarmlandAuctionSyncEvent.new(state, notification), false)
        sent = -1
    end

    if AuctionManager.DEBUG then
        print(string.format("[FarmlandAuctions] Sync broadcast farmlandId=%d started=%s auctionOnly=%s clients=%s notification=%s", tonumber(state.farmlandId or 0) or 0, tostring(state.hasStarted == true), tostring(state.auctionOnlyPurchase == true), tostring(sent), tostring(notification ~= nil and notification.kind or "none")))
    end
end

function AuctionManager:tryInitServer()
    if not isServer() then return end
    if isInitialized then return end
    if g_currentMission == nil or g_currentMission.missionInfo == nil or g_currentMission.environment == nil then return end

    self:loadSettings()
    isInitialized = true

    print(string.format("[FarmlandAuctions] INIT OK | day=%s time=%.2f",
        tostring(g_currentMission.environment.currentDay),
        tonumber(g_currentMission.environment:getEnvironmentTime() or 0)))

    self:updateUnownedFarmlands()
   -- print(string.format("[FarmlandAuctions] Unowned farmland count=%d", #unownedFarmlandIds))

    savePath = g_currentMission.missionInfo:getSavegameDirectory(g_currentMission.missionInfo.savegameIndex) .. "/auction.xml"
   -- print(string.format("[FarmlandAuctions] savePath=%s exists=%s", tostring(savePath), tostring(fileExists(savePath))))

    if fileExists(savePath) then
        currentAuction = Auction.loadFromXmlFile(savePath)
      --  print(string.format("[FarmlandAuctions] loadFromXmlFile => %s", tostring(currentAuction ~= nil)))
    end

    if currentAuction == nil then
        local farmlandId = unownedFarmlandIds[math.random(math.max(1, #unownedFarmlandIds))]
      --  print(string.format("[FarmlandAuctions] generateNextAuction(farmlandId=%s)", tostring(farmlandId)))
        self:generateNextAuction(farmlandId)
    end

    dirtyState = true
    self:broadcastSync(nil)
end

function AuctionManager:generateNextAuction(farmlandId)
    if not isServer() then
        return
    end

    farmlandId = tonumber(farmlandId) or 0

    self:updateUnownedFarmlands()
    if #unownedFarmlandIds <= 0 then
        print("[FarmlandAuctions] ERROR: no buyable unowned farmlands found")
        return
    end

    local farmlands = g_farmlandManager and g_farmlandManager:getFarmlands() or {}

    local function isValidAuctionFarmland(fid)
        fid = tonumber(fid) or 0
        if fid == 0 then
            return false
        end

        local ownerId = tonumber(g_farmlandManager:getFarmlandOwner(fid) or 0) or 0
        if ownerId ~= FarmlandManager.NO_OWNER_FARM_ID then
            return false
        end

        local farmland = farmlands[fid]
        local price = 0
        local isBuyable = true

        if farmland ~= nil and farmland.price ~= nil then
            price = tonumber(farmland.price) or 0
        end

        if farmland ~= nil then
            local currentBuyable = getFarmlandBuyableState(farmland)
            if currentBuyable ~= nil then
                isBuyable = currentBuyable == true
            end
        end

        if _buyableOriginalState[fid] ~= nil then
            isBuyable = _buyableOriginalState[fid].value == true
        end

        return price > 0 and isBuyable
    end

    if not isValidAuctionFarmland(farmlandId) then
        farmlandId = tonumber(unownedFarmlandIds[math.random(#unownedFarmlandIds)]) or 0
    end

    if not isValidAuctionFarmland(farmlandId) then
        print("[FarmlandAuctions] ERROR: no valid farmland for next auction")
        return
    end

    local ownerId = tonumber(g_farmlandManager:getFarmlandOwner(farmlandId) or 0) or 0
    local now = nowHours()

    local sdMin = math.max(1, tonumber(self.settings and self.settings.startDelayMinHours) or 4)
    local sdMax = math.max(sdMin, tonumber(self.settings and self.settings.startDelayMaxHours) or 18)
    local startDelayHours = math.random(sdMin, sdMax)
    local durationHours = self:getRandomAuctionDurationHours()
    local startTime = now + startDelayHours
    local endTime = startTime + durationHours
    local auctionName = formatFarmlandName(farmlandId)

    currentAuction = Auction.newServer(farmlandId, auctionName, startTime, endTime)
    ensureAuctionOriginalPrice(currentAuction)
    _didStartNotify = false

    print(string.format(
        "[FarmlandAuctions] Next auction scheduled: farmlandId=%d owner=%d name='%s' startsIn=%.2fh duration=%dh",
        tonumber(farmlandId) or 0,
        tonumber(ownerId) or 0,
        tostring(auctionName),
        tonumber(startTime - now) or 0,
        tonumber(durationHours) or 0
    ))
end

function AuctionManager:loadMap()
    print("[FarmlandAuctions] loadMap() called")

    self:loadSettings()
    self:installPurchaseHooks()
    self:_registerConsoleCmdOnce()

    self._fa_actionEventId = nil
    self._fa_lastActive = false
    self._fa_registered = false

    if FarmlandAuctionBidDialog ~= nil then
        FarmlandAuctionBidDialog.INSTANCE = nil
    end

    if g_gui ~= nil and FarmlandAuctionBidDialog ~= nil and FarmlandAuctionBidDialog.register ~= nil then
        local ok = FarmlandAuctionBidDialog.register(MOD_DIR)
        print(string.format("[FarmlandAuctions] preload dialog register=%s", tostring(ok)))
    end
end

function AuctionManager:deleteMap()
    self:restoreBuyableStates()

    if g_inputBinding ~= nil and self._fa_actionEventId ~= nil then
        pcall(function() g_inputBinding:removeActionEvent(self._fa_actionEventId) end)
    end
    self._fa_actionEventId = nil
    self._fa_lastActive = false
    self._fa_registered = false
end

function AuctionManager:update(dt)
    dt = dt or 0

    if isClient() then
        if _ringBuildPending == true and (_ringPendingFarmlandId or 0) ~= 0 then
            _ringRetryMs = (_ringRetryMs or 0) + dt
            if _ringRetryMs >= 500 then
                _ringRetryMs = 0
                setRingTargetFarmland(_ringPendingFarmlandId)
            end
        else
            _ringRetryMs = 0
        end
        updateRingBlink(dt)
    end

    if not isInitialized and isServer() then
        self:tryInitServer()
    end

    self:applyFarmlandPurchaseRules()

    -- MP late-join sync: new clients start with the local default settings table.
    -- If auction-only was enabled before they joined, their map UI would still
    -- show the standard buy button until the admin command was executed again.
    -- Detect connection count changes and also send a slow fallback sync while
    -- auction-only is active.
    if isServer() and isInitialized then
        local clientCount = 0
        if g_server ~= nil and g_server.getClientConnections ~= nil then
            local connections = g_server:getClientConnections() or {}
            clientCount = #connections
        end

        _joinSyncMs = (_joinSyncMs or 0) + dt
        local auctionOnly = self.settings ~= nil and self.settings.auctionOnlyPurchase == true
        if clientCount ~= (_lastKnownClientCount or -1) or (auctionOnly and _joinSyncMs >= 5000) then
            _lastKnownClientCount = clientCount
            _joinSyncMs = 0
            self:broadcastSync(nil)
        end
    end

    local auctionFid = tonumber(currentAuction and currentAuction.farmlandId or 0) or 0
    local running = isAuctionRunning(currentAuction)

    if isClient() then
        self:_registerBidActionOnce()
        self:_updateBidActionUI(running, auctionFid)
    end

    if currentAuction == nil then
        if isClient() and _ringFarmlandId ~= 0 then
            setRingTargetFarmland(0)
        end
        return
    end

    if isClient() then
        self._fa_lastRingFid = self._fa_lastRingFid or 0
        self._fa_lastRingRunning = self._fa_lastRingRunning or false

        if running ~= self._fa_lastRingRunning or (running and auctionFid ~= self._fa_lastRingFid) then
            self._fa_lastRingRunning = running
            self._fa_lastRingFid = (running and auctionFid) or 0
            setRingTargetFarmland((running and auctionFid) or 0)
        end
    end

    if isClient() and running then
        showLocalEndWarnings(currentAuction)
    end

    if isServer() and isInitialized then
        if currentAuction:isOutdated() then
            local notification = currentAuction:auctionEndedServer()

            self:updateUnownedFarmlands()
            if #unownedFarmlandIds > 0 then
                local nextId = unownedFarmlandIds[math.random(#unownedFarmlandIds)]
                self:generateNextAuction(nextId)
            else
                print("[FarmlandAuctions] WARN: no unowned farmlands left")
                currentAuction = nil
            end

            dirtyState = true
            self:broadcastSync(notification)
            return
        end

        if AuctionManager.NPC_BIDDING and currentAuction ~= nil and currentAuction.hasStarted then
            local ok, n, outbid, extraNotification = currentAuction:tryNpcBid(nowHours())
            if ok then
                dirtyState = true
                if outbid ~= nil then
                    self:_notifyOutbidFarm(outbid)
                end
                self:broadcastSync(n)
                if extraNotification ~= nil then
                    self:broadcastSync(extraNotification)
                end
            end
        end

        if not currentAuction.hasStarted and nowHours() >= currentAuction.startTime then
            currentAuction.hasStarted = true
            _didStartNotify = false
            dirtyState = true
        end

        if currentAuction.hasStarted and not _didStartNotify then
            _didStartNotify = true

            -- print(string.format("[FarmlandAuctions] AUCTION STARTED | farmlandId=%d name='%s'",
                -- tonumber(currentAuction.farmlandId), tostring(currentAuction.name)))

            dirtyState = true
            self:broadcastSync(makeAuctionStartedNotification(currentAuction))
        end

        local remaining = currentAuction:remainingTimeHours()
		
        if currentAuction.hasStarted and remaining > 0 then
            local warnFid = tonumber(currentAuction.farmlandId or 0) or 0

            if not currentAuction.oneHourWarningSent and remaining <= 1 then
                currentAuction.oneHourWarningSent = true
               -- print(string.format("[FarmlandAuctions] End warning sent: 1h farmlandId=%s remaining=%.4f", tostring(warnFid), tonumber(remaining or 0) or 0))
                self:broadcastText(i18nText("EndInOneHour", "The auction ends in one hour!"), {1, 0.84, 0, 1}, "warn1h:" .. tostring(warnFid))
                dirtyState = true
            end

            if not currentAuction.thirtyMinWarningSent and remaining <= 0.5 then
                currentAuction.thirtyMinWarningSent = true
              --  print(string.format("[FarmlandAuctions] End warning sent: 30m farmlandId=%s remaining=%.4f", tostring(warnFid), tonumber(remaining or 0) or 0))
                self:broadcastText(i18nText("EndInThirtyMinutes", "The auction ends in 30 minutes!"), {1, 0.84, 0, 1}, "warn30m:" .. tostring(warnFid))
                dirtyState = true
            end
        end

        if dirtyState then
            lastSyncMs = (lastSyncMs or 0) + dt
            if lastSyncMs >= 250 then
                lastSyncMs = 0
                dirtyState = false
                self:broadcastSync(nil)
            end
        end
    end
end

function AuctionManager:draw()
    if currentAuction == nil or g_currentMission == nil then return end

    local fid = getPlayerFarmlandId()
    if fid ~= 0 and fid == (tonumber(currentAuction.farmlandId) or 0) and isAuctionRunning(currentAuction) then
        local now = nowHours()
        local endT = tonumber(currentAuction.endTime) or 0
        local endsIn = math.max(0, endT - now)
      
        self._drawDebugCounter = (self._drawDebugCounter or 0) + 1
        if self._drawDebugCounter >= 300 then
            self._drawDebugCounter = 0
           -- print(string.format("[FA] draw: now=%.4f endTime=%.4f endsIn=%.4f", now, endT, endsIn))
        end
        local nextBid = (tonumber(currentAuction.currentPrice) or 0) + (tonumber(currentAuction.betStepSize) or 0)
        local txt = (i18nText("KeyInfo", "Drücke B, um zu bieten") .. " ")
            .. g_i18n:formatMoney(nextBid)
            .. " (" .. formatRemainingTimeShort(endsIn) .. ")"
        g_currentMission:addExtraPrintText(txt)

        local farmId = 0
        if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
            farmId = tonumber(g_localPlayer.farmId) or 0
        elseif g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
            farmId = tonumber(g_currentMission.player.farmId) or 0
        end

    end
end

function AuctionManager:saveSavegame()
    if not isServer() then return end
    if currentAuction ~= nil and savePath ~= nil then
        currentAuction:saveToXml(savePath)
    end
end

local function isBidKeySym(sym, unicode)
    if Input ~= nil then
        if Input.KEY_b ~= nil and sym == Input.KEY_b then return true end
        if Input.KEY_B ~= nil and sym == Input.KEY_B then return true end
    end

    local u = tonumber(unicode) or 0
    return u == string.byte("b") or u == string.byte("B")
end

function AuctionManager:keyEvent(unicode, sym, modifier, isDown, eventUsed)
    if eventUsed == true or isDown ~= true or not isClient() then
        return false
    end

    if isBidKeySym(sym, unicode) then
        if self:_tryOpenBidDialog("keyEvent") then
            return true
        end
    end

    return false
end

print(string.format("[FarmlandAuctions] Registering ModEventListener (mod=%s)", tostring(MOD_NAME)))
addModEventListener(AuctionManager)