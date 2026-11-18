-- core.lua for ForeverSkillManager
local addonName, FSM = ...
_G.ForeverSkillManager = FSM

FSM.Events = FSM.Events or {}

----------------------------------------------------
-- Secret-Safe Value Helpers (WoW Forever / 11+ client)
----------------------------------------------------
function FSM.IsSecret(v)
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

function FSM.SafeString(v)
    if v == nil or FSM.IsSecret(v) then return nil end
    local ok, res = pcall(function()
        if type(v) == "string" and v ~= "" then
            return v
        end
        return nil
    end)
    return ok and res or nil
end

function FSM.SafeGetText(fontString)
    if not fontString or not fontString.GetText then return nil end
    local ok, text = pcall(fontString.GetText, fontString)
    if not ok or not text then return nil end
    return FSM.SafeString(text)
end

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
FSM:RegisterEventSafe("CRAFT_SHOW")
FSM:RegisterEventSafe("CRAFT_CLOSE")


