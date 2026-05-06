local addonName = select(1, ...)
local addon = select(2, ...)

-- Live "current session" window. Subscribes to the Tracker so it refreshes
-- whenever an application or session state changes.

local Module = {}
addon.Modules = addon.Modules or {}
addon.Modules.Current = Module

local APP_ROW_H = 22

local function fmtTime(t)
    return addon.Utils:FormatTimeOfDay(t)
end

function Module:Build()
    local w = addon.Window:New({
        name = "Current",
        title = "DrySpell — current session",
        width = 760,
        height = 460,
    })

    -- Top header: who's queueing, ilvl, spec/role, total time elapsed.
    local h = CreateFrame("Frame", nil, w.body)
    h:SetPoint("TOPLEFT", w.body, "TOPLEFT", 8, -8)
    h:SetPoint("RIGHT", w.body, "RIGHT", -8, 0)
    h:SetHeight(70)
    addon.Utils:SetBackgroundColor(h, 0, 0, 0, 0.25)

    local headerLine = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerLine:SetPoint("TOPLEFT", 8, -6)
    headerLine:SetText("No active session")

    local subLine = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subLine:SetPoint("TOPLEFT", 8, -28)

    local statsLine = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statsLine:SetPoint("TOPLEFT", 8, -48)

    -- "End session" button (right side of header).
    local endBtn = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
    endBtn:SetSize(96, 22)
    endBtn:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    endBtn:SetText("End session")
    endBtn:SetScript("OnClick", function()
        addon.Tracker:EndCurrentSession()
    end)

    -- Application list header.
    local listHeader = CreateFrame("Frame", nil, w.body)
    listHeader:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8)
    listHeader:SetPoint("RIGHT", w.body, "RIGHT", -8, 0)
    listHeader:SetHeight(APP_ROW_H)
    addon.Utils:SetBackgroundColor(listHeader, 0, 0, 0, 0.4)

    local function colHeader(text, x, w_)
        local fs = listHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", listHeader, "LEFT", x, 0)
        fs:SetWidth(w_)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
    end
    -- x positions / widths are kept in sync with row layout below.
    colHeader("Time",        8,   60)
    colHeader("Title",       72,  180)
    colHeader("Activity",    256, 180)
    colHeader("Difficulty",  440, 90)
    colHeader("T/H/D",       534, 64)
    colHeader("Outcome",     596, 110)

    -- Scroll for the application list.
    local scroll = CreateFrame("ScrollFrame", nil, w.body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", w.body, "BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local rowPool = {}
    local function getRow(i)
        local row = rowPool[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetSize(560, APP_ROW_H)
        if i % 2 == 0 then addon.Utils:SetBackgroundColor(row, 1, 1, 1, 0.04) end
        local function fs(x, w_)
            local f = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f:SetPoint("LEFT", row, "LEFT", x, 0)
            f:SetWidth(w_); f:SetJustifyH("LEFT")
            return f
        end
        row.t        = fs(8,   60)
        row.title    = fs(72,  180)
        row.activity = fs(256, 180)
        row.diff     = fs(440, 90)
        row.members  = fs(534, 56)
        row.outcome  = fs(596, 110)
        -- Tooltip with full group details (leader, comment, ilvl req).
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local data = self._group
            if not data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(data.name or "(unknown)", 1, 1, 1)
            if data.activityFullName then
                GameTooltip:AddLine(data.activityFullName, 0.8, 0.8, 1)
            end
            if data.difficultyName then
                GameTooltip:AddLine("Difficulty: " .. data.difficultyName, 1, 1, 0.5)
            end
            if data.categoryName then
                GameTooltip:AddLine("Category: " .. data.categoryName, 1, 1, 0.5)
            end
            if data.leaderName then
                GameTooltip:AddLine("Leader: " .. data.leaderName, 0.8, 0.8, 0.8)
            end
            if data.numMembers and data.maxNumPlayers then
                GameTooltip:AddLine(string.format("Members: %d / %d", data.numMembers, data.maxNumPlayers), 0.8, 0.8, 0.8)
            elseif data.numMembers then
                GameTooltip:AddLine("Members: " .. data.numMembers, 0.8, 0.8, 0.8)
            end
            if data.tankCount or data.healerCount or data.damagerCount then
                GameTooltip:AddLine(string.format("Tanks %d  Healers %d  DPS %d",
                    data.tankCount or 0, data.healerCount or 0, data.damagerCount or 0), 0.8, 0.8, 0.8)
            end
            if data.groupIlvl then
                GameTooltip:AddLine("Required ilvl: " .. data.groupIlvl, 0.8, 0.8, 0.8)
            end
            if data.comment and data.comment ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(data.comment, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rowPool[i] = row
        return row
    end

    -- Find the most recent finalized session for the logged-in character so
    -- we can show it when no session is active. Walking newest -> oldest is
    -- cheap (we cap history at 500) and avoids any extra bookkeeping.
    local function lastSessionForCurrentChar()
        local key = addon.Utils:CharKey()
        local sessions = addon.Database:GetSessions()
        for i = #sessions, 1, -1 do
            local s = sessions[i]
            if s and s.player and s.player.key == key then return s end
        end
        return nil
    end

    function w:Refresh()
        addon.Tracker:RefreshPlayerSnapshot()
        local s = addon.Tracker:GetCurrentSession()
        local isActive = s ~= nil
        if not s then
            -- Fall back to the last session for *this* character so the
            -- window keeps showing useful info between sessions.
            s = lastSessionForCurrentChar()
        end
        if not s then
            headerLine:SetText("No sessions yet on this character")
            subLine:SetText("Queue for a group in Premade Groups to start tracking.")
            statsLine:SetText("")
            endBtn:SetEnabled(false)
            for _, r in ipairs(rowPool) do r:Hide() end
            content:SetHeight(1)
            return
        end
        endBtn:SetEnabled(isActive)
        local p = s.player or {}
        local r, g, b = addon.Utils:ClassColor(p.class)
        local stateTag = isActive and "" or "  |cffaaaaaa(last session)|r"
        headerLine:SetText(string.format("|cff%02x%02x%02x%s|r — %s%s",
            math.floor(r*255), math.floor(g*255), math.floor(b*255),
            p.name or "?", p.specName or "?", stateTag))
        subLine:SetText(string.format("Role: %s    ilvl: %s    Started: %s",
            addon.Utils:RoleLabel(p.specRole), tostring(p.ilvl or "?"),
            addon.Utils:FormatDateTime(s.startedAt)))
        local rejections = (s.declineCount or 0) + (s.delistCount or 0) + (s.timeoutCount or 0)
        local dur
        if isActive then
            dur = time() - (s.startedAt or time())
            statsLine:SetText(string.format("Elapsed: %s    Rejections: %d (declines %d, delists %d, timeouts %d)",
                addon.Utils:FormatDuration(dur), rejections,
                s.declineCount or 0, s.delistCount or 0, s.timeoutCount or 0))
        else
            dur = s.duration or 0
            local outcomeText = ({
                success   = "|cff66ff66accepted|r",
                abandoned = "|cffaaaaaaabandoned|r",
                manual    = "|cffaaaaaaended manually|r",
            })[s.outcome] or s.outcome or "?"
            statsLine:SetText(string.format("Outcome: %s    Duration: %s    Rejections: %d (declines %d, delists %d, timeouts %d)",
                outcomeText, addon.Utils:FormatDuration(dur), rejections,
                s.declineCount or 0, s.delistCount or 0, s.timeoutCount or 0))
        end

        -- Render applications, newest first.
        local n = 0
        for i = #s.appOrder, 1, -1 do
            local resultID = s.appOrder[i]
            local app = s.applications[resultID]
            if app then
                n = n + 1
                local row = getRow(n)
                row:Show()
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((n-1) * APP_ROW_H))
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                row.t:SetText(fmtTime(app.appliedAt))
                local g_ = app.groupAtApply or app.groupAtEnd or {}
                row._group = g_  -- for the tooltip handler
                -- Prefer the sticky `app.title` we captured at apply time;
                -- fall back through both group snapshots; only land on the
                -- "(unknown)" placeholder if nothing has a usable name.
                row.title:SetText(app.title or g_.name or "(unknown)")
                row.activity:SetText(g_.activityFullName or g_.activityShortName or "?")
                row.diff:SetText(g_.difficultyName or "-")
                -- Prefer T/H/D breakdown; fall back to plain count when the
                -- per-role data isn't available (older API path or odd group).
                if g_.tankCount or g_.healerCount or g_.damagerCount then
                    row.members:SetText(string.format("|cff5599ff%d|r/|cff55ff55%d|r/|cffff5555%d|r",
                        g_.tankCount or 0, g_.healerCount or 0, g_.damagerCount or 0))
                elseif g_.numMembers and g_.maxNumPlayers then
                    row.members:SetText(g_.numMembers .. "/" .. g_.maxNumPlayers)
                elseif g_.numMembers then
                    row.members:SetText(tostring(g_.numMembers))
                else
                    row.members:SetText("-")
                end
                local term = app.terminalStatus
                if term == "accepted" then
                    row.outcome:SetText("|cff66ff66accepted|r")
                elseif term then
                    row.outcome:SetText(term)
                else
                    row.outcome:SetText("|cffffff00pending|r")
                end
            end
        end
        for i = n + 1, #rowPool do rowPool[i]:Hide() end
        content:SetHeight(math.max(1, n * APP_ROW_H))
    end

    -- Live tick to keep the elapsed-time label current while window is shown.
    w:SetScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + elapsed
        if self._tickAccum >= 1 then
            self._tickAccum = 0
            if self:IsShown() then self:Refresh() end
        end
    end)

    -- Tracker callbacks fire on application/session state changes.
    addon.Tracker:Subscribe(function() if w:IsShown() then w:Refresh() end end)
    w:HookScript("OnShow", function() w:Refresh() end)
    return w
end
