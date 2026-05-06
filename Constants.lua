local addonName = select(1, ...)
local addon = select(2, ...)

addon.Constants = {
    prefix = "|cff33ff99[DrySpell]|r ",
    minimapIcon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
    sizes = {
        border = 1,
        padding = 8,
        rowHeight = 22,
    },
    -- Application status -> outcome classification.
    -- Statuses that should count as a "decline" for streak purposes.
    declineStatuses = {
        declined          = "declined",
        declined_full     = "declined_full",
        declined_delisted = "declined_delisted",
        timedout          = "timedout",
        failed            = "failed",
    },
    -- Statuses caused by the player and don't break the streak as a "decline";
    -- they simply close the application.
    selfCancelStatuses = {
        cancelled        = true,
        inviteddeclined  = true,
    },
    successStatus      = "inviteaccepted",
    appliedStatus      = "applied",
    invitedStatus      = "invited",
    -- Allowed values for the timeFormat setting (read by Utils:FormatTime*).
    timeFormat = {
        TWELVE = "12h",
        TWENTY_FOUR = "24h",
    },
    -- Allowed values for the dateFormat setting (read by Utils:FormatDate).
    -- Each entry is { id, label, strftime } so adding more options later
    -- means appending one row.
    dateFormat = {
        SLASH_MDY = "slash_mdy",   -- 05/05/2026
        SLASH_DMY = "slash_dmy",   -- 05/05/2026 (DD/MM)
        DASH_MDY  = "dash_mdy",    -- 05-05-2026
        ISO       = "iso",         -- 2026-05-05
        LONG      = "long",        -- May 5, 2026
        SHORT     = "short",       -- May 05
    },
    -- Default idle grace before an open session is auto-finalized as abandoned.
    idleGraceSeconds   = 20 * 60,
    weekSeconds        = 7 * 24 * 60 * 60,
}
