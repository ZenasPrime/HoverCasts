-- Bindings.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: Bindings
--
-- Purpose:
--   Provides a thin wrapper around Blizzard's click-cast binding API
--   (C_ClickBindings) and resolves each binding into display-ready data:
--     • Button label (via Util)
--     • Action name (spell / macro / interact)
--     • Mana cost (spells only)
--     • Cooldown remaining (spells only)
--
-- Public API:
--   B.RefreshCache()
--     - Refreshes the click-cast binding cache from C_ClickBindings.
--
--   B.ResolveAction(binding) -> actionName, manaCost, cooldownSeconds, isSpell
--     - Converts a single binding table into readable, displayable values.
--
--   B.GetEntriesForMask(mask) -> entries[]
--     - Returns a list of entries matching the given modifier mask.
--
-- Notes:
--   • Retail API shapes differ across builds; RefreshCache() tolerates both:
--       - { bindings = {...} }
--       - an array table of bindings (info[1..n])
--   • Cooldown and mana are only meaningful for spells; macros/interactions
--     return nil for these fields.
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.Bindings = ns.Bindings or {}
local B = ns.Bindings

local U = ns.Util

-- Cached click-binding list, as returned by C_ClickBindings.GetProfileInfo().
-- Shape depends on build; we normalize to an array of binding tables.
B.cached = nil

-- -----------------------------------------------------------------------------
-- Cache
-- -----------------------------------------------------------------------------
-- Populates B.cached with an array of bindings.
-- Safe to call at login and periodically (very lightweight).
function B.RefreshCache()
    B.cached = {}

    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo then
        return
    end

    local info = C_ClickBindings.GetProfileInfo()
    if type(info) ~= "table" then
        return
    end

    -- Modern shape: { bindings = {...} }
    if type(info.bindings) == "table" then
        B.cached = info.bindings
        return
    end

    -- Older/alternate shape: array of bindings
    if #info > 0 then
        B.cached = info
        return
    end
end

-- -----------------------------------------------------------------------------
-- Spell helpers (Retail-safe)
-- -----------------------------------------------------------------------------
-- Resolves a spellID to a localized spell name if possible.
--
-- @param spellID number
-- @return string|nil
local function ResolveSpellName(spellID)
    if not spellID then return nil end

    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end

    -- Fallback for older/alternate builds
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return info.name
        end
    end

    return nil
end

-- Returns the mana cost for a spellID if the spell has a mana cost.
--
-- @param spellID number
-- @return number|nil
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

-- Returns remaining cooldown seconds for a spellID, or nil if ready.
--
-- @param spellID number
-- @return number|nil
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

-- -----------------------------------------------------------------------------
-- Binding resolution
-- -----------------------------------------------------------------------------
-- Converts a raw binding table into:
--   actionName          (string)
--   manaCostOrNil       (number|nil)
--   cooldownSecondsOrNil(number|nil)
--   isSpell             (boolean)
--
-- @param binding table
-- @return string, number|nil, number|nil, boolean
function B.ResolveAction(binding)
    if type(binding) ~= "table" then
        return "Unknown", nil, nil, false
    end

    -- Different builds use different keys; actionID is our best "any of these".
    local actionID =
        binding.actionID or binding.spellID or binding.macroID or binding.action or binding.id

    local t = binding.type or binding.actionType

    -- Enum.ClickBindingType is present in modern builds; tolerate strings too.
    local enumSpell    = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Spell
    local enumMacro    = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Macro
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
        local cd   = GetSpellCooldownRemaining(actionID)
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

-- -----------------------------------------------------------------------------
-- Entry list builder
-- -----------------------------------------------------------------------------
-- Builds the list of entries matching the current modifier mask.
-- Each entry:
--   {
--     btn       = "Left"/"Right"/"Button 4"/... (human-friendly)
--     action    = "Rejuvenation"
--     mana      = 800 (number|nil)
--     cd        = 1.5 (seconds remaining, number|nil)
--     isSpell   = true/false
--     _rawButton= original binding button token
--   }
--
-- Sorting is handled by the caller (HoverCasts.lua) to keep policy in one place.
--
-- @param mask number
-- @return table[]
function B.GetEntriesForMask(mask)
    if not B.cached then
        B.RefreshCache()
    end

    local src = B.cached
    if not src or #src == 0 then
        return {}
    end

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
                _rawButton = rawBtn,
            }
        end
    end

    return out
end
