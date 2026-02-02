-- Bindings.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: Bindings
--
-- Responsibilities:
--   • Read Blizzard click-cast bindings from C_ClickBindings (profile cache)
--   • Resolve each binding into displayable action data:
--       - Spell name (or macro/interact label)
--       - Mana cost (mana spells only)
--       - Cooldown remaining (seconds; nil if none)
--       - Spell vs non-spell flag
--
-- Notes:
--   • Some modern API returns "secure/secret" values (not directly comparable).
--     We sanitize/cast cooldown fields to plain numbers before comparisons.
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.Bindings = ns.Bindings or {}
local B = ns.Bindings
local U = ns.Util

B.cached = nil

-- -----------------------------------------------------------------------------
-- Cache
-- -----------------------------------------------------------------------------

--- Refreshes the click-cast binding cache from the active profile.
function B.RefreshCache()
    B.cached = {}

    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo then
        return
    end

    local info = C_ClickBindings.GetProfileInfo()
    if type(info) ~= "table" then
        return
    end

    -- Retail has been observed returning either { bindings = {...} } or an array-like table.
    if type(info.bindings) == "table" then
        B.cached = info.bindings
        return
    end

    if #info > 0 then
        B.cached = info
        return
    end
end

-- -----------------------------------------------------------------------------
-- Spell helpers
-- -----------------------------------------------------------------------------

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

-- Some APIs can return "secret" numbers that error on compare/math.
-- Safely coerce to a plain Lua number by attempting arithmetic in pcall.
local function SafeNumber(v)
    if v == nil then return nil end

    -- First try arithmetic coercion (this will fail for "secret" values)
    local ok, n = pcall(function()
        return (v + 0)
    end)
    if ok and type(n) == "number" then
        return n
    end

    -- Fallback: tonumber in pcall (covers strings)
    ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then
        return n
    end

    return nil
end

local function GetSpellCooldownRemaining(spellID)
    if not spellID then return nil end

    -- Prefer classic API if present (often safest), but still sanitize.
    if type(GetSpellCooldown) == "function" then
        local startTime, duration, enabled = GetSpellCooldown(spellID)

        startTime = SafeNumber(startTime)
        duration  = SafeNumber(duration)

        if enabled == 0 then
            return nil
        end
        if not startTime or not duration then
            return nil
        end

        local ok, isZeroOrNeg = pcall(function()
            return duration <= 0
        end)
        if (not ok) or isZeroOrNeg then
            return nil
        end

        local ok2, remaining = pcall(function()
            return (startTime + duration) - GetTime()
        end)
        if ok2 and remaining and remaining > 0.05 then
            return remaining
        end
        return nil
    end

    -- Fallback: C_Spell.GetSpellCooldown (sanitize and guard all ops)
    if not C_Spell or not C_Spell.GetSpellCooldown then
        return nil
    end

    local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cd) ~= "table" then
        return nil
    end

    local startTime = SafeNumber(cd.startTime)
    local duration  = SafeNumber(cd.duration)

    if not startTime or not duration then
        return nil
    end

    local ok3, isZeroOrNeg = pcall(function()
        return duration <= 0
    end)
    if (not ok3) or isZeroOrNeg then
        return nil
    end

    local ok4, remaining = pcall(function()
        return (startTime + duration) - GetTime()
    end)
    if ok4 and remaining and remaining > 0.05 then
        return remaining
    end

    return nil
end


-- -----------------------------------------------------------------------------
-- Binding resolution
-- -----------------------------------------------------------------------------

--- Resolves a single click binding into action data.
-- @param binding table
-- @return string actionName
-- @return number|nil manaCost
-- @return number|nil cooldownRemainingSeconds
-- @return boolean isSpell
function B.ResolveAction(binding)
    if type(binding) ~= "table" then
        return "Unknown", nil, nil, false
    end

    local actionID = binding.actionID or binding.spellID or binding.macroID or binding.action or binding.id
    local t = binding.type or binding.actionType

    local enumSpell   = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Spell
    local enumMacro   = Enum and Enum.ClickBindingType and Enum.ClickBindingType.Macro
    local enumInteract= Enum and Enum.ClickBindingType and Enum.ClickBindingType.Interact

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
        local name = (GetMacroInfo and GetMacroInfo(actionID)) or "Macro"
        return name, nil, nil, false
    end

    if isInteract then
        return "Interact", nil, nil, false
    end

    return "Unknown", nil, nil, false
end

-- -----------------------------------------------------------------------------
-- Query
-- -----------------------------------------------------------------------------

--- Returns a list of entries for the given modifier mask.
-- Each entry:
--   { btn, action, mana, cd, isSpell, _rawButton }
-- Sorting is done by the caller (HoverCasts.lua) so UI rules live in one place.
-- @param mask number
-- @return table
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
