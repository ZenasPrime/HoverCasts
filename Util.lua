-- Util.lua
-- Shared helpers for HoverCasts.
-- Namespace pattern:
--   local ADDON_NAME, ns = ...
--   ns.Util = { ... }

local ADDON_NAME, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

-- -------------------------------------------------------
-- Modifier masks (Retail click casting uses these values)
-- Shift = 3, Ctrl = 12, Alt = 48
-- Combined values add together (e.g. Shift+Ctrl+Alt = 63)
-- -------------------------------------------------------
function U.CurrentModifierMask()
    local mask = 0
    if IsShiftKeyDown() then mask = mask + 3 end
    if IsControlKeyDown() then mask = mask + 12 end
    if IsAltKeyDown() then mask = mask + 48 end
    return mask
end

function U.ModifierTextFromMask(mask)
    local t = {}
    if bit.band(mask, 3) ~= 0 then t[#t+1] = "Shift" end
    if bit.band(mask, 12) ~= 0 then t[#t+1] = "Ctrl" end
    if bit.band(mask, 48) ~= 0 then t[#t+1] = "Alt" end
    return table.concat(t, "+")
end

function U.WrapModifierText(raw)
    if not raw or raw == "" then raw = "None" end
    return ("[%s]"):format(raw)
end

-- -------------------------------------------------------
-- Button label normalization
-- -------------------------------------------------------
function U.NiceButtonName(btn)
    if not btn then return "?" end
    if btn == "LeftButton" then return "Left" end
    if btn == "MiddleButton" then return "Middle" end
    if btn == "RightButton" then return "Right" end

    local n = btn:match("^Button(%d+)$")
    if n then return "Button " .. n end

    return btn
end

-- -------------------------------------------------------
-- Text coloring helpers
-- -------------------------------------------------------
function U.ColorText(txt, r, g, b)
    if not txt then return "" end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, txt)
end

function U.ColorHexText(text, hex6)
    if not text or text == "" then return "" end
    return ("|cff%s%s|r"):format(hex6, text)
end

function U.ClassColorForUnit(unit)
    if not unit then return 1, 1, 1 end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- -------------------------------------------------------
-- Cooldown formatting
-- -------------------------------------------------------
function U.FormatCooldown(sec)
    if not sec then return nil end
    if sec < 10 then
        return ("%.1fs"):format(sec)
    elseif sec < 60 then
        return ("%ds"):format(math.floor(sec + 0.5))
    else
        return ("%dm"):format(math.ceil(sec / 60))
    end
end

-- -------------------------------------------------------
-- FontString measurement
-- Uses unbounded width when available so we measure accurately.
-- -------------------------------------------------------
function U.MeasureFS(fs, text)
    fs:SetText(text or "")
    if fs.GetUnboundedStringWidth then
        return fs:GetUnboundedStringWidth() or 0
    end
    return fs:GetStringWidth() or 0
end
