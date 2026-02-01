-- HoverFilter.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: HoverFilter
--
-- Purpose:
--   Determines whether HoverCasts should activate for the unit currently
--   under the mouse cursor.
--
-- Design goals:
--   • Prefer unit-based resolution over frame-name matching (robust to UI changes)
--   • Support modern Blizzard Party / Raid frames (including secure templates)
--   • Allow per-unit-type enable/disable via Settings
--   • Explicitly exclude third-party unit frames (e.g. HealBot)
--   • Gracefully fall back to name-based checks when required
--
-- Primary export:
--   HF.GetHoveredUnit() -> unitID | nil
--
-- Notes:
--   • This file contains *no UI code*
--   • This file does *not* depend on click-casting APIs
--   • All policy decisions are centralized here
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.HoverFilter = ns.HoverFilter or {}
local HF = ns.HoverFilter

-- Settings module (optional; safe defaults used if unavailable)
local S = ns.Settings

-- -----------------------------------------------------------------------------
-- Frame → Unit resolution
-- -----------------------------------------------------------------------------
-- Attempts to resolve a valid WoW unitID from a frame or its attributes.
-- This is the PRIMARY mechanism and fixes Party Frame compatibility.
--
-- @param frame table
-- @return unitID|string|nil
local function ResolveUnitFromFrame(frame)
    if not frame then return nil end

    -- Direct unit assignment (common on secure frames)
    if frame.unit and UnitExists(frame.unit) then
        return frame.unit
    end

    -- Secure attribute-based unit resolution
    if frame.GetAttribute then
        local u = frame:GetAttribute("unit")
        if u and UnitExists(u) then
            return u
        end
    end

    -- Nested unitFrame patterns (used by some Blizzard templates)
    if frame.unitFrame and frame.unitFrame.unit and UnitExists(frame.unitFrame.unit) then
        return frame.unitFrame.unit
    end

    return nil
end

-- -----------------------------------------------------------------------------
-- Third-party exclusion
-- -----------------------------------------------------------------------------
-- Hard exclusion for known addon unit frames.
-- This prevents conflicts and duplicate hover behavior.
--
-- @param frame table
-- @return boolean
local function IsHealBotFrame(frame)
    local name = frame and frame.GetName and frame:GetName() or nil
    return name and name:match("^HealBot_") ~= nil
end

-- -----------------------------------------------------------------------------
-- Unit-based allow list (PRIMARY gate)
-- -----------------------------------------------------------------------------
-- Determines whether a given unitID is permitted based on user settings.
-- This logic fixes Blizzard Party Frames by operating on unit IDs directly.
--
-- @param unit string
-- @return boolean
local function IsAllowedUnit(unit)
    -- Fetch frame toggles from Settings, or fall back to safe defaults
    local f = (S and S.GetFrames and S:GetFrames()) or {
        party  = true,
        raid   = true,
        focus  = true,
        player = false,
        target = false,
        enemy  = false,
        world  = false,
    }

    if unit == "focus"  then return f.focus  end
    if unit == "player" then return f.player end
    if unit == "target" then return f.target end

    if unit:match("^party") then return f.party end
    if unit:match("^raid")  then return f.raid  end

    -- Optional enemy-adjacent units (opt-in)
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
-- Used only when unit resolution is not directly available on the hovered frame.
-- This preserves compatibility with edge-case Blizzard layouts.
--
-- @param frame table
-- @return boolean
local function IsAllowedBlizzardFrameByName(frame)
    if not frame then return false end

    local name = frame.GetName and frame:GetName() or nil
    if not name then return false end

    -- Explicit exclusion
    if name:match("^HealBot_") then return false end

    local f = (S and S.GetFrames and S:GetFrames()) or {
        party  = true,
        raid   = true,
        focus  = true,
        player = false,
        target = false,
        enemy  = false,
        world  = false,
    }

    if f.party and name:match("^PartyFrame") then return true end

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
-- Determines the unit HoverCasts should currently act upon.
-- Uses GetMouseFoci() to traverse the frame stack under the cursor.
--
-- Resolution order:
--   1. Unit-based allow list (preferred)
--   2. Name-based fallback (legacy safety net)
--   3. Optional world-unit fallback (mouseover)
--
-- @return unitID|string|nil
function HF.GetHoveredUnit()
    local foci = (type(GetMouseFoci) == "function") and GetMouseFoci() or nil

    if foci and #foci > 0 then
        for _, focus in ipairs(foci) do
            local cur = focus
            local depth = 0

            while cur and depth < 25 do
                -- Hard stop on excluded addon frames
                if IsHealBotFrame(cur) then
                    break
                end

                -- ✅ PRIMARY: unit-driven resolution
                local unit = ResolveUnitFromFrame(cur)
                if unit and IsAllowedUnit(unit) then
                    return unit
                end

                -- Fallback: name-based frame filtering
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

    -- Optional world-unit support (e.g., NPCs, nameplates)
    local frames = (S and S.GetFrames and S:GetFrames()) or nil
    if frames and frames.world and UnitExists("mouseover") then
        return "mouseover"
    end

    return nil
end
