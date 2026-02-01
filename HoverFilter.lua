-- HoverFilter.lua
-- Decides which hovered units HoverCasts should react to.

local ADDON_NAME, ns = ...
ns.HoverFilter = ns.HoverFilter or {}
local HF = ns.HoverFilter

local S = ns.Settings

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

local function IsHealBotFrame(frame)
    local name = frame and frame.GetName and frame:GetName() or nil
    return name and name:match("^HealBot_") ~= nil
end

-- Unit-driven allow list (this is what fixes Party frames)
local function IsAllowedUnit(unit)
    local f = (S and S.GetFrames and S:GetFrames()) or nil
    if not f then
        f = { party = true, raid = true, focus = true, player = false, target = false, enemy = false, world = false }
    end

    if unit == "focus" then
        return f.focus
    end

    if unit == "player" then
        return f.player
    end

    if unit == "target" then
        return f.target
    end

    if unit:match("^party") then
        return f.party
    end

    if unit:match("^raid") then
        return f.raid
    end

    -- Optional: treat some “enemy-ish” units as a toggle (you can refine later)
    if f.enemy then
        if unit == "targettarget" or unit == "focustarget" then
            return true
        end
        -- sometimes shows as "party1target" etc; include if you want:
        if unit:match("^party%d+target$") then
            return true
        end
    end

    return false
end

-- Name-based fallback (keep it, but it’s no longer the primary gate)
local function IsAllowedBlizzardFrameByName(frame)
    if not frame then return false end
    local name = frame.GetName and frame:GetName() or nil
    if not name then return false end

    if name:match("^HealBot_") then return false end

    local f = (S and S.GetFrames and S:GetFrames()) or nil
    if not f then
        f = { party = true, raid = true, focus = true, player = false, target = false, enemy = false, world = false }
    end

    if f.party and name:match("^PartyFrame") then return true end
    if f.raid and (name:match("^CompactPartyFrame") or name:match("^CompactRaidFrame") or name:match("^CompactRaidGroup")) then return true end
    if f.focus and name:match("^FocusFrame") then return true end
    if f.player and name:match("^PlayerFrame") then return true end
    if f.target and name:match("^TargetFrame") then return true end

    if f.enemy then
        if name:match("^TargetFrameToT") or name:match("^FocusFrameToT") or name:match("^TargetOfTargetFrame") or name:match("^FocusTargetFrame") then
            return true
        end
    end

    return false
end

function HF.GetHoveredUnit()
    local foci = (type(GetMouseFoci) == "function") and GetMouseFoci() or nil
    if foci and #foci > 0 then
        for _, focus in ipairs(foci) do
            local cur = focus
            local depth = 0

            while cur and depth < 25 do
                -- hard exclude HealBot
                if IsHealBotFrame(cur) then
                    break
                end

                -- ✅ Primary: unit-driven check
                local unit = ResolveUnitFromFrame(cur)
                if unit and IsAllowedUnit(unit) then
                    return unit
                end

                -- Fallback: name-based check (for cases where unit is only on an ancestor)
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

    -- Optional world units
    local frames = (S and S.GetFrames and S:GetFrames()) or nil
    if frames and frames.world and UnitExists("mouseover") then
        return "mouseover"
    end

    return nil
end
