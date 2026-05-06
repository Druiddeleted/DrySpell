# CLAUDE.md — DrySpell

Project-specific guidance on top of the general addon guidance in `~/projects/addons/CLAUDE.md`.

## What this addon does

Tracks LFG application outcomes (declined, delisted, timed out, accepted) across every character on the account, batches them into "sessions" (first sign-up → accept or 20-min idle), and shows two windows: a live current-session view and a history view with this-week and all-time longest dry-streak stats.

See `README.md` for the user-facing description.

## File layout

Top-level Lua files load first (libs → core → tracker → window/db helpers), then `Modules/*.lua` define the actual UI:

- `Constants.lua` — status classification (`declineStatuses`, `selfCancelStatuses`, `successStatus`), default idle grace.
- `Utils.lua` — small helpers: `CharKey`, `FormatDuration`, `GetCurrentWeekStart`, `ClassColor`, `Print`, `Debug`.
- `Events.lua` — AlterEgo-style event dispatcher with optional debounced bucket. DrySpell uses `runsImmediately = true` for all LFG events (volume is low).
- `Window.lua` — minimal draggable framed window factory (titlebar + body + close button), modeled after AlterEgo's but trimmed.
- `Database.lua` — AceDB-3.0 wrapper. SavedVariables key is `DrySpellDB`; everything is account-wide under `.global`.
- `Tracker.lua` — **the heart of the addon.** State machine that maps `LFG_LIST_APPLICATION_STATUS_UPDATED` and `LFG_LIST_SEARCH_RESULT_UPDATED` events into structured sessions. Owns `Tracker.session` (the in-memory current session) and writes finalized sessions via `addon.Database:AppendSession`.
- `Core.lua` — AceAddon entry point. Wires up slash commands, LibDataBroker/LibDBIcon, and calls `Modules.Sessions:Build()` / `Modules.Current:Build()` from `OnInitialize`.
- `Modules/Sessions.lua` — history window: two stat blocks (week / all-time) plus a scrolling list of finalized sessions newest-first.
- `Modules/Current.lua` — live current-session window. Subscribes to `Tracker.callbacks` and runs a 1Hz `OnUpdate` to keep the elapsed-time label fresh while shown.

## Vendored libs (`Libs/`)

We pull the same set AlterEgo uses, except we don't need the AceConfig/AceGUI/AceLocale/AceSerializer stack:

- LibStub, CallbackHandler-1.0
- LibDataBroker-1.1, LibDBIcon-1.0 (minimap button + addon compartment)
- AceAddon-3.0, AceConsole-3.0, AceTimer-3.0, AceDB-3.0
- TaintLess

`.toc` load order matches AlterEgo's: TaintLess → LibStub → CallbackHandler → LibDataBroker → LibDBIcon → Ace stack → addon source. Don't reorder these without testing — TaintLess must be first.

## Session lifecycle (the tricky bit)

A session is created lazily — the first time we see a non-terminal `LFG_LIST_APPLICATION_STATUS_UPDATED` and there's no current session, we capture the player snapshot (name, class, spec, role, ilvl) and start tracking. Subsequent sign-ups on the same character add applications to the same session.

Terminal application statuses are classified by `Constants.declineStatuses`:

- `declined`, `declined_full`, `failed` → counted as a generic decline
- `declined_delisted` → counted as a delist
- `timedout` → counted as a timeout
- Self-caused (`cancelled`, `inviteddeclined`) → recorded but not counted toward the streak (you didn't get rejected, you walked away from that one application)
- `inviteaccepted` → ends the session as `success`

When **all** applications in a session are terminal, we start a `C_Timer.NewTimer(idleGraceSeconds, ...)`. If a new application arrives before it fires, we cancel it. If it fires, we finalize the session as `abandoned`. A user can also force-end via the "End session" button or `/ds end` (outcome = `manual`).

If you change a character mid-session — different toon logs in while a session is open — we still consider it the same session; the player snapshot is taken once at session start. (If we later want per-character sessions, this is the place.)

## Week-bucketing

`Database:GetCurrentWeekStart()` uses `C_DateAndTime.GetSecondsUntilWeeklyReset` to compute the start of the current week, then anchors that value in `db.global.weekAnchor` so historical sessions can be bucketed consistently across all weeks. Don't replace this with `time() - 7*86400` — it'll drift relative to the actual server reset.

## Releasing a new version

CurseForge project ID is **not yet set** — the workflow has a `REPLACE_WITH_CURSEFORGE_PROJECT_ID` placeholder. Once a CurseForge project exists for DrySpell:

1. Edit `.github/workflows/release.yml`, replace the placeholder with the numeric project ID.
2. Add a `CF_API_KEY` secret to the GitHub repo.
3. Tag and push as in the parent CLAUDE.md.

## Testing

No automated harness. `./sync DrySpell` then `/reload` in-game. To exercise the tracker without queueing for real groups, use `/run` with a forged event:

```
/run DrySpellEventsFrame:GetScript("OnEvent")(DrySpellEventsFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined", "applied")
```

Check the result with `/ds current`. Use `/ds wipe` to reset captured history between test runs.
