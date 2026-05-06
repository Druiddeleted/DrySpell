local addonName = select(1, ...)
local addon = select(2, ...)

local Database = {}
addon.Database = Database

-- AceDB defaults. SavedVariables key is DrySpellDB; everything is account-wide
-- (under .global) so sessions and stats span all characters automatically.
local defaults = {
    global = {
        debug = false,
        idleGraceSeconds = addon.Constants.idleGraceSeconds,
        countAbandonedInStats = true,
        timeFormat = addon.Constants.timeFormat.TWELVE,
        dateFormat = addon.Constants.dateFormat.SLASH_MDY,
        notifyOnAccepted = true,
        notifyOnSessionEnd = true,
        sessions = {},        -- list of finalized sessions, oldest -> newest
        characters = {},      -- key = "Realm-Name" -> { class, classLocalized, level, ... }
        minimap = {           -- LibDBIcon profile
            hide = false,
            lock = false,
            minimapPos = 215,
        },
        weekAnchor = nil,     -- captured once: a weeklyReset moment used to bucket history into weeks
    },
}

function Database:Initialize()
    local AceDB = LibStub("AceDB-3.0")
    self.db = AceDB:New("DrySpellDB", defaults, "Default")

    -- Capture a stable weekly-reset anchor the first time we know one. Used
    -- to bucket finished sessions into weeks for "this week" stats.
    if not self.db.global.weekAnchor then
        local anchor = addon.Utils:GetCurrentWeekStart()
        if anchor and anchor > 0 then
            self.db.global.weekAnchor = anchor
        end
    end
end

function Database:UpdateCharacterInfo()
    local key = addon.Utils:CharKey()
    local entry = self.db.global.characters[key] or {}
    entry.class = select(2, UnitClass("player"))
    entry.classLocalized = UnitClass("player")
    entry.level = UnitLevel("player")
    local race, raceFile = UnitRace("player")
    entry.race = raceFile
    entry.raceLocalized = race
    entry.faction = UnitFactionGroup("player")
    entry.lastSeen = time()
    self.db.global.characters[key] = entry
end

function Database:GetSessions()
    return self.db.global.sessions
end

-- Append a finalized session record. Trim to a sane history cap.
local MAX_HISTORY = 500
function Database:AppendSession(session)
    table.insert(self.db.global.sessions, session)
    while #self.db.global.sessions > MAX_HISTORY do
        table.remove(self.db.global.sessions, 1)
    end
end

-- Returns the start-of-current-week unix time, using the saved anchor when
-- available so it stays consistent for the whole week.
function Database:GetCurrentWeekStart()
    local now = time()
    local anchor = self.db.global.weekAnchor
    if not anchor then
        anchor = addon.Utils:GetCurrentWeekStart()
        if anchor and anchor > 0 then
            self.db.global.weekAnchor = anchor
        else
            return now - addon.Constants.weekSeconds
        end
    end
    local week = addon.Constants.weekSeconds
    local weeksSinceAnchor = math.floor((now - anchor) / week)
    return anchor + weeksSinceAnchor * week
end
