local addonName = select(1, ...)
local addon = select(2, ...)

-- Lightweight event dispatcher modeled after AlterEgo's Events.lua.
-- Supports immediate handlers (for low-frequency LFG events we always want
-- promptly) plus a debounced bucket for chatty events. We use immediate=true
-- for nearly everything since the LFG event volume is naturally low.
local Events = {}
addon.Events = Events
Events.handlers = {}
Events.runtime = { pendingByEventName = {} }
Events.frame = CreateFrame("Frame", addonName .. "EventsFrame")

local BUCKET_INTERVAL_SEC = 2

local function packVarargs(...)
    local n = select("#", ...)
    local t = { n = n }
    for i = 1, n do t[i] = select(i, ...) end
    return t
end

local function unpackVarargs(packed)
    if not packed or (packed.n or 0) == 0 then return end
    return unpack(packed, 1, packed.n)
end

Events.frame:SetScript("OnEvent", function(frame, event, ...)
    local list = Events.handlers[event]
    if not list then return end

    local packed = packVarargs(...)
    for i = 1, #list do
        if list[i].runsImmediately then
            list[i].fn(frame, event, unpackVarargs(packed))
        end
    end

    local hasBucketed = false
    for i = 1, #list do
        if not list[i].runsImmediately then hasBucketed = true; break end
    end
    if not hasBucketed then return end

    local pending = Events.runtime.pendingByEventName
    local bucket = pending[event]
    if not bucket or not bucket.timer then
        bucket = { packed = packed }
        pending[event] = bucket
        bucket.timer = C_Timer.NewTimer(BUCKET_INTERVAL_SEC, function()
            local snap = bucket.packed
            bucket.timer = nil
            pending[event] = nil
            local current = Events.handlers[event]
            if not current then return end
            for j = 1, #current do
                if not current[j].runsImmediately then
                    current[j].fn(frame, event, unpackVarargs(snap))
                end
            end
        end)
    else
        bucket.packed = packed
    end
end)

function Events:RegisterEvent(event, callback, runsImmediately)
    if type(event) == "table" then
        for _, e in ipairs(event) do self:RegisterEvent(e, callback, runsImmediately) end
        return
    end
    local list = self.handlers[event]
    if not list then
        list = {}
        self.handlers[event] = list
        self.frame:RegisterEvent(event)
    end
    list[#list + 1] = { fn = callback, runsImmediately = runsImmediately ~= false }
end
