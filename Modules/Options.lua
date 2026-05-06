local addonName = select(1, ...)
local addon = select(2, ...)

-- Settings panel registered with the modern Blizzard Settings API. Exposes the
-- handful of knobs that aren't worth dedicated UI elsewhere.

local Module = {}
addon.Modules = addon.Modules or {}
addon.Modules.Options = Module

local function makeCheck(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    fs:SetText(label)
    cb.label = fs
    return cb
end

function Module:Build()
    local panel = CreateFrame("Frame", "DrySpellOptionsPanel")
    panel.name = "DrySpell"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DrySpell")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(560); subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Track LFG declines, delistings, and time-to-accepted across all your characters.")

    -- Hide minimap button
    local minimapCB = makeCheck(panel, "Hide minimap button")
    minimapCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    minimapCB:SetScript("OnClick", function(self)
        local mm = addon.Database.db.global.minimap
        mm.hide = self:GetChecked() == true
        if mm.hide then addon.Libs.LibDBIcon:Hide(addonName)
        else addon.Libs.LibDBIcon:Show(addonName) end
    end)

    -- Count abandoned sessions in stats
    local abandonedCB = makeCheck(panel, "Include abandoned sessions in stats blocks")
    abandonedCB:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 0, -8)
    abandonedCB:SetScript("OnClick", function(self)
        addon.Database.db.global.countAbandonedInStats = self:GetChecked() == true
        local sessions = addon.Window:GetWindow("Sessions")
        if sessions and sessions.Refresh then sessions:Refresh() end
    end)

    -- Notify on accepted
    local notifyCB = makeCheck(panel, "Show big notification when accepted into a group")
    notifyCB:SetPoint("TOPLEFT", abandonedCB, "BOTTOMLEFT", 0, -8)
    notifyCB:SetScript("OnClick", function(self)
        addon.Database.db.global.notifyOnAccepted = self:GetChecked() == true
    end)

    -- Print session summary when a session ends
    local summaryCB = makeCheck(panel, "Print session summary in chat when a session ends")
    summaryCB:SetPoint("TOPLEFT", notifyCB, "BOTTOMLEFT", 0, -8)
    summaryCB:SetScript("OnClick", function(self)
        addon.Database.db.global.notifyOnSessionEnd = self:GetChecked() == true
    end)

    -- Debug logging
    local debugCB = makeCheck(panel, "Print debug log messages to chat")
    debugCB:SetPoint("TOPLEFT", summaryCB, "BOTTOMLEFT", 0, -8)
    debugCB:SetScript("OnClick", function(self)
        addon.Database.db.global.debug = self:GetChecked() == true
    end)

    -- Time format dropdown (12h / 24h)
    local timeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    timeLabel:SetPoint("TOPLEFT", debugCB, "BOTTOMLEFT", 0, -20)
    timeLabel:SetText("Time format")

    local timeDropdown = CreateFrame("Frame", "DrySpellTimeFormatDropdown", panel, "UIDropDownMenuTemplate")
    timeDropdown:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", -16, -4)

    local function setTimeFormat(value)
        addon.Database.db.global.timeFormat = value
        UIDropDownMenu_SetText(timeDropdown, value == addon.Constants.timeFormat.TWENTY_FOUR and "24-hour" or "12-hour")
        -- Refresh open windows so the change takes effect immediately.
        local s = addon.Window:GetWindow("Sessions"); if s and s.Refresh then s:Refresh() end
        local c = addon.Window:GetWindow("Current");  if c and c.Refresh then c:Refresh() end
    end

    UIDropDownMenu_Initialize(timeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "12-hour (3:14 pm)"
        info.value = addon.Constants.timeFormat.TWELVE
        info.func = function() setTimeFormat(info.value) end
        UIDropDownMenu_AddButton(info, level)
        info = UIDropDownMenu_CreateInfo()
        info.text = "24-hour (15:14)"
        info.value = addon.Constants.timeFormat.TWENTY_FOUR
        info.func = function() setTimeFormat(info.value) end
        UIDropDownMenu_AddButton(info, level)
    end)
    UIDropDownMenu_SetWidth(timeDropdown, 140)

    -- Date format dropdown — anchored to the time label's TOPRIGHT so both
    -- label rows (and therefore both dropdowns) sit at the same Y.
    local dateLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dateLabel:SetPoint("TOPLEFT", timeLabel, "TOPRIGHT", 200, 0)
    dateLabel:SetText("Date format")

    local dateDropdown = CreateFrame("Frame", "DrySpellDateFormatDropdown", panel, "UIDropDownMenuTemplate")
    dateDropdown:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", -16, -4)

    -- Single source of truth for the dropdown rows. Adding a new format
    -- means appending an entry here plus a branch in Utils:FormatDate.
    local DATE_OPTIONS = {
        { value = addon.Constants.dateFormat.SLASH_MDY, label = "MM/DD/YYYY (05/05/2026)" },
        { value = addon.Constants.dateFormat.SLASH_DMY, label = "DD/MM/YYYY (05/05/2026)" },
        { value = addon.Constants.dateFormat.DASH_MDY,  label = "MM-DD-YYYY (05-05-2026)" },
        { value = addon.Constants.dateFormat.ISO,       label = "YYYY-MM-DD (2026-05-05)" },
        { value = addon.Constants.dateFormat.LONG,      label = "Month D, YYYY (May 5, 2026)" },
        { value = addon.Constants.dateFormat.SHORT,     label = "Mon DD (May 05)" },
    }
    local function dateLabelFor(value)
        for _, o in ipairs(DATE_OPTIONS) do if o.value == value then return o.label end end
        return DATE_OPTIONS[1].label
    end
    local function setDateFormat(value)
        addon.Database.db.global.dateFormat = value
        UIDropDownMenu_SetText(dateDropdown, dateLabelFor(value))
        local s = addon.Window:GetWindow("Sessions"); if s and s.Refresh then s:Refresh() end
        local c = addon.Window:GetWindow("Current");  if c and c.Refresh then c:Refresh() end
    end
    UIDropDownMenu_Initialize(dateDropdown, function(self, level)
        for _, opt in ipairs(DATE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function() setDateFormat(opt.value) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(dateDropdown, 200)

    -- Idle grace slider (1 - 60 minutes)
    local sliderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sliderLabel:SetPoint("TOPLEFT", timeDropdown, "BOTTOMLEFT", 16, -16)
    sliderLabel:SetText("Idle grace before a session is considered abandoned")

    local sliderHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sliderHelp:SetPoint("TOPLEFT", sliderLabel, "BOTTOMLEFT", 0, -2)
    sliderHelp:SetWidth(560); sliderHelp:SetJustifyH("LEFT")
    sliderHelp:SetText("If you've had no open application for this long with no accept, the session is recorded as abandoned.")

    local slider = CreateFrame("Slider", "DrySpellIdleGraceSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", sliderHelp, "BOTTOMLEFT", 4, -16)
    slider:SetWidth(280)
    slider:SetMinMaxValues(1, 60)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("1m")
    _G[slider:GetName() .. "High"]:SetText("60m")
    local sliderValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sliderValue:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        addon.Database.db.global.idleGraceSeconds = value * 60
        sliderValue:SetText(value .. " minutes")
    end)

    -- Wipe history button
    local wipeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    wipeBtn:SetSize(140, 22)
    wipeBtn:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -28)
    wipeBtn:SetText("Wipe session history")
    wipeBtn:SetScript("OnClick", function()
        StaticPopup_Show("DRYSPELL_WIPE_CONFIRM")
    end)

    StaticPopupDialogs["DRYSPELL_WIPE_CONFIRM"] = {
        text = "Permanently delete all DrySpell session history?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            wipe(addon.Database.db.global.sessions)
            local sessions = addon.Window:GetWindow("Sessions")
            if sessions and sessions.Refresh then sessions:Refresh() end
            addon.Utils:Print("session history wiped")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = STATICPOPUP_NUMDIALOGS,
    }

    -- Sync the panel widgets to current SavedVariables every time it's shown,
    -- not just at creation, since other code paths can change these too.
    panel:SetScript("OnShow", function()
        local g = addon.Database.db.global
        minimapCB:SetChecked(g.minimap and g.minimap.hide == true)
        abandonedCB:SetChecked(g.countAbandonedInStats ~= false)
        notifyCB:SetChecked(g.notifyOnAccepted ~= false)
        summaryCB:SetChecked(g.notifyOnSessionEnd ~= false)
        debugCB:SetChecked(g.debug == true)
        local fmt = g.timeFormat or addon.Constants.timeFormat.TWELVE
        UIDropDownMenu_SetSelectedValue(timeDropdown, fmt)
        UIDropDownMenu_SetText(timeDropdown, fmt == addon.Constants.timeFormat.TWENTY_FOUR and "24-hour" or "12-hour")
        local dfmt = g.dateFormat or addon.Constants.dateFormat.SLASH_MDY
        UIDropDownMenu_SetSelectedValue(dateDropdown, dfmt)
        UIDropDownMenu_SetText(dateDropdown, dateLabelFor(dfmt))
        local minutes = math.max(1, math.floor((g.idleGraceSeconds or addon.Constants.idleGraceSeconds) / 60 + 0.5))
        slider:SetValue(minutes)
        sliderValue:SetText(minutes .. " minutes")
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        Module._category = category
    elseif _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panel)
    end
    Module._panel = panel
end

function Module:Open()
    if Settings and Settings.OpenToCategory and self._category and self._category.GetID then
        Settings.OpenToCategory(self._category:GetID())
    elseif _G.InterfaceOptionsFrame_OpenToCategory and self._panel then
        _G.InterfaceOptionsFrame_OpenToCategory(self._panel)
        _G.InterfaceOptionsFrame_OpenToCategory(self._panel)
    end
end
