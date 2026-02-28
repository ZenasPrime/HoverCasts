-- Settings.lua
-- SavedVariables + accessors for HoverCasts options.

local ADDON_NAME, ns = ...
ns.Settings = ns.Settings or {}
local S = ns.Settings

-- IMPORTANT:
-- Add this to your .toc:
-- ## SavedVariables: HoverCastsDB

local DEFAULTS = {
    frames = {
        party  = true,
        raid   = true,
        focus  = true,

        -- NEW (requested):
        player = false,
        target = false,  -- (useful paired with player)
        enemy  = false,  -- optional “enemy-ish” units (ToT, focus target, etc.)
        world  = false,  -- allow UnitExists("mouseover") world units
    }
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = type(dst[k]) == "table" and dst[k] or {}
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function S:Init()
    HoverCastsDB = HoverCastsDB or {}
    CopyDefaults(HoverCastsDB, DEFAULTS)
end

function S:GetFrames()
    if not HoverCastsDB or not HoverCastsDB.frames then
        return DEFAULTS.frames
    end
    return HoverCastsDB.frames
end

function S:SetFrameEnabled(key, enabled)
    if type(key) ~= "string" then return end
    if not HoverCastsDB then HoverCastsDB = {} end
    if type(HoverCastsDB.frames) ~= "table" then HoverCastsDB.frames = {} end
    if enabled == nil then
        HoverCastsDB.frames[key] = not not DEFAULTS.frames[key]
    else
        HoverCastsDB.frames[key] = not not enabled
    end
end

function S:ToggleFrame(key)
    local f = self:GetFrames()
    self:SetFrameEnabled(key, not f[key])
    return self:GetFrames()[key]
end

function S:FramesSummary()
    local f = self:GetFrames()
    local function yn(b) return b and "ON" or "OFF" end
    return ("party=%s raid=%s focus=%s player=%s target=%s enemy=%s world=%s"):format(
        yn(f.party), yn(f.raid), yn(f.focus),
        yn(f.player), yn(f.target), yn(f.enemy), yn(f.world)
    )
end