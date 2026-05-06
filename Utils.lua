local addonName = select(1, ...)
local addon = select(2, ...)

local Utils = {}
addon.Utils = Utils

function Utils:SetBackgroundColor(frame, r, g, b, a)
    if not frame.bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints(frame)
    end
    frame.bg:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
end

function Utils:TableCount(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Utils:TableForEach(t, fn)
    if not t then return end
    for k, v in pairs(t) do fn(v, k) end
end

function Utils:TableFind(t, predicate)
    if not t then return nil end
    for _, v in pairs(t) do
        if predicate(v) then return v end
    end
end

function Utils:TableFilter(t, predicate)
    local out = {}
    for _, v in ipairs(t or {}) do
        if predicate(v) then table.insert(out, v) end
    end
    return out
end

function Utils:TableMergeConfig(dest, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" and type(dest[k]) == "table" then
            self:TableMergeConfig(dest[k], v)
        else
            dest[k] = v
        end
    end
    return dest
end

function Utils:CharKey()
    local realm = GetRealmName() or "?"
    local name = UnitName("player") or "?"
    return realm .. "-" .. name
end

-- Format a duration in seconds as a compact human string.
function Utils:FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then
        return seconds .. "s"
    end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m < 60 then
        return string.format("%dm %02ds", m, s)
    end
    local h = math.floor(m / 60)
    m = m % 60
    if h < 24 then
        return string.format("%dh %02dm", h, m)
    end
    local d = math.floor(h / 24)
    h = h % 24
    return string.format("%dd %02dh", d, h)
end

-- Returns the unix-time of the most recent weekly reset moment.
-- Stable across calls within a week, since it's anchored to GetSecondsUntilWeeklyReset.
function Utils:GetCurrentWeekStart()
    local secondsUntil = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset)
        and C_DateAndTime.GetSecondsUntilWeeklyReset() or nil
    if not secondsUntil then
        return time() - addon.Constants.weekSeconds
    end
    local nextReset = time() + secondsUntil
    return nextReset - addon.Constants.weekSeconds
end

-- Active time format ("12h" / "24h"). Falls back to the constant default
-- before the database is ready (e.g. very early in addon load).
function Utils:GetTimeFormat()
    local g = DrySpellDB and DrySpellDB.global
    local fmt = g and g.timeFormat
    if fmt == addon.Constants.timeFormat.TWENTY_FOUR or fmt == addon.Constants.timeFormat.TWELVE then
        return fmt
    end
    return addon.Constants.timeFormat.TWELVE
end

-- Format a unix time as just the time of day, honoring the user's preference.
-- 12h: "3:14:07 pm" / "3:14 pm". 24h: "15:14:07" / "15:14".
function Utils:FormatTimeOfDay(t, withSeconds)
    if not t then return "-" end
    if withSeconds == nil then withSeconds = true end
    if self:GetTimeFormat() == addon.Constants.timeFormat.TWENTY_FOUR then
        return withSeconds and date("%H:%M:%S", t) or date("%H:%M", t)
    end
    -- date("%I") gives 01-12 with a leading zero; trim it for cleaner display.
    local h = tonumber(date("%I", t)) or 12
    if withSeconds then
        return string.format("%d:%s %s", h, date("%M:%S", t), date("%p", t):lower())
    end
    return string.format("%d:%s %s", h, date("%M", t), date("%p", t):lower())
end

-- Active date format ("slash_mdy", "iso", etc.). Falls back to slash_mdy.
function Utils:GetDateFormat()
    local g = DrySpellDB and DrySpellDB.global
    local fmt = g and g.dateFormat
    local D = addon.Constants.dateFormat
    for _, v in pairs(D) do if v == fmt then return fmt end end
    return D.SLASH_MDY
end

-- Format a unix time as just the date, honoring the user's preference.
function Utils:FormatDate(t)
    if not t then return "-" end
    local D = addon.Constants.dateFormat
    local fmt = self:GetDateFormat()
    if fmt == D.SLASH_MDY then return date("%m/%d/%Y", t)
    elseif fmt == D.SLASH_DMY then return date("%d/%m/%Y", t)
    elseif fmt == D.DASH_MDY  then return date("%m-%d-%Y", t)
    elseif fmt == D.ISO       then return date("%Y-%m-%d", t)
    elseif fmt == D.LONG      then return date("%B %-d, %Y", t)
    elseif fmt == D.SHORT     then return date("%b %d", t)
    end
    return date("%m/%d/%Y", t)
end

-- Format a unix time as a date + time of day (no seconds), combining the
-- two helpers. e.g. "05/05/2026 3:14 pm" or "2026-05-05 15:14".
function Utils:FormatDateTime(t)
    if not t then return "-" end
    return self:FormatDate(t) .. " " .. self:FormatTimeOfDay(t, false)
end

-- Friendly label for an LFG/spec role string. `GetSpecializationInfo` returns
-- "TANK" / "HEALER" / "DAMAGER" — the last one in particular reads weird in
-- the UI, so map it to "DPS".
local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
function Utils:RoleLabel(role)
    if not role or role == "" then return "?" end
    return ROLE_LABELS[role] or role
end

-- Localized class color (returns r,g,b,a or white if unknown).
function Utils:ClassColor(classFile)
    if not classFile then return 1, 1, 1, 1 end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b, 1 end
    return 1, 1, 1, 1
end

function Utils:Print(...)
    print(addon.Constants.prefix .. table.concat({...}, " "))
end

function Utils:Debug(fmt, ...)
    if not (DrySpellDB and DrySpellDB.global and DrySpellDB.global.debug) then return end
    local msg = (select("#", ...) > 0) and fmt:format(...) or fmt
    print(addon.Constants.prefix .. "|cff888888" .. msg .. "|r")
end
