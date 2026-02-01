-- Util.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: Util
--
-- Shared helpers used across the addon (Bindings / UI / HoverFilter / Entrypoint).
--
-- Namespace pattern:
--   local ADDON_NAME, ns = ...
--   ns.Util = ns.Util or {}
--   local U = ns.Util
--
-- Contents:
--   • Modifier mask helpers (Retail click-casting bitmask scheme)
--   • Button label normalization (Left/Middle/Right/Button4+)
--   • Text coloring helpers (RGB + hex)
--   • Unit class-color lookup
--   • Cooldown formatting
--   • FontString measurement (unbounded width when available)
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

-- -----------------------------------------------------------------------------
-- Modifier masks (Retail click casting uses these values)
--
-- Blizzard click-casting uses a bitmask-like numeric scheme:
--   Shift = 3
--   Ctrl  = 12
--   Alt   = 48
-- Combined values add together:
--   Shift+Ctrl+Alt = 3 + 12 + 48 = 63
-- -----------------------------------------------------------------------------

--- Returns the current click-cast modifier mask (0 if none).
-- @return number mask
function U.CurrentModifierMask()
    local mask = 0
    if IsShiftKeyDown() then mask = mask + 3 end
    if IsControlKeyDown() then mask = mask + 12 end
    if IsAltKeyDown() then mask = mask + 48 end
    return mask
end

--- Converts a modifier mask into a human-readable string ("Shift+Ctrl", etc.).
-- @param mask number
-- @return string
function U.ModifierTextFromMask(mask)
    local t = {}
    if bit.band(mask, 3) ~= 0 then t[#t+1] = "Shift" end
    if bit.band(mask, 12) ~= 0 then t[#t+1] = "Ctrl" end
    if bit.band(mask, 48) ~= 0 then t[#t+1] = "Alt" end
    return table.concat(t, "+")
end

--- Wraps modifier text in brackets and normalizes empty to "None".
-- @param raw string|nil modifier text (e.g., "Shift+Ctrl") or nil/empty
-- @return string formatted, e.g. "[Shift+Ctrl]" or "[None]"
function U.WrapModifierText(raw)
    if not raw or raw == "" then raw = "None" end
    return ("[%s]"):format(raw)
end

-- -----------------------------------------------------------------------------
-- Button label normalization
-- -----------------------------------------------------------------------------

--- Normalizes Blizzard mouse button tokens to compact labels for display.
-- Examples:
--   "LeftButton"   -> "Left"
--   "MiddleButton" -> "Middle"
--   "RightButton"  -> "Right"
--   "Button4"      -> "Button 4"
-- @param btn string|nil
-- @return string
function U.NiceButtonName(btn)
    if not btn then return "?" end
    if btn == "LeftButton" then return "Left" end
    if btn == "MiddleButton" then return "Middle" end
    if btn == "RightButton" then return "Right" end

    local n = btn:match("^Button(%d+)$")
    if n then return "Button " .. n end

    return btn
end

-- -----------------------------------------------------------------------------
-- Text coloring helpers
-- -----------------------------------------------------------------------------

--- Colors text using RGB values in the range [0..1].
-- @param txt string|nil
-- @param r number
-- @param g number
-- @param b number
-- @return string
function U.ColorText(txt, r, g, b)
    if not txt then return "" end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, txt)
end

--- Colors text using a 6-character hex color string (e.g. "ff8a8a").
-- @param text string|nil
-- @param hex6 string
-- @return string
function U.ColorHexText(text, hex6)
    if not text or text == "" then return "" end
    return ("|cff%s%s|r"):format(hex6, text)
end

--- Returns the RAID_CLASS_COLORS RGB values for a unit, or white if unavailable.
-- @param unit string|nil
-- @return number r, number g, number b
function U.ClassColorForUnit(unit)
    if not unit then return 1, 1, 1 end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- -----------------------------------------------------------------------------
-- Cooldown formatting
-- -----------------------------------------------------------------------------

--- Formats a cooldown value in seconds for compact display.
--   < 10s  -> "0.5s" (one decimal)
--   < 60s  -> "12s"  (rounded)
--   >= 60s -> "2m"   (ceiling minutes)
-- @param sec number|nil
-- @return string|nil
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

-- -----------------------------------------------------------------------------
-- FontString measurement
-- -----------------------------------------------------------------------------

--- Measures a FontString's width for the given text.
-- Uses unbounded width when available (prevents truncation-related mismeasurement).
-- @param fs FontString
-- @param text string|nil
-- @return number
function U.MeasureFS(fs, text)
    fs:SetText(text or "")
    if fs.GetUnboundedStringWidth then
        return fs:GetUnboundedStringWidth() or 0
    end
    return fs:GetStringWidth() or 0
end
