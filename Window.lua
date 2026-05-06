local addonName = select(1, ...)
local addon = select(2, ...)

local TITLEBAR_HEIGHT = 28
local Utils = addon.Utils

local Window = {}
addon.Window = Window
Window.windows = {}

-- Create a simple draggable framed window with a titlebar + body.
-- Modeled after AlterEgo's Window.lua but trimmed to what DrySpell needs.
function Window:New(opts)
    opts = opts or {}
    local name = opts.name or ("Window" .. (Utils:TableCount(self.windows) + 1))
    local w = CreateFrame("Frame", addonName .. "Window" .. name, opts.parent or UIParent, "BackdropTemplate")
    w.config = opts
    w:SetFrameStrata("MEDIUM")
    w:SetFrameLevel(3000)
    w:SetToplevel(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetSize(opts.width or 600, opts.height or 400)
    if opts.point then
        w:SetPoint(unpack(opts.point))
    else
        w:SetPoint("CENTER")
    end
    Utils:SetBackgroundColor(w, 0.11, 0.14, 0.16, 1)

    w:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    w:SetBackdropBorderColor(0, 0, 0, 0.5)

    -- Titlebar
    local tb = CreateFrame("Frame", "$parentTitleBar", w)
    tb:SetPoint("TOPLEFT", w, "TOPLEFT")
    tb:SetPoint("TOPRIGHT", w, "TOPRIGHT")
    tb:SetHeight(TITLEBAR_HEIGHT)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() w:StartMoving() end)
    tb:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
    Utils:SetBackgroundColor(tb, 0, 0, 0, 0.5)
    w.titlebar = tb

    local title = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", tb, "LEFT", 10, 0)
    title:SetText(opts.title or name)
    tb.title = title

    -- Close button. UIPanelCloseButton's default size is 32x32 which overflows
    -- our 28px titlebar; explicitly size & inset it.
    local close = CreateFrame("Button", "$parentClose", tb, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:ClearAllPoints()
    close:SetPoint("RIGHT", tb, "RIGHT", -4, 0)
    close:SetFrameLevel(tb:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() w:Hide() end)
    w.closeButton = close

    -- Body
    local body = CreateFrame("Frame", "$parentBody", w)
    body:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -TITLEBAR_HEIGHT - 2)
    body:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -4, 4)
    Utils:SetBackgroundColor(body, 0, 0, 0, 0)
    w.body = body

    function w:SetTitle(text) title:SetText(text) end
    function w:Toggle(state)
        if state == nil then state = not w:IsVisible() end
        w:SetShown(state)
    end

    w:Hide()
    table.insert(UISpecialFrames, w:GetName())
    self.windows[name] = w
    return w
end

function Window:GetWindow(name)
    return self.windows[name]
end

function Window:Toggle(name)
    local w = self.windows[name or "Sessions"]
    if not w then return end
    w:Toggle()
end
