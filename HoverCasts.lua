-- HoverCasts.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: Entrypoint
--
-- Responsibilities:
--   • Register events and drive rendering while hovering supported unit frames.
--   • Provide slash commands for basic control and debugging.
--   • Orchestrate data flow:
--       HoverFilter -> hovered unit
--       Bindings    -> click-cast bindings for current modifier mask
--       UI          -> tooltip render + sizing + placement
--
-- Public-release behavior:
--   • Prints ONE welcome/help line ONCE per session (login/reload).
--   • No other automatic chat output.
--   • /hc with no args or unknown args prints the same help line.
--
-- Dependencies (loaded via other addon files):
--   ns.Util        -> U
--   ns.HoverFilter -> HF
--   ns.Bindings    -> B
--   ns.UI          -> UI
--
-- Notes:
--   • Spec retrieval is intentionally conservative: only the player's spec is
--     reliably available without inspecting others (safe default).
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local U  = ns.Util
local HF = ns.HoverFilter
local B  = ns.Bindings
local UI = ns.UI

local f = CreateFrame("Frame")

-- -----------------------------------------------------------------------------
-- Configuration (defaults)
-- -----------------------------------------------------------------------------
-- These are runtime defaults. Settings persistence (SavedVariables) can later
-- override them.
local CONFIG = {
    -- Layout
    padding = 6,
    lineSpacing = 1,
    maxLines = 12,
    scale = 1.0,

    -- Background/border
    bgAlpha = 0.92,
    borderAlpha = 0.90,

    -- Cursor anchoring
    cursorOffsetX = 40,
    cursorOffsetY = -40,
    clampPadding = 10,

    -- Update cadence (while tooltip shown)
    pollInterval = 0.05,

    -- Columns
    minActionX = 0,
    minActionGap = 4,
    manaGap = 8,

    -- Fade
    fadeInTime = 0.04,
    fadeOutTime = 0.04,

    -- Modifier line styling
    modTextUseHighlight = true,
    modTextHighlightColor = { r = 1.00, g = 1.00, b = 1.00 }, -- white
    modTextGlow = false,

    -- Cooldown styling (grey out spell name + light-red cooldown suffix)
    cooldownParenHex = "ff8a8a",
    cooldownGreyHex  = "b0b0b0",

    -- Mana column color
    manaHex = "4da6ff",

    -- Debug behavior
    showWhenNoUnit = false,
}

-- Tooltip instance
local tip = UI.Create(CONFIG)

-- -----------------------------------------------------------------------------
-- Sorting (left, middle, right, then extra buttons)
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- Unit info helpers
-- -----------------------------------------------------------------------------
-- Returns player's spec name, if reliably available; otherwise nil.
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

-- Builds: "Level X Race Spec Class" (spec only if we can get it safely).
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

-- -----------------------------------------------------------------------------
-- Modifier line styling
-- -----------------------------------------------------------------------------
-- Produces the modifier display line (already wrapped and optionally colorized).
local function BuildModifierLine(mask)
    local raw = U.ModifierTextFromMask(mask)
    local wrapped = U.WrapModifierText(raw)

    if CONFIG.modTextUseHighlight then
        local c = CONFIG.modTextHighlightColor
        return U.ColorText(wrapped, c.r, c.g, c.b)
    end

    return wrapped
end

-- -----------------------------------------------------------------------------
-- Render pipeline
-- -----------------------------------------------------------------------------
local _inRender = false

local function Render()
    if _inRender then return end
    _inRender = true

    -- Decide whether we should be visible
    local unit = HF.GetHoveredUnit()
    if not unit and not CONFIG.showWhenNoUnit then
        tip:FadeOut()
        _inRender = false
        return
    end

    -- Ensure we have bindings cached
    if not B.cached then
        B.RefreshCache()
    end

    local mask = U.CurrentModifierMask()

    -- Header + modifier line
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

    -- Gather entries for this modifier mask and sort
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

    -- Render + position
    UI.Render(tip, CONFIG, headerText, modLine, entries)
    tip:SetCursorAnchoredPosition()
    tip:FadeIn()

    _inRender = false
end

-- -----------------------------------------------------------------------------
-- Poll: keep position + hide reliably while tooltip is shown
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- Events (safe registration)
-- -----------------------------------------------------------------------------
local function SafeRegisterEvent(frame, evt)
    pcall(frame.RegisterEvent, frame, evt)
end

SafeRegisterEvent(f, "PLAYER_LOGIN")
SafeRegisterEvent(f, "UPDATE_MOUSEOVER_UNIT")
SafeRegisterEvent(f, "MODIFIER_STATE_CHANGED")
SafeRegisterEvent(f, "CURSOR_CHANGED")

-- -----------------------------------------------------------------------------
-- Chat output (public release policy)
-- -----------------------------------------------------------------------------
local function Print(msg)
    print(("HoverCasts: %s"):format(tostring(msg)))
end

local HELP_LINE =
    "Hover party/raid/focus frames to view click-cast bindings. Commands: /hc on | off | refresh | strict"

-- Forward-declared welcome (must exist before PLAYER_LOGIN fires)
local function Welcome()
    Print(HELP_LINE)
end

-- Print once per session on login/reload
local _welcomedThisSession = false

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
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

-- -----------------------------------------------------------------------------
-- Slash commands
-- -----------------------------------------------------------------------------
SLASH_HOVERCASTS1 = "/hc"
SLASH_HOVERCASTS2 = "/hovercasts"
SLASH_HOVERCASTS3 = "/hcc" -- back-compat

SlashCmdList.HOVERCASTS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" then
        Welcome()
        return
    end

    if msg == "on" then
        CONFIG.showWhenNoUnit = true
        tip:Show()
        tip:SetAlpha(1)
        Render()
        Print("Debug on (show even without unit).")
        return
    end

    if msg == "off" then
        tip:Hide()
        Print("Hidden.")
        return
    end

    if msg == "refresh" then
        B.RefreshCache()
        Render()
        Print("Refreshed.")
        return
    end

    if msg == "strict" then
        CONFIG.showWhenNoUnit = false
        Render()
        Print("Strict mode (only show on allowed unit frames).")
        return
    end

    -- Unknown arg → single help line
    Welcome()
end
