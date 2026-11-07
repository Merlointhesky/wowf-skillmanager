-- options.lua for ForeverSkillManager (following ForeverNPCAssistant architecture)
local addonName, FSM = ...

local defaults = {
    autoAddSpells = true,     -- Toggle for placing NEW spells in free slots
    autoUpgradeSpells = true, -- Toggle for upgrading existing spell ranks on bar
    autoAddGear = true,       -- Toggle for placing NEW on-use gear in free slots
    autoUpgradeGear = true,   -- Toggle for replacing swapped on-use gear on bar
    trainerAlert = true,      -- Toggle for popup reminder on level up
    talentAlert = true,       -- Toggle for unspent talent points reminder on login/level up
    autoTrainSpells = false,  -- Toggle for auto-learning available spells at class trainer
    debugMode = false,        -- Toggle for debug chat logging
    minimapPos = 180,         -- Angle position around minimap (West / 9 o'clock)
    trainerCache = {},        -- Cached trainer spells: [charKey] = { [key] = {...} }
}

local configFrame = CreateFrame("Frame", "ForeverSkillManagerOptionsPanel", UIParent, "BackdropTemplate,BasicFrameTemplateWithInset")
configFrame:SetSize(320, 346)
configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", configFrame.StartMoving)
configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
configFrame:SetFrameStrata("DIALOG")
configFrame:Hide()

if configFrame.TitleText then
    configFrame.TitleText:SetText("Forever Skill Manager")
end

local function ToggleOptions()
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        if FSM.RefreshOptionCheckboxes then
            FSM.RefreshOptionCheckboxes()
        end
        configFrame:Show()
    end
end
FSM.ToggleOptions = ToggleOptions

local optionCheckButtons = {}

function FSM.RefreshOptionCheckboxes()
    if not ForeverSkillManagerDB then return end
    for key, cb in pairs(optionCheckButtons) do
        cb:SetChecked(ForeverSkillManagerDB[key] and true or false)
    end
end

local function InitOptionsPanel()
    local function createCheck(label, settingKey, yOffset)
        local cb = CreateFrame("CheckButton", "ForeverSkillManagerCheck_" .. settingKey, configFrame, "InterfaceOptionsCheckButtonTemplate")
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, yOffset)

        local cbName = (cb.GetName and cb:GetName()) or ("ForeverSkillManagerCheck_" .. settingKey)
        local text = cb.Text or _G[cbName .. "Text"]
        if text and text.SetText then text:SetText(label) end

        cb:SetChecked(ForeverSkillManagerDB[settingKey])
        cb:SetScript("OnClick", function(self)
            ForeverSkillManagerDB[settingKey] = self:GetChecked() and true or false
            if FSM.UpdateMinimapAlert then
                FSM.UpdateMinimapAlert()
            end
        end)
        optionCheckButtons[settingKey] = cb
    end

    createCheck("Auto-add new spells to action bar", "autoAddSpells", -40)
    createCheck("Auto-upgrade spell ranks in place", "autoUpgradeSpells", -68)
    createCheck("Auto-add equipped 'Use' gear & trinkets", "autoAddGear", -96)
    createCheck("Auto-update swapped 'Use' gear on bar", "autoUpgradeGear", -124)
    createCheck("Trainer level-up reminder popup", "trainerAlert", -152)
    createCheck("Unspent talent points reminder", "talentAlert", -180)
    createCheck("Auto-learn spells at class trainer", "autoTrainSpells", -208)

    local viewTrainerBtn = CreateFrame("Button", nil, configFrame, "GameMenuButtonTemplate")
    viewTrainerBtn:SetPoint("BOTTOMLEFT", 20, 48)
    viewTrainerBtn:SetSize(135, 24)
    viewTrainerBtn:SetText("Trainer Spells")
    viewTrainerBtn:SetScript("OnClick", function()
        if FSM.OpenTrainerReminder then
            FSM.OpenTrainerReminder(true)
        end
    end)

    local scanGearBtn = CreateFrame("Button", nil, configFrame, "GameMenuButtonTemplate")
    scanGearBtn:SetPoint("BOTTOMRIGHT", -20, 48)
    scanGearBtn:SetSize(135, 24)
    scanGearBtn:SetText("Scan Gear")
    scanGearBtn:SetScript("OnClick", function()
        if FSM.ScanAndAddEquippedGear then
            FSM.ScanAndAddEquippedGear()
        end
    end)

    local resetCacheBtn = CreateFrame("Button", nil, configFrame, "GameMenuButtonTemplate")
    resetCacheBtn:SetPoint("BOTTOMLEFT", 20, 16)
    resetCacheBtn:SetSize(135, 24)
    resetCacheBtn:SetText("Clear Cache")
    resetCacheBtn:SetScript("OnClick", function()
        local charKey = FSM.GetCharKey and FSM.GetCharKey() or "Player"
        if ForeverSkillManagerDB.trainerCache and ForeverSkillManagerDB.trainerCache[charKey] then
            ForeverSkillManagerDB.trainerCache[charKey] = {}
            print("|cff00ff00[Forever Skill Manager]|r Cleared trainer cache for " .. charKey .. ".")
            if FSM.UpdateMinimapAlert then
                FSM.UpdateMinimapAlert()
            end
        end
    end)

    local closeBtn = CreateFrame("Button", nil, configFrame, "GameMenuButtonTemplate")
    closeBtn:SetPoint("BOTTOMRIGHT", -20, 16)
    closeBtn:SetSize(135, 24)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        configFrame:Hide()
    end)
end

local function UpdateMinimapButtonPosition(button, angle)
    local width = (Minimap and Minimap:GetWidth()) or 140
    if width == 0 then width = 140 end
    local radius = (width / 2) + 12
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap or UIParent, "CENTER", x, y)
end

local minimapButton = nil

local function UpdateMinimapAlert()
    if not minimapButton or not minimapButton.alertBadge then return end
    local showAlert = false
    if ForeverSkillManagerDB then
        if ForeverSkillManagerDB.trainerAlert and FSM.CheckAvailableTrainerSpells then
            local availableSpells = FSM.CheckAvailableTrainerSpells()
            if availableSpells and #availableSpells > 0 then
                showAlert = true
            end
        end
        if not showAlert and ForeverSkillManagerDB.talentAlert and FSM.GetUnspentTalentPoints then
            local unspent = FSM.GetUnspentTalentPoints()
            if unspent and unspent > 0 then
                showAlert = true
            end
        end
    end
    if showAlert then
        minimapButton.alertBadge:Show()
    else
        minimapButton.alertBadge:Hide()
    end
end
FSM.UpdateMinimapAlert = UpdateMinimapAlert

local function CreateMinimapButton()
    if not Minimap or minimapButton then return end

    local button = CreateFrame("Button", "ForeverSkillManagerMiniMapButton", Minimap)
    minimapButton = button
    button:SetSize(33, 33)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(10)

    -- Inner Icon (Official Blizzard Dimensions matching ForeverNPCAssistant)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

    -- Circular Tracking Border Overlay (Official Blizzard Dimensions)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Notification Badge (! indicator when trainer spells or talent points are available)
    local alertBadge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alertBadge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 2)
    alertBadge:SetText("|cff00ff00!|r")
    alertBadge:Hide()
    button.alertBadge = alertBadge

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    UpdateMinimapButtonPosition(button, ForeverSkillManagerDB.minimapPos or 180)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            ForeverSkillManagerDB.minimapPos = angle
            UpdateMinimapButtonPosition(self, angle)
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() self.isDragging = false end)
        else
            self.isDragging = false
        end
    end)

    button:SetScript("OnMouseUp", function(self, btn)
        if not self.isDragging then
            if btn == "LeftButton" then
                ToggleOptions()
            elseif btn == "RightButton" then
                if FSM.OpenTrainerReminder then
                    FSM.OpenTrainerReminder(true)
                end
            end
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Skill Manager", 1, 1, 1)
        if ForeverSkillManagerDB then
            GameTooltip:AddDoubleLine("Auto-Add Spells:", ForeverSkillManagerDB.autoAddSpells and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Auto-Upgrade Spells:", ForeverSkillManagerDB.autoUpgradeSpells and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Auto-Add 'Use' Gear:", ForeverSkillManagerDB.autoAddGear and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Auto-Update Swapped Gear:", ForeverSkillManagerDB.autoUpgradeGear and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Trainer Reminder Alert:", ForeverSkillManagerDB.trainerAlert and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Talent Reminder Alert:", ForeverSkillManagerDB.talentAlert and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
            GameTooltip:AddDoubleLine("Auto-Train at Trainer:", ForeverSkillManagerDB.autoTrainSpells and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")

            local addedAlertHeader = false
            if FSM.GetUnspentTalentPoints then
                local unspent = FSM.GetUnspentTalentPoints()
                if unspent and unspent > 0 then
                    GameTooltip:AddLine(" ")
                    addedAlertHeader = true
                    GameTooltip:AddLine("|cff00ff00Unspent Talent Points:|r |cffffd100" .. unspent .. "|r", 0.8, 0.8, 0.8)
                end
            end

            if FSM.CheckAvailableTrainerSpells and FSM.FormatCoin then
                local availableSpells, totalCost = FSM.CheckAvailableTrainerSpells()
                if #availableSpells > 0 then
                    if not addedAlertHeader then
                        GameTooltip:AddLine(" ")
                    end
                    local money = GetMoney and GetMoney() or 0
                    local costColor = (money >= totalCost) and "|cff00ff00" or "|cffff5555"
                    GameTooltip:AddLine("|cffffff00Available Trainer Spells:|r " .. #availableSpells .. " (" .. costColor .. FSM.FormatCoin(totalCost) .. "|r)", 0.8, 0.8, 0.8)
                end
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to open options.", 0.2, 1, 0.2, true)
        GameTooltip:AddLine("Right-click to view trainer spells.", 1, 0.8, 0, true)
        GameTooltip:AddLine("Drag to position around minimap.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:Show()
end
FSM.CreateMinimapButton = CreateMinimapButton

FSM.Events = FSM.Events or {}

FSM.Events["ADDON_LOADED"] = function(self, loadedAddon)
    if loadedAddon == addonName or loadedAddon == "ForeverSkillManager" then
        if type(ForeverSkillManagerDB) ~= "table" then
            ForeverSkillManagerDB = {}
        end

        -- Legacy flat key migration
        if ForeverSkillManagerDB.autoAdd ~= nil then
            if ForeverSkillManagerDB.autoAddSpells == nil then ForeverSkillManagerDB.autoAddSpells = ForeverSkillManagerDB.autoAdd end
            if ForeverSkillManagerDB.autoAddGear == nil then ForeverSkillManagerDB.autoAddGear = ForeverSkillManagerDB.autoAdd end
            ForeverSkillManagerDB.autoAdd = nil
        end
        if ForeverSkillManagerDB.autoUpgrade ~= nil then
            if ForeverSkillManagerDB.autoUpgradeSpells == nil then ForeverSkillManagerDB.autoUpgradeSpells = ForeverSkillManagerDB.autoUpgrade end
            if ForeverSkillManagerDB.autoUpgradeGear == nil then ForeverSkillManagerDB.autoUpgradeGear = ForeverSkillManagerDB.autoUpgrade end
            ForeverSkillManagerDB.autoUpgrade = nil
        end

        for k, v in pairs(defaults) do
            if ForeverSkillManagerDB[k] == nil then
                ForeverSkillManagerDB[k] = v
            end
        end
        FSM.settings = ForeverSkillManagerDB

        InitOptionsPanel()
        CreateMinimapButton()
    end
end

-- Fallback initialization hook in case ADDON_LOADED was missed
FSM.Events["PLAYER_LOGIN"] = function(self)
    if type(ForeverSkillManagerDB) == "table" then
        CreateMinimapButton()
    end
end

-- Slash Commands
SLASH_FOREVERSKILLMANAGER1 = "/fsm"
SLASH_FOREVERSKILLMANAGER2 = "/skillmanager"
SLASH_FOREVERSKILLMANAGER3 = "/foreverskillmanager"
SlashCmdList["FOREVERSKILLMANAGER"] = function(msg)
    local cleanMsg = msg and (strtrim and strtrim(msg) or msg:gsub("^%s*(.-)%s*$", "%1")):lower() or ""
    if cleanMsg == "trainer" or cleanMsg == "spells" then
        if FSM.OpenTrainerReminder then
            FSM.OpenTrainerReminder(true)
        end
    elseif cleanMsg == "scan" or cleanMsg == "gear" then
        if FSM.ScanAndAddEquippedGear then
            FSM.ScanAndAddEquippedGear()
        end
    elseif cleanMsg == "debug" then
        if ForeverSkillManagerDB then
            ForeverSkillManagerDB.debugMode = not ForeverSkillManagerDB.debugMode
            print("|cff00ff00[Forever Skill Manager]|r Debug mode: " .. (ForeverSkillManagerDB.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        end
    elseif cleanMsg == "help" then
        print("|cff00ff00Forever Skill Manager commands:|r")
        print("  |cffffff00/fsm|r - Toggle configuration panel")
        print("  |cffffff00/fsm trainer|r - View available trainer spells")
        print("  |cffffff00/fsm scan|r - Scan and add equipped on-use gear")
        print("  |cffffff00/fsm debug|r - Toggle debug logging")
    else
        ToggleOptions()
    end
end
