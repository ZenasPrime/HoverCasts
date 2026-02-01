-- UI.lua
-- -----------------------------------------------------------------------------
-- HoverCasts :: UI
--
-- Purpose:
--   Owns the tooltip frame used by HoverCasts:
--     • Builds the tooltip frame, header + modifier lines, and fixed row pool.
--     • Renders rows from resolved binding entries.
--     • Measures text widths to compute compact columns:
--         Button | Ability | Mana
--     • Positions tooltip near cursor with smart “flip + clamp” to avoid
--       rendering off-screen.
--     • Provides snappy fade in/out helpers.
--
-- Public API:
--   UI.Create(config) -> tip
--     - Creates the tooltip frame and returns it. The returned frame ("tip")
--       includes helper methods:
--         tip:SetCursorAnchoredPosition()
--         tip:FadeIn()
--         tip:FadeOut()
--         tip:ClearRows()
--
--   UI.Render(tip, config, headerText, modText, entries)
--     - Renders the header + modifier line and the entry table, and computes
--       the tooltip size + column anchors.
--
-- Inputs expected by UI.Render:
--   headerText: string
--     - Already colorized (name class-colored) by caller.
--   modText: string
--     - Already wrapped/colored (e.g. "[Shift+Ctrl]") by caller.
--   entries: array of tables (from Bindings.GetEntriesForMask), typically
--            already sorted by caller.
--     - Each entry may include:
--         e.btn        (string)
--         e.action     (string)
--         e.actionText (string) -- optional (colorized + cooldown suffix)
--         e.manaText   (string) -- optional (colorized)
--
-- Notes:
--   • This module intentionally does not decide “what to show” — only “how to
--     show it.” Filtering/sorting/formatting policy stays in the entrypoint.
-- -----------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

local U = ns.Util

-- -----------------------------------------------------------------------------
-- UI.Create
-- -----------------------------------------------------------------------------
-- Creates the tooltip frame and control helpers.
--
-- @param config table
-- @return Frame tip
function UI.Create(config)
    local tip = CreateFrame("Frame", "HoverCastsTip", UIParent, "BackdropTemplate")
    tip:SetScale(config.scale or 1)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:SetAlpha(0)
    tip:Hide()

    tip:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    tip:SetBackdropColor(0.05, 0.05, 0.06, config.bgAlpha or 0.92)
    tip:SetBackdropBorderColor(0.35, 0.35, 0.38, config.borderAlpha or 0.90)

    -- Header (unit info)
    tip.header = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.header:SetPoint("TOPLEFT", config.padding, -config.padding)
    tip.header:SetJustifyH("LEFT")

    -- Modifier line (e.g. "[Shift+Ctrl]" already colored by caller)
    tip.modLine = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tip.modLine:SetPoint("TOPLEFT", tip.header, "BOTTOMLEFT", 0, -(config.lineSpacing + 3))
    tip.modLine:SetJustifyH("LEFT")

    -- Hidden measuring strings to get accurate widths for each column style.
    tip.measureBtn  = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tip.measureAct  = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.measureMana = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.measureBtn:Hide(); tip.measureAct:Hide(); tip.measureMana:Hide()

    -- Row pool (fixed number of rows; we show/hide as needed).
    tip.rows = {}
    local ROW_H = 12

    for i = 1, config.maxLines do
        local row = CreateFrame("Frame", nil, tip)
        row:SetHeight(ROW_H)

        if i == 1 then
            row:SetPoint("TOPLEFT", tip.modLine, "BOTTOMLEFT", -config.padding, -(config.lineSpacing + 4))
            row:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", tip.rows[i-1], "BOTTOMLEFT", 0, -config.lineSpacing)
            row:SetPoint("TOPRIGHT", tip.rows[i-1], "BOTTOMRIGHT", 0, -config.lineSpacing)
        end

        -- Left column: Button name
        row.button = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.button:SetPoint("LEFT", row, "LEFT", config.padding, 0)
        row.button:SetJustifyH("LEFT")

        -- Right column: Mana
        row.mana = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.mana:SetPoint("RIGHT", row, "RIGHT", -config.padding, 0)
        row.mana:SetJustifyH("RIGHT")

        -- Middle column: Ability (anchors set dynamically during Render)
        row.action = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.action:SetJustifyH("LEFT")

        row:Hide()
        tip.rows[i] = row
    end

    -- -------------------------------------------------------------------------
    -- Cursor-relative positioning (smart flip + clamp)
    -- -------------------------------------------------------------------------
    -- Places tooltip away from cursor and clamps to screen bounds.
    function tip:SetCursorAnchoredPosition()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        x, y = x / s, y / s

        local w = self:GetWidth() or 0
        local h = self:GetHeight() or 0

        local pad = config.clampPadding or 10
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()

        -- Choose quadrant: right vs left, down vs up
        local placeRight = (x < uiW * 0.55)
        local placeDown  = (y > uiH * 0.45)

        local offX = config.cursorOffsetX or 40
        local offY = config.cursorOffsetY or -40

        local left = placeRight and (x + offX) or (x - offX - w)
        local top  = placeDown  and (y + offY) or (y - offY + h)

        -- Clamp within screen
        if left < pad then left = pad end
        if (left + w + pad) > uiW then left = uiW - w - pad end

        if top > (uiH - pad) then top = uiH - pad end
        if (top - h) < pad then top = pad + h end

        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    -- -------------------------------------------------------------------------
    -- Fade helpers
    -- -------------------------------------------------------------------------
    function tip:FadeIn()
        self:Show()
        if UIFrameFadeIn then
            UIFrameFadeIn(self, config.fadeInTime or 0.04, self:GetAlpha() or 0, 1)
        else
            self:SetAlpha(1)
        end
    end

    function tip:FadeOut()
        if UIFrameFadeOut then
            UIFrameFadeOut(self, config.fadeOutTime or 0.04, self:GetAlpha() or 1, 0)
        else
            self:SetAlpha(0)
            self:Hide()
        end
    end

    -- -------------------------------------------------------------------------
    -- Utility: Clear rows without touching data tables
    -- -------------------------------------------------------------------------
    function tip:ClearRows()
        for i = 1, config.maxLines do
            local row = self.rows[i]
            row.button:SetText("")
            row.action:SetText("")
            row.mana:SetText("")
            row.action:ClearAllPoints()
            row:Hide()
        end
    end

    return tip
end

-- -----------------------------------------------------------------------------
-- UI.Render
-- -----------------------------------------------------------------------------
-- Renders header/mod line + entries, measures columns, sizes tooltip,
-- and anchors the action column between button and mana.
--
-- @param tip Frame
-- @param config table
-- @param headerText string
-- @param modText string
-- @param entries table[]|nil
function UI.Render(tip, config, headerText, modText, entries)
    tip.header:SetText(headerText or "")
    tip.modLine:SetText(modText or "")

    tip:ClearRows()

    local shownCount = 0

    -- Fill rows
    if not entries or #entries == 0 then
        local row = tip.rows[1]
        row.button:SetText("")
        row.action:SetText("No bindings for this modifier set.")
        row.mana:SetText("")
        row:Show()
        shownCount = 1
    else
        shownCount = math.min(#entries, config.maxLines)
        for i = 1, shownCount do
            local row = tip.rows[i]
            local e = entries[i]

            row.button:SetText(e.btn or "")
            row.action:SetText(e.actionText or (e.action or ""))

            if e.manaText then
                row.mana:SetText(e.manaText)
            else
                row.mana:SetText("")
            end

            row:Show()
        end
    end

    -- Measure columns using hidden measuring strings (accurate widths)
    local maxBtnW, maxActionW, maxManaW = 0, 0, 0

    for i = 1, shownCount do
        local row = tip.rows[i]
        if row and row:IsShown() then
            maxBtnW    = math.max(maxBtnW,    U.MeasureFS(tip.measureBtn,  row.button:GetText()))
            maxManaW   = math.max(maxManaW,   U.MeasureFS(tip.measureMana, row.mana:GetText()))
            maxActionW = math.max(maxActionW, U.MeasureFS(tip.measureAct,  row.action:GetText()))
        end
    end

    local pad = config.padding or 6

    -- Action column starts after button column (plus a small gap)
    local actionX = pad + maxBtnW + (config.minActionGap or 4)
    if actionX < (config.minActionX or 0) then
        actionX = config.minActionX or 0
    end

    -- Tooltip width must fit: button + gap + action + gap + mana + padding
    local headerW = U.MeasureFS(tip.measureAct, tip.header:GetText()) + pad * 2
    local modW    = U.MeasureFS(tip.measureAct, tip.modLine:GetText()) + pad * 2

    local totalW =
        pad
        + maxBtnW
        + (config.minActionGap or 4)
        + maxActionW
        + (config.manaGap or 8)
        + maxManaW
        + pad

    local width = math.max(totalW, headerW, modW)

    -- Height: header + modLine + rows + padding
    local height =
        pad
        + (tip.header:GetStringHeight() or 0)
        + (config.lineSpacing + 3)
        + (tip.modLine:GetStringHeight() or 0)
        + (config.lineSpacing + 6)

    for i = 1, shownCount do
        local row = tip.rows[i]
        if row and row:IsShown() then
            height = height + row:GetHeight() + (config.lineSpacing or 1)
        end
    end

    height = height + pad

    tip:SetSize(width, height)

    -- Anchor action between button and mana column (right inset reserves mana)
    local inset = pad + (config.manaGap or 8) + maxManaW

    for i = 1, shownCount do
        local row = tip.rows[i]
        if row and row:IsShown() then
            row.action:ClearAllPoints()
            row.action:SetPoint("LEFT", row, "LEFT", actionX, 0)
            row.action:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
        end
    end
end
