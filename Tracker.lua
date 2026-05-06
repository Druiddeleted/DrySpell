local addonName = select(1, ...)
local addon = select(2, ...)

-- The Tracker owns the in-memory "current session" state machine and turns
-- raw C_LFGList events into structured session records. When a session ends
-- (success/abandoned/manual) it appends a record to the database via
-- addon.Database:AppendSession.
--
-- Vocabulary:
--   * application = your sign-up to one specific premade group (one resultID)
--   * session     = the span from your first sign-up while idle to either an
--                   accept (success) or idle-grace expiry (abandoned)
--
-- A session contains many applications. Each application has a terminal status.

local Tracker = {}
addon.Tracker = Tracker
Tracker.session = nil      -- nil when no session is currently active
Tracker.idleTimer = nil
Tracker.callbacks = {}     -- listeners notified when current-session state changes

local C = addon.Constants

-- Subscribe to "session changed" events. Cheap callback fan-out used by the
-- live current-session UI to refresh.
function Tracker:Subscribe(fn)
    table.insert(self.callbacks, fn)
end

local function fireCallbacks()
    for _, fn in ipairs(Tracker.callbacks) do
        local ok, err = pcall(fn)
        if not ok then addon.Utils:Debug("callback error: %s", tostring(err)) end
    end
end

-- Build a snapshot of the current player. Captured once at session start so
-- the session record reflects who was queueing (spec/ilvl can change later).
-- Read the player's current spec/role. May return nil on freshly-logged-in
-- characters before talent data syncs; callers should treat nil as "unknown"
-- and try again later.
local function readCurrentSpec()
    if not GetSpecialization then return nil, nil end
    local idx = GetSpecialization()
    if not idx or idx < 1 then return nil, nil end
    if GetSpecializationInfo then
        local _, name, _, _, role = GetSpecializationInfo(idx)
        return name, role
    end
    return nil, nil
end

local function snapshotPlayer()
    local classLocalized, classFile = UnitClass("player")
    local specName, specRole = readCurrentSpec()
    local equipped = select(2, GetAverageItemLevel())
    return {
        key = addon.Utils:CharKey(),
        name = UnitName("player"),
        realm = GetRealmName(),
        class = classFile,
        classLocalized = classLocalized,
        level = UnitLevel("player"),
        specName = specName,
        specRole = specRole,
        ilvl = equipped and math.floor(equipped + 0.5) or nil,
    }
end

-- Heal up the current session's player snapshot if any fields are nil and the
-- live API now has them. Cheap to call from the Current window's refresh.
function Tracker:RefreshPlayerSnapshot()
    local s = self.session
    if not s or not s.player then return end
    local p = s.player
    if not p.specName or not p.specRole then
        local n, r = readCurrentSpec()
        if n then p.specName = n end
        if r then p.specRole = r end
    end
    if not p.classLocalized then
        local cl, cf = UnitClass("player")
        p.classLocalized = cl
        if not p.class then p.class = cf end
    end
    if not p.ilvl then
        local equipped = select(2, GetAverageItemLevel())
        if equipped and equipped > 0 then p.ilvl = math.floor(equipped + 0.5) end
    end
end

-- Look up a search result and produce a stable snapshot of the group's
-- public-facing data. Some fields can change later (numMembers, isDelisted),
-- so we capture them at apply time and again at terminal time.
-- Resolve the activity descriptor for a search result. The retail API exposes
-- both `activityID` (legacy single) and `activityIDs` (table); some patches
-- only populate one. Returns the first valid entry, or nil.
local function pickActivityID(info)
    if not info then return nil end
    if info.activityID and info.activityID > 0 then return info.activityID end
    if info.activityIDs then
        for _, id in ipairs(info.activityIDs) do
            if id and id > 0 then return id end
        end
    end
    return nil
end

local function snapshotGroup(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return nil end
    local activityID = pickActivityID(info)
    -- iLvl is the modern field name on the result struct; older docs called
    -- it requiredItemLevel. Prefer iLvl, fall back if it shows up.
    local groupIlvl = info.iLvl or info.requiredItemLevel
    local snap = {
        resultID    = resultID,
        activityID  = activityID,
        name        = info.name,
        comment     = info.comment,
        leaderName  = info.leaderName,
        numMembers  = info.numMembers,
        groupIlvl   = (groupIlvl and groupIlvl > 0) and groupIlvl or nil,
        isDelisted  = info.isDelisted,
        autoAccept  = info.autoAccept,
        age         = info.age,
        voiceChat   = info.voiceChat,
    }
    if activityID and C_LFGList.GetActivityInfoTable then
        local a = C_LFGList.GetActivityInfoTable(activityID)
        if a then
            snap.activityFullName   = a.fullName
            snap.activityShortName  = a.shortName
            snap.categoryID         = a.categoryID
            snap.activityGroupID    = a.groupFinderActivityGroupID
            snap.maxNumPlayers      = a.maxNumPlayers
            snap.minLevel           = a.minLevel
            snap.useHonorLevel      = a.useHonorLevel
            snap.displayType        = a.displayType
        end
    end
    -- Category (Dungeons, Raids, PvP, Custom, etc.).
    if snap.categoryID and C_LFGList.GetCategoryInfo then
        local catName = C_LFGList.GetCategoryInfo(snap.categoryID)
        snap.categoryName = catName
    end
    -- Activity group = the difficulty bucket (Mythic+, Heroic, Raid Finder, ...).
    if snap.activityGroupID and snap.activityGroupID > 0 and C_LFGList.GetActivityGroupInfo then
        local diffName = C_LFGList.GetActivityGroupInfo(snap.activityGroupID)
        snap.difficultyName = diffName
    end
    -- Per-role member counts. Newer retail returns a struct; some patches
    -- return 4 separate values. Handle both shapes.
    if C_LFGList.GetSearchResultMemberCounts then
        local r1, r2, r3, r4 = C_LFGList.GetSearchResultMemberCounts(resultID)
        if type(r1) == "table" then
            snap.tankCount    = r1.TANK    or r1.TANKS    or 0
            snap.healerCount  = r1.HEALER  or r1.HEALERS  or 0
            snap.damagerCount = r1.DAMAGER or r1.DAMAGERS or 0
            snap.norolerCount = r1.NOROLE  or 0
        elseif type(r1) == "number" then
            snap.tankCount, snap.healerCount, snap.damagerCount, snap.norolerCount = r1, r2 or 0, r3 or 0, r4 or 0
        end
    end
    return snap
end

local function newSession()
    return {
        startedAt    = time(),
        endedAt      = nil,
        outcome      = "active",   -- "success" | "abandoned" | "manual" | "active"
        player       = snapshotPlayer(),
        applications = {},
        appOrder     = {},          -- ordered list of resultIDs as we saw them
        declineCount = 0,           -- counts decline-flavored terminations only
        delistCount  = 0,
        timeoutCount = 0,
        otherCount   = 0,           -- self-cancels, declined-by-you, failed-other
        acceptedAt   = nil,
        acceptedGroup = nil,
    }
end

-- Persist the in-memory active session into SavedVariables so a /reload or
-- crash doesn't lose it. Cheap (one assignment) so we call it on every state
-- change.
local function persistActive()
    if not (addon.Database and addon.Database.db) then return end
    addon.Database.db.global.activeSession = Tracker.session
    addon.Database.db.global.activeSessionSavedAt = time()
end

local function clearActive()
    if not (addon.Database and addon.Database.db) then return end
    addon.Database.db.global.activeSession = nil
    addon.Database.db.global.activeSessionSavedAt = nil
end

local function ensureSession()
    if Tracker.session then return Tracker.session end
    Tracker.session = newSession()
    addon.Utils:Debug("session started for %s", Tracker.session.player.key)
    persistActive()
    fireCallbacks()
    return Tracker.session
end

local function cancelIdleTimer()
    if Tracker.idleTimer then
        Tracker.idleTimer:Cancel()
        Tracker.idleTimer = nil
    end
end

-- Compute number of "open" (non-terminal) applications in the current session.
local function openApplicationCount()
    local s = Tracker.session
    if not s then return 0 end
    local n = 0
    for _, app in pairs(s.applications) do
        if not app.endedAt then n = n + 1 end
    end
    return n
end

local function printSessionSummary(s)
    local g = addon.Database and addon.Database.db and addon.Database.db.global
    if not g or g.notifyOnSessionEnd == false then return end
    local outcomeText = ({
        success   = "|cff66ff66accepted|r",
        abandoned = "|cffaaaaaaabandoned|r",
        manual    = "|cffaaaaaaended manually|r",
    })[s.outcome] or s.outcome or "?"
    local p = s.player or {}
    local who = (p.name or "?") .. (p.specName and ("  " .. p.specName) or "")
        .. (p.specRole and ("  " .. addon.Utils:RoleLabel(p.specRole)) or "")
    local rule = "|cffffd200" .. string.rep("-", 48) .. "|r"
    local rejections = (s.declineCount or 0) + (s.delistCount or 0) + (s.timeoutCount or 0)
    local total = 0
    for _ in pairs(s.applications or {}) do total = total + 1 end
    print(rule)
    print(string.format("|cffffd200Session %s|r — %s", outcomeText, who))
    print(string.format("  Duration: %s    Applications: %d    Rejections: %d (%d declines, %d delists, %d timeouts)",
        addon.Utils:FormatDuration(s.duration or 0),
        total, rejections,
        s.declineCount or 0, s.delistCount or 0, s.timeoutCount or 0))
    print(rule)
end

local function finalizeSession(outcome)
    local s = Tracker.session
    if not s then return end
    cancelIdleTimer()
    s.endedAt = time()
    s.outcome = outcome
    s.duration = s.endedAt - s.startedAt
    -- Streak count: declines + delists + timeouts (the "rejection" buckets).
    s.streakCount = s.declineCount + s.delistCount + s.timeoutCount
    addon.Database:AppendSession(s)
    addon.Utils:Debug("session %s after %ds with %d rejections", outcome, s.duration, s.streakCount)
    printSessionSummary(s)
    Tracker.session = nil
    clearActive()
    fireCallbacks()
end

-- After all current applications terminate, start a grace timer. If a new
-- application doesn't show up within the grace window we finalize the
-- session as abandoned.
local function maybeStartIdleTimer()
    if not Tracker.session then return end
    if openApplicationCount() > 0 then return end
    cancelIdleTimer()
    local grace = (DrySpellDB and DrySpellDB.global and DrySpellDB.global.idleGraceSeconds)
        or C.idleGraceSeconds
    Tracker.idleTimer = C_Timer.NewTimer(grace, function()
        Tracker.idleTimer = nil
        if Tracker.session and openApplicationCount() == 0 then
            finalizeSession("abandoned")
        end
    end)
end

-- Public: end the current session manually (e.g. user clicks "End session").
function Tracker:EndCurrentSession()
    if not self.session then return end
    finalizeSession("manual")
end

function Tracker:GetCurrentSession()
    return self.session
end

-- Print a prominent on-screen + chat notification when an application is
-- accepted. Gated on the notifyOnAccepted setting so users who don't want
-- the noise can turn it off.
function Tracker:NotifyAccepted(app, session)
    local g = addon.Database and addon.Database.db and addon.Database.db.global
    if not g or g.notifyOnAccepted == false then return end

    local snap = app.groupAtEnd or app.groupAtApply or {}
    local title    = app.title or snap.name or "(no title)"
    local leader   = snap.leaderName or "?"
    local activity = snap.activityFullName or snap.activityShortName or "?"
    local diff     = snap.difficultyName or snap.categoryName

    -- Big centered banner — same surface raid warnings use, can't miss it.
    if RaidNotice_AddMessage and RaidBossEmoteFrame then
        RaidNotice_AddMessage(RaidBossEmoteFrame,
            "DrySpell: invite accepted!",
            ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.5, b = 0 })
    end
    if PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.READY_CHECK or 8960)
    end

    -- Multi-line chat block. Border lines + colored header so it's hard to
    -- miss in a busy chat frame.
    local rule = "|cffffd200" .. string.rep("=", 48) .. "|r"
    print(rule)
    print("|cff66ff66Accepted:|r |cffffffff" .. title .. "|r")
    local activityLine = activity
    if diff and diff ~= "" then activityLine = activityLine .. " — " .. diff end
    print("  " .. activityLine .. "  |cffaaaaaa(leader: " .. leader .. ")|r")
    if session then
        local elapsed = (session.acceptedAt or time()) - (session.startedAt or time())
        local rejections = (session.declineCount or 0) + (session.delistCount or 0) + (session.timeoutCount or 0)
        print(string.format("  After %s and %d rejection(s).",
            addon.Utils:FormatDuration(elapsed), rejections))
    end
    print(rule)
end

-- Handle one application status update.
local function handleApplicationStatus(resultID, newStatus, oldStatus)
    if not resultID or not newStatus then return end
    addon.Utils:Debug("app %s: %s -> %s", tostring(resultID), tostring(oldStatus), tostring(newStatus))

    -- Invite accepted -> session success regardless of prior state.
    if newStatus == C.successStatus then
        local s = ensureSession()
        local app = s.applications[resultID]
        if not app then
            app = { resultID = resultID, appliedAt = time(), groupAtApply = snapshotGroup(resultID) }
            s.applications[resultID] = app
            table.insert(s.appOrder, resultID)
        end
        app.endedAt = time()
        app.terminalStatus = "accepted"
        app.groupAtEnd = snapshotGroup(resultID)
        s.acceptedAt = time()
        s.acceptedGroup = app.groupAtEnd or app.groupAtApply
        Tracker:NotifyAccepted(app, s)
        finalizeSession("success")
        return
    end

    -- Track new applications. Apply moments may show up as either a transition
    -- to "applied" or with the resultID already in C_LFGList.GetApplications().
    if newStatus == C.appliedStatus or newStatus == C.invitedStatus then
        local s = ensureSession()
        if not s.applications[resultID] then
            local snap = snapshotGroup(resultID)
            -- Sticky title: store on the app directly so even if the group
            -- delists (and the snapshot becomes nil) we never lose the name
            -- the user actually saw when they clicked Sign Up.
            local app = {
                resultID     = resultID,
                appliedAt    = time(),
                groupAtApply = snap,
                title        = snap and snap.name or nil,
            }
            s.applications[resultID] = app
            table.insert(s.appOrder, resultID)
            cancelIdleTimer()
            -- If the search-result cache wasn't ready yet, retry on a short
            -- delay so the title isn't permanently nil for this app.
            if not app.title then
                C_Timer.After(0.5, backfillMissingTitles)
                C_Timer.After(2.0, backfillMissingTitles)
            end
            fireCallbacks()
        end
        return
    end

    -- Anything else is potentially terminal. If we have no session there's
    -- nothing to record.
    local s = Tracker.session
    if not s then return end
    local app = s.applications[resultID]
    if not app then
        -- Terminal status for an application we never saw the apply event for
        -- (race / addon load). Synthesize one so we can still record it.
        local snap = snapshotGroup(resultID)
        app = {
            resultID     = resultID,
            appliedAt    = time(),
            groupAtApply = snap,
            title        = snap and snap.name or nil,
        }
        s.applications[resultID] = app
        table.insert(s.appOrder, resultID)
    end
    if app.endedAt then return end  -- already finalized

    app.endedAt = time()
    app.terminalStatus = newStatus
    -- Re-snapshot at terminal time, but never let a nil/empty result wipe
    -- a name we already captured at apply time.
    local endSnap = snapshotGroup(resultID)
    app.groupAtEnd = endSnap
    if endSnap and endSnap.name and endSnap.name ~= "" then
        app.title = endSnap.name
    end

    if C.declineStatuses[newStatus] then
        if newStatus == "declined_delisted" then
            s.delistCount = s.delistCount + 1
        elseif newStatus == "timedout" then
            s.timeoutCount = s.timeoutCount + 1
        else
            s.declineCount = s.declineCount + 1
        end
    elseif C.selfCancelStatuses[newStatus] then
        s.otherCount = s.otherCount + 1
    else
        s.otherCount = s.otherCount + 1
    end

    fireCallbacks()
    maybeStartIdleTimer()
end

-- Walk every application in the current session and try to fill in a usable
-- title/group snapshot for those that didn't capture one at apply time. This
-- handles the case where C_LFGList.GetSearchResultInfo wasn't ready yet (early
-- in /reload, or right after sign-up before the search cache warms).
local function backfillMissingTitles()
    local s = Tracker.session
    if not s then return end
    local refreshed = false
    for _, app in pairs(s.applications) do
        if not app.title or app.title == "" then
            local snap = snapshotGroup(app.resultID)
            if snap and snap.name and snap.name ~= "" then
                app.title = snap.name
                if not app.groupAtApply or not app.groupAtApply.name then
                    app.groupAtApply = snap
                else
                    -- Merge any newly-available fields without clobbering
                    -- existing ones.
                    for k, v in pairs(snap) do
                        if app.groupAtApply[k] == nil then app.groupAtApply[k] = v end
                    end
                end
                refreshed = true
            end
        end
    end
    if refreshed then fireCallbacks() end
end
Tracker.BackfillMissingTitles = backfillMissingTitles

-- LFG_LIST_SEARCH_RESULT_UPDATED fires when a posted group changes (members
-- joining/leaving, comment edits, delisting). For groups we've applied to,
-- a delisting eventually surfaces as a declined_delisted status update — but
-- some clients can be slow about that, so we also probe the application info
-- here as a safety net. Also a great moment to backfill any missing titles.
local function handleSearchResultUpdated(resultID)
    if not (C_LFGList and C_LFGList.GetApplicationInfo) then return end
    local s = Tracker.session
    if not s then return end
    local app = s.applications[resultID]
    if not app or app.endedAt then return end
    local info = C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(resultID)
    if info and not (app.title and app.title ~= "") and info.name and info.name ~= "" then
        local snap = snapshotGroup(resultID)
        if snap then
            app.title = snap.name
            app.groupAtApply = app.groupAtApply or snap
            fireCallbacks()
        end
    end
    if info and info.isDelisted then
        handleApplicationStatus(resultID, "declined_delisted", nil)
    end
end

-- Restore an in-flight session that was persisted before a /reload or crash.
-- If too much time has elapsed (more than the idle grace), finalize it as
-- abandoned instead of resuming. Otherwise resume in place and rearm the
-- idle timer based on remaining elapsed.
local function restorePersistedSession()
    local g = addon.Database and addon.Database.db and addon.Database.db.global
    if not g or not g.activeSession then return end
    local stored = g.activeSession
    local savedAt = g.activeSessionSavedAt or stored.startedAt or time()
    local grace = g.idleGraceSeconds or C.idleGraceSeconds
    local elapsedSinceSave = time() - savedAt
    Tracker.session = stored
    if elapsedSinceSave > grace and openApplicationCount() == 0 then
        addon.Utils:Debug("restored session past grace (%ds) -> abandoning", elapsedSinceSave)
        finalizeSession("abandoned")
        return
    end
    addon.Utils:Debug("restored active session (saved %ds ago)", elapsedSinceSave)
    fireCallbacks()
    -- Backfill any titles that didn't capture pre-reload, and retry on a
    -- short delay since C_LFGList may not be fully ready yet at init time.
    backfillMissingTitles()
    C_Timer.After(2.0, backfillMissingTitles)
    C_Timer.After(5.0, backfillMissingTitles)
    -- Rearm idle timer if no open apps. Use what's left of the grace window.
    if openApplicationCount() == 0 then
        local remaining = math.max(1, grace - elapsedSinceSave)
        cancelIdleTimer()
        Tracker.idleTimer = C_Timer.NewTimer(remaining, function()
            Tracker.idleTimer = nil
            if Tracker.session and openApplicationCount() == 0 then
                finalizeSession("abandoned")
            end
        end)
    end
end

function Tracker:Initialize()
    local Events = addon.Events
    Events:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED",
        function(_, _, resultID, newStatus, oldStatus)
            handleApplicationStatus(resultID, newStatus, oldStatus)
            persistActive()
        end, true)
    Events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED",
        function(_, _, resultID)
            handleSearchResultUpdated(resultID)
            persistActive()
        end, true)
    -- Player switched chars / loaded in: refresh character row.
    Events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        addon.Database:UpdateCharacterInfo()
    end, true)
    Events:RegisterEvent({"PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_UP"}, function()
        addon.Database:UpdateCharacterInfo()
    end, true)
    -- Final persist on logout/reload so the latest state is saved even if no
    -- LFG events fired since the last persist.
    Events:RegisterEvent("PLAYER_LOGOUT", function()
        persistActive()
    end, true)
    restorePersistedSession()
end
