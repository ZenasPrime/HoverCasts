-- HoverFilter.lua
-- Determines whether we should show the tooltip and which unit it applies to.
-- Design intent:
--   Only show while hovering Blizzard Party / Compact Party/Raid / Focus frames.
--   Explicitly ignore HealBot frames.

local ADDON_NAME, ns = ...
ns.HoverFilter = ns.HoverFilter or {}
local HF = ns.HoverFilter

-- Blizzard party/raid/focus frames we allow
local function IsBlizzardUnitFrame(frame)
    if not frame then return false end
    local name = frame.GetName and frame:GetName() or nil
    if not name then return false end

    if name:match("^PartyFrame") then return true end
    if name:match("^CompactPartyFrame") then return true end
    if name:match("^CompactRaidFrame") then return true end
    if name:match("^CompactRaidGroup") then return true end
    if name:match("^FocusFrame") then return true end

    return false
end

local function ResolveUnitFromFrame(frame)
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

-- Returns a unit token (e.g. "party1", "raid7", "focus") or nil.
function HF.GetHoveredUnit()
    local foci = (type(GetMouseFoci) == "function") and GetMouseFoci() or nil
    if not foci or #foci == 0 then return nil end

    for _, focus in ipairs(foci) do
        local cur = focus
        local depth = 0

        while cur and depth < 25 do
            local name = cur.GetName and cur:GetName() or nil
            -- Explicitly ignore HealBot
            if name and name:match("^HealBot_") then
                break
            end

            if IsBlizzardUnitFrame(cur) then
                local unit = ResolveUnitFromFrame(cur)
                if unit then return unit end
            end

            cur = cur.GetParent and cur:GetParent() or nil
            depth = depth + 1
        end
    end

    return nil
end
