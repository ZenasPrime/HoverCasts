-- UI.lua
-- Tooltip UI: build rows, size/measure columns, smart positioning, fade.

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local U = ns.Util

-- Creates and returns the tooltip frame + helpers.
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

    tip.header = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.header:SetPoint("TOPLEFT", config.padding, -config.padding)
    tip.header:SetJustifyH("LEFT")

    tip.modLine = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tip.modLine:SetPoint("TOPLEFT", tip.header, "BOTTOMLEFT", 0, -(config.lineSpacing + 3))
    tip.modLine:SetJustifyH("LEFT")

    -- Hidden measure strings (for accurate widths)
    tip.measureBtn  = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tip.measureAct  = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.measureMana = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip.measureBtn:Hide(); tip.measureAct:Hide(); tip.measureMana:Hide()

    -- Rows
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

        row.button = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.button:SetPoint("LEFT", row, "LEFT", config.padding, 0)
        row.button:SetJustifyH("LEFT")

        row.mana = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.mana:SetPoint("RIGHT", row, "RIGHT", -config.padding, 0)
        row.mana:SetJustifyH("RIGHT")

        row.action = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.action:SetJustifyH("LEFT")

        row:Hide()
        tip.rows[i] = row
    end

    -- Positioning
    function tip:SetCursorAnchoredPosition()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        x, y = x / s, y / s

        local w = self:GetWidth() or 0
        local h = self:GetHeight() or 0

        local pad = config.clampPadding or 10
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()

        local placeRight = (x < uiW * 0.55)
        local placeDown  = (y > uiH * 0.45)

        local offX = config.cursorOffsetX or 40
        local offY = config.cursorOffsetY or -40

        local left = placeRight and (x + offX) or (x - offX - w)
        local top  = placeDown  and (y + offY) or (y - offY + h)

        if left < pad then left = pad end
        if (left + w + pad) > uiW then left = uiW - w - pad end

        if top > (uiH - pad) then top = uiH - pad end
        if (top - h) < pad then top = pad + h end

        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    -- Fade helpers
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

    -- Row clear
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

-- Renders rows and sizes tooltip.
-- Inputs:
--   tip: tooltip
--   config: config table
--   headerText: string (already colorized)
--   modText: string (already wrapped/colored as desired)
--   entries: list from Bindings.GetEntriesForMask (already sorted by caller)
function UI.Render(tip, config, headerText, modText, entries)
    tip.header:SetText(headerText or "")
    tip.modLine:SetText(modText or "")

    tip:ClearRows()

    local shownCount = 0
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

    -- Measure columns
    local maxBtnW, maxActionW, maxManaW = 0, 0, 0
    for i = 1, shownCount do
        local row = tip.rows[i]
        if row and row:IsShown() then
            maxBtnW = math.max(maxBtnW, U.MeasureFS(tip.measureBtn, row.button:GetText()))
            maxManaW = math.max(maxManaW, U.MeasureFS(tip.measureMana, row.mana:GetText()))
            maxActionW = math.max(maxActionW, U.MeasureFS(tip.measureAct, row.action:GetText()))
        end
    end

    local pad = config.padding or 6
    local actionX = pad + maxBtnW + (config.minActionGap or 4)
    if actionX < (config.minActionX or 0) then actionX = config.minActionX or 0 end

    local headerW = U.MeasureFS(tip.measureAct, tip.header:GetText()) + pad * 2
    local modW    = U.MeasureFS(tip.measureAct, tip.modLine:GetText()) + pad * 2
    local totalW  = pad + maxBtnW + (config.minActionGap or 4) + maxActionW + (config.manaGap or 8) + maxManaW + pad
    local width   = math.max(totalW, headerW, modW)

    -- Height
    local height = pad
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

    -- Anchor action between button and mana column
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
