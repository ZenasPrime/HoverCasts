-- HoverCasts.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: Entrypoint
--
-- Public-release behavior:
--   • One welcome/help line printed ONCE per session on login/reload.
--   • No other automatic chat output.
--   • /hc with no args or unknown args prints the same help line.
--
-- Slash commands:
--   /hc                      -> help
--   /hc on|off               -> debug show/hide (showWhenNoUnit)
--   /hc refresh              -> refresh click-cast cache
--   /hc strict               -> strict mode (show only on allowed unit frames)
--   /hc frames               -> print frame toggles summary
--   /hc <frame>              -> toggle a frame (party/raid/focus/player/target/enemy/world)
--   /hc <frame> on|off        -> set a frame explicitly
--
-- Dependencies (loaded via other addon files):
--   ns.Util        -> U
--   ns.HoverFilter -> HF
--   ns.Bindings    -> B
--   ns.UI          -> UI
--   ns.Settings    -> S (optional but recommended)
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local U  = ns.Util
local HF = ns.HoverFilter
local B  = ns.Bindings
local UI = ns.UI
local S  = ns.Settings

local f = CreateFrame("Frame")

-- ---------------------------------------------------------------------
-- Basic safety: if a required module is missing, fail quietly.
-- (Avoid chat spam; just don't run.)
-- ---------------------------------------------------------------------
if not (U and HF and B and UI) then
    -- If you want a single visible hint during development, uncomment:
    -- print("HoverCasts: Missing module(s). Check .toc load order.")
    return
end

-- ---------------------------------------------------------------------
-- Config (defaults)
-- ---------------------------------------------------------------------
local CONFIG = {
    padding = 6,
    lineSpacing = 1,
    maxLines = 12,
    scale = 1.0,

    bgAlpha = 0.92,
    borderAlpha = 0.90,

    cursorOffsetX = 40,
    cursorOffsetY = -40,

    clampPadding = 10,
    pollInterval = 0.05,

    minActionX = 0,
    minActionGap = 4,
    manaGap = 8,

    fadeInTime = 0.04,
    fadeOutTime = 0.04,

    -- modifier text highlight
    modTextUseHighlight = true,
    modTextHighlightColor = { r = 1.00, g = 1.00, b = 1.00 }, -- white
    modTextGlow = false,

    -- cooldown styling
    cooldownParenHex = "ff8a8a", -- light red
    cooldownGreyHex  = "b0b0b0", -- grey spell name when on cooldown

    -- mana column color
    manaHex = "4da6ff",

    -- debug
    showWhenNoUnit = false,
}

local tip = UI.Create(CONFIG)

-- ---------------------------------------------------------------------
-- Sorting (left, middle, right, buttons…)
-- ---------------------------------------------------------------------
local BUTTON_ORDER = {
    LeftButton   = 1,
    MiddleButton = 2,
    RightButton  = 3,
    Button4      = 4,
    Button5      = 5,
}

local function SortEntries(a, b)
    local oa = BUTTON_ORDER[a._rawButton] or 99
    local ob = BUTTON_ORDER[b._rawButton] or 99
    if oa ~= ob then return oa < ob end
    return tostring(a.action) < tostring(b.action)
end

-- ---------------------------------------------------------------------
-- Unit info line helpers
-- ---------------------------------------------------------------------
local function GetUnitSpecName(unit)
    if not unit or not UnitExists(unit) then return nil end
    if not UnitIsPlayer(unit) then return nil end
    if not UnitIsUnit(unit, "player") then return nil end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex and C_SpecializationInfo.GetSpecializationInfo then
            local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            if specID and C_SpecializationInfo.GetSpecializationInfoByID then
                local _, specName = C_SpecializationInfo.GetSpecializationInfoByID(specID)
                if specName and specName ~= "" then
                    return specName
                end
            end
        end
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, specName = GetSpecializationInfo(specIndex)
            if specName and specName ~= "" then
                return specName
            end
        end
    end

    return nil
end

local function GetUnitInfoText(unit)
    if not unit or not UnitExists(unit) then return "" end

    local level = UnitLevel(unit)
    if not level or level <= 0 then level = "??" end

    local race = UnitRace(unit) or ""
    local className = UnitClass(unit) or ""
    local spec = GetUnitSpecName(unit) or ""

    local parts = {}
    parts[#parts+1] = ("Level %s"):format(tostring(level))
    if race ~= "" then parts[#parts+1] = race end
    if spec ~= "" then parts[#parts+1] = spec end
    if className ~= "" then parts[#parts+1] = className end

    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------
-- Modifier line styling
-- ---------------------------------------------------------------------
local function BuildModifierLine(mask)
    local raw = U.ModifierTextFromMask(mask)
    local wrapped = U.WrapModifierText(raw)

    if CONFIG.modTextUseHighlight then
        local c = CONFIG.modTextHighlightColor
        return U.ColorText(wrapped, c.r, c.g, c.b)
    end

    return wrapped
end

-- ---------------------------------------------------------------------
-- Render pipeline
-- ---------------------------------------------------------------------
local _inRender = false

local function Render()
    if _inRender then return end
    _inRender = true

    local unit = HF.GetHoveredUnit()
    if not unit and not CONFIG.showWhenNoUnit then
        tip:FadeOut()
        _inRender = false
        return
    end

    if not B.cached then
        B.RefreshCache()
    end

    local mask = U.CurrentModifierMask()
    local headerText = ""
    local modLine = BuildModifierLine(mask)

    if unit then
        local name = UnitName(unit) or "Unknown"
        local r, g, b = U.ClassColorForUnit(unit)
        local info = GetUnitInfoText(unit)

        if info ~= "" then
            headerText = ("%s (%s)"):format(U.ColorText(name, r, g, b), info)
        else
            headerText = U.ColorText(name, r, g, b)
        end
    end

    local entries = B.GetEntriesForMask(mask)
    table.sort(entries, SortEntries)

    -- Precompute per-entry display strings (cooldown + grey-out + mana text)
    for _, e in ipairs(entries) do
        local actionName = e.action or ""
        local cdText = (e.cd and e.cd > 0) and U.FormatCooldown(e.cd) or nil

        if e.isSpell and cdText then
            actionName = U.ColorHexText(actionName, CONFIG.cooldownGreyHex)
        end

        local actionText = actionName
        if cdText then
            actionText = ("%s %s"):format(
                actionText,
                U.ColorHexText(("(%s)"):format(cdText), CONFIG.cooldownParenHex)
            )
        end
        e.actionText = actionText

        if e.mana then
            e.manaText = ("|cff%s%d mana|r"):format(CONFIG.manaHex, e.mana)
        else
            e.manaText = nil
        end
    end

    UI.Render(tip, CONFIG, headerText, modLine, entries)
    tip:SetCursorAnchoredPosition()
    tip:FadeIn()

    _inRender = false
end

-- ---------------------------------------------------------------------
-- Poll: keep position + hide reliably
-- ---------------------------------------------------------------------
do
    local accum = 0
    tip:SetScript("OnUpdate", function(_, dt)
        if not tip:IsShown() then return end

        tip:SetCursorAnchoredPosition()

        accum = accum + dt
        if accum >= (CONFIG.pollInterval or 0.05) then
            accum = 0
            Render()
        end

        if tip:GetAlpha() <= 0.01 then
            tip:Hide()
        end
    end)
end

-- ---------------------------------------------------------------------
-- Events (safe)
-- ---------------------------------------------------------------------
local function SafeRegisterEvent(frame, evt)
    pcall(frame.RegisterEvent, frame, evt)
end

SafeRegisterEvent(f, "PLAYER_LOGIN")
SafeRegisterEvent(f, "UPDATE_MOUSEOVER_UNIT")
SafeRegisterEvent(f, "MODIFIER_STATE_CHANGED")
SafeRegisterEvent(f, "CURSOR_CHANGED")

-- ---------------------------------------------------------------------
-- Chat helpers + welcome
-- ---------------------------------------------------------------------
local function Print(msg)
    print(("HoverCasts: %s"):format(tostring(msg)))
end

local HELP_LINE =
    "Hover party/raid/focus frames to view click-cast bindings. " ..
    "Commands: /hc frames | /hc <frame> [on|off] | /hc refresh | /hc strict"

local function Welcome()
    Print(HELP_LINE)
end

local _welcomedThisSession = false

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Initialize SavedVariables (if Settings module is present)
        if S and S.Init then
            pcall(S.Init, S)
        end

        B.RefreshCache()
        Render()

        if not _welcomedThisSession then
            _welcomedThisSession = true
            Welcome()
        end
        return
    end

    if event == "UPDATE_MOUSEOVER_UNIT"
        or event == "MODIFIER_STATE_CHANGED"
        or event == "CURSOR_CHANGED" then
        Render()
        return
    end
end)

-- ---------------------------------------------------------------------
-- Frame toggle helpers (Settings)
-- ---------------------------------------------------------------------
local VALID_FRAME_KEYS = {
    party = true,
    raid = true,
    focus = true,
    player = true,
    target = true,
    enemy = true,
    world = true,
}

local function PrintFramesSummary()
    if S and S.FramesSummary then
        Print("Frames: " .. S:FramesSummary())
    else
        Print("Frames: settings module not loaded (check .toc order).")
    end
end

local function SetOrToggleFrame(key, maybeState)
    key = (key or ""):lower()
    if not VALID_FRAME_KEYS[key] then
        return false, ("Unknown frame '%s'"):format(tostring(key))
    end

    if not (S and S.SetFrameEnabled and S.ToggleFrame and S.GetFrames) then
        return false, "Settings module not loaded (check .toc order)."
    end

    local newValue
    if maybeState == nil or maybeState == "" then
        newValue = S:ToggleFrame(key)
    else
        local state = tostring(maybeState):lower()
        if state == "on" or state == "1" or state == "true" then
            S:SetFrameEnabled(key, true)
            newValue = true
        elseif state == "off" or state == "0" or state == "false" then
            S:SetFrameEnabled(key, false)
            newValue = false
        else
            return false, "State must be 'on' or 'off'."
        end
    end

    return true, ("%s = %s"):format(key, newValue and "ON" or "OFF")
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
SLASH_HOVERCASTS1 = "/hc"
SLASH_HOVERCASTS2 = "/hovercasts"
SLASH_HOVERCASTS3 = "/hcc" -- back-compat

SlashCmdList.HOVERCASTS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        Welcome()
        return
    end

    -- tokenization: "<a> <b>"
    local a, b = msg:match("^(%S+)%s*(.-)$")
    b = (b and b:gsub("^%s+", ""):gsub("%s+$", "")) or ""

    if a == "on" then
        CONFIG.showWhenNoUnit = true
        tip:Show()
        tip:SetAlpha(1)
        Render()
        Print("Debug on (show even without unit).")
        return
    end

    if a == "off" then
        tip:Hide()
        Print("Hidden.")
        return
    end

    if a == "refresh" then
        B.RefreshCache()
        Render()
        Print("Refreshed.")
        return
    end

    if a == "strict" then
        CONFIG.showWhenNoUnit = false
        Render()
        Print("Strict mode (only show on allowed unit frames).")
        return
    end

    if a == "frames" then
        PrintFramesSummary()
        return
    end

    -- Frame toggle: "/hc player" or "/hc player on|off"
    if VALID_FRAME_KEYS[a] then
        local ok, res = SetOrToggleFrame(a, b ~= "" and b or nil)
        if ok then
            Print(res)
            PrintFramesSummary()
            Render()
        else
            Print(res)
            Welcome()
        end
        return
    end

    -- Unknown arg → single help line
    Welcome()
end