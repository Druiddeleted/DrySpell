local addonName = select(1, ...)
local addon = select(2, ...)

-- Expose addon table globally in debug builds for inspection from /run.
-- _G[addonName] = addon

local Core = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceTimer-3.0")
addon.Core = Core

addon.Libs = {
    LibDBIcon     = LibStub("LibDBIcon-1.0"),
    LibDataBroker = LibStub("LibDataBroker-1.1"),
}

function Core:OnInitialize()
    addon.Database:Initialize()
    addon.Database:UpdateCharacterInfo()
    addon.Tracker:Initialize()
    addon.Modules.Sessions:Build()
    addon.Modules.Current:Build()
    addon.Modules.Options:Build()

    -- Slash commands: /ds, /dryspell.
    self:RegisterChatCommand("ds", function(input)
        self:HandleSlash(input)
    end)
    self:RegisterChatCommand("dryspell", function(input)
        self:HandleSlash(input)
    end)

    -- Minimap button via LibDataBroker + LibDBIcon, exactly as AlterEgo does.
    local ldbObject = {
        label = addonName,
        type  = "launcher",
        icon  = addon.Constants.minimapIcon,
        OnClick = function(_, mouseButton)
            local shift = IsLeftShiftKeyDown() or IsRightShiftKeyDown()
            if mouseButton == "RightButton" then
                addon.Modules.Options:Open()
            elseif mouseButton == "LeftButton" and shift then
                addon.Window:Toggle("Current")
            else
                addon.Window:Toggle("Sessions")
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("DrySpell", 1, 1, 1)
            tooltip:AddLine("|cff00ff00Left click|r — open session history.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            tooltip:AddLine("|cff00ff00Shift+Left click|r — open current session.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            tooltip:AddLine("|cff00ff00Right click|r — open settings.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            local s = addon.Tracker:GetCurrentSession()
            if s then
                local elapsed = time() - s.startedAt
                tooltip:AddLine(string.format("Active: %d rejection(s) over %s",
                    (s.declineCount + s.delistCount + s.timeoutCount),
                    addon.Utils:FormatDuration(elapsed)), 1, 1, 0)
            end
        end,
    }
    addon.Libs.LibDataBroker:NewDataObject(addonName, ldbObject)
    addon.Libs.LibDBIcon:Register(addonName, ldbObject, addon.Database.db.global.minimap)
    addon.Libs.LibDBIcon:AddButtonToCompartment(addonName)
end

function Core:HandleSlash(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" or input == "history" or input == "sessions" then
        addon.Window:Toggle("Sessions")
    elseif input == "current" or input == "live" then
        addon.Window:Toggle("Current")
    elseif input == "options" or input == "config" then
        addon.Modules.Options:Open()
    elseif input == "minimap" then
        local mm = addon.Database.db.global.minimap
        mm.hide = not mm.hide
        if mm.hide then
            addon.Libs.LibDBIcon:Hide(addonName)
            addon.Utils:Print("minimap button hidden (use /ds minimap to show again)")
        else
            addon.Libs.LibDBIcon:Show(addonName)
            addon.Utils:Print("minimap button visible")
        end
    elseif input == "end" or input == "stop" then
        if addon.Tracker:GetCurrentSession() then
            addon.Tracker:EndCurrentSession()
            addon.Utils:Print("current session ended")
        else
            addon.Utils:Print("no active session")
        end
    elseif input == "debug" then
        local g = addon.Database.db.global
        g.debug = not g.debug
        addon.Utils:Print("debug = " .. tostring(g.debug))
    elseif input == "wipe" then
        wipe(addon.Database.db.global.sessions)
        addon.Utils:Print("session history wiped")
    elseif input == "help" then
        addon.Utils:Print("commands:")
        print("  /ds                    open session history window")
        print("  /ds current            open current session window")
        print("  /ds options            open the settings panel")
        print("  /ds end                end the current session manually")
        print("  /ds minimap            toggle the minimap button")
        print("  /ds debug              toggle debug logging")
        print("  /ds wipe               clear all session history")
    else
        addon.Utils:Print("unknown command (try /ds help)")
    end
end
