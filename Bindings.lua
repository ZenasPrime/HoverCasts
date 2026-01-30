-- Bindings.lua
-- Click casting binding cache + binding resolution (spell/mana/cooldown).

local ADDON_NAME, ns = ...
ns.Bindings = ns.Bindings or {}
local B = ns.Bindings
local U = ns.Util

B.cached = nil

function B.RefreshCache()
    B.cached = {}
    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo then return end

    local info = C_ClickBindings.GetProfileInfo()
    if type(info) ~= "table" then return end

    if type(info.bindings) == "table" then
        B.cached = info.bindings
        return
    end

    if #info > 0 then
        B.cached = info
        return
    end
end

local function ResolveSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return info.name
        end
    end
    return nil
end

local function GetSpellManaCost(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then
        return nil
    end

    local costs = C_Spell.GetSpellPowerCost(spellID)
    if not costs then return nil end

    for _, cost in ipairs(costs) do
        if cost.type == Enum.PowerType.Mana and cost.cost and cost.cost > 0 then
            return cost.cost
        end
    end

    return nil
end

local function GetSpellCooldownRemaining(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellCooldown then
        return nil
    end

    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd or not cd.startTime or not cd.duration or cd.duration <= 0 then
        return nil
    end

    local remaining = (cd.startTime + cd.duration) - GetTime()
    if remaining and remaining > 0.05 then
        return remaining
    end
    return nil
end

-- Returns:
--   actionName, manaCostOrNil, cooldownSecondsOrNil, isSpellBool
function B.ResolveAction(binding)
    if type(binding) ~= "table" then
        return "Unknown", nil, nil, false
    end

    local actionID = binding.actionID or binding.spellID or binding.macroID or binding.action or binding.id
    local t = binding.type or binding.actionType

    local enumSpell = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Spell
    local enumMacro = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Macro
    local enumInteract = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Interact

    local isSpell =
        (t == "SPELL") or (t == "Spell") or (enumSpell and t == enumSpell) or (binding.spellID ~= nil)

    local isMacro =
        (t == "MACRO") or (t == "Macro") or (enumMacro and t == enumMacro) or (binding.macroID ~= nil)

    local isInteract =
        (t == "INTERACTION") or (t == "Interact") or (enumInteract and t == enumInteract)

    if isSpell and actionID then
        local name = ResolveSpellName(actionID) or "Unknown Spell"
        local mana = GetSpellManaCost(actionID)
        local cd = GetSpellCooldownRemaining(actionID)
        return name, mana, cd, true
    end

    if isMacro and actionID then
        local name = GetMacroInfo and GetMacroInfo(actionID) or "Macro"
        return name, nil, nil, false
    end

    if isInteract then
        return "Interact", nil, nil, false
    end

    return "Unknown", nil, nil, false
end

-- Returns a sorted list of entries for the given modifier mask.
-- Each entry:
--   { btn, action, mana, cd, isSpell, _rawButton }
function B.GetEntriesForMask(mask)
    if not B.cached then B.RefreshCache() end
    local src = B.cached
    if not src or #src == 0 then return {} end

    local out = {}
    for _, bnd in ipairs(src) do
        local bmods = bnd.modifiers or bnd.mods or 0
        if bmods == mask then
            local rawBtn = bnd.button or bnd.mouseButton or bnd.key
            local btn = U.NiceButtonName(rawBtn)
            local action, mana, cd, isSpell = B.ResolveAction(bnd)

            out[#out + 1] = {
                btn = btn,
                action = action,
                mana = mana,
                cd = cd,
                isSpell = isSpell,
                _rawButton = rawBtn
            }
        end
    end

    return out
end
