local addonName = select(1, ...)
local addon = select(2, ...)

-- Session history + statistics window. Shows two stat blocks (this week and
-- all time), then a scrolling list of finished sessions newest -> oldest.

local Module = {}
addon.Modules = addon.Modules or {}
addon.Modules.Sessions = Module

local ROW_H = 26
local COL_DATE_W = 120
local COL_CHAR_W = 140
local COL_ROLE_W = 90
local COL_RESULT_W = 100
local COL_DURATION_W = 90
local COL_REJECT_W = 70

local function fmtDate(t)
    return addon.Utils:FormatDateTime(t)
end

-- Returns: longestStreakCount, longestStreakDuration, totalSessions,
-- successCount, abandonedCount, totalRejections.
local function computeStats(sessions, sinceTime, activeSession)
    local includeAbandoned = (addon.Database.db.global.countAbandonedInStats ~= false)
    local longestCount, longestDuration = 0, 0
    local total, success, abandoned, rejections = 0, 0, 0, 0
    for _, s in ipairs(sessions) do
        local inWindow = (not sinceTime) or (s.endedAt and s.endedAt >= sinceTime)
        local include = inWindow and (includeAbandoned or s.outcome ~= "abandoned")
        if include then
            total = total + 1
            if s.outcome == "success" then success = success + 1
            elseif s.outcome == "abandoned" then abandoned = abandoned + 1 end
            local rc = (s.declineCount or 0) + (s.delistCount or 0) + (s.timeoutCount or 0)
            rejections = rejections + rc
            if rc > longestCount then longestCount = rc end
            local dur = s.duration or ((s.endedAt or time()) - (s.startedAt or 0))
            if dur > longestDuration then longestDuration = dur end
        end
    end
    -- Include the in-flight session in streak/duration stats (its current
    -- running totals can already be the longest), but don't count it toward
    -- "total / success / abandoned / rejections" — those are completion metrics.
    if activeSession then
        local inWindow = (not sinceTime) or (activeSession.startedAt and activeSession.startedAt >= sinceTime)
        if inWindow then
            local rc = (activeSession.declineCount or 0) + (activeSession.delistCount or 0) + (activeSession.timeoutCount or 0)
            if rc > longestCount then longestCount = rc end
            local dur = time() - (activeSession.startedAt or time())
            if dur > longestDuration then longestDuration = dur end
        end
    end
    return longestCount, longestDuration, total, success, abandoned, rejections
end

local function makeStatBlock(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(280, 96)
    addon.Utils:SetBackgroundColor(f, 0, 0, 0, 0.25)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.title:SetText(title)

    f.streakLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.streakLabel:SetPoint("TOPLEFT", 8, -28)
    f.streakLabel:SetText("Longest streak (rejections):")

    f.streakValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.streakValue:SetPoint("TOPRIGHT", -8, -28)

    f.durLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.durLabel:SetPoint("TOPLEFT", 8, -46)
    f.durLabel:SetText("Longest streak (time):")

    f.durValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.durValue:SetPoint("TOPRIGHT", -8, -46)

    f.totalsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.totalsLabel:SetPoint("TOPLEFT", 8, -66)
    f.totalsLabel:SetText("Sessions:")

    f.totalsValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.totalsValue:SetPoint("TOPRIGHT", -8, -66)

    function f:Update(streakCount, streakDur, total, success, abandoned, rejections)
        self.streakValue:SetText(tostring(streakCount or 0))
        self.durValue:SetText(addon.Utils:FormatDuration(streakDur or 0))
        self.totalsValue:SetText(string.format("%d (%d ok, %d abandoned, %d rejections)",
            total or 0, success or 0, abandoned or 0, rejections or 0))
    end
    return f
end

function Module:Build()
    local w = addon.Window:New({
        name = "Sessions",
        title = "DrySpell — session history",
        width = 760,
        height = 520,
    })

    -- Stat blocks at the top.
    local weekBlock = makeStatBlock(w.body, "This week")
    weekBlock:SetPoint("TOPLEFT", w.body, "TOPLEFT", 8, -8)
    local allBlock = makeStatBlock(w.body, "All time")
    allBlock:SetPoint("TOPLEFT", weekBlock, "TOPRIGHT", 8, 0)

    -- Header row for the session list.
    local header = CreateFrame("Frame", nil, w.body)
    header:SetPoint("TOPLEFT", weekBlock, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", w.body, "RIGHT", -8, 0)
    header:SetHeight(ROW_H)
    addon.Utils:SetBackgroundColor(header, 0, 0, 0, 0.4)

    local function addHeaderText(text, w_, x)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(w_)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        return fs
    end
    local x = 8
    addHeaderText("Ended",        COL_DATE_W,     x); x = x + COL_DATE_W
    addHeaderText("Character",    COL_CHAR_W,    x); x = x + COL_CHAR_W
    addHeaderText("Spec / Role",  COL_ROLE_W,    x); x = x + COL_ROLE_W
    addHeaderText("Outcome",      COL_RESULT_W,  x); x = x + COL_RESULT_W
    addHeaderText("Duration",     COL_DURATION_W, x); x = x + COL_DURATION_W
    addHeaderText("Rejections",   COL_REJECT_W,  x)

    -- Scrolling list of sessions.
    local scroll = CreateFrame("ScrollFrame", nil, w.body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", w.body, "BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local rowPool = {}

    local function getRow(i)
        local row = rowPool[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetSize(700, ROW_H)
        if i % 2 == 0 then
            addon.Utils:SetBackgroundColor(row, 1, 1, 1, 0.04)
        end
        local function makeText(width)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(width)
            fs:SetJustifyH("LEFT")
            return fs
        end
        local x_ = 8
        row.date = makeText(COL_DATE_W);     row.date:SetPoint("LEFT", row, "LEFT", x_, 0); x_ = x_ + COL_DATE_W
        row.char = makeText(COL_CHAR_W);     row.char:SetPoint("LEFT", row, "LEFT", x_, 0); x_ = x_ + COL_CHAR_W
        row.role = makeText(COL_ROLE_W);     row.role:SetPoint("LEFT", row, "LEFT", x_, 0); x_ = x_ + COL_ROLE_W
        row.outcome = makeText(COL_RESULT_W); row.outcome:SetPoint("LEFT", row, "LEFT", x_, 0); x_ = x_ + COL_RESULT_W
        row.dur = makeText(COL_DURATION_W);  row.dur:SetPoint("LEFT", row, "LEFT", x_, 0); x_ = x_ + COL_DURATION_W
        row.rej = makeText(COL_REJECT_W);    row.rej:SetPoint("LEFT", row, "LEFT", x_, 0)
        rowPool[i] = row
        return row
    end

    function w:Refresh()
        local sessions = addon.Database:GetSessions()
        local active = addon.Tracker and addon.Tracker:GetCurrentSession() or nil
        local weekStart = addon.Database:GetCurrentWeekStart()

        weekBlock:Update(computeStats(sessions, weekStart, active))
        allBlock:Update(computeStats(sessions, nil, active))

        -- Build the display list: active session first (if any), then
        -- finalized sessions newest -> oldest.
        local list = {}
        if active then table.insert(list, { session = active, isActive = true }) end
        for i = #sessions, 1, -1 do
            table.insert(list, { session = sessions[i], isActive = false })
        end

        local y = 0
        for i, entry in ipairs(list) do
            local s = entry.session
            local row = getRow(i)
            row:Show()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            if entry.isActive then
                row.date:SetText("|cffffd200started " .. fmtDate(s.startedAt) .. "|r")
            else
                row.date:SetText(fmtDate(s.endedAt))
            end
            local p = s.player or {}
            row.char:SetText(p.name or "?")
            local r, g, b = addon.Utils:ClassColor(p.class)
            row.char:SetTextColor(r, g, b)
            local roleStr = p.specName or "?"
            if p.specRole then roleStr = roleStr .. " / " .. addon.Utils:RoleLabel(p.specRole) end
            row.role:SetText(roleStr)
            if entry.isActive then
                row.outcome:SetText("|cffffd200in progress|r")
            else
                local oc = s.outcome or "?"
                if oc == "success" then
                    row.outcome:SetText("|cff66ff66accepted|r")
                elseif oc == "abandoned" then
                    row.outcome:SetText("|cffaaaaaaabandoned|r")
                else
                    row.outcome:SetText(oc)
                end
            end
            local dur = entry.isActive
                and (time() - (s.startedAt or time()))
                or (s.duration or 0)
            row.dur:SetText(addon.Utils:FormatDuration(dur))
            row.rej:SetText(tostring((s.declineCount or 0) + (s.delistCount or 0) + (s.timeoutCount or 0)))
            y = y + ROW_H
        end
        for i = #list + 1, #rowPool do rowPool[i]:Hide() end
        content:SetHeight(math.max(1, y))
    end

    -- Refresh live whenever the Tracker reports a state change (apply, decline,
    -- delist, accept, idle finalize). Plus a 1Hz tick while shown to keep the
    -- in-progress row's elapsed time current.
    if addon.Tracker and addon.Tracker.Subscribe then
        addon.Tracker:Subscribe(function() if w:IsShown() then w:Refresh() end end)
    end
    w:SetScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + elapsed
        if self._tickAccum >= 1 then
            self._tickAccum = 0
            if self:IsShown() and addon.Tracker:GetCurrentSession() then self:Refresh() end
        end
    end)
    w:HookScript("OnShow", function() w:Refresh() end)
    return w
end
