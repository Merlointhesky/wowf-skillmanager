-- core.lua for ForeverSkillManager
local addonName, FSM = ...
_G.ForeverSkillManager = FSM

FSM.Events = FSM.Events or {}

-- Centralized Event Frame (following the exact architecture of ForeverNPCAssistant)
local eventFrame = CreateFrame("Frame", "ForeverSkillManagerEventFrame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if FSM.Events and FSM.Events[event] then
        FSM.Events[event](FSM, ...)
    end
end)

function FSM:RegisterEventSafe(event)
    pcall(function()
        eventFrame:RegisterEvent(event)
    end)
end

FSM:RegisterEventSafe("ADDON_LOADED")
FSM:RegisterEventSafe("PLAYER_LOGIN")
FSM:RegisterEventSafe("LEARNED_SPELL_IN_TAB")
FSM:RegisterEventSafe("LEARNED_SPELL_IN_SKILL_LINE") 
FSM:RegisterEventSafe("PLAYER_EQUIPMENT_CHANGED")
FSM:RegisterEventSafe("PLAYER_REGEN_ENABLED")
FSM:RegisterEventSafe("PLAYER_LEVEL_UP")
FSM:RegisterEventSafe("TRAINER_SHOW")
FSM:RegisterEventSafe("TRAINER_UPDATE")
FSM:RegisterEventSafe("SPELLS_CHANGED")
FSM:RegisterEventSafe("CHARACTER_POINTS_CHANGED")
FSM:RegisterEventSafe("PLAYER_MONEY")


