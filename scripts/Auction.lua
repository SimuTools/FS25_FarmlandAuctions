Auction = {}
Auction.__index = Auction
Auction.DEBUG = false
Auction.CONFIG_PATH = "config/auctionNpcProfiles.xml"

local function _aDbg(fmt, ...)
    if Auction.DEBUG then
        local ok, msg = pcall(string.format, "[FarmlandAuctions] " .. tostring(fmt), ...)
        if ok then print(msg) else print("[FarmlandAuctions] " .. tostring(fmt)) end
    end
end

local function _hoursNow()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return 0 end
    local dayMs = tonumber(env.dayTime or env:getEnvironmentTime() or 0) or 0
    return dayMs / 3600000 + (env.currentDay or 0) * 24
end

local function _fmtHoursToDayHour(h)
    h = tonumber(h) or 0
    local day = math.floor(h / 24)
    local hour = h - day * 24
    return string.format("Day %d, %.2fh", day, hour)
end

local function _fmtDeltaHours(h)
    h = tonumber(h) or 0
    local sign = ""
    if h < 0 then
        sign = "-"
        h = -h
    end
    local days = math.floor(h / 24)
    local hours = h - days * 24
    if days > 0 then
        return string.format("%s%d d %.2f h", sign, days, hours)
    end
    return string.format("%s%.2f h", sign, hours)
end

local function _safeRandomName(list, fallback)
    if list ~= nil and #list > 0 then
        return list[math.random(#list)]
    end
    return fallback
end

local function _clamp(v, mn, mx)
    v = tonumber(v) or 0
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function _copyArray(src)
    local out = {}
    if src ~= nil then
        for i = 1, #src do
            out[i] = src[i]
        end
    end
    return out
end

local function _shuffle(list)
    local arr = _copyArray(list)
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

local function _randRangeFloat(minValue, maxValue)
    minValue = tonumber(minValue) or 0
    maxValue = tonumber(maxValue) or minValue
    if maxValue < minValue then
        maxValue = minValue
    end
    return minValue + math.random() * (maxValue - minValue)
end

local function _getFieldStatsForFarmland(farmlandId)
    local stats = {
        fieldCount = 0,
        totalArea = 0,
        hasFields = false,
        sizeClass = "medium"
    }

    if g_fieldManager == nil or g_fieldManager.fields == nil then
        return stats
    end

    for _, field in pairs(g_fieldManager.fields) do
        local ffid = 0
        if field ~= nil then
            if field.farmland ~= nil and field.farmland.id ~= nil then
                ffid = tonumber(field.farmland.id) or 0
            elseif field.farmlandId ~= nil then
                ffid = tonumber(field.farmlandId) or 0
            end
        end

        if ffid == farmlandId then
            stats.fieldCount = stats.fieldCount + 1
            stats.hasFields = true

            local area = 0
            if field.fieldArea ~= nil then
                area = tonumber(field.fieldArea) or 0
            elseif field.area ~= nil then
                area = tonumber(field.area) or 0
            elseif field.areaInHa ~= nil then
                area = tonumber(field.areaInHa) or 0
            end

            stats.totalArea = stats.totalArea + math.max(0, area)
        end
    end

    if not stats.hasFields then
        stats.sizeClass = "nofield"
    elseif stats.totalArea >= 18 or stats.fieldCount >= 3 then
        stats.sizeClass = "large"
    elseif stats.totalArea <= 6 and stats.fieldCount <= 1 then
        stats.sizeClass = "small"
    else
        stats.sizeClass = "medium"
    end

    return stats
end

local function _xmlExists(xmlId, key)
    if xmlId == nil or xmlId == 0 then
        return false
    end
    if hasXMLProperty ~= nil then
        local ok, value = pcall(hasXMLProperty, xmlId, key)
        if ok and value == true then
            return true
        end
    end
    local ok2, value2 = pcall(getXMLString, xmlId, key)
    return ok2 and value2 ~= nil
end

function Auction.ensureConfigLoaded()
    if Auction._config ~= nil then
        return Auction._config
    end

    local cfg = {
        settings = {
            minBidders = 2,
            maxBidders = 6,
            npcWinPlayerLeadMultiplier = 1.00,
            npcWinLateMultiplier = 1.00,
            npcWinChanceAgainstPlayer = 0.40,
            npcCounterChance = 0.10,
            npcImmediateCounterMinHours = 0.001,
            npcImmediateCounterMaxHours = 0.008,
            npcPlannedReactionMinHours = 0.08,
            npcPlannedReactionMaxHours = 1.20,
            npcLateWinBlockHours = 8.0,
            softCloseEnabled = true,
            softCloseTriggerHours = 0.08,
            softCloseExtendHours = 0.20,
            softCloseMaxExtensions = 2,
            globalNpcGapMinHours = 0.10,
            globalNpcGapMaxHours = 0.90,
            auctionDiscountMinPct = 0.15,
            auctionDiscountMaxPct = 0.55
        },
        npcNames = {
            "Meyer Agrar",
            "Hof Petersen",
            "Lohnbetrieb Krüger",
            "Heidehof Lehmann",
            "Feldgut Hansen",
            "Agrar Nord",
            "Bergmann Landwirtschaft",
            "Landerwerb Schulz",
            "Ackerteam Behrens",
            "Gut Hohenried"
        },
        auctionHouses = {
            de = {
                "Nordland Auktionen",
                "Heide Auktionshaus",
                "Land & Feld Auktionen",
                "Agrar Auktionen Bevensen",
                "Auktionshaus am Markt",
                "Hofgut Auktionen"
            },
            en = {
                "Northern Fields Auctions",
                "Green Valley Auction House",
                "Country Land Exchange",
                "Harvest Hill Auctions",
                "Rural Estate Auctions",
                "Meadowbrook Auction House"
            }
        }
    }

    local path = Utils.getFilename(Auction.CONFIG_PATH, g_currentModDirectory or "")
    if fileExists(path) then
        local xmlId = loadXMLFile("auctionNpcProfiles", path)
        if xmlId ~= nil and xmlId ~= 0 then
            cfg.settings.minBidders = math.max(1, getXMLInt(xmlId, "auctionNpcProfiles.settings#minBidders") or cfg.settings.minBidders)
            cfg.settings.maxBidders = math.max(cfg.settings.minBidders, getXMLInt(xmlId, "auctionNpcProfiles.settings#maxBidders") or cfg.settings.maxBidders)
            cfg.settings.npcWinPlayerLeadMultiplier = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcWinPlayerLeadMultiplier") or cfg.settings.npcWinPlayerLeadMultiplier, 0.01, 1)
            cfg.settings.npcWinLateMultiplier = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcWinLateMultiplier") or cfg.settings.npcWinLateMultiplier, 0.01, 1)
            cfg.settings.npcWinChanceAgainstPlayer = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcWinChanceAgainstPlayer") or cfg.settings.npcWinChanceAgainstPlayer, 0.01, 1)
            cfg.settings.npcCounterChance = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcCounterChance") or cfg.settings.npcCounterChance, 0.0, 1)
            cfg.settings.npcImmediateCounterMinHours = math.max(0.0003, getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcImmediateCounterMinHours") or cfg.settings.npcImmediateCounterMinHours)
            cfg.settings.npcImmediateCounterMaxHours = math.max(cfg.settings.npcImmediateCounterMinHours, getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcImmediateCounterMaxHours") or cfg.settings.npcImmediateCounterMaxHours)
            cfg.settings.npcPlannedReactionMinHours = math.max(0.01, getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcPlannedReactionMinHours") or cfg.settings.npcPlannedReactionMinHours)
            cfg.settings.npcPlannedReactionMaxHours = math.max(cfg.settings.npcPlannedReactionMinHours, getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcPlannedReactionMaxHours") or cfg.settings.npcPlannedReactionMaxHours)
            cfg.settings.npcLateWinBlockHours = math.max(0.25, getXMLFloat(xmlId, "auctionNpcProfiles.settings#npcLateWinBlockHours") or cfg.settings.npcLateWinBlockHours)
            cfg.settings.softCloseEnabled = (getXMLBool(xmlId, "auctionNpcProfiles.settings#softCloseEnabled") ~= false)
            cfg.settings.softCloseTriggerHours = math.max(0.01, getXMLFloat(xmlId, "auctionNpcProfiles.settings#softCloseTriggerHours") or cfg.settings.softCloseTriggerHours)
            cfg.settings.softCloseExtendHours = math.max(0.01, getXMLFloat(xmlId, "auctionNpcProfiles.settings#softCloseExtendHours") or cfg.settings.softCloseExtendHours)
            cfg.settings.softCloseMaxExtensions = math.max(0, getXMLInt(xmlId, "auctionNpcProfiles.settings#softCloseMaxExtensions") or cfg.settings.softCloseMaxExtensions)
            cfg.settings.globalNpcGapMinHours = math.max(0.02, getXMLFloat(xmlId, "auctionNpcProfiles.settings#globalNpcGapMinHours") or cfg.settings.globalNpcGapMinHours)
            cfg.settings.globalNpcGapMaxHours = math.max(cfg.settings.globalNpcGapMinHours, getXMLFloat(xmlId, "auctionNpcProfiles.settings#globalNpcGapMaxHours") or cfg.settings.globalNpcGapMaxHours)

            cfg.settings.auctionDiscountMinPct = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#auctionDiscountMinPct") or cfg.settings.auctionDiscountMinPct, 0.00, 0.95)
            cfg.settings.auctionDiscountMaxPct = _clamp(getXMLFloat(xmlId, "auctionNpcProfiles.settings#auctionDiscountMaxPct") or cfg.settings.auctionDiscountMaxPct, cfg.settings.auctionDiscountMinPct, 0.95)

            cfg.npcNames = {}
            local i = 0
            while _xmlExists(xmlId, string.format("auctionNpcProfiles.npcNames.name(%d)#value", i)) do
                local value = getXMLString(xmlId, string.format("auctionNpcProfiles.npcNames.name(%d)#value", i))
                if value ~= nil and value ~= "" then
                    cfg.npcNames[#cfg.npcNames + 1] = value
                end
                i = i + 1
            end

            local langs = { "de", "en" }
            for _, lang in ipairs(langs) do
                cfg.auctionHouses[lang] = {}
                local j = 0
                while _xmlExists(xmlId, string.format("auctionNpcProfiles.auctionHouses.%s.house(%d)#name", lang, j)) do
                    local value = getXMLString(xmlId, string.format("auctionNpcProfiles.auctionHouses.%s.house(%d)#name", lang, j))
                    if value ~= nil and value ~= "" then
                        cfg.auctionHouses[lang][#cfg.auctionHouses[lang] + 1] = value
                    end
                    j = j + 1
                end
            end

            delete(xmlId)
        end
    end

    Auction._config = cfg
    return cfg
end

function Auction.newServer(farmlandId, name, startTime, endTime)
    Auction.ensureConfigLoaded()

    local self = setmetatable({}, Auction)
    self.auctionStartPriceRatio = 1.0
    self.betRatio = 0.035

    self.oneHourWarningSent = false
    self.thirtyMinWarningSent = false
    self.name = name or "Auction"

    self.farmlandId = farmlandId or 0
local farmland = g_farmlandManager:getFarmlandById(self.farmlandId)

local storedOriginalPrice = 0
local currentFarmlandPrice = 0

if farmland ~= nil then
    storedOriginalPrice = tonumber(farmland.faOriginalPrice or 0) or 0
    currentFarmlandPrice = tonumber(farmland.price or 0) or 0
    if currentFarmlandPrice <= 0 then
        currentFarmlandPrice = tonumber(farmland.price or 0) or 0
    end
end

self.originalPrice = math.max(storedOriginalPrice, currentFarmlandPrice)

if farmland ~= nil then
    farmland.faOriginalPrice = self.originalPrice
end
self.npcSettings = Auction.ensureConfigLoaded().settings

self.discountPct = _randRangeFloat(
    self.npcSettings.auctionDiscountMinPct or 0.15,
    self.npcSettings.auctionDiscountMaxPct or 0.55
)

self.normalPrice = math.max(1000, math.floor(self.originalPrice * (1 - self.discountPct)))

    self.startTime = startTime or 0
    self.endTime = endTime or 0

    self.currentPrice = self.normalPrice
    self.currentHighestFarmId = FarmlandManager.NO_OWNER_FARM_ID
    self.currentHighestName = nil
    self.currentHighestIsNpc = false

    self.betStepSize = math.max(100, math.floor(self.normalPrice * self.betRatio))
    self.maxPrice = self.originalPrice

    self.hasStarted = false
    self.auctionHouseName = self:generateAuctionHouseName()
    self.fieldStats = _getFieldStatsForFarmland(self.farmlandId)
    self.bidHistory = {}
    self.hadPlayerBid = false
    self.lastBidTime = 0
    self.nextNpcGlobalBidTime = self.startTime
    self.softCloseExtensionCount = 0

  g_farmlandManager:setLandOwnership(self.farmlandId, FarmlandManager.NOT_BUYABLE_FARM_ID)

    self.npcBetTimes = {}
    self.npcBidders = {}
    self:generateRandomNpcBets()

    local now = _hoursNow()
    _aDbg(
        "Auction created: farmlandId=%d name='%s' house='%s' originalPrice=%d auctionBase=%d discountPct=%.2f%% start=%s end=%s (starts in %s, duration %s)",
        self.farmlandId,
        tostring(self.name),
        tostring(self.auctionHouseName),
        math.floor(self.originalPrice or 0),
        math.floor(self.normalPrice or 0),
        (self.discountPct or 0) * 100,
        _fmtHoursToDayHour(self.startTime),
        _fmtHoursToDayHour(self.endTime),
        _fmtDeltaHours((self.startTime or 0) - now),
        _fmtDeltaHours((self.endTime or 0) - (self.startTime or 0))
    )
    return self
end

function Auction.newClientFromState(state)
    Auction.ensureConfigLoaded()

    local self = setmetatable({}, Auction)
    self.auctionStartPriceRatio = state.auctionStartPriceRatio or 1.0
    self.betRatio = state.betRatio or 0.035
    self.oneHourWarningSent = state.oneHourWarningSent or false
    self.thirtyMinWarningSent = state.thirtyMinWarningSent or false
    self.name = state.name or "Auction"
    self.farmlandId = state.farmlandId or 0
    self.originalPrice = state.originalPrice or state.normalPrice or 0
    self.discountPct = state.discountPct or 0
    self.normalPrice = state.normalPrice or 0
    self.startTime = state.startTime or 0
    self.endTime = state.endTime or 0
    self.currentPrice = state.currentPrice or 0
    self.currentHighestFarmId = state.currentHighestFarmId or FarmlandManager.NO_OWNER_FARM_ID
    self.currentHighestName = state.currentHighestName
    self.currentHighestIsNpc = state.currentHighestIsNpc or false
    self.betStepSize = state.betStepSize or 100
    self.maxPrice = state.maxPrice or self.originalPrice or self.normalPrice
    self.hasStarted = state.hasStarted or false
    self.auctionHouseName = state.auctionHouseName or "Auction House"
    self.fieldStats = state.fieldStats or _getFieldStatsForFarmland(self.farmlandId)
    self.bidHistory = state.bidHistory or {}
    self.hadPlayerBid = state.hadPlayerBid or false
    self.lastBidTime = state.lastBidTime or 0
    self.nextNpcGlobalBidTime = state.nextNpcGlobalBidTime or self.startTime
    self.softCloseExtensionCount = state.softCloseExtensionCount or 0
    self.npcSettings = Auction.ensureConfigLoaded().settings
    self.npcBetTimes = {}
    self.npcBidders = {}
    return self
end

function Auction:toState()
    return {
        auctionStartPriceRatio = self.auctionStartPriceRatio,
        betRatio = self.betRatio,
        oneHourWarningSent = self.oneHourWarningSent,
        thirtyMinWarningSent = self.thirtyMinWarningSent,
        name = self.name,
        farmlandId = self.farmlandId,
        originalPrice = self.originalPrice,
        discountPct = self.discountPct,
        normalPrice = self.normalPrice,
        startTime = self.startTime,
        endTime = self.endTime,
        currentPrice = self.currentPrice,
        currentHighestFarmId = self.currentHighestFarmId,
        currentHighestName = self.currentHighestName,
        currentHighestIsNpc = self.currentHighestIsNpc,
        betStepSize = self.betStepSize,
        maxPrice = self.maxPrice,
        hasStarted = self.hasStarted,
        auctionHouseName = self.auctionHouseName,
        fieldStats = self.fieldStats,
        bidHistory = self.bidHistory,
        hadPlayerBid = self.hadPlayerBid,
        lastBidTime = self.lastBidTime,
        nextNpcGlobalBidTime = self.nextNpcGlobalBidTime,
        softCloseExtensionCount = self.softCloseExtensionCount
    }
end

function Auction:isOutdated()
    return _hoursNow() > (self.endTime or 0)
end

function Auction:remainingTimeHours()
    return (self.endTime or 0) - _hoursNow()
end

function Auction:getDurationHours()
    return math.max(0.01, (self.endTime or 0) - (self.startTime or 0))
end

function Auction:getTimeProgress()
    local duration = self:getDurationHours()
    local remaining = math.max(0, self:remainingTimeHours())
    return math.max(0, math.min(1, 1 - (remaining / duration)))
end

function Auction:getDynamicBidStep()
    local progress = self:getTimeProgress()
    local ratio = 0.022

    if progress >= 0.92 then
        ratio = 0.034
    elseif progress >= 0.75 then
        ratio = 0.030
    elseif progress >= 0.45 then
        ratio = 0.026
    end

    if self.fieldStats ~= nil then
        if self.fieldStats.sizeClass == "large" then
            ratio = ratio * 1.10
        elseif self.fieldStats.sizeClass == "nofield" then
            ratio = ratio * 0.80
        end
    end

    return math.max(100, math.floor(self.normalPrice * ratio))
end

local function _getFarmAvailableMoney(farm)
    if farm == nil then
        return 0
    end

    local values = {}

    if farm.getBalance ~= nil then
        local ok, value = pcall(farm.getBalance, farm)
        if ok and value ~= nil then
            values[#values + 1] = tonumber(value) or 0
        end
    end

    values[#values + 1] = tonumber(farm.money) or 0
    values[#values + 1] = tonumber(farm.balance) or 0

    if farm.stats ~= nil then
        values[#values + 1] = tonumber(farm.stats.balance) or 0
        values[#values + 1] = tonumber(farm.stats.money) or 0
    end

    local best = values[1] or 0
    for i = 2, #values do
        if values[i] > best then
            best = values[i]
        end
    end

    return best
end

function Auction:canBid(farmId, steps)
    steps = math.max(1, tonumber(steps) or 1)
    if farmId == nil then
        return false, "INVALID_FARM"
    end
    if farmId == FarmlandManager.NO_OWNER_FARM_ID then
        return true, nil
    end

    local nextPrice = self.currentPrice + (self:getDynamicBidStep() * steps)
    if nextPrice > (self.originalPrice or self.maxPrice or nextPrice) then
        return false, "MAX_PRICE_REACHED"
    end

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        return false, "INVALID_FARM"
    end

    local balance = _getFarmAvailableMoney(farm)
    if balance >= nextPrice then
        return true, nil
    end

    return false, "NOT_ENOUGH_MONEY"
end

function Auction:generateAuctionHouseName()
    local lang = "en"
    if g_i18n ~= nil and g_i18n.getLanguageShort ~= nil then
        local ok, value = pcall(g_i18n.getLanguageShort, g_i18n)
        if ok and value ~= nil then
            lang = tostring(value)
        end
    end

    local cfg = Auction.ensureConfigLoaded()
    local names = cfg.auctionHouses[lang] or cfg.auctionHouses.en
    return _safeRandomName(names, lang == "de" and "Auktionshaus" or "Auction House")
end

function Auction:_getNpcNamePool()
    local cfg = Auction.ensureConfigLoaded()
    local names = _shuffle(cfg.npcNames or {})
    if #names == 0 then
        names = { "NPC 1", "NPC 2", "NPC 3" }
    end
    return names
end

function Auction:newNpcProfile(index, name)
    local costMultiplier = 1
    if g_currentMission ~= nil and g_currentMission.economyManager ~= nil and g_currentMission.economyManager.getCostMultiplier ~= nil then
        costMultiplier = g_currentMission.economyManager:getCostMultiplier()
    end

    local baseValue = math.max(self.originalPrice or 0, self.normalPrice or 0)
    local conservativeBias = math.random()

    local minLimit = math.floor(baseValue * (0.84 + conservativeBias * 0.08) * costMultiplier)
    local maxLimit = math.floor(baseValue * (1.06 + conservativeBias * 0.22) * costMultiplier)

    if math.random() < 0.22 then
        maxLimit = math.floor(baseValue * (1.12 + math.random() * 0.16) * costMultiplier)
    end

    if self.fieldStats ~= nil then
        if self.fieldStats.sizeClass == "large" then
            maxLimit = math.floor(maxLimit * 1.05)
        elseif self.fieldStats.sizeClass == "nofield" then
            maxLimit = math.floor(maxLimit * 0.88)
            minLimit = math.floor(minLimit * 0.92)
        end
    end

    if maxLimit < minLimit then
        maxLimit = minLimit
    end

    local duration = self:getDurationHours()
    local planBidCount = math.random(3, 6)

    if duration >= 72 then
        planBidCount = math.random(4, 7)
    elseif duration <= 36 then
        planBidCount = math.random(2, 5)
    end

    if self.fieldStats ~= nil and self.fieldStats.sizeClass == "nofield" then
        planBidCount = math.max(1, planBidCount - 1)
    end

    return {
        name = tostring(name or ("NPC " .. tostring(index or 1))),
        maxBid = math.random(minLimit, maxLimit),
        aggression = 0.80 + math.random() * 0.30,
        patience = 0.75 + math.random() * 0.30,
        snipeChance = 0.04 + math.random() * 0.10,
        nextBidTime = self.startTime,
        active = true,
        planBidCount = planBidCount,
        bidsPlaced = 0,
        dropoutBias = 0.90 + math.random() * 0.06,
        lastDecisionTime = 0,
        mayBeatPlayerEndgame = (math.random() <= ((self.npcSettings and self.npcSettings.npcWinChanceAgainstPlayer) or 0.40)),
        forcedReaction = false,
        reserved = false
    }
end

function Auction:generateRandomNpcBets()
    self.npcBidders = {}
    self.npcBetTimes = {}

    local cfg = Auction.ensureConfigLoaded()
    local names = self:_getNpcNamePool()
    local available = #names
    local bidderMin = math.max(1, cfg.settings.minBidders or 2)
    local bidderMax = math.max(bidderMin, cfg.settings.maxBidders or 6)
    bidderMax = math.min(bidderMax, math.max(1, available))

    if self.fieldStats ~= nil and self.fieldStats.sizeClass == "large" then
        bidderMax = math.min(math.max(bidderMin, bidderMax + 1), math.max(1, available))
    elseif self.fieldStats ~= nil and self.fieldStats.sizeClass == "nofield" then
        bidderMax = math.max(1, bidderMax - 1)
        bidderMin = math.max(1, math.min(bidderMin, bidderMax))
    end

    local bidderCount = math.random(bidderMin, bidderMax)
    local duration = math.max(24, self:getDurationHours())

    for i = 1, bidderCount do
        local npc = self:newNpcProfile(i, names[i])

        local slots = {}
        local bidCount = math.max(1, npc.planBidCount or 1)

        local firstMin = 0.08
        local firstMax = math.min(1.25, math.max(0.35, duration * 0.03))
        local mainStart = self.startTime + math.min(0.40, math.max(0.12, duration * 0.01))
        local mainEnd = self.endTime - math.max(0.75, duration * 0.06)

        slots[1] = self.startTime + _randRangeFloat(firstMin, firstMax)

        for j = 2, bidCount do
            local progressMin = math.max(0.06, (j - 1) / math.max(2, bidCount + 1))
            local progressMax = math.min(0.96, (j + 1) / math.max(3, bidCount + 1))

            local tMin = self.startTime + duration * progressMin
            local tMax = self.startTime + duration * progressMax

            tMin = math.max(mainStart, tMin)
            tMax = math.min(mainEnd, tMax)

            if tMax <= tMin then
                tMax = tMin + 0.15
            end

            slots[#slots + 1] = _randRangeFloat(tMin, tMax)
        end

        table.sort(slots)

        npc.bidSlots = slots
        npc.nextBidTime = slots[1] or (self.startTime + 0.25)
        npc.planBidCount = #slots

        self.npcBidders[i] = npc
    end

    local highestLimit = self.originalPrice
    local reactiveIndex = 0
    local reactiveBest = -1

    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil then
            if (npc.maxBid or 0) > highestLimit then
                highestLimit = npc.maxBid or highestLimit
            end

            if (npc.maxBid or 0) > reactiveBest then
                reactiveBest = npc.maxBid or 0
                reactiveIndex = i
            end
        end
    end

    self.maxPrice = highestLimit
    self.betStepSize = self:getDynamicBidStep()

    local firstNpcBidAt = 0
    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil and npc.nextBidTime ~= nil then
            if firstNpcBidAt == 0 or npc.nextBidTime < firstNpcBidAt then
                firstNpcBidAt = npc.nextBidTime
            end
        end
    end

    self.nextNpcGlobalBidTime = firstNpcBidAt > 0 and firstNpcBidAt or (self.startTime + 0.10)

    if reactiveIndex > 0 and self.npcBidders[reactiveIndex] ~= nil then
        local reactiveNpc = self.npcBidders[reactiveIndex]
        reactiveNpc.reserved = true

        local guaranteedReactiveMax = math.floor((self.originalPrice or self.normalPrice or 0) * _randRangeFloat(0.98, 1.08))
        if self.fieldStats ~= nil and self.fieldStats.sizeClass == "large" then
            guaranteedReactiveMax = math.floor(guaranteedReactiveMax * 1.03)
        end

        reactiveNpc.maxBid = math.max(tonumber(reactiveNpc.maxBid or 0) or 0, guaranteedReactiveMax)
    end

    local totalPlanned = 0
    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        totalPlanned = totalPlanned + math.max(0, npc and npc.planBidCount or 0)
    end

    _aDbg(
        "[NPCGEN] bidders=%d totalPlannedBids=%d auctionBase=%d original=%d firstNpcBidAt=%s",
        bidderCount,
        totalPlanned,
        tonumber(self.normalPrice or 0) or 0,
        tonumber(self.originalPrice or 0) or 0,
        _fmtHoursToDayHour(firstNpcBidAt)
    )
end

function Auction:getCurrentHighestDisplayName()
    if self.currentHighestIsNpc then
        return self.currentHighestName or "NPC"
    end
    if self.currentHighestFarmId ~= nil and self.currentHighestFarmId > 0 then
        return "Farm " .. tostring(self.currentHighestFarmId)
    end
    return nil
end

function Auction:_appendHistory(farmId, bidderName)
    self.bidHistory = self.bidHistory or {}

    local entry = {
        farmId = tonumber(farmId or 0) or 0,
        isNpc = (tonumber(farmId or 0) or 0) == FarmlandManager.NO_OWNER_FARM_ID,
        bidderName = bidderName or nil,
        price = self.currentPrice or 0,
        time = _hoursNow()
    }

    if not entry.isNpc and (entry.farmId or 0) > 0 then
        entry.bidderName = "Farm " .. tostring(entry.farmId)
    elseif entry.isNpc then
        entry.bidderName = bidderName or "NPC"
    end

    table.insert(self.bidHistory, 1, entry)
    while #self.bidHistory > 4 do
        table.remove(self.bidHistory)
    end
end

function Auction:_calcNextNpcGlobalGap(now)
    local progress = self:getTimeProgress()
    local minGap = self.npcSettings.globalNpcGapMinHours or 0.10
    local maxGap = self.npcSettings.globalNpcGapMaxHours or 0.90

    if progress < 0.30 then
        minGap = math.max(minGap, 0.20)
        maxGap = math.max(maxGap, 1.20)
    elseif progress < 0.65 then
        minGap = math.max(minGap, 0.12)
        maxGap = math.max(maxGap, 0.70)
    else
        minGap = math.max(0.04, minGap * 0.6)
        maxGap = math.max(minGap + 0.04, maxGap * 0.6)
    end

    self.nextNpcGlobalBidTime = now + minGap + math.random() * math.max(0.01, maxGap - minGap)
end

function Auction:_tryApplySoftClose()
    if self.npcSettings.softCloseEnabled ~= true then
        return nil
    end
    if (self.softCloseExtensionCount or 0) >= (self.npcSettings.softCloseMaxExtensions or 0) then
        return nil
    end
    if self:remainingTimeHours() > (self.npcSettings.softCloseTriggerHours or 0.08) then
        return nil
    end

    self.endTime = (self.endTime or 0) + (self.npcSettings.softCloseExtendHours or 0.20)
    self.softCloseExtensionCount = (self.softCloseExtensionCount or 0) + 1
    return {
        kind = "SOFT_CLOSE_EXTENDED",
        hours = self.npcSettings.softCloseExtendHours or 0.20,
        count = self.softCloseExtensionCount
    }
end

function Auction:placeBidServer(farmId, bidderName)
    local canBid, reason = self:canBid(farmId, 1)
    if not canBid then
        return false, { kind = reason or "NOT_ENOUGH_MONEY", farmId = farmId }, nil, nil
    end

    local previousFarmId = self.currentHighestFarmId
    local previousWasNpc = self.currentHighestIsNpc
    local previousName = self.currentHighestName

    self.betStepSize = self:getDynamicBidStep()

    local nextPrice = math.floor(self.currentPrice + self.betStepSize)
    local hardCap = self.originalPrice or self.maxPrice or nextPrice
    if nextPrice > hardCap then
        return false, { kind = "MAX_PRICE_REACHED", farmId = farmId }, nil, nil
    end

    self.currentPrice = nextPrice
    self.currentHighestFarmId = farmId
    self.currentHighestIsNpc = (farmId == FarmlandManager.NO_OWNER_FARM_ID)
    self.currentHighestName = bidderName
    self.lastBidTime = _hoursNow()

    if not self.currentHighestIsNpc and (tonumber(farmId or 0) or 0) > 0 then
        self.hadPlayerBid = true
        self:_scheduleNpcReactionAfterPlayerBid(farmId)
    end

    local notification
    if farmId ~= FarmlandManager.NO_OWNER_FARM_ID then
        notification = { kind = "FARM_HIGHEST", farmId = farmId, price = self.currentPrice, npcName = tostring(bidderName or "") }
    else
        local npcName = bidderName or "NPC"
        notification = { kind = "NPC_HIGHEST", npcName = npcName, price = self.currentPrice }
    end

    self:_appendHistory(farmId, bidderName)

    local outbid = nil
    if previousFarmId ~= nil and previousFarmId > 0 and previousFarmId ~= farmId then
        outbid = {
            farmId = previousFarmId,
            previousWasNpc = previousWasNpc,
            previousName = previousName,
            newIsNpc = self.currentHighestIsNpc,
            newFarmId = self.currentHighestFarmId,
            newName = self.currentHighestName,
            price = self.currentPrice
        }
    end

    local extraNotification = self:_tryApplySoftClose()
    return true, notification, outbid, extraNotification
end

function Auction:scheduleNpcRetry(npc, now, playerHighest)
    if npc == nil then
        return
    end

    npc.forcedReaction = false

    if npc.bidSlots ~= nil then
        local nextSlot = nil
        for i = 1, #npc.bidSlots do
            local t = npc.bidSlots[i]
            if t ~= nil and t > now then
                nextSlot = t
                break
            end
        end
        npc.nextBidTime = nextSlot or (self.endTime + 999)
        return
    end

    npc.nextBidTime = self.endTime + 999
end

function Auction:canNpcStillBid(npc)
    if npc == nil or npc.active ~= true then
        return false
    end

    if (npc.bidsPlaced or 0) >= (npc.planBidCount or 1) then
        return false
    end

    local nextPrice = self.currentPrice + self:getDynamicBidStep()
    local hardCap = self.originalPrice or self.maxPrice or nextPrice

    if nextPrice > hardCap then
        return false
    end
    if nextPrice > (npc.maxBid or 0) then
        return false
    end

    if npc.bidSlots ~= nil then
        local hasFutureSlot = false
        for i = 1, #npc.bidSlots do
            local t = npc.bidSlots[i]
            if t ~= nil and t >= _hoursNow() then
                hasFutureSlot = true
                break
            end
        end
        if not hasFutureSlot and npc.forcedReaction ~= true then
            return false
        end
    end

    return true
end

function Auction:_findReactiveNpcCandidate()
    local candidate = nil
    local bestScore = -999

    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil and npc.active == true and npc.forcedReaction ~= true and npc.reserved == true and self:canNpcStillBid(npc) then
            local remainingBudget = math.max(0, (npc.maxBid or 0) - self.currentPrice)
            local budgetFactor = math.max(0, math.min(1, remainingBudget / math.max(1, self.originalPrice * 0.25)))
            local score = budgetFactor + ((npc.aggression or 1) - 1) * 0.40 + math.random() * 0.15
            if score > bestScore then
                bestScore = score
                candidate = npc
            end
        end
    end

    if candidate ~= nil then
        return candidate
    end

    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil and npc.active == true and npc.forcedReaction ~= true and self:canNpcStillBid(npc) then
            local remainingBudget = math.max(0, (npc.maxBid or 0) - self.currentPrice)
            local budgetFactor = math.max(0, math.min(1, remainingBudget / math.max(1, self.originalPrice * 0.25)))
            local score = budgetFactor + ((npc.aggression or 1) - 1) * 0.40 + math.random() * 0.15
            if score > bestScore then
                bestScore = score
                candidate = npc
            end
        end
    end

    return candidate
end

function Auction:_scheduleNpcReactionAfterPlayerBid(farmId)
    local now = _hoursNow()

    if math.random() > (self.npcSettings.npcCounterChance or 0.10) then
        _aDbg(
            "[NPCPLAN] no instant counter after player bid farmId=%d chance=%.2f currentPrice=%d",
            tonumber(farmId or 0) or 0,
            tonumber(self.npcSettings.npcCounterChance or 0.10) or 0.10,
            tonumber(self.currentPrice or 0) or 0
        )
        return
    end

    local npc = self:_findReactiveNpcCandidate()
    if npc == nil then
        _aDbg(
            "[NPCPLAN] no reactive NPC available after player bid farmId=%d currentPrice=%d originalPrice=%d auctionBase=%d",
            tonumber(farmId or 0) or 0,
            tonumber(self.currentPrice or 0) or 0,
            tonumber(self.originalPrice or 0) or 0,
            tonumber(self.normalPrice or 0) or 0
        )
        return
    end

    local minDelay = self.npcSettings.npcImmediateCounterMinHours or 0.001
    local maxDelay = self.npcSettings.npcImmediateCounterMaxHours or 0.008
    local delay = minDelay + math.random() * math.max(0.0002, maxDelay - minDelay)
    local when = now + delay

    npc.nextBidTime = when
    npc.forcedReaction = true
    npc.lastDecisionTime = now

    if self.nextNpcGlobalBidTime == nil then
        self.nextNpcGlobalBidTime = when
    else
        self.nextNpcGlobalBidTime = math.min(self.nextNpcGlobalBidTime, when)
    end

    _aDbg(
        "[NPCPLAN] instant counter armed farmId=%d npc='%s' scheduledIn=%s scheduledAt=%s maxBid=%d current=%d original=%d auctionBase=%d",
        tonumber(farmId or 0) or 0,
        tostring(npc.name or "NPC"),
        _fmtDeltaHours(delay),
        _fmtHoursToDayHour(when),
        tonumber(npc.maxBid or 0) or 0,
        tonumber(self.currentPrice or 0) or 0,
        tonumber(self.originalPrice or 0) or 0,
        tonumber(self.normalPrice or 0) or 0
    )
end

function Auction:_chanceNpcMayTakeLead(npc)
    local remaining = self:remainingTimeHours()
    local duration = self:getDurationHours()

    local dynamicLateBlock = math.min(
        self.npcSettings.npcLateWinBlockHours or 8.0,
        math.max(0.5, duration * 0.22)
    )

    if self.hadPlayerBid == true and self.currentHighestFarmId ~= nil and self.currentHighestFarmId > 0 then
        if remaining <= dynamicLateBlock then
            if npc == nil or npc.mayBeatPlayerEndgame ~= true then
                return 0.0
            end
            return _clamp(self.npcSettings.npcWinChanceAgainstPlayer or 0.40, 0.01, 1.0)
        end
        return 1.0
    end

    return 1.0
end

function Auction:tryNpcBid(nowHoursValue)
    if self.npcBidders == nil or not self.hasStarted then
        return false, nil, nil, nil
    end

    local now = tonumber(nowHoursValue) or 0
    if now < (tonumber(self.nextNpcGlobalBidTime or 0) or 0) then
        return false, nil, nil, nil
    end

    local playerHighest = self.currentHighestFarmId ~= nil and self.currentHighestFarmId > 0
    local candidate = nil
    local bestScore = -999

    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil and npc.active == true and now >= (tonumber(npc.nextBidTime or 0) or 0) then
            if not self:canNpcStillBid(npc) then
                npc.active = false
            else
                local remainingBudget = math.max(0, (tonumber(npc.maxBid or 0) or 0) - (tonumber(self.currentPrice or 0) or 0))
                local budgetFactor = math.max(0, math.min(1, remainingBudget / math.max(1, (tonumber(self.originalPrice or 0) or 0) * 0.22)))
                local score = budgetFactor + ((tonumber(npc.aggression or 1) or 1) - 1) * 0.35 + math.random() * 0.20

                if npc.forcedReaction == true then
                    score = score + 3.0
                end

                if playerHighest then
                    score = score + 0.15
                end

                if score > bestScore then
                    bestScore = score
                    candidate = npc
                end
            end
        end
    end

    if candidate == nil then
        local nextDue = nil

        for i = 1, #self.npcBidders do
            local npc = self.npcBidders[i]
            if npc ~= nil and npc.active == true and npc.nextBidTime ~= nil then
                if nextDue == nil or npc.nextBidTime < nextDue then
                    nextDue = npc.nextBidTime
                end
            end
        end

        self.nextNpcGlobalBidTime = nextDue or (now + 0.01)
        return false, nil, nil, nil
    end

    local chance
    if candidate.forcedReaction == true then
        chance = 1.00
    elseif playerHighest then
        chance = 0.78
    else
        chance = 0.60
    end

    chance = chance * self:_chanceNpcMayTakeLead(candidate)
    chance = _clamp(chance, 0.0, 1.0)

    _aDbg(
        "[NPCBID] due npc='%s' forced=%s playerHighest=%s chance=%.3f current=%d step=%d maxBid=%d",
        tostring(candidate.name or "NPC"),
        tostring(candidate.forcedReaction == true),
        tostring(playerHighest),
        chance,
        tonumber(self.currentPrice or 0) or 0,
        tonumber(self:getDynamicBidStep() or 0) or 0,
        tonumber(candidate.maxBid or 0) or 0
    )

    if math.random() <= chance then
        candidate.bidsPlaced = (candidate.bidsPlaced or 0) + 1
        local ok, notification, outbid, extra = self:placeBidServer(FarmlandManager.NO_OWNER_FARM_ID, candidate.name)
        self:scheduleNpcRetry(candidate, now, false)
        candidate.forcedReaction = false

        local nextDue = nil
        for i = 1, #self.npcBidders do
            local npc = self.npcBidders[i]
            if npc ~= nil and npc.active == true and npc.nextBidTime ~= nil then
                if nextDue == nil or npc.nextBidTime < nextDue then
                    nextDue = npc.nextBidTime
                end
            end
        end
        self.nextNpcGlobalBidTime = nextDue or (self.endTime + 999)

        _aDbg(
            "[NPCBID] placed npc='%s' price=%d bidsPlaced=%d nextNpcGlobal=%.3f",
            tostring(candidate.name or "NPC"),
            tonumber(self.currentPrice or 0) or 0,
            tonumber(candidate.bidsPlaced or 0) or 0,
            tonumber(self.nextNpcGlobalBidTime or 0) or 0
        )

        return ok, notification, outbid, extra
    end

    self:scheduleNpcRetry(candidate, now, playerHighest)
    candidate.forcedReaction = false

    local nextDue = nil
    for i = 1, #self.npcBidders do
        local npc = self.npcBidders[i]
        if npc ~= nil and npc.active == true and npc.nextBidTime ~= nil then
            if nextDue == nil or npc.nextBidTime < nextDue then
                nextDue = npc.nextBidTime
            end
        end
    end
    self.nextNpcGlobalBidTime = nextDue or (now + 0.01)

    _aDbg("[NPCBID] skipped npc='%s' chance=%.3f", tostring(candidate.name or "NPC"), chance)
    return false, nil, nil, nil
end

function Auction:auctionEndedServer()
    if self.currentHighestFarmId ~= nil and self.currentHighestFarmId > 0 then
        -- Reset from NOT_BUYABLE to NO_OWNER first so setLandOwnership works
        local currentOwner = tonumber(g_farmlandManager:getFarmlandOwner(self.farmlandId) or 0) or 0
        if currentOwner == FarmlandManager.NOT_BUYABLE_FARM_ID then
            g_farmlandManager:setLandOwnership(self.farmlandId, FarmlandManager.NO_OWNER_FARM_ID)
        end

        g_farmlandManager:setLandOwnership(self.farmlandId, self.currentHighestFarmId)

        -- Notify FS25 internals so minimap/field colors update on server
        if g_messageCenter ~= nil then
            if currentOwner ~= FarmlandManager.NO_OWNER_FARM_ID and currentOwner ~= FarmlandManager.NOT_BUYABLE_FARM_ID then
                g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, currentOwner)
            end
            g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, self.currentHighestFarmId)
        end

        local currentFarm = g_farmManager:getFarmById(self.currentHighestFarmId)
        if currentFarm ~= nil then
            if currentFarm:getBalance() < self.currentPrice then
                local missingMoney = self.currentPrice - currentFarm:getBalance()
                local loanToTake = math.ceil(missingMoney / 5000) * 5000
                currentFarm.loan = currentFarm:getLoan() + loanToTake
                g_currentMission:addMoney(loanToTake, self.currentHighestFarmId, MoneyType.LOAN, true, true)
            end
            g_currentMission:addMoney(-self.currentPrice, self.currentHighestFarmId, MoneyType.FIELD_BUY, true, true)
        end

        -- Include farmlandId so clients know which field was sold
        return { kind = "SOLD_TO_FARM", farmId = self.currentHighestFarmId, price = self.currentPrice, farmlandId = self.farmlandId }
    end

    g_farmlandManager:setLandOwnership(self.farmlandId, FarmlandManager.NO_OWNER_FARM_ID)
    local farmland = g_farmlandManager:getFarmlandById(self.farmlandId)
    if farmland ~= nil then
        farmland.price = self.originalPrice or self.normalPrice
    end
    return { kind = "NOT_SOLD", price = self.currentPrice }
end

function Auction:saveToXml(pathToXML)
    local xmlId = createXMLFile("auction", pathToXML, "auction")

    setXMLFloat(xmlId, "auction.auctionStartPriceRatio", self.auctionStartPriceRatio)
    setXMLFloat(xmlId, "auction.betRatio", self.betRatio)
    setXMLFloat(xmlId, "auction.startTime", self.startTime)
    setXMLFloat(xmlId, "auction.endTime", self.endTime)
    setXMLFloat(xmlId, "auction.originalPrice", self.originalPrice or 0)
    setXMLFloat(xmlId, "auction.discountPct", self.discountPct or 0)
    setXMLFloat(xmlId, "auction.normalPrice", self.normalPrice)
    setXMLFloat(xmlId, "auction.currentPrice", self.currentPrice)
    setXMLFloat(xmlId, "auction.maxPrice", self.maxPrice)
    setXMLInt(xmlId, "auction.farmlandId", self.farmlandId)
    setXMLInt(xmlId, "auction.currentHighestFarmId", self.currentHighestFarmId)

    setXMLBool(xmlId, "auction.oneHourWarningSent", self.oneHourWarningSent)
    setXMLBool(xmlId, "auction.thirtyMinWarningSent", self.thirtyMinWarningSent)
    setXMLBool(xmlId, "auction.hasStarted", self.hasStarted)
    setXMLBool(xmlId, "auction.currentHighestIsNpc", self.currentHighestIsNpc)
    setXMLBool(xmlId, "auction.hadPlayerBid", self.hadPlayerBid == true)

    setXMLFloat(xmlId, "auction.lastBidTime", self.lastBidTime or 0)
    setXMLFloat(xmlId, "auction.nextNpcGlobalBidTime", self.nextNpcGlobalBidTime or 0)
    setXMLInt(xmlId, "auction.softCloseExtensionCount", self.softCloseExtensionCount or 0)

    setXMLString(xmlId, "auction.name", self.name)
    setXMLString(xmlId, "auction.auctionHouseName", self.auctionHouseName or "")
    setXMLString(xmlId, "auction.currentHighestName", self.currentHighestName or "")

    if self.fieldStats ~= nil then
        setXMLInt(xmlId, "auction.fieldStats.fieldCount", self.fieldStats.fieldCount or 0)
        setXMLFloat(xmlId, "auction.fieldStats.totalArea", self.fieldStats.totalArea or 0)
        setXMLBool(xmlId, "auction.fieldStats.hasFields", self.fieldStats.hasFields == true)
        setXMLString(xmlId, "auction.fieldStats.sizeClass", self.fieldStats.sizeClass or "medium")
    end

    if self.npcBidders ~= nil then
        for i = 1, #self.npcBidders do
            local npc = self.npcBidders[i]
            if npc ~= nil then
                local base = string.format("auction.npcBidders.bid%02d", i)
                setXMLString(xmlId, base .. "#name", npc.name or "")
                setXMLFloat(xmlId, base .. "#maxBid", npc.maxBid or 0)
                setXMLFloat(xmlId, base .. "#aggression", npc.aggression or 1)
                setXMLFloat(xmlId, base .. "#patience", npc.patience or 1)
                setXMLFloat(xmlId, base .. "#snipeChance", npc.snipeChance or 0.1)
                setXMLFloat(xmlId, base .. "#nextBidTime", npc.nextBidTime or 0)
                setXMLBool(xmlId, base .. "#active", npc.active == true)
                setXMLInt(xmlId, base .. "#planBidCount", npc.planBidCount or 1)
                setXMLInt(xmlId, base .. "#bidsPlaced", npc.bidsPlaced or 0)
                setXMLFloat(xmlId, base .. "#dropoutBias", npc.dropoutBias or 0.9)
                setXMLBool(xmlId, base .. "#mayBeatPlayerEndgame", npc.mayBeatPlayerEndgame == true)
                setXMLBool(xmlId, base .. "#forcedReaction", npc.forcedReaction == true)
                setXMLFloat(xmlId, base .. "#lastDecisionTime", npc.lastDecisionTime or 0)
            end
        end
    end

    if self.bidHistory ~= nil then
        for i = 1, #self.bidHistory do
            local item = self.bidHistory[i]
            if item ~= nil then
                local base = string.format("auction.bidHistory.item%02d", i)
                setXMLInt(xmlId, base .. "#farmId", item.farmId or 0)
                setXMLBool(xmlId, base .. "#isNpc", item.isNpc == true)
                setXMLString(xmlId, base .. "#bidderName", item.bidderName or "")
                setXMLFloat(xmlId, base .. "#price", item.price or 0)
                setXMLFloat(xmlId, base .. "#time", item.time or 0)
            end
        end
    end

    saveXMLFile(xmlId)
    delete(xmlId)
end

function Auction.loadFromXmlFile(pathToXML)
    Auction.ensureConfigLoaded()

    local xmlId = loadXMLFile("auction", pathToXML)
    if xmlId == 0 then
        return nil
    end

    local startTime = getXMLFloat(xmlId, "auction.startTime") or 0
    local endTime = getXMLFloat(xmlId, "auction.endTime") or 0
    local farmlandId = getXMLInt(xmlId, "auction.farmlandId") or 0
    local name = getXMLString(xmlId, "auction.name") or "Auction"

    local a = Auction.newServer(farmlandId, name, startTime, endTime)

    a.auctionStartPriceRatio = getXMLFloat(xmlId, "auction.auctionStartPriceRatio") or a.auctionStartPriceRatio
    a.betRatio = getXMLFloat(xmlId, "auction.betRatio") or a.betRatio
    a.oneHourWarningSent = getXMLBool(xmlId, "auction.oneHourWarningSent") or false
    a.thirtyMinWarningSent = getXMLBool(xmlId, "auction.thirtyMinWarningSent") or false
    a.hasStarted = getXMLBool(xmlId, "auction.hasStarted") or false
    a.currentHighestIsNpc = getXMLBool(xmlId, "auction.currentHighestIsNpc") or false
    a.hadPlayerBid = getXMLBool(xmlId, "auction.hadPlayerBid") or false

    a.currentHighestFarmId = getXMLInt(xmlId, "auction.currentHighestFarmId") or a.currentHighestFarmId
    a.originalPrice = getXMLFloat(xmlId, "auction.originalPrice") or a.originalPrice
    a.discountPct = getXMLFloat(xmlId, "auction.discountPct") or a.discountPct
    a.normalPrice = getXMLFloat(xmlId, "auction.normalPrice") or a.normalPrice
    a.currentPrice = getXMLFloat(xmlId, "auction.currentPrice") or a.currentPrice
    a.maxPrice = getXMLFloat(xmlId, "auction.maxPrice") or a.maxPrice
    a.currentHighestName = getXMLString(xmlId, "auction.currentHighestName") or a.currentHighestName
    a.auctionHouseName = getXMLString(xmlId, "auction.auctionHouseName") or a.auctionHouseName
    a.lastBidTime = getXMLFloat(xmlId, "auction.lastBidTime") or 0
    a.nextNpcGlobalBidTime = getXMLFloat(xmlId, "auction.nextNpcGlobalBidTime") or a.startTime
    a.softCloseExtensionCount = getXMLInt(xmlId, "auction.softCloseExtensionCount") or 0

    a.fieldStats = {
        fieldCount = getXMLInt(xmlId, "auction.fieldStats.fieldCount") or 0,
        totalArea = getXMLFloat(xmlId, "auction.fieldStats.totalArea") or 0,
        hasFields = getXMLBool(xmlId, "auction.fieldStats.hasFields") or false,
        sizeClass = getXMLString(xmlId, "auction.fieldStats.sizeClass") or "medium"
    }

    a.betStepSize = a:getDynamicBidStep()
    a.npcBidders = {}

    local i = 1
    while hasXMLProperty(xmlId, string.format("auction.npcBidders.bid%02d", i)) do
        local base = string.format("auction.npcBidders.bid%02d", i)
        a.npcBidders[i] = {
            name = getXMLString(xmlId, base .. "#name") or ("NPC " .. tostring(i)),
            maxBid = getXMLFloat(xmlId, base .. "#maxBid") or a.originalPrice,
            aggression = getXMLFloat(xmlId, base .. "#aggression") or 1,
            patience = getXMLFloat(xmlId, base .. "#patience") or 1,
            snipeChance = getXMLFloat(xmlId, base .. "#snipeChance") or 0.1,
            nextBidTime = getXMLFloat(xmlId, base .. "#nextBidTime") or a.startTime,
            active = getXMLBool(xmlId, base .. "#active"),
            planBidCount = getXMLInt(xmlId, base .. "#planBidCount") or 1,
            bidsPlaced = getXMLInt(xmlId, base .. "#bidsPlaced") or 0,
            dropoutBias = getXMLFloat(xmlId, base .. "#dropoutBias") or 0.9,
            mayBeatPlayerEndgame = getXMLBool(xmlId, base .. "#mayBeatPlayerEndgame"),
            forcedReaction = getXMLBool(xmlId, base .. "#forcedReaction"),
            lastDecisionTime = getXMLFloat(xmlId, base .. "#lastDecisionTime") or 0
        }

        if a.npcBidders[i].active == nil then a.npcBidders[i].active = false end
        if a.npcBidders[i].mayBeatPlayerEndgame == nil then
            a.npcBidders[i].mayBeatPlayerEndgame = (math.random() <= ((a.npcSettings and a.npcSettings.npcWinChanceAgainstPlayer) or 0.40))
        end
        if a.npcBidders[i].forcedReaction == nil then a.npcBidders[i].forcedReaction = false end

        i = i + 1
    end

    a.bidHistory = {}
    local h = 1
    while hasXMLProperty(xmlId, string.format("auction.bidHistory.item%02d", h)) do
        local base = string.format("auction.bidHistory.item%02d", h)
        a.bidHistory[h] = {
            farmId = getXMLInt(xmlId, base .. "#farmId") or 0,
            isNpc = getXMLBool(xmlId, base .. "#isNpc") or false,
            bidderName = getXMLString(xmlId, base .. "#bidderName") or "",
            price = getXMLFloat(xmlId, base .. "#price") or 0,
            time = getXMLFloat(xmlId, base .. "#time") or 0
        }
        h = h + 1
    end

    delete(xmlId)

    local farmland = g_farmlandManager:getFarmlandById(a.farmlandId)
    if farmland ~= nil then
        local storedOriginalPrice = tonumber(farmland.faOriginalPrice or 0) or 0
        local currentFarmlandPrice = tonumber(farmland.price or 0) or 0
        local savedOriginalPrice = tonumber(a.originalPrice or 0) or 0
        a.originalPrice = math.max(savedOriginalPrice, storedOriginalPrice, currentFarmlandPrice)
        a.maxPrice = math.max(tonumber(a.maxPrice or 0) or 0, a.originalPrice or 0)
        farmland.faOriginalPrice = a.originalPrice or currentFarmlandPrice
    end

    g_farmlandManager:setLandOwnership(a.farmlandId, FarmlandManager.NOT_BUYABLE_FARM_ID)

    local now = _hoursNow()
    _aDbg(
        "Auction loaded: farmlandId=%d name='%s' house='%s' originalPrice=%d auctionBase=%d discountPct=%.2f%% start=%s end=%s (starts in %s, remaining %s) currentPrice=%d highestFarmId=%d",
        a.farmlandId or 0,
        tostring(a.name),
        tostring(a.auctionHouseName),
        math.floor(a.originalPrice or 0),
        math.floor(a.normalPrice or 0),
        (a.discountPct or 0) * 100,
        _fmtHoursToDayHour(a.startTime),
        _fmtHoursToDayHour(a.endTime),
        _fmtDeltaHours((a.startTime or 0) - now),
        _fmtDeltaHours((a.endTime or 0) - now),
        math.floor(a.currentPrice or 0),
        tonumber(a.currentHighestFarmId or 0)
    )

    return a
end