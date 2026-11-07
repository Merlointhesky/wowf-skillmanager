-- skills.lua for ForeverSkillManager
local addonName, FSM = ...

local pendingSpells = {}
local pendingEquipment = {}
local currentEquippedItems = {}

-- Debug mode can be toggled in-game via /fsm debug
local function IsDebugMode()
    return ForeverSkillManagerDB and ForeverSkillManagerDB.debugMode or false
end

local function DebugPrint(msg)
    if IsDebugMode() then
        print("|cff00ccff[FSM DEBUG]|r " .. msg)
    end
end

-- Standard visible action bar ranges (Bar 2 through Bar 6)
-- Note: Bar 1 range is dynamic based on GetActionBarPage()
local STANDARD_BAR_RANGES = {
    { 13, 24 },  -- Action Bar 2 (Page 2)
    { 25, 36 },  -- Action Bar 3 (Right Bar 2)
    { 37, 48 },  -- Action Bar 4 (Right Bar 1)
    { 49, 60 },  -- Action Bar 5 (Bottom Right Bar)
    { 61, 72 },  -- Action Bar 6 (Bottom Left Bar)
}

----------------------------------------------------
-- Hidden Tooltip Scanner
----------------------------------------------------
local scanTooltip = CreateFrame("GameTooltip", "FSMCacheScanTooltip", UIParent, "GameTooltipTemplate")

----------------------------------------------------
-- Compatibility & Helper Wrappers (WoW Forever 1.6 / 16001)
----------------------------------------------------
local function StripColorCodes(text)
    if type(text) ~= "string" then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function GetCharKey()
    local name, arg2 = UnitName("player")
    name = name or "Player"
    local realm = GetRealmName() or "Realm"

    -- WoW Forever 1.6 supports character last names via UnitName 2nd return or UnitLastName
    local lastName = nil
    if type(arg2) == "string" and arg2 ~= "" and arg2 ~= realm then
        lastName = arg2
    end
    if not lastName and UnitLastName then
        local last = UnitLastName("player")
        if type(last) == "string" and last ~= "" then
            lastName = last
        end
    end

    local fullName = lastName and (name .. " " .. lastName) or name
    local fullKey = fullName .. " - " .. realm
    local legacyKey = name .. " - " .. realm

    -- Migrate legacy first-name-only cache entry if needed
    if fullKey ~= legacyKey and ForeverSkillManagerDB and ForeverSkillManagerDB.trainerCache then
        if ForeverSkillManagerDB.trainerCache[legacyKey] and not ForeverSkillManagerDB.trainerCache[fullKey] then
            ForeverSkillManagerDB.trainerCache[fullKey] = ForeverSkillManagerDB.trainerCache[legacyKey]
            ForeverSkillManagerDB.trainerCache[legacyKey] = nil
        end
    end

    return fullKey
end
FSM.GetCharKey = GetCharKey

local function GetUnspentTalentPointsCount()
    if UnitCharacterPoints then
        local pts = tonumber(UnitCharacterPoints("player"))
        if pts and pts > 0 then return pts end
    end
    if GetUnspentTalentPoints then
        local ok, pts = pcall(GetUnspentTalentPoints, false, false, 1)
        if ok and tonumber(pts) and tonumber(pts) > 0 then return tonumber(pts) end
        local ok2, pts2 = pcall(GetUnspentTalentPoints)
        if ok2 and tonumber(pts2) and tonumber(pts2) > 0 then return tonumber(pts2) end
    end
    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local ok, hasUnspent, numPoints = pcall(C_ClassTalents.HasUnspentTalentPoints)
        if ok and hasUnspent then
            return tonumber(numPoints) or 1
        end
    end
    return 0
end
FSM.GetUnspentTalentPoints = GetUnspentTalentPointsCount

local function GetSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then return info.name end
        if type(info) == "string" then return info end
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

local function GetSpellRankText(spellID)
    if not spellID then return "" end
    if C_Spell and C_Spell.GetSpellSubtext then
        local sub = C_Spell.GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    if GetSpellSubtext then
        local sub = GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    return ""
end

local function GetSpellRankNumber(spellID)
    local subtext = GetSpellRankText(spellID)
    if subtext and subtext ~= "" then
        local num = subtext:match("(%d+)")
        if num then return tonumber(num) end
    end
    return 0
end

local function IsSpellPassive(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellPassive then
        return C_Spell.IsSpellPassive(spellID)
    end
    if IsPassiveSpell then
        return IsPassiveSpell(spellID)
    end
    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.IsSpellBookItemPassive then
        local slotIndex, bank = C_SpellBook.FindSpellBookSlotForSpell(spellID)
        if slotIndex and bank then
            return C_SpellBook.IsSpellBookItemPassive(slotIndex, bank)
        end
    end
    return false
end

local function GetItemName(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemInfo then
        local name = C_Item.GetItemInfo(itemID)
        if name then return name end
    end
    if GetItemInfo then
        return (GetItemInfo(itemID))
    end
    return nil
end

local function GetItemOnUseSpell(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemSpell then
        local spellName = C_Item.GetItemSpell(itemID)
        if spellName then return spellName end
    end
    if GetItemSpell then
        return GetItemSpell(itemID)
    end
    return nil
end

local function FormatCoin(copper)
    copper = tonumber(copper) or 0
    if copper == 0 then return "|cff00ff00Free|r" end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    elseif GetCoinTextureString then
        return GetCoinTextureString(copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    local str = ""
    if gold > 0 then
        str = str .. gold .. " |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t "
    end
    if silver > 0 then
        str = str .. silver .. " |TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t "
    end
    if cop > 0 or (gold == 0 and silver == 0) then
        str = str .. cop .. " |TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
    end
    return str
end
FSM.FormatCoin = FormatCoin

local function HasOnUseEffect(itemLink, equipSlot)
    local itemID = nil
    if itemLink then
        local id = itemLink:match("item:(%d+)")
        if id then itemID = tonumber(id) end
    end
    if not itemID and equipSlot then
        itemID = GetInventoryItemID("player", equipSlot)
    end
    if not itemID then return false end

    local spellName = GetItemOnUseSpell(itemID)
    if not spellName then return false end

    -- Verify active "Use:" effect in tooltip
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    if equipSlot and not itemLink then
        scanTooltip:SetInventoryItem("player", equipSlot)
    elseif itemLink then
        scanTooltip:SetHyperlink(itemLink)
    end

    local triggerPattern = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower():gsub("%%s", ""):gsub(":", "")
    for i = 1, scanTooltip:NumLines() do
        local line = _G["FSMCacheScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                local lowerText = text:lower()
                if lowerText:find("^use:") or lowerText:find(triggerPattern, 1, true) then
                    return true
                end
            end
        end
    end

    -- Trinket slots (13, 14) that have an associated spell are on-use
    if equipSlot and (equipSlot == 13 or equipSlot == 14) then
        return true
    end

    return false
end

----------------------------------------------------
-- New/Upgraded Skill Highlighting
----------------------------------------------------
local glowingSlots = {}

local function HighlightSlot(slot)
    if not slot then return end
    glowingSlots[slot] = true
    
    -- Attempt to find and glow the physical button for standard UI layouts
    local btn = nil
    if slot >= 1 and slot <= 12 then btn = _G["ActionButton" .. slot]
    elseif slot >= 25 and slot <= 36 then btn = _G["MultiBarRightButton" .. (slot - 24)]
    elseif slot >= 37 and slot <= 48 then btn = _G["MultiBarLeftButton" .. (slot - 36)]
    elseif slot >= 49 and slot <= 60 then btn = _G["MultiBarBottomRightButton" .. (slot - 48)]
    elseif slot >= 61 and slot <= 72 then btn = _G["MultiBarBottomLeftButton" .. (slot - 60)]
    end

    if btn and ActionButton_ShowOverlayGlow then
        ActionButton_ShowOverlayGlow(btn)
    end
end

local function ClearHighlight(slot)
    if not slot or not glowingSlots[slot] then return end
    glowingSlots[slot] = nil
    
    local btn = nil
    if slot >= 1 and slot <= 12 then btn = _G["ActionButton" .. slot]
    elseif slot >= 25 and slot <= 36 then btn = _G["MultiBarRightButton" .. (slot - 24)]
    elseif slot >= 37 and slot <= 48 then btn = _G["MultiBarLeftButton" .. (slot - 36)]
    elseif slot >= 49 and slot <= 60 then btn = _G["MultiBarBottomRightButton" .. (slot - 48)]
    elseif slot >= 61 and slot <= 72 then btn = _G["MultiBarBottomLeftButton" .. (slot - 60)]
    end

    if btn and ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(btn)
    end
end

-- Hook Tooltip to detect when the player mouses over ANY action button globally
if GameTooltip and GameTooltip.SetAction then
    hooksecurefunc(GameTooltip, "SetAction", function(self, slot)
        if slot and glowingSlots[slot] then
            ClearHighlight(slot)
        end
    end)
end

-- Re-apply glow when forms/stances page the main action bar
if ActionButton_Update then
    hooksecurefunc("ActionButton_Update", function(self)
        local slot = self.action
        if slot and glowingSlots[slot] and ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(self)
        end
    end)
end

----------------------------------------------------
-- Safe Cursor Action Placement & Empty Slot Lookup
----------------------------------------------------
local function SafePlaceSpell(spellID, slot)
    DebugPrint("SafePlaceSpell(" .. tostring(spellID) .. ", slot=" .. tostring(slot) .. ")")
    ClearCursor()

    -- Try 1: C_Spell.PickupSpell
    if C_Spell and C_Spell.PickupSpell then
        pcall(C_Spell.PickupSpell, spellID)
    end

    -- Try 2: Legacy PickupSpell by ID
    if GetCursorInfo() ~= "spell" and PickupSpell then
        pcall(PickupSpell, spellID)
    end

    -- Try 3: PickupSpell by Name (handles unsynced spellbook states)
    if GetCursorInfo() ~= "spell" and PickupSpell then
        local spName = GetSpellName(spellID)
        if spName then pcall(PickupSpell, spName) end
    end

    -- Try 4: C_SpellBook lookup
    if GetCursorInfo() ~= "spell" and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.PickupSpellBookItem then
        local slotIndex, bank = C_SpellBook.FindSpellBookSlotForSpell(spellID)
        if slotIndex and bank then
            pcall(C_SpellBook.PickupSpellBookItem, slotIndex, bank)
        end
    end

    -- Try 5: Legacy FindSpellBookSlotBySpellID
    if GetCursorInfo() ~= "spell" and FindSpellBookSlotBySpellID and PickupSpellBookItem then
        local bookSlot = FindSpellBookSlotBySpellID(spellID)
        if bookSlot then
            pcall(PickupSpellBookItem, bookSlot, "spell")
        end
    end

    -- Try 6: Manual spellbook scan by name
    if GetCursorInfo() ~= "spell" then
        local targetName = GetSpellName(spellID)
        if targetName then
            local playerBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
            local found = false

            if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
                local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
                for lineIndex = 1, numSkillLines do
                    local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
                    if lineInfo and not lineInfo.isGuild then
                        local offset = lineInfo.itemIndexOffset or 0
                        local numItems = lineInfo.numSpellBookItems or 0
                        for j = 1, numItems do
                            local slotIdx = offset + j
                            local bookName = nil
                            if C_SpellBook.GetSpellBookItemName then
                                bookName = C_SpellBook.GetSpellBookItemName(slotIdx, playerBank)
                            end
                            if not bookName and C_SpellBook.GetSpellBookItemInfo then
                                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, playerBank)
                                if itemInfo then
                                    local sID = itemInfo.spellID or itemInfo.actionID
                                    if sID then bookName = GetSpellName(sID) end
                                end
                            end
                            if bookName == targetName then
                                if C_SpellBook.PickupSpellBookItem then
                                    pcall(C_SpellBook.PickupSpellBookItem, slotIdx, playerBank)
                                elseif PickupSpellBookItem then
                                    pcall(PickupSpellBookItem, slotIdx, "spell")
                                end
                                found = true
                                break
                            end
                        end
                    end
                    if found then break end
                end
            end
        end
    end

    local cursorType = GetCursorInfo()
    if cursorType == "spell" then
        PlaceAction(slot)
        ClearCursor()

        -- Verify action placement
        local actionType, actionID = GetActionInfo(slot)
        if actionType == "spell" or HasAction(slot) then
            DebugPrint(" -> PlaceAction SUCCESS and verified for slot " .. tostring(slot))
            return true
        else
            if IsDebugMode() then
                print("|cffff6600[FSM DEBUG]|r  -> PlaceAction executed but slot " .. tostring(slot) .. " remained empty!")
            end
            return false
        end
    else
        ClearCursor()
        if IsDebugMode() then
            print("|cffff6600[FSM DEBUG]|r  -> FAILED to pick up spell, cursor was: " .. tostring(cursorType))
        end
        return false
    end
end

local function SafePlaceItem(itemID, slot)
    ClearCursor()
    if C_Item and C_Item.PickupItem then
        C_Item.PickupItem(itemID)
    elseif PickupItem then
        PickupItem(itemID)
    end

    local cursorType = GetCursorInfo()
    if cursorType == "item" then
        PlaceAction(slot)
        ClearCursor()
        return true
    else
        ClearCursor()
        return false
    end
end

local function FindFirstEmptySlot()
    -- 1. Check Currently Active Main Bar Page (handles active stance/form bar)
    local currentPage = GetActionBarPage and GetActionBarPage() or 1
    local mainBarStart = ((currentPage - 1) * 12) + 1
    local mainBarEnd = mainBarStart + 11

    for slot = mainBarStart, mainBarEnd do
        if not HasAction(slot) then
            return slot
        end
    end

    -- 2. If in a stance/form (currentPage > 1), also check Base Action Bar 1 (Slots 1 to 12)
    if currentPage ~= 1 then
        for slot = 1, 12 do
            if not HasAction(slot) then
                return slot
            end
        end
    end

    -- 3. Cycle through Action Bars 2, 3, 4, 5, 6 sequentially
    for _, range in ipairs(STANDARD_BAR_RANGES) do
        -- Skip range 13-24 if Page 2 is currently being forced as active
        if not (currentPage == 2 and range[1] == 13) then
            for slot = range[1], range[2] do
                if not HasAction(slot) then
                    return slot
                end
            end
        end
    end

    return nil
end

----------------------------------------------------
-- Trainer Caching & Verification
----------------------------------------------------
local function ParseRankNumber(rankStr)
    if type(rankStr) ~= "string" or rankStr == "" then return nil end
    local num = StripColorCodes(rankStr):match("[Rr]ank%s+(%d+)") or StripColorCodes(rankStr):match("^(%d+)$")
    return num and tonumber(num) or nil
end

local function IsSpellOrRankKnown(name, rank, spellID)
    local playerBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"

    if (not rank or rank == "") and spellID then
        rank = GetSpellRankText(spellID)
    end

    if spellID then
        if C_Spell and C_Spell.IsSpellKnownOrOverridesKnown and C_Spell.IsSpellKnownOrOverridesKnown(spellID) then return true end
        if C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(spellID) then return true end
        if IsSpellKnown and IsSpellKnown(spellID) then return true end
        if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
        if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
            if C_SpellBook.FindSpellBookSlotForSpell(spellID) then return true end
        end
    end

    local reqRankNum = ParseRankNumber(rank)

    local function CheckBookEntry(bookName, bookRank, bookSpellID)
        if bookSpellID and spellID and bookSpellID == spellID then
            return true
        end
        if not bookName or bookName ~= name then
            return false
        end
        local bookRankNum = ParseRankNumber(bookRank)
        if reqRankNum and bookRankNum then
            -- If the player already knows this rank or a higher rank, it's known/superseded
            return bookRankNum >= reqRankNum
        elseif not reqRankNum and not bookRankNum then
            -- If both have no rank text, only treat as same spell if they don't have conflicting spellIDs
            if spellID and bookSpellID and spellID ~= bookSpellID then
                return false
            end
            return (not rank or rank == "") and (not bookRank or bookRank == "")
        elseif rank and rank ~= "" and bookRank and bookRank == rank then
            return true
        end
        return false
    end

    if name then
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
            local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
            for lineIndex = 1, numSkillLines do
                local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
                if lineInfo and not lineInfo.isGuild then
                    local offset = lineInfo.itemIndexOffset or 0
                    local numItems = lineInfo.numSpellBookItems or 0
                    for j = 1, numItems do
                        local slotIndex = offset + j
                        local bookName, bookRank, sID
                        if C_SpellBook.GetSpellBookItemInfo then
                            local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, playerBank)
                            if itemInfo then
                                sID = itemInfo.spellID or itemInfo.actionID
                                bookName = itemInfo.name
                                bookRank = itemInfo.subName
                            end
                        end
                        if C_SpellBook.GetSpellBookItemName then
                            local n, r = C_SpellBook.GetSpellBookItemName(slotIndex, playerBank)
                            bookName = bookName or n
                            if not bookRank or bookRank == "" then bookRank = r end
                        end
                        if sID then
                            if not bookName then bookName = GetSpellName(sID) end
                            if not bookRank or bookRank == "" then bookRank = GetSpellRankText(sID) end
                        end

                        if CheckBookEntry(bookName, bookRank, sID) then
                            return true
                        end
                    end
                end
            end
        elseif GetNumSpellTabs and GetSpellTabInfo then
            local numTabs = GetNumSpellTabs() or 0
            for tabIndex = 1, numTabs do
                local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
                offset = offset or 0
                numSpells = numSpells or 0
                for j = 1, numSpells do
                    local slotIndex = offset + j
                    local bookName, bookRank, sID
                    if GetSpellBookItemName then
                        bookName, bookRank = GetSpellBookItemName(slotIndex, "spell")
                    end
                    if GetSpellBookItemInfo then
                        local _, id = GetSpellBookItemInfo(slotIndex, "spell")
                        sID = id
                    end
                    if CheckBookEntry(bookName, bookRank, sID) then
                        return true
                    end
                end
            end
        else
            local maxSpells = 250
            for slotIndex = 1, maxSpells do
                local bookName, bookRank
                if C_SpellBook and C_SpellBook.GetSpellBookItemName then
                    bookName, bookRank = C_SpellBook.GetSpellBookItemName(slotIndex, playerBank)
                elseif GetSpellBookItemName then
                    bookName, bookRank = GetSpellBookItemName(slotIndex, "spell")
                end
                if CheckBookEntry(bookName, bookRank, nil) then
                    return true
                end
            end
        end
    end

    return false
end

local function ExtractTrainerTooltipData(serviceIndex)
    local foundSpellID, foundRank, foundReqLevel = nil, nil, nil

    local function InspectText(rawText, isFirstLineRight)
        if type(rawText) ~= "string" or rawText == "" then return end
        local clean = StripColorCodes(rawText)
        if not foundRank or foundRank == "" then
            local rMatch = clean:match("^([Rr]ank%s+%d+)$") or (isFirstLineRight and clean:match("([Rr]ank%s+%d+)"))
            if rMatch then
                foundRank = rMatch:gsub("^r", "R")
            end
        end
        if not foundReqLevel or foundReqLevel <= 0 then
            local lMatch = clean:match("[Rr]equires%s+[Ll]evel%s+(%d+)") or clean:match("[Ll]evel%s+(%d+)%s+[Rr]equired")
            if lMatch then
                foundReqLevel = tonumber(lMatch)
            end
        end
    end

    -- 1. WoW Forever 16001 structured C_TooltipInfo scan
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, serviceIndex)
        if ok and data then
            if data.spellID then foundSpellID = data.spellID
            elseif data.id then foundSpellID = data.id end

            if type(data.lines) == "table" then
                for idx, line in ipairs(data.lines) do
                    InspectText(line.rightText, idx == 1)
                    InspectText(line.leftText, idx == 1)
                    if type(line.args) == "table" then
                        for _, arg in ipairs(line.args) do
                            if type(arg) == "table" and type(arg.stringVal) == "string" then
                                InspectText(arg.stringVal, idx == 1)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Fallback hidden GameTooltip scan (with strict nil checks on GetText)
    if (not foundReqLevel or foundReqLevel <= 0 or not foundRank or foundRank == "") and scanTooltip and scanTooltip.SetTrainerService then
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTooltip:ClearLines()
        local ok = pcall(scanTooltip.SetTrainerService, scanTooltip, serviceIndex)
        if ok then
            local numLines = scanTooltip:NumLines() or 0
            for lineIdx = 1, numLines do
                local rightLine = _G["FSMCacheScanTooltipTextRight" .. lineIdx]
                if rightLine and rightLine.GetText then
                    local rText = rightLine:GetText()
                    if rText then InspectText(rText, lineIdx == 1) end
                end
                local leftLine = _G["FSMCacheScanTooltipTextLeft" .. lineIdx]
                if leftLine and leftLine.GetText then
                    local lText = leftLine:GetText()
                    if lText then InspectText(lText, lineIdx == 1) end
                end
            end
        end
    end

    return foundSpellID, foundRank, foundReqLevel
end

local function CacheTrainerSpells()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    if C_Trainer and C_Trainer.IsTradeskillTrainer and C_Trainer.IsTradeskillTrainer() then return end

    local numServices = GetNumTrainerServices and GetNumTrainerServices() or 0
    if C_Trainer and C_Trainer.GetNumTrainerServices then 
        numServices = C_Trainer.GetNumTrainerServices() 
    end
    
    DebugPrint("CacheTrainerSpells triggered. Services found: " .. tostring(numServices))
    if numServices == 0 then return end

    local charKey = GetCharKey()
    ForeverSkillManagerDB.trainerCache = ForeverSkillManagerDB.trainerCache or {}
    ForeverSkillManagerDB.trainerCache[charKey] = ForeverSkillManagerDB.trainerCache[charKey] or {}
    local cache = ForeverSkillManagerDB.trainerCache[charKey]

    for i = 1, numServices do
        local name, rank, category, cost, reqLevel, spellID

        if C_Trainer and C_Trainer.GetTrainerServiceInfo then
            local info = C_Trainer.GetTrainerServiceInfo(i)
            if info then
                name, rank, cost, reqLevel, spellID = info.name, info.subText, info.moneyCost, info.reqLevel, info.spellID
                category = (info.serviceType == 2) and "used" or ((info.serviceType == 0) and "available" or "unavailable")
                if info.serviceType == 3 then category = "header" end
            end
        else
            name, rank, category = GetTrainerServiceInfo(i)
            cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            if GetTrainerServiceLevelReq then reqLevel = GetTrainerServiceLevelReq(i) end
        end

        -- Handle 16001 engine returning availability/header in the 2nd return value ('rank')
        if rank == "available" or rank == "unavailable" or rank == "used" or rank == "header" then
            category = rank
            rank = ""
        end

        if name and category ~= "header" then
            local tipSpellID, tipRank, tipReqLevel = ExtractTrainerTooltipData(i)
            if not spellID and tipSpellID then
                spellID = tipSpellID
            end
            if (not rank or rank == "") and tipRank and tipRank ~= "" then
                rank = tipRank
            end
            if (not rank or rank == "") and spellID then
                local sub = GetSpellRankText(spellID)
                if sub and sub ~= "" then rank = sub end
            end
            if (not reqLevel or tonumber(reqLevel) <= 0) and tipReqLevel and tipReqLevel > 0 then
                reqLevel = tipReqLevel
            end

            reqLevel = tonumber(reqLevel) or 1
            rank = rank or ""

            -- Purge any legacy duplicate keys that used the unstable trainer row index '_i' for this spell
            for existingKey, existingInfo in pairs(cache) do
                if type(existingInfo) == "table" and existingInfo.name == name then
                    if (existingInfo.rank or "") == rank and existingInfo.reqLevel == reqLevel and existingKey ~= spellID then
                        cache[existingKey] = nil
                    elseif (existingInfo.rank or "") == "" and rank ~= "" and existingInfo.reqLevel == reqLevel then
                        cache[existingKey] = nil
                    end
                end
            end

            -- Deterministic key by spellID or (name + rank + reqLevel)
            local serviceKey = spellID or (name .. "_" .. rank .. "_" .. reqLevel)
            local isKnown = (category == "used") or IsSpellOrRankKnown(name, rank, spellID)

            DebugPrint("Caching spell: " .. tostring(name) .. " | Rank: " .. tostring(rank) .. " | Level: " .. tostring(reqLevel) .. " | Known: " .. tostring(isKnown))

            cache[serviceKey] = {
                name = name,
                rank = rank,
                cost = cost or 0,
                reqLevel = reqLevel,
                spellID = spellID,
                known = isKnown
            }
        elseif name and category == "header" then
            -- Remove any accidentally cached header rows from older versions
            for existingKey, existingInfo in pairs(cache) do
                if type(existingInfo) == "table" and existingInfo.name == name and (existingInfo.cost or 0) == 0 and not existingInfo.spellID then
                    cache[existingKey] = nil
                end
            end
        end
    end

    if FSM.UpdateMinimapAlert then
        FSM.UpdateMinimapAlert()
    end
end

local function AutoTrainAvailableSpells()
    if not ForeverSkillManagerDB or not ForeverSkillManagerDB.autoTrainSpells then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    if C_Trainer and C_Trainer.IsTradeskillTrainer and C_Trainer.IsTradeskillTrainer() then return end
    if not BuyTrainerService then return end

    local numServices = GetNumTrainerServices and GetNumTrainerServices() or 0
    if C_Trainer and C_Trainer.GetNumTrainerServices then
        numServices = C_Trainer.GetNumTrainerServices()
    end
    if numServices == 0 then return end

    local trainedCount = 0
    for i = 1, numServices do
        local name, rank, category, cost
        if C_Trainer and C_Trainer.GetTrainerServiceInfo then
            local info = C_Trainer.GetTrainerServiceInfo(i)
            if info then
                name, rank, cost = info.name, info.subText, info.moneyCost
                category = (info.serviceType == 0) and "available" or "other"
            end
        else
            name, rank, category = GetTrainerServiceInfo(i)
            cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
        end

        if rank == "available" or rank == "unavailable" or rank == "used" or rank == "header" then
            category = rank
            rank = ""
        end

        if name and category == "available" then
            local money = GetMoney and GetMoney() or 0
            cost = tonumber(cost) or 0
            if money >= cost then
                BuyTrainerService(i)
                trainedCount = trainedCount + 1
            end
        end
    end

    if trainedCount > 0 then
        print("|cff00ff00[Forever Skill Manager]|r Auto-trained |cffffd100" .. trainedCount .. "|r available spell(s).")
    end
end

local function CheckAvailableTrainerSpells(overrideLevel)
    local playerLevel = tonumber(overrideLevel) or tonumber(UnitLevel("player")) or 1
    local available = {}
    local upcoming = {}
    local totalCost = 0
    local charKey = GetCharKey()

    if not ForeverSkillManagerDB or not ForeverSkillManagerDB.trainerCache or not ForeverSkillManagerDB.trainerCache[charKey] then
        return available, 0, upcoming
    end

    local cache = ForeverSkillManagerDB.trainerCache[charKey]
    for key, info in pairs(cache) do
        local rLvl = tonumber(info.reqLevel) or 1
        local actuallyKnown = IsSpellOrRankKnown(info.name, info.rank, info.spellID)

        -- Repair any higher-level spells that were falsely marked known by the old name-matching bug
        if info.known and not actuallyKnown and rLvl > playerLevel then
            info.known = false
        elseif actuallyKnown then
            info.known = true
        end

        if not info.known then
            if rLvl <= playerLevel then
                table.insert(available, {
                    key = key, name = info.name, rank = info.rank, 
                    cost = info.cost or 0, level = rLvl, spellID = info.spellID
                })
                totalCost = totalCost + (info.cost or 0)
            -- Upcoming spells strictly between (playerLevel + 1) and (playerLevel + 3)
            elseif rLvl > playerLevel and rLvl <= (playerLevel + 3) then
                table.insert(upcoming, {
                    key = key, name = info.name, rank = info.rank, 
                    cost = info.cost or 0, level = rLvl, spellID = info.spellID
                })
            end
        end
    end

    table.sort(available, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return (a.name or "") < (b.name or "")
    end)
    
    table.sort(upcoming, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return (a.name or "") < (b.name or "")
    end)

    return available, totalCost, upcoming
end
FSM.CheckAvailableTrainerSpells = CheckAvailableTrainerSpells


----------------------------------------------------
-- Trainer Popup / Reminder Window (Interactive & Modernized)
----------------------------------------------------
local popupFrame = CreateFrame("Frame", "FSMTrainerPopupFrame", UIParent, "BackdropTemplate,BasicFrameTemplateWithInset")
popupFrame:SetSize(480, 500)
popupFrame:SetPoint("CENTER")
popupFrame:SetMovable(true)
popupFrame:EnableMouse(true)
popupFrame:RegisterForDrag("LeftButton")
popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
popupFrame:SetFrameStrata("DIALOG")
popupFrame:Hide()

if popupFrame.TitleText then
    popupFrame.TitleText:SetText("Class Trainer Spells")
end

local scrollFrame = CreateFrame("ScrollFrame", "FSMTrainerScrollFrame", popupFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 16, -34)
scrollFrame:SetPoint("BOTTOMRIGHT", -36, 48)

local scrollContent = CreateFrame("Frame", "FSMTrainerScrollContent", scrollFrame)
scrollContent:SetSize(410, 10)
scrollFrame:SetScrollChild(scrollContent)

local popupCloseBtn = CreateFrame("Button", nil, popupFrame, "GameMenuButtonTemplate")
popupCloseBtn:SetPoint("BOTTOM", 0, 14)
popupCloseBtn:SetSize(120, 24)
popupCloseBtn:SetText("Dismiss")
popupCloseBtn:SetScript("OnClick", function() popupFrame:Hide() end)

local uiRows = {}
local dividerTextures = {}

local function GetSpellIcon(spellID)
    if not spellID then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
    if GetSpellTexture then return GetSpellTexture(spellID) end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetOrCreateDivider(index)
    if dividerTextures[index] then return dividerTextures[index] end
    local tex = scrollContent:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(1, 1, 1, 0.1)
    tex:SetSize(410, 1)
    dividerTextures[index] = tex
    return tex
end

local function GetOrCreateRow(index)
    if uiRows[index] then return uiRows[index] end
    
    local row = CreateFrame("Button", nil, scrollContent)
    row:SetSize(410, 36) -- Taller row for modern look
    
    -- Subtle dark background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.25)
    row.bg = bg
    
    -- Hover Highlight
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row:SetHighlightTexture(highlight)
    
    -- Icon with cropped edges for a borderless modern feel
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) 
    row.icon = icon
    
    -- Spell Name & Rank
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    text:SetJustifyH("LEFT")
    row.text = text
    
    -- Cost
    local cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cost:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    cost:SetJustifyH("RIGHT")
    row.cost = cost
    
    row:SetScript("OnEnter", function(self)
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        elseif self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 0.82, 0, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    uiRows[index] = row
    return row
end

local function OpenTrainerReminder(manual, overrideLevel)
    local playerLevel = tonumber(overrideLevel) or UnitLevel("player")
    local availableSpells, totalCost, upcomingSpells = CheckAvailableTrainerSpells(playerLevel)
    local unspentTalents = GetUnspentTalentPointsCount()
    local playerMoney = GetMoney and GetMoney() or 0

    if popupFrame.TitleText then
        popupFrame.TitleText:SetText("Trainer Spells - Level " .. playerLevel)
    end

    -- Hide all existing rows and dividers
    for _, row in ipairs(uiRows) do row:Hide() end
    for _, div in ipairs(dividerTextures) do div:Hide() end
    
    local yOffset = -5
    local rowIndex = 1
    local divIndex = 1
    
    local function AddTextRow(textStr, fontStr, color, height, xOffset)
        local row = GetOrCreateRow(rowIndex)
        row.spellID = nil
        row.tooltipText = nil
        row:SetScript("OnClick", nil)
        row.icon:Hide()
        row.bg:Hide()
        row.cost:SetText("")
        row.text:SetFontObject(fontStr or "GameFontHighlightSmall")
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", xOffset or 4, 0)
        row.text:SetText((color or "|cffffffff") .. textStr .. "|r")
        row:SetHeight(height or 24)
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        row:EnableMouse(false)
        row:Show()
        yOffset = yOffset - (height or 24) - 2
        rowIndex = rowIndex + 1
    end

    local function AddDivider()
        local div = GetOrCreateDivider(divIndex)
        div:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset - 4)
        div:Show()
        yOffset = yOffset - 12
        divIndex = divIndex + 1
    end

    local function AddTalentBannerRow(points)
        local row = GetOrCreateRow(rowIndex)
        row.spellID = nil
        row.tooltipText = "Click to open your Talents window."
        row.bg:SetColorTexture(0.25, 0.2, 0.02, 0.45)
        row.bg:Show()
        row.icon:SetTexture("Interface\\Icons\\Ability_Marksmanship")
        row.icon:Show()
        row:EnableMouse(true)
        row.text:SetFontObject("GameFontNormal")
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
        local plural = (points == 1) and "Point" or "Points"
        row.text:SetText("|cff00ff00Unspent Talent " .. plural .. ":|r |cffffd100" .. points .. "|r")
        row.cost:SetText("|cffaaaaaa(Click to Open)|r")
        row:SetScript("OnClick", function()
            if ToggleTalentFrame then
                pcall(ToggleTalentFrame)
            end
        end)
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        row:Show()
        yOffset = yOffset - 40
        rowIndex = rowIndex + 1
    end
    
    local function AddSpellRow(spell, isAvailableSection)
        local row = GetOrCreateRow(rowIndex)
        row.spellID = spell.spellID
        row.tooltipText = nil
        row:SetScript("OnClick", nil)
        row.bg:SetColorTexture(0, 0, 0, 0.25)
        row.bg:Show()
        row.icon:SetTexture(GetSpellIcon(spell.spellID))
        row.icon:Show()
        row:EnableMouse(true)
        row.text:SetFontObject("GameFontNormal")
        
        -- Explicitly format and show the rank
        local rankStr = (spell.rank and spell.rank ~= "") and (" (" .. spell.rank .. ")") or ""
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
        row.text:SetText("|cffffd100" .. spell.name .. "|r|cff888888" .. rankStr .. "|r")

        local spellCost = tonumber(spell.cost) or 0
        if isAvailableSection and spellCost > 0 and playerMoney < spellCost then
            row.cost:SetText("|cffff5555" .. FormatCoin(spellCost) .. "|r")
        else
            row.cost:SetText(FormatCoin(spellCost))
        end
        
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        row:Show()
        yOffset = yOffset - 38
        rowIndex = rowIndex + 1
    end

    if unspentTalents > 0 and (manual or not ForeverSkillManagerDB or ForeverSkillManagerDB.talentAlert) then
        AddTalentBannerRow(unspentTalents)
        AddDivider()
    end

    if #availableSpells == 0 then
        AddTextRow("No unlearned trainer spells available for your current level.", "GameFontHighlight", "|cffaaaaaa", 30)
    else
        AddTextRow("Available Spells (Level " .. playerLevel .. " & Below)", "GameFontNormalLarge", "|cff00ff00", 30)
        for _, spell in ipairs(availableSpells) do
            AddSpellRow(spell, true)
        end
        if totalCost > 0 and playerMoney < totalCost then
            local shortBy = totalCost - playerMoney
            AddTextRow("Total Available Cost: " .. FormatCoin(totalCost) .. "  |cffff5555(Short by " .. FormatCoin(shortBy) .. ")|r", "GameFontNormal", "|cffffff00", 24, 8)
        else
            AddTextRow("Total Available Cost: " .. FormatCoin(totalCost), "GameFontNormal", "|cffffff00", 24, 8)
        end
    end

    if upcomingSpells and #upcomingSpells > 0 then
        if #availableSpells > 0 then AddDivider() end
        yOffset = yOffset - 8
        AddTextRow("Upcoming Spells (Next 3 Levels)", "GameFontNormalLarge", "|cff00ccff", 30)
        
        local currentGroupLevel = -1
        local groupCost = 0
        
        for i, spell in ipairs(upcomingSpells) do
            if spell.level ~= currentGroupLevel then
                if currentGroupLevel ~= -1 then
                    AddTextRow("Total cost for Level " .. currentGroupLevel .. ": " .. FormatCoin(groupCost), "GameFontHighlightSmall", "|cffaaaaaa", 20, 8)
                    yOffset = yOffset - 8
                end
                currentGroupLevel = spell.level
                groupCost = 0
                AddTextRow("Level " .. currentGroupLevel .. ":", "GameFontNormal", "|cffffffff", 24, 4)
            end
            
            AddSpellRow(spell, false)
            groupCost = groupCost + (spell.cost or 0)
            
            if i == #upcomingSpells then
                AddTextRow("Total cost for Level " .. currentGroupLevel .. ": " .. FormatCoin(groupCost), "GameFontHighlightSmall", "|cffaaaaaa", 20, 8)
            end
        end
    elseif #availableSpells == 0 then
        AddTextRow("Visit your class trainer to discover and cache upcoming abilities!", "GameFontHighlightSmall", "|cffaaaaaa", 24)
    end

    scrollContent:SetHeight(math.abs(yOffset) + 20)
    popupFrame:Show()
end
FSM.OpenTrainerReminder = OpenTrainerReminder



----------------------------------------------------
-- Action Bar & Equipment Logic
----------------------------------------------------
local function ProcessLearnedSpell(spellID)
    DebugPrint("ProcessLearnedSpell called with spellID=" .. tostring(spellID))

    if InCombatLockdown() then
        DebugPrint(" -> BLOCKED: in combat lockdown, queuing spell")
        table.insert(pendingSpells, spellID)
        return
    end

    local isPassive = IsSpellPassive(spellID)
    DebugPrint(" -> IsSpellPassive = " .. tostring(isPassive))
    if isPassive then
        return
    end

    local spellName = GetSpellName(spellID)
    DebugPrint(" -> spellName = " .. tostring(spellName))
    if not spellName then return end

    DebugPrint(" -> autoAddSpells = " .. tostring(ForeverSkillManagerDB.autoAddSpells))
    DebugPrint(" -> autoUpgradeSpells = " .. tostring(ForeverSkillManagerDB.autoUpgradeSpells))

    -- Mark known in trainer cache (matching exact spellID or matching both spell name and rank)
    local charKey = GetCharKey()
    local learnedRank = GetSpellRankText(spellID)
    local learnedRankNum = ParseRankNumber(learnedRank)
    if ForeverSkillManagerDB.trainerCache and ForeverSkillManagerDB.trainerCache[charKey] then
        for key, info in pairs(ForeverSkillManagerDB.trainerCache[charKey]) do
            if info.spellID and info.spellID == spellID then
                info.known = true
            elseif info.name == spellName then
                local cachedRankNum = ParseRankNumber(info.rank)
                if learnedRankNum and cachedRankNum then
                    if learnedRankNum >= cachedRankNum then
                        info.known = true
                    end
                elseif not info.spellID and (info.rank or "") == (learnedRank or "") then
                    info.known = true
                end
            end
        end
    end
    if FSM.UpdateMinimapAlert then
        FSM.UpdateMinimapAlert()
    end

    -- Check if spell is already present across ALL Action Bars (Slots 1 to 120)
    local existingSlots = {}
    for slot = 1, 120 do
        local actionType, actionID = GetActionInfo(slot)
        if actionType == "spell" then
            local existingName = GetSpellName(actionID)
            if existingName == spellName then
                table.insert(existingSlots, { slot = slot, spellID = actionID, rank = GetSpellRankNumber(actionID) })
            end
        end
    end
    DebugPrint(" -> existingSlots count = " .. #existingSlots)

    -- 1. Upgrade existing spell on bar (preserves lower downranked ranks if multiple exist)
    if ForeverSkillManagerDB.autoUpgradeSpells and #existingSlots > 0 then
        local alreadyCurrent = false
        for _, entry in ipairs(existingSlots) do
            if entry.spellID == spellID then
                alreadyCurrent = true
                break
            end
        end

        if not alreadyCurrent then
            local highestRank = -1
            for _, entry in ipairs(existingSlots) do
                if entry.rank > highestRank then
                    highestRank = entry.rank
                end
            end

            local upgraded = false
            for _, entry in ipairs(existingSlots) do
                if entry.rank == highestRank or #existingSlots == 1 then
                    if SafePlaceSpell(spellID, entry.slot) then
                        upgraded = true
                        print("|cff00ff00[Forever Skill Manager]|r Upgraded spell |cffffd100" .. spellName .. "|r in slot " .. entry.slot .. ".")
                        HighlightSlot(entry.slot)
                    end
                end
            end
            if upgraded then return end
        else
            return
        end
    end

    -- 2. Place completely new spell into first open action bar slot across visible Bars
    if ForeverSkillManagerDB.autoAddSpells and #existingSlots == 0 then
        local emptySlot = FindFirstEmptySlot()
        DebugPrint(" -> NEW SPELL PATH: emptySlot = " .. tostring(emptySlot))
        if emptySlot then
            local placed = SafePlaceSpell(spellID, emptySlot)
            DebugPrint(" -> SafePlaceSpell result = " .. tostring(placed))
            if placed then
                print("|cff00ff00[Forever Skill Manager]|r Placed new spell |cffffd100" .. spellName .. "|r in empty slot " .. emptySlot .. ".")
                HighlightSlot(emptySlot)
            else
                if IsDebugMode() then
                    print("|cffff6600[FSM DEBUG]|r  -> SafePlaceSpell FAILED for spellID=" .. tostring(spellID) .. " slot=" .. tostring(emptySlot))
                end
            end
        else
            print("|cff00ff00[Forever Skill Manager]|r Action bars are full! Could not place new spell |cffffd100" .. spellName .. "|r.")
        end
    end
end

local function ProcessEquipmentChange(equipSlot)
    if InCombatLockdown() then
        table.insert(pendingEquipment, equipSlot)
        return
    end

    local oldItemID = currentEquippedItems[equipSlot]
    local newItemID = GetInventoryItemID("player", equipSlot)
    currentEquippedItems[equipSlot] = newItemID

    if not newItemID then return end

    local newItemLink = GetInventoryItemLink("player", equipSlot)
    if not HasOnUseEffect(newItemLink, equipSlot) then return end

    local itemName = GetItemName(newItemID) or "Item"
    local placed = false

    -- 1. Replace swapped on-use item in its original slot across ALL bars (Slots 1 to 120)
    if ForeverSkillManagerDB.autoUpgradeGear and oldItemID and oldItemID ~= newItemID then
        for slot = 1, 120 do
            local actionType, actionID = GetActionInfo(slot)
            if actionType == "item" and actionID == oldItemID then
                if SafePlaceItem(newItemID, slot) then
                    placed = true
                    print("|cff00ff00[Forever Skill Manager]|r Replaced gear with |cffffd100" .. itemName .. "|r in slot " .. slot .. ".")
                    HighlightSlot(slot)
                    break
                end
            end
        end
    end

    -- 2. Verify if item is already present on ALL action bars (Slots 1 to 120)
    if not placed then
        for slot = 1, 120 do
            local actionType, actionID = GetActionInfo(slot)
            if actionType == "item" and actionID == newItemID then
                placed = true
                break
            end
        end
    end

    -- 3. Place new on-use gear into first open action slot
    if ForeverSkillManagerDB.autoAddGear and not placed then
        local emptySlot = FindFirstEmptySlot()
        if emptySlot then
            if SafePlaceItem(newItemID, emptySlot) then
                print("|cff00ff00[Forever Skill Manager]|r Placed on-use item |cffffd100" .. itemName .. "|r in empty slot " .. emptySlot .. ".")
                HighlightSlot(emptySlot)
            end
        else
            print("|cff00ff00[Forever Skill Manager]|r Action bars are full! Could not place on-use item |cffffd100" .. itemName .. "|r.")
        end
    end
end

local function CacheEquippedItems()
    if not GetInventoryItemID then return end
    for slot = 1, 19 do
        currentEquippedItems[slot] = GetInventoryItemID("player", slot)
    end
end

local function ScanAndAddEquippedGear()
    if InCombatLockdown() then
        print("|cff00ff00[Forever Skill Manager]|r Cannot scan gear while in combat.")
        return
    end

    local count = 0
    for slot = 1, 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            currentEquippedItems[slot] = itemID
            local itemLink = GetInventoryItemLink("player", slot)
            if HasOnUseEffect(itemLink, slot) then
                local alreadyOnBar = false
                for barSlot = 1, 120 do
                    local actionType, actionID = GetActionInfo(barSlot)
                    if actionType == "item" and actionID == itemID then
                        alreadyOnBar = true
                        break
                    end
                end

                if not alreadyOnBar then
                    local emptySlot = FindFirstEmptySlot()
                    if emptySlot then
                        if SafePlaceItem(itemID, emptySlot) then
                            local itemName = GetItemName(itemID) or "Item"
                            count = count + 1
                            print("|cff00ff00[Forever Skill Manager]|r Placed on-use item |cffffd100" .. itemName .. "|r in slot " .. emptySlot .. ".")
                            HighlightSlot(emptySlot)
                        end
                    else
                        print("|cff00ff00[Forever Skill Manager]|r Action bars are full!")
                        break
                    end
                end
            end
        end
    end

    if count == 0 then
        print("|cff00ff00[Forever Skill Manager]|r All equipped on-use items are already placed on your action bars.")
    end
end
FSM.ScanAndAddEquippedGear = ScanAndAddEquippedGear

----------------------------------------------------
-- Spellbook Snapshot for SPELLS_CHANGED fallback
----------------------------------------------------
local knownSpellIDs = {}
local spellbookInitialized = false

local function SnapshotSpellbook()
    local snapshot = {}
    local playerBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for lineIndex = 1, numSkillLines do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
            if lineInfo and not lineInfo.isGuild then
                local offset = lineInfo.itemIndexOffset or 0
                local numItems = lineInfo.numSpellBookItems or 0
                for j = 1, numItems do
                    local slotIndex = offset + j
                    local sID = nil
                    if C_SpellBook.GetSpellBookItemInfo then
                        local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, playerBank)
                        if itemInfo then
                            sID = itemInfo.spellID or itemInfo.actionID
                        end
                    end
                    if sID then
                        snapshot[sID] = true
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo then
        local numTabs = GetNumSpellTabs() or 0
        for tabIndex = 1, numTabs do
            local _, _, tabOffset, numSpells = GetSpellTabInfo(tabIndex)
            tabOffset = tabOffset or 0
            numSpells = numSpells or 0
            for j = 1, numSpells do
                local slotIndex = tabOffset + j
                local sID = nil
                if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, playerBank)
                    if itemInfo then
                        sID = itemInfo.spellID or itemInfo.actionID
                    end
                end
                if sID then
                    snapshot[sID] = true
                end
            end
        end
    end

    return snapshot
end

----------------------------------------------------
-- Event Handlers hooked into FSM.Events
----------------------------------------------------
FSM.Events = FSM.Events or {}

local function NotifyUnspentTalents()
    if not ForeverSkillManagerDB or not ForeverSkillManagerDB.talentAlert then return end
    local unspent = GetUnspentTalentPointsCount()
    if unspent > 0 then
        local plural = (unspent == 1) and "talent point" or "talent points"
        print("|cff00ff00[Forever Skill Manager]|r You have |cffffd100" .. unspent .. " unspent " .. plural .. "|r! Don't forget to spend them.")
    end
end

local prevLogin = FSM.Events["PLAYER_LOGIN"]
FSM.Events["PLAYER_LOGIN"] = function(self, ...)
    if prevLogin then prevLogin(self, ...) end
    CacheEquippedItems()
    knownSpellIDs = SnapshotSpellbook()
    spellbookInitialized = true
    local count = 0
    for _ in pairs(knownSpellIDs) do count = count + 1 end
    DebugPrint("Spellbook snapshot initialized with " .. count .. " spells")

    -- Check for unlearned trainer spells and unspent talent points on login/reload
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            if FSM.UpdateMinimapAlert then
                FSM.UpdateMinimapAlert()
            end
            NotifyUnspentTalents()
            if ForeverSkillManagerDB and ForeverSkillManagerDB.trainerAlert then
                local playerLevel = UnitLevel("player")
                if FSM.CheckAvailableTrainerSpells then
                    local availableSpells = FSM.CheckAvailableTrainerSpells(playerLevel)
                    if #availableSpells > 0 and FSM.OpenTrainerReminder then
                        FSM.OpenTrainerReminder(false, playerLevel)
                    end
                end
            end
        end)
    end
end

FSM.Events["TRAINER_SHOW"] = function(self)
    CacheTrainerSpells()
    AutoTrainAvailableSpells()
end

FSM.Events["TRAINER_UPDATE"] = function(self)
    CacheTrainerSpells()
end

FSM.Events["CHARACTER_POINTS_CHANGED"] = function(self)
    if FSM.UpdateMinimapAlert then
        FSM.UpdateMinimapAlert()
    end
    if popupFrame and popupFrame:IsShown() and FSM.OpenTrainerReminder then
        FSM.OpenTrainerReminder(true)
    end
end

FSM.Events["PLAYER_MONEY"] = function(self)
    if popupFrame and popupFrame:IsShown() and FSM.OpenTrainerReminder then
        FSM.OpenTrainerReminder(true)
    end
end

FSM.Events["PLAYER_LEVEL_UP"] = function(self, newLevel)
    if not ForeverSkillManagerDB then return end
    
    local level = tonumber(newLevel) or UnitLevel("player")
    
    local function HandleLevelUpChecks()
        if FSM.UpdateMinimapAlert then
            FSM.UpdateMinimapAlert()
        end
        NotifyUnspentTalents()
        if ForeverSkillManagerDB.trainerAlert and FSM.CheckAvailableTrainerSpells then
            local availableSpells = FSM.CheckAvailableTrainerSpells(level)
            -- Only pop the window open if there are spells available to train at this level
            if #availableSpells > 0 and FSM.OpenTrainerReminder then
                FSM.OpenTrainerReminder(false, level)
            end
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(1.0, HandleLevelUpChecks)
    else
        HandleLevelUpChecks()
    end
end

FSM.Events["LEARNED_SPELL_IN_TAB"] = function(self, spellID, ...)
    DebugPrint("LEARNED_SPELL_IN_TAB fired! spellID=" .. tostring(spellID))
    if spellID and type(spellID) == "number" and spellID > 0 then
        ProcessLearnedSpell(spellID)
    end
end

FSM.Events["LEARNED_SPELL_IN_SKILL_LINE"] = function(self, spellID, ...)
    DebugPrint("LEARNED_SPELL_IN_SKILL_LINE fired! spellID=" .. tostring(spellID))
    if spellID and type(spellID) == "number" and spellID > 0 then
        ProcessLearnedSpell(spellID)
    end
end

local spellsChangedThrottle = 0
FSM.Events["SPELLS_CHANGED"] = function(self)
    if not spellbookInitialized then return end

    local now = GetTime()
    if now - spellsChangedThrottle < 0.5 then return end
    spellsChangedThrottle = now

    local newSnapshot = SnapshotSpellbook()
    local newSpellIDs = {}
    for sID in pairs(newSnapshot) do
        if not knownSpellIDs[sID] then
            table.insert(newSpellIDs, sID)
        end
    end

    if #newSpellIDs > 0 then
        DebugPrint("SPELLS_CHANGED detected " .. #newSpellIDs .. " new spell(s)")
        for _, sID in ipairs(newSpellIDs) do
            local nm = GetSpellName(sID)
            DebugPrint(" -> New spell from SPELLS_CHANGED: " .. tostring(nm) .. " (ID=" .. sID .. ")")
            ProcessLearnedSpell(sID)
        end
    end

    knownSpellIDs = newSnapshot
end

FSM.Events["PLAYER_EQUIPMENT_CHANGED"] = function(self, equipSlot)
    ProcessEquipmentChange(equipSlot)
end

FSM.Events["PLAYER_REGEN_ENABLED"] = function(self)
    if #pendingSpells > 0 then
        for _, spellID in ipairs(pendingSpells) do
            ProcessLearnedSpell(spellID)
        end
        pendingSpells = {}
    end

    if #pendingEquipment > 0 then
        for _, equipSlot in ipairs(pendingEquipment) do
            ProcessEquipmentChange(equipSlot)
        end
        pendingEquipment = {}
    end
end

print("|cff00ff00Forever Skill Manager v1.4.1|r loaded. Type |cffffff00/fsm|r for options.")