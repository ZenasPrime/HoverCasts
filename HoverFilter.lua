-- HoverFilter.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: HoverFilter
--
-- Purpose:
--   Determines whether HoverCasts should activate for the unit currently
--   under the mouse cursor.
--
-- Goals:
--   • Prefer unit-based resolution over frame-name matching (robust to UI changes)
--   • Support Blizzard Party / Raid frames (secure templates)
--   • Allow per-unit-type enable/disable via Settings (SavedVariables)
--   • Exclude third-party unit frames (e.g. HealBot)
--   • Graceful fallback for edge cases
--
-- Primary export:
--   HF.GetHoveredUnit() -> unitID | nil
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.HoverFilter = ns.HoverFilter or {}
local HF = ns.HoverFilter

local S = ns.Settings

-- -----------------------------------------------------------------------------
-- Frame -> Unit resolution (PRIMARY)
-- -----------------------------------------------------------------------------
local function ResolveUnitFromFrame(frame)
    if not frame then return nil end

    if frame.unit and UnitExists(frame.unit) then
        return frame.unit
    end

    if frame.GetAttribute then
        local u = frame:GetAttribute("unit")
        if u and UnitExists(u) then
            return u
        end
    end

    if frame.unitFrame and frame.unitFrame.unit and UnitExists(frame.unitFrame.unit) then
        return frame.unitFrame.unit
    end

    return nil
end

-- -----------------------------------------------------------------------------
-- Third-party exclusion
-- -----------------------------------------------------------------------------
local function IsHealBotFrame(frame)
    local name = frame and frame.GetName and frame:GetName() or nil
    return name and name:match("^HealBot_") ~= nil
end

-- -----------------------------------------------------------------------------
-- Settings helper
-- -----------------------------------------------------------------------------
local function GetFrameToggles()
    if S and S.GetFrames then
        local ok, frames = pcall(S.GetFrames, S)
        if ok and type(frames) == "table" then
            return frames
        end
    end

    -- Safe defaults
    return {
        party  = true,
        raid   = true,
        focus  = true,
        player = false,
        target = false,
        enemy  = false,
        world  = false,
    }
end

-- -----------------------------------------------------------------------------
-- Unit allow list (PRIMARY gate)
-- -----------------------------------------------------------------------------
local function IsAllowedUnit(unit)
    if not unit or unit == "" then return false end
    local f = GetFrameToggles()

    if unit == "focus"  then return not not f.focus  end
    if unit == "player" then return not not f.player end
    if unit == "target" then return not not f.target end

    if unit:match("^party") then return not not f.party end
    if unit:match("^raid")  then return not not f.raid  end

    if f.enemy then
        if unit == "targettarget" or unit == "focustarget" then
            return true
        end
        if unit:match("^party%d+target$") then
            return true
        end
    end

    return false
end

-- -----------------------------------------------------------------------------
-- Frame-name allow list (FALLBACK)
-- -----------------------------------------------------------------------------
local function IsAllowedBlizzardFrameByName(frame)
    if not frame then return false end
    local name = frame.GetName and frame:GetName() or nil
    if not name then return false end

    if name:match("^HealBot_") then return false end

    local f = GetFrameToggles()

    -- Party frames (Retail)
    if f.party and name:match("^PartyFrame") then
        return true
    end

    -- Raid / Compact
    if f.raid and (
        name:match("^CompactPartyFrame") or
        name:match("^CompactRaidFrame")  or
        name:match("^CompactRaidGroup")
    ) then
        return true
    end

    if f.focus  and name:match("^FocusFrame")  then return true end
    if f.player and name:match("^PlayerFrame") then return true end
    if f.target and name:match("^TargetFrame") then return true end

    if f.enemy then
        if name:match("^TargetFrameToT")
        or name:match("^FocusFrameToT")
        or name:match("^TargetOfTargetFrame")
        or name:match("^FocusTargetFrame") then
            return true
        end
    end

    return false
end

-- -----------------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------------
function HF.GetHoveredUnit()
    local foci = (type(GetMouseFoci) == "function") and GetMouseFoci() or nil

    if foci and #foci > 0 then
        for _, focus in ipairs(foci) do
            local cur = focus
            local depth = 0

            while cur and depth < 25 do
                if IsHealBotFrame(cur) then
                    break
                end

                local unit = ResolveUnitFromFrame(cur)
                if unit and IsAllowedUnit(unit) then
                    return unit
                end

                if IsAllowedBlizzardFrameByName(cur) then
                    local u2 = ResolveUnitFromFrame(cur)
                    if u2 and IsAllowedUnit(u2) then
                        return u2
                    end
                end

                cur = cur.GetParent and cur:GetParent() or nil
                depth = depth + 1
            end
        end
    end

    -- Optional "world" unit support
    local frames = GetFrameToggles()
    if frames.world and UnitExists("mouseover") then
        return "mouseover"
    end

    return nil
end