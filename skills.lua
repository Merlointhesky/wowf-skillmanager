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
local IsSecret = FSM.IsSecret or function(v)
    if v == nil then return false end
    local issecret = rawget(_G, "issecretvalue") or issecretvalue
    if issecret and issecret(v) then return true end
    local issectbl = rawget(_G, "issecrettable") or issecrettable
    if issectbl and issectbl(v) then return true end
    local canaccess = rawget(_G, "canaccessvalue") or canaccessvalue
    if canaccess and not canaccess(v) then return true end
    local ok = pcall(function() return v == "" end)
    if not ok then return true end
    return false
end

local SafeString = FSM.SafeString or function(v)
    if v == nil or IsSecret(v) then return nil end
    local ok, res = pcall(function()
        if type(v) == "string" and v ~= "" then
            return v
        end
        return nil
    end)
    return ok and res or nil
end

local SafeGetText = FSM.SafeGetText or function(fontString)
    if not fontString or not fontString.GetText then return nil end
    local ok, text = pcall(fontString.GetText, fontString)
    if not ok or not text then return nil end
    return SafeString(text)
end

local function StripColorCodes(text)
    text = SafeString(text)
    if not text then return "" end
    local ok, clean = pcall(function()
        return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end)
    return ok and clean or ""
end

local function GetCharKey()
    local name, arg2 = UnitName("player")
    name = SafeString(name) or "Player"
    local realm = SafeString(GetRealmName()) or "Realm"

    -- WoW Forever 1.6 supports character last names via UnitName 2nd return or UnitLastName
    local lastName = nil
    local safeArg2 = SafeString(arg2)
    if safeArg2 and safeArg2 ~= realm then
        lastName = safeArg2
    end
    if not lastName and UnitLastName then
        local last = SafeString(UnitLastName("player"))
        if last then
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
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            if type(info) == "table" and not IsSecret(info) then
                local name = SafeString(info.name)
                if name then return name end
            elseif type(info) == "string" then
                local name = SafeString(info)
                if name then return name end
            end
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name then
            return SafeString(name)
        end
    end
    return nil
end

local function GetSpellRankText(spellID)
    if not spellID then return "" end
    if C_Spell and C_Spell.GetSpellSubtext then
        local ok, sub = pcall(C_Spell.GetSpellSubtext, spellID)
        if ok then
            local s = SafeString(sub)
            if s then return s end
        end
    end
    if GetSpellSubtext then
        local ok, sub = pcall(GetSpellSubtext, spellID)
        if ok then
            local s = SafeString(sub)
            if s then return s end
        end
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
    local numLines = 0
    local okNum, n = pcall(scanTooltip.NumLines, scanTooltip)
    if okNum and type(n) == "number" and not IsSecret(n) then
        numLines = n
    end
    for i = 1, numLines do
        local line = _G["FSMCacheScanTooltipTextLeft" .. i]
        local text = SafeGetText(line)
        if text then
            local lowerText = text:lower()
            if lowerText:find("^use:") or lowerText:find(triggerPattern, 1, true) then
                return true
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

    -- Fast O(1) check: if this exact spellID is in our spellbook snapshot, it's definitely known
    if spellID and knownSpellIDs and knownSpellIDs[spellID] then
        return true
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
                        local isFuture = false
                        if C_SpellBook.GetSpellBookItemInfo then
                            local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, playerBank)
                            if itemInfo then
                                if itemInfo.itemType and Enum and Enum.SpellBookItemType and itemInfo.itemType == Enum.SpellBookItemType.FutureSpell then
                                    isFuture = true
                                else
                                    sID = itemInfo.spellID or itemInfo.actionID
                                    bookName = itemInfo.name
                                    bookRank = itemInfo.subName
                                end
                            end
                        end
                        if not isFuture then
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
                    local isFuture = false
                    if GetSpellBookItemInfo then
                        local itemType, id = GetSpellBookItemInfo(slotIndex, "spell")
                        if itemType == "FUTURESPELL" then
                            isFuture = true
                        else
                            sID = id
                        end
                    end
                    if not isFuture then
                        if GetSpellBookItemName then
                            bookName, bookRank = GetSpellBookItemName(slotIndex, "spell")
                        end
                        if CheckBookEntry(bookName, bookRank, sID) then
                            return true
                        end
                    end
                end
            end
        else
            local maxSpells = 250
            for slotIndex = 1, maxSpells do
                local bookName, bookRank, isFuture
                if GetSpellBookItemInfo then
                    local itemType = GetSpellBookItemInfo(slotIndex, "spell")
                    if itemType == "FUTURESPELL" then isFuture = true end
                end
                if not isFuture then
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
    end

    return false
end

local function ExtractTrainerTooltipData(serviceIndex)
    local foundSpellID, foundRank, foundReqLevel, foundClasses = nil, nil, nil, nil

    local function InspectText(rawText, isFirstLineRight)
        rawText = SafeString(rawText)
        if not rawText then return end
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
        if not foundClasses then
            local cMatch = clean:match("^[Cc]lasses:%s*(.+)$") or clean:match("^[Cc]lass:%s*(.+)$")
            if cMatch then
                foundClasses = cMatch
            end
        end
    end

    -- 1. WoW Forever 16001 structured C_TooltipInfo scan
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, serviceIndex)
        if ok and type(data) == "table" and not IsSecret(data) then
            if data.spellID and not IsSecret(data.spellID) then foundSpellID = data.spellID
            elseif data.id and not IsSecret(data.id) then foundSpellID = data.id end

            if type(data.lines) == "table" and not IsSecret(data.lines) then
                for idx, line in ipairs(data.lines) do
                    if type(line) == "table" and not IsSecret(line) then
                        InspectText(line.rightText, idx == 1)
                        InspectText(line.leftText, idx == 1)
                        if type(line.args) == "table" and not IsSecret(line.args) then
                            for _, arg in ipairs(line.args) do
                                if type(arg) == "table" and not IsSecret(arg) and type(arg.stringVal) == "string" then
                                    InspectText(arg.stringVal, idx == 1)
                                end
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
            local numLines = 0
            local okNum, n = pcall(scanTooltip.NumLines, scanTooltip)
            if okNum and type(n) == "number" and not IsSecret(n) then
                numLines = n
            end
            for lineIdx = 1, numLines do
                local rightLine = _G["FSMCacheScanTooltipTextRight" .. lineIdx]
                local rText = SafeGetText(rightLine)
                if rText then InspectText(rText, lineIdx == 1) end

                local leftLine = _G["FSMCacheScanTooltipTextLeft" .. lineIdx]
                local lText = SafeGetText(leftLine)
                if lText then InspectText(lText, lineIdx == 1) end
            end
        end
    end

    return foundSpellID, foundRank, foundReqLevel, foundClasses
end

----------------------------------------------------
-- Allowed Trainer & Skill Classification Filters
----------------------------------------------------
local WEAPON_SKILLS = {
    ["One-Handed Axes"] = true,
    ["Two-Handed Axes"] = true,
    ["One-Handed Maces"] = true,
    ["Two-Handed Maces"] = true,
    ["One-Handed Swords"] = true,
    ["Two-Handed Swords"] = true,
    ["Daggers"] = true,
    ["Staves"] = true,
    ["Polearms"] = true,
    ["Fist Weapons"] = true,
    ["Bows"] = true,
    ["Crossbows"] = true,
    ["Guns"] = true,
    ["Thrown"] = true,
}

local BEAST_TRAINING_UNIQUE_SKILLS = {
    ["Great Stamina"] = true,
    ["Natural Armor"] = true,
    ["Arcane Resistance"] = true,
    ["Fire Resistance"] = true,
    ["Frost Resistance"] = true,
    ["Nature Resistance"] = true,
    ["Shadow Resistance"] = true,
    ["Dive"] = true,
    ["Furious Howl"] = true,
    ["Lightning Breath"] = true,
    ["Shell Shield"] = true,
    ["Scorpid Poison"] = true,
    ["Screech"] = true,
    ["Thunderstomp"] = true,
    ["Bite"] = true,
    ["Prowl"] = true,
    ["Warp"] = true,
    ["Gore"] = true,
    ["Poison Spit"] = true,
    ["Fire Breath"] = true,
    ["Lava Breath"] = true,
    ["Demoralizing Screech"] = true,
    ["Swoop"] = true,
    ["Tendon Rip"] = true,
}

local isBeastTrainingWindowActive = false

local function IsBeastTrainingWindowOpen()
    if isBeastTrainingWindowActive then
        return true
    end
    if CraftIsPetTraining and CraftIsPetTraining() then
        return true
    end
    if GetCraftSkillLine then
        local line = GetCraftSkillLine()
        if line and (line == "Beast Training" or tostring(line):find("Beast Training")) then
            return true
        end
    end
    if CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown() then
        local title = SafeGetText(CraftFrameTitleText)
        if title and (title == "Beast Training" or title:find("Beast Training")) then
            return true
        end
    end
    if BeastTrainingFrame and BeastTrainingFrame.IsShown and BeastTrainingFrame:IsShown() then
        return true
    end
    if PetTrainingFrame and PetTrainingFrame.IsShown and PetTrainingFrame:IsShown() then
        return true
    end
    return false
end

local function IsBeastTrainingSkill(name)
    name = SafeString(name)
    if not name then return false end
    name = StripColorCodes(name):match("^%s*(.-)%s*$") or name
    local _, playerClass = UnitClass("player")
    playerClass = playerClass or "UNKNOWN"

    -- Unique pet abilities from the Beast Training window (never valid player class skills)
    if BEAST_TRAINING_UNIQUE_SKILLS[name] then
        return true
    end

    -- Abilities shared by name with player spells in other classes:
    -- For Hunters, these belong exclusively to the pet Beast Training window
    if playerClass == "HUNTER" then
        if name == "Growl" or name == "Cower" or name == "Dash" or name == "Claw" or name == "Charge" then
            return true
        end
    end

    return false
end

local function IsRidingSkill(name)
    name = SafeString(name)
    if not name then return false end
    if name:find("Riding") or name:find("Piloting") or name:find("Cold Weather Flying") then
        return true
    end
    return false
end

----------------------------------------------------
-- Talent Spell Identification & Caching
----------------------------------------------------
local KNOWN_TALENT_ABILITIES = {
    -- Druid
    ["Feral Charge"] = true,
    ["Feral Charge - Bear"] = true,
    ["Feral Charge - Cat"] = true,
    ["Insect Swarm"] = true,
    ["Nature's Swiftness"] = true,
    ["Swiftmend"] = true,
    ["Faerie Fire (Feral)"] = true,

    -- Hunter
    ["Aimed Shot"] = true,
    ["Scatter Shot"] = true,
    ["Bestial Wrath"] = true,
    ["Wyvern Sting"] = true,
    ["Intimidation"] = true,
    ["Trueshot Aura"] = true,
    ["Counterattack"] = true,
    ["Readiness"] = true,
    ["Silencing Shot"] = true,
    ["Chimera Shot"] = true,
    ["Kill Shot"] = true,
    ["Explosive Shot"] = true,
    ["Black Arrow"] = true,

    -- Mage
    ["Pyroblast"] = true,
    ["Blast Wave"] = true,
    ["Combustion"] = true,
    ["Arcane Power"] = true,
    ["Ice Barrier"] = true,
    ["Cold Snap"] = true,
    ["Presence of Mind"] = true,
    ["Dragon's Breath"] = true,
    ["Living Bomb"] = true,
    ["Deep Freeze"] = true,
    ["Arcane Barrage"] = true,
    ["Slow"] = true,

    -- Paladin
    ["Holy Shock"] = true,
    ["Repentance"] = true,
    ["Seal of Command"] = true,
    ["Blessing of Kings"] = true,
    ["Blessing of Sanctuary"] = true,
    ["Consecration"] = true,
    ["Holy Shield"] = true,
    ["Crusader Strike"] = true,
    ["Divine Storm"] = true,
    ["Avenger's Shield"] = true,
    ["Hammer of the Righteous"] = true,
    ["Shield of the Righteous"] = true,

    -- Priest
    ["Holy Nova"] = true,
    ["Desperate Prayer"] = true,
    ["Inner Focus"] = true,
    ["Power Infusion"] = true,
    ["Silence"] = true,
    ["Vampiric Embrace"] = true,
    ["Shadowform"] = true,
    ["Lightwell"] = true,
    ["Mind Flay"] = true,
    ["Penance"] = true,
    ["Circle of Healing"] = true,
    ["Pain Suppression"] = true,
    ["Dispersion"] = true,
    ["Psychic Horror"] = true,
    ["Vampiric Touch"] = true,

    -- Rogue
    ["Ghostly Strike"] = true,
    ["Riposte"] = true,
    ["Blade Flurry"] = true,
    ["Adrenaline Rush"] = true,
    ["Cold Blood"] = true,
    ["Preparation"] = true,
    ["Hemorrhage"] = true,
    ["Premeditation"] = true,
    ["Shadowstep"] = true,
    ["Mutilate"] = true,
    ["Killing Spree"] = true,
    ["Shadow Dance"] = true,

    -- Shaman
    ["Elemental Mastery"] = true,
    ["Mana Tide Totem"] = true,
    ["Stormstrike"] = true,
    ["Nature's Swiftness"] = true,
    ["Lava Lash"] = true,
    ["Thunderstorm"] = true,
    ["Riptide"] = true,
    ["Feral Spirit"] = true,

    -- Warlock
    ["Shadowburn"] = true,
    ["Conflagrate"] = true,
    ["Siphon Life"] = true,
    ["Soul Link"] = true,
    ["Dark Pact"] = true,
    ["Demonic Sacrifice"] = true,
    ["Amplify Curse"] = true,
    ["Unstable Affliction"] = true,
    ["Haunt"] = true,
    ["Metamorphosis"] = true,
    ["Chaos Bolt"] = true,
    ["Shadowfury"] = true,

    -- Warrior
    ["Sweeping Strikes"] = true,
    ["Death Wish"] = true,
    ["Bloodthirst"] = true,
    ["Piercing Howl"] = true,
    ["Concussion Blow"] = true,
    ["Shield Slam"] = true,
    ["Last Stand"] = true,
    ["Mortal Strike"] = true,
    ["Bladestorm"] = true,
    ["Shockwave"] = true,
    ["Devastate"] = true,
}

local talentCache = {}

local function RefreshTalentCache()
    talentCache = {}

    -- 1. Scan modern C_Traits API (Dragonflight / War Within / 11+ client)
    if C_Traits and C_Traits.GetConfigsByType then
        for cfgType = 0, 3 do
            local ok, configIDs = pcall(C_Traits.GetConfigsByType, cfgType)
            if ok and type(configIDs) == "table" then
                for _, configID in ipairs(configIDs) do
                    local okConf, configInfo = pcall(C_Traits.GetConfigInfo, configID)
                    if okConf and configInfo and configInfo.treeIDs then
                        for _, treeID in ipairs(configInfo.treeIDs) do
                            local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
                            if okNodes and type(nodeIDs) == "table" then
                                for _, nodeID in ipairs(nodeIDs) do
                                    local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                                    if okNode and nodeInfo and nodeInfo.entryIDs then
                                        for _, entryID in ipairs(nodeInfo.entryIDs) do
                                            local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                                            if okEntry and entryInfo and entryInfo.definitionID then
                                                local okDef, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                                                if okDef and defInfo and defInfo.spellID then
                                                    talentCache[defInfo.spellID] = true
                                                    local sn = GetSpellName(defInfo.spellID)
                                                    if sn then
                                                        talentCache[sn] = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Scan classic talent tabs (GetNumTalentTabs, GetNumTalents, GetTalentInfo)
    if GetNumTalentTabs and GetTalentInfo then
        local okTabs, numTabs = pcall(GetNumTalentTabs)
        if okTabs and numTabs and numTabs > 0 then
            for tab = 1, numTabs do
                local numTalents = GetNumTalents and GetNumTalents(tab) or 40
                for i = 1, numTalents do
                    local okTalent, tName = pcall(GetTalentInfo, tab, i)
                    if okTalent and tName and type(tName) == "string" and tName ~= "" then
                        talentCache[tName] = true
                    end
                    if GetTalentSpell then
                        local okSpell, tSpellID = pcall(GetTalentSpell, tab, i)
                        if okSpell and tSpellID and type(tSpellID) == "number" then
                            talentCache[tSpellID] = true
                        end
                    end
                end
            end
        end
    end

    -- 3. Scan tiered talent grid (GetMaxTalentTier, GetTalentInfo)
    if GetMaxTalentTier and GetTalentInfo then
        local okTier, maxTier = pcall(GetMaxTalentTier)
        if okTier and maxTier and maxTier > 0 then
            for tier = 1, maxTier do
                for col = 1, 4 do
                    local okT, tID, tName = pcall(GetTalentInfo, tier, col, 1)
                    if okT then
                        if tID and type(tID) == "number" then talentCache[tID] = true end
                        if tName and type(tName) == "string" and tName ~= "" then talentCache[tName] = true end
                    end
                end
            end
        end
    end

    -- 4. Scan C_SpecializationInfo PvP talent queries if present
    if C_SpecializationInfo and C_SpecializationInfo.GetPvpTalentInfo then
        for slotIndex = 1, 3 do
            local okSlot, slotInfo = pcall(C_SpecializationInfo.GetPvpTalentSlotInfo, slotIndex)
            if okSlot and slotInfo and slotInfo.selectedTalentID then
                local okInfo, tInfo = pcall(C_SpecializationInfo.GetPvpTalentInfo, slotInfo.selectedTalentID)
                if okInfo and tInfo and tInfo.spellID then
                    talentCache[tInfo.spellID] = true
                    if tInfo.name then talentCache[tInfo.name] = true end
                end
            end
        end
    end
end
FSM.RefreshTalentCache = RefreshTalentCache

local function IsTalentSpell(spellID, spellName)
    if not spellName and spellID then
        spellName = GetSpellName(spellID)
    end
    local cleanName = spellName and StripColorCodes(spellName):match("^%s*(.-)%s*$") or spellName

    -- 1. Static known talent abilities lookup
    if cleanName and KNOWN_TALENT_ABILITIES[cleanName] then
        return true
    end

    -- 2. Dynamic talent cache (spellID and name)
    if spellID and talentCache[spellID] then
        return true
    end
    if cleanName and talentCache[cleanName] then
        return true
    end

    -- 3. Modern C_Spell API
    if C_Spell then
        if C_Spell.IsClassTalentSpell then
            if spellID then
                local ok, isTalent = pcall(C_Spell.IsClassTalentSpell, spellID)
                if ok and isTalent then return true end
            end
            if cleanName then
                local ok, isTalent = pcall(C_Spell.IsClassTalentSpell, cleanName)
                if ok and isTalent then return true end
            end
        end
        if C_Spell.IsPvPTalentSpell then
            if spellID then
                local ok, isPvP = pcall(C_Spell.IsPvPTalentSpell, spellID)
                if ok and isPvP then return true end
            end
            if cleanName then
                local ok, isPvP = pcall(C_Spell.IsPvPTalentSpell, cleanName)
                if ok and isPvP then return true end
            end
        end
    end

    -- 4. Modern C_SpellBook API
    if C_SpellBook and spellID and C_SpellBook.FindSpellBookSlotForSpell then
        local okFind, slotIndex, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID)
        if okFind and slotIndex then
            if C_SpellBook.IsClassTalentSpellBookItem then
                local ok, isTalent = pcall(C_SpellBook.IsClassTalentSpellBookItem, slotIndex, bank or "spell")
                if ok and isTalent then return true end
                local ok2, isTalent2 = pcall(C_SpellBook.IsClassTalentSpellBookItem, slotIndex)
                if ok2 and isTalent2 then return true end
            end
            if C_SpellBook.IsPvPTalentSpellBookItem then
                local ok, isPvP = pcall(C_SpellBook.IsPvPTalentSpellBookItem, slotIndex, bank or "spell")
                if ok and isPvP then return true end
                local ok2, isPvP2 = pcall(C_SpellBook.IsPvPTalentSpellBookItem, slotIndex)
                if ok2 and isPvP2 then return true end
            end
        end
    end

    return false
end
FSM.IsTalentSpell = IsTalentSpell

local function GetTrainerNPCTitle()
    local unit = (UnitExists("npc") and "npc") or (UnitExists("target") and "target") or nil
    if not unit then return nil end

    -- Try C_TooltipInfo first if available
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local okData, data = pcall(C_TooltipInfo.GetUnit, unit)
        if okData and type(data) == "table" and not IsSecret(data) and type(data.lines) == "table" and not IsSecret(data.lines) then
            for i = 2, math.min(#data.lines, 5) do
                local lineData = data.lines[i]
                if type(lineData) == "table" and not IsSecret(lineData) then
                    local text = SafeString(lineData.leftText)
                    if text then
                        local clean = StripColorCodes(text):match("^%s*(.-)%s*$")
                        if clean and clean ~= "" then
                            local title = clean:match("^<(.+)>$") or clean:match("<(.+)>")
                            if title then return title end
                            if i == 2 and not clean:find("^Level") and not clean:find("^Requires") and not clean:find("Player") and not clean:find("Elite") and not clean:find("Boss") then
                                return clean
                            end
                        end
                    end
                end
            end
        end
    end

    if scanTooltip and scanTooltip.SetUnit then
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTooltip:ClearLines()
        local ok = pcall(scanTooltip.SetUnit, scanTooltip, unit)
        if ok then
            local numLines = 0
            local okNum, n = pcall(scanTooltip.NumLines, scanTooltip)
            if okNum and type(n) == "number" and not IsSecret(n) then
                numLines = n
            end
            for i = 2, math.min(numLines, 5) do
                local line = _G["FSMCacheScanTooltipTextLeft" .. i]
                local text = SafeGetText(line)
                if text then
                    local clean = StripColorCodes(text):match("^%s*(.-)%s*$")
                    if clean and clean ~= "" then
                        local title = clean:match("^<(.+)>$") or clean:match("<(.+)>")
                        if title then return title end
                        if i == 2 and not clean:find("^Level") and not clean:find("^Requires") and not clean:find("Player") and not clean:find("Elite") and not clean:find("Boss") then
                            return clean
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function IsTrainerNPCAllowed()
    if IsBeastTrainingWindowOpen() then return false end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    if C_Trainer and C_Trainer.IsTradeskillTrainer and C_Trainer.IsTradeskillTrainer() then return false end

    local _, playerClass = UnitClass("player")
    playerClass = playerClass or "UNKNOWN"

    local title = SafeString(GetTrainerNPCTitle())
    if not title then
        return true -- Fallback to service-level filtering
    end

    local lower = title:lower()

    -- 1. Weapon Masters / Weapon Trainers (always blocked)
    if lower:find("weapon") then
        DebugPrint("Blocked trainer NPC: Weapon Master (" .. title .. ")")
        return false
    end

    -- 2. Riding Trainers (always blocked)
    if lower:find("riding") or lower:find("mount") then
        DebugPrint("Blocked trainer NPC: Riding Trainer (" .. title .. ")")
        return false
    end

    -- 3. Hunter Pet Trainers / Beast Trainers (always blocked - skills belong to Beast Training window)
    if lower:find("pet trainer") or lower:find("beast trainer") or lower:find("pet training") or lower:find("beast training") then
        DebugPrint("Blocked trainer NPC: Pet / Beast Trainer (" .. title .. ")")
        return false
    end

    -- 4. Warlock Demon Trainers (only allowed for Warlocks)
    if lower:find("demon trainer") then
        if playerClass == "WARLOCK" then
            return true
        else
            DebugPrint("Blocked demon trainer NPC for non-warlock (" .. title .. ")")
            return false
        end
    end

    -- 5. Mage Portal Trainers (only allowed for Mages)
    if lower:find("portal") then
        if playerClass == "MAGE" then
            return true
        else
            DebugPrint("Blocked portal trainer NPC for non-mage (" .. title .. ")")
            return false
        end
    end

    -- 6. Specific Class Trainers
    local classTokens = {
        WARRIOR = "warrior",
        PALADIN = "paladin",
        HUNTER  = "hunter",
        ROGUE   = "rogue",
        PRIEST  = "priest",
        SHAMAN  = "shaman",
        MAGE    = "mage",
        WARLOCK = "warlock",
        DRUID   = "druid",
    }

    for cls, token in pairs(classTokens) do
        if lower:find(token) then
            if playerClass == cls then
                return true
            else
                DebugPrint("Blocked foreign class trainer NPC (" .. title .. ", player is " .. tostring(playerClass) .. ")")
                return false
            end
        end
    end

    return true
end

local function IsTrainerSpellAllowed(name, rank, spellID, reqLevel, reqClasses)
    name = SafeString(name)
    if not name then return false end
    reqClasses = SafeString(reqClasses)
    local localizedClass, playerClass = UnitClass("player")
    playerClass = playerClass or "UNKNOWN"
    localizedClass = localizedClass or ""

    -- 1. Always reject Weapon Master proficiencies
    if WEAPON_SKILLS[name] then
        return false
    end

    -- 2. Always reject Riding Trainer skills
    if IsRidingSkill(name) then
        return false
    end

    -- 3. Portal / Teleport skills: only allowed for Mages
    if name:find("^Teleport:") or name:find("^Portal:") then
        return (playerClass == "MAGE")
    end

    -- 4. Warlock Demon Grimoires / Pet Books: only allowed for Warlocks
    if name:find("^Grimoire of ") then
        return (playerClass == "WARLOCK")
    end

    -- 5. Beast Training skills (always ignored for Hunters; unique pet skills ignored for all classes)
    if IsBeastTrainingSkill(name) then
        return false
    end

    -- 6. If tooltip explicitly specifies class restrictions, verify player's class is allowed
    if reqClasses and reqClasses ~= "" then
        local lowerReq = reqClasses:lower()
        local lowerEng = playerClass:lower()
        local lowerLoc = localizedClass:lower()
        if not lowerReq:find(lowerEng, 1, true) and not lowerReq:find(lowerLoc, 1, true) then
            return false
        end
    end

    return true
end

local function CleanTrainerCache(charKey)
    if not ForeverSkillManagerDB or not ForeverSkillManagerDB.trainerCache then return end

    local function CleanSingleCache(cache, keyName)
        if type(cache) ~= "table" then return end
        local purgedCount = 0

        -- 1. Purge disallowed, invalid, or status-keyword corrupted entries (e.g. rank="unavailable" or key="...unavailable")
        for key, info in pairs(cache) do
            local shouldPurge = false
            if type(info) ~= "table" then
                shouldPurge = true
            elseif not IsTrainerSpellAllowed(info.name, info.rank, info.spellID, info.reqLevel, info.reqClasses) then
                shouldPurge = true
            else
                local rClean = tostring(info.rank or ""):lower():gsub("%s+", "")
                if rClean == "unavailable" or rClean == "available" or rClean == "used" or rClean == "header" then
                    shouldPurge = true
                elseif type(key) == "string" and (key:find("unavailable$") or key:find("available$") or key:find("used$") or key:find("header$")) then
                    shouldPurge = true
                end
            end

            if shouldPurge then
                cache[key] = nil
                purgedCount = purgedCount + 1
            end
        end

        -- 2. Purge any duplicate non-numeric string keys if a numeric spellID key exists for the same spell
        for key, info in pairs(cache) do
            if type(info) == "table" and type(key) ~= "number" and info.spellID and cache[info.spellID] then
                cache[key] = nil
                purgedCount = purgedCount + 1
            end
        end

        if purgedCount > 0 then
            DebugPrint("CleanTrainerCache: Purged " .. purgedCount .. " invalid/stale entries from cache for " .. tostring(keyName))
        end
    end

    if charKey then
        CleanSingleCache(ForeverSkillManagerDB.trainerCache[charKey], charKey)
    else
        for k, cache in pairs(ForeverSkillManagerDB.trainerCache) do
            CleanSingleCache(cache, k)
        end
    end
end
FSM.CleanTrainerCache = CleanTrainerCache

local function CacheTrainerSpells()
    if IsBeastTrainingWindowOpen() then return end
    if not IsTrainerNPCAllowed() then return end

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
            if info and not IsSecret(info) then
                name = SafeString(info.name)
                rank = SafeString(info.subText) or ""
                cost = (not IsSecret(info.moneyCost) and tonumber(info.moneyCost)) or 0
                reqLevel = (not IsSecret(info.reqLevel) and tonumber(info.reqLevel)) or 0
                spellID = (not IsSecret(info.spellID) and info.spellID) or nil
                category = (info.serviceType == 2) and "used" or ((info.serviceType == 0) and "available" or "unavailable")
                if info.serviceType == 3 then category = "header" end
            end
        else
            local rawName, rawRank, rawCat = GetTrainerServiceInfo(i)
            name = SafeString(rawName)
            rank = SafeString(rawRank) or ""
            category = SafeString(rawCat) or ""
            cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            if GetTrainerServiceLevelReq then reqLevel = GetTrainerServiceLevelReq(i) end
        end

        -- Handle 16001 engine returning availability/header in the 2nd return value ('rank')
        local rClean = tostring(rank or ""):lower():gsub("%s+", "")
        if rClean == "available" or rClean == "unavailable" or rClean == "used" or rClean == "header" then
            category = rClean
            rank = ""
        end

        if name and category ~= "header" then
            local tipSpellID, tipRank, tipReqLevel, tipClasses = ExtractTrainerTooltipData(i)
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

            -- Check if this service is an allowed spell (Class skill, Hunter pet skill, Warlock grimoire, Mage portal)
            if not IsTrainerSpellAllowed(name, rank, spellID, reqLevel, tipClasses) then
                -- Purge any previously cached entries for this disallowed spell
                for existingKey, existingInfo in pairs(cache) do
                    if type(existingInfo) == "table" and existingInfo.name == name then
                        cache[existingKey] = nil
                    end
                end
            else
                -- Purge any legacy duplicate keys that used the unstable trainer row index '_i' or invalid ranks
                for existingKey, existingInfo in pairs(cache) do
                    if type(existingInfo) == "table" and existingInfo.name == name then
                        local exRank = tostring(existingInfo.rank or ""):lower():gsub("%s+", "")
                        if exRank == "unavailable" or exRank == "available" or exRank == "used" or exRank == "header" then
                            cache[existingKey] = nil
                        elseif (existingInfo.rank or "") == rank and existingInfo.reqLevel == reqLevel and existingKey ~= spellID then
                            cache[existingKey] = nil
                        elseif (existingInfo.rank or "") == "" and rank ~= "" and existingInfo.reqLevel == reqLevel then
                            cache[existingKey] = nil
                        end
                    end
                end

                -- Deterministic key by spellID or (name + rank + reqLevel)
                local serviceKey = spellID or (name .. "_" .. rank .. "_" .. reqLevel)
                local isKnown = false
                if category == "used" then
                    isKnown = true
                elseif category == "available" or category == "unavailable" then
                    isKnown = false
                else
                    isKnown = IsSpellOrRankKnown(name, rank, spellID)
                end

                DebugPrint("Caching spell: " .. tostring(name) .. " | Rank: " .. tostring(rank) .. " | Level: " .. tostring(reqLevel) .. " | Known: " .. tostring(isKnown))

                cache[serviceKey] = {
                    name = name,
                    rank = rank,
                    cost = cost or 0,
                    reqLevel = reqLevel,
                    spellID = spellID,
                    reqClasses = tipClasses,
                    known = isKnown
                }
            end
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
    if IsBeastTrainingWindowOpen() then return end
    if not IsTrainerNPCAllowed() then return end
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
            if info and not IsSecret(info) then
                name = SafeString(info.name)
                rank = SafeString(info.subText) or ""
                cost = (not IsSecret(info.moneyCost) and tonumber(info.moneyCost)) or 0
                category = (info.serviceType == 0) and "available" or "other"
            end
        else
            local rawName, rawRank, rawCat = GetTrainerServiceInfo(i)
            name = SafeString(rawName)
            rank = SafeString(rawRank) or ""
            category = SafeString(rawCat) or ""
            cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
        end

        local rClean = tostring(rank or ""):lower():gsub("%s+", "")
        if rClean == "available" or rClean == "unavailable" or rClean == "used" or rClean == "header" then
            category = rClean
            rank = ""
        end

        if name and category == "available" and IsTrainerSpellAllowed(name) then
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

    CleanTrainerCache(charKey)

    local cache = ForeverSkillManagerDB.trainerCache[charKey]
    local seenAvailable = {}
    local seenUpcoming = {}

    for key, info in pairs(cache) do
        local rClean = tostring(info.rank or ""):lower():gsub("%s+", "")
        local isInvalidRank = (rClean == "unavailable" or rClean == "available" or rClean == "used" or rClean == "header")
        local isInvalidKey = type(key) == "string" and (key:find("unavailable$") or key:find("available$") or key:find("used$") or key:find("header$"))

        -- Purge any disallowed / non-class spells or status-corrupted legacy entries
        if isInvalidRank or isInvalidKey or not IsTrainerSpellAllowed(info.name, info.rank, info.spellID, info.reqLevel, info.reqClasses) then
            cache[key] = nil
        else
            local rLvl = tonumber(info.reqLevel) or 1
            local actuallyKnown = IsSpellOrRankKnown(info.name, info.rank, info.spellID)

            -- Keep known status strictly in sync with the player's actual spellbook
            info.known = actuallyKnown

            if not info.known then
                local dedupKey = (info.spellID and tostring(info.spellID)) or (info.name .. "_" .. (info.rank or "") .. "_" .. rLvl)
                if rLvl <= playerLevel then
                    if not seenAvailable[dedupKey] then
                        seenAvailable[dedupKey] = true
                        table.insert(available, {
                            key = key, name = info.name, rank = info.rank, 
                            cost = info.cost or 0, level = rLvl, spellID = info.spellID
                        })
                        totalCost = totalCost + (info.cost or 0)
                    end
                -- Upcoming spells strictly between (playerLevel + 1) and (playerLevel + 3)
                elseif rLvl > playerLevel and rLvl <= (playerLevel + 3) then
                    if not seenUpcoming[dedupKey] then
                        seenUpcoming[dedupKey] = true
                        table.insert(upcoming, {
                            key = key, name = info.name, rank = info.rank, 
                            cost = info.cost or 0, level = rLvl, spellID = info.spellID
                        })
                    end
                end
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
        
        -- Explicitly format and show the rank (guard against any status keyword leaking into rank text)
        local rankStr = ""
        local rClean = tostring(spell.rank or ""):lower():gsub("%s+", "")
        if spell.rank and spell.rank ~= "" and rClean ~= "unavailable" and rClean ~= "available" and rClean ~= "used" and rClean ~= "header" then
            rankStr = " (" .. spell.rank .. ")"
        end
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

    if IsBeastTrainingWindowOpen() then
        DebugPrint(" -> BLOCKED: Beast Training window is open")
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

    if IsBeastTrainingSkill(spellName) then
        DebugPrint(" -> BLOCKED: ignoring skill from Beast Training window (" .. spellName .. ")")
        return
    end

    DebugPrint(" -> autoAddSpells = " .. tostring(ForeverSkillManagerDB.autoAddSpells))
    DebugPrint(" -> autoUpgradeSpells = " .. tostring(ForeverSkillManagerDB.autoUpgradeSpells))

    local isTalent = IsTalentSpell(spellID, spellName)
    DebugPrint(" -> isTalent = " .. tostring(isTalent))

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
        if isTalent and not ForeverSkillManagerDB.autoAddTalentSpells then
            DebugPrint(" -> BLOCKED: ignoring talent ability from action bar placement (" .. tostring(spellName) .. ")")
            return
        end

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
                            local isFuture = (itemInfo.itemType and Enum and Enum.SpellBookItemType and itemInfo.itemType == Enum.SpellBookItemType.FutureSpell)
                            if not isFuture then
                                sID = itemInfo.spellID or itemInfo.actionID
                            end
                        end
                    end
                    if sID then
                        local sName = GetSpellName(sID)
                        if not IsBeastTrainingSkill(sName) then
                            snapshot[sID] = true
                        end
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
                local isFuture = false
                if GetSpellBookItemInfo then
                    local itemType, id = GetSpellBookItemInfo(slotIndex, "spell")
                    if itemType == "FUTURESPELL" then
                        isFuture = true
                    else
                        sID = id
                    end
                end
                if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and not isFuture then
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, playerBank)
                    if itemInfo then
                        if itemInfo.itemType and Enum and Enum.SpellBookItemType and itemInfo.itemType == Enum.SpellBookItemType.FutureSpell then
                            isFuture = true
                            sID = nil
                        else
                            sID = itemInfo.spellID or itemInfo.actionID or sID
                        end
                    end
                end
                if sID and not isFuture then
                    local sName = GetSpellName(sID)
                    if not IsBeastTrainingSkill(sName) then
                        snapshot[sID] = true
                    end
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
    CleanTrainerCache()
    CacheEquippedItems()
    RefreshTalentCache()
    knownSpellIDs = SnapshotSpellbook()
    if talentCache then
        for id in pairs(talentCache) do
            if type(id) == "number" then
                knownSpellIDs[id] = true
            end
        end
    end
    spellbookInitialized = true
    local count = 0
    for _ in pairs(knownSpellIDs) do count = count + 1 end
    DebugPrint("Spellbook snapshot initialized with " .. count .. " spells")

    -- Check for unlearned trainer spells and unspent talent points on login/reload
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            CleanTrainerCache()
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
    if popupFrame and popupFrame:IsShown() and FSM.OpenTrainerReminder then
        FSM.OpenTrainerReminder(true)
    end
end

FSM.Events["TRAINER_UPDATE"] = function(self)
    CacheTrainerSpells()
    if popupFrame and popupFrame:IsShown() and FSM.OpenTrainerReminder then
        FSM.OpenTrainerReminder(true)
    end
end

FSM.Events["CHARACTER_POINTS_CHANGED"] = function(self)
    RefreshTalentCache()
    if talentCache then
        for id in pairs(talentCache) do
            if type(id) == "number" then
                knownSpellIDs[id] = true
            end
        end
    end
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
        knownSpellIDs[spellID] = true
        ProcessLearnedSpell(spellID)
    end
end

FSM.Events["LEARNED_SPELL_IN_SKILL_LINE"] = function(self, spellID, ...)
    DebugPrint("LEARNED_SPELL_IN_SKILL_LINE fired! spellID=" .. tostring(spellID))
    if spellID and type(spellID) == "number" and spellID > 0 then
        knownSpellIDs[spellID] = true
        ProcessLearnedSpell(spellID)
    end
end

FSM.Events["CRAFT_SHOW"] = function(self)
    if (CraftIsPetTraining and CraftIsPetTraining()) or (GetCraftSkillLine and (GetCraftSkillLine() == "Beast Training" or tostring(GetCraftSkillLine()):find("Beast Training"))) then
        isBeastTrainingWindowActive = true
        DebugPrint("Beast Training window opened (CRAFT_SHOW)")
    end
end

FSM.Events["CRAFT_CLOSE"] = function(self)
    if isBeastTrainingWindowActive then
        isBeastTrainingWindowActive = false
        DebugPrint("Beast Training window closed (CRAFT_CLOSE)")
    end
end

local spellsChangedThrottle = 0
FSM.Events["SPELLS_CHANGED"] = function(self)
    if not spellbookInitialized then return end
    if IsBeastTrainingWindowOpen() then
        DebugPrint("SPELLS_CHANGED ignored: Beast Training window is open")
        return
    end

    local now = GetTime()
    if now - spellsChangedThrottle < 0.5 then return end
    spellsChangedThrottle = now

    local newSnapshot = SnapshotSpellbook()
    local newSpellIDs = {}
    for sID in pairs(newSnapshot) do
        if not knownSpellIDs[sID] then
            table.insert(newSpellIDs, sID)
            knownSpellIDs[sID] = true
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

    -- Retain all previously known spells across shapeshifts, stances, and form switches
    for sID in pairs(newSnapshot) do
        knownSpellIDs[sID] = true
    end
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