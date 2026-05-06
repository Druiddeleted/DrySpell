# DrySpell

Track every premade group that declined or delisted on you, across every character on your account, and see how long it really takes to get into a group.

## What it tracks

For every Premade Groups sign-up on every character:

- The character that queued (name, realm, class, level)
- The spec and role you queued as
- Your equipped item level at sign-up
- The group's title, leader, comment, activity (dungeon / raid / battleground), required ilvl, member count
- The terminal status of your application: declined, declined_full, declined_delisted, timedout, failed, cancelled, or accepted

## Sessions

A **session** spans from your first sign-up while idle until either you get into a group (success) or you stop queueing for 20 minutes (abandoned). You can also manually end a session from the current-session window.

Each session records its duration, the count of rejections (declines + delists + timeouts), and the full list of groups you were bounced from.

## Statistics

The session history window shows two stat blocks:

- **This week** — Tuesday after server reset → following Tuesday before reset, computed from `C_DateAndTime.GetSecondsUntilWeeklyReset` so it tracks correctly in any region.
- **All time** — every session ever recorded.

For each block: longest dry streak by rejection count, longest dry streak by wall-clock time, total sessions, successes / abandons / total rejections.

## Slash commands

- `/ds` — open the session history window
- `/ds current` — open the live current-session window
- `/ds end` — manually end the current session
- `/ds minimap` — toggle the minimap button
- `/ds debug` — toggle debug logging
- `/ds wipe` — clear all session history

`/dryspell` is an alias for `/ds`.

## Minimap button

Left-click opens the session history window. Right-click opens the current-session window. The button is registered through LibDataBroker / LibDBIcon so it also appears in the Blizzard addon compartment. Use `/ds minimap` (or right-click in the LibDBIcon options of any other addon that exposes them) to hide it.

## License

MIT — see `LICENSE`.

---

## CurseForge listing copy

### Summary (one-liner)

> Track every LFG queue across all your characters — see how long you waited, how many groups declined you, and your longest dry streaks of the week.

### Description

**Tired of staring at the Premade Groups list, wondering how many leaders just silently passed on you?**

DrySpell quietly tracks every group you sign up for — the declines, the delists, the timeouts, and the wait times — so you finally have answers instead of vibes. See your worst dry streaks of the week, get a satisfying banner the moment you're accepted, and keep a full history of every queue across every character on your account.

#### What it does

DrySpell watches the LFG / Premade Groups system and records each application you make: the group's title, leader, dungeon or raid, difficulty, role makeup, and what eventually happened to your sign-up. Related applications get bundled into a **session** — from your first sign-up while idle, to the moment you're accepted (or you walk away for too long).

For each session DrySpell tracks:

- **Character, spec, role, and item level** at the time you queued
- **Every application** with the full group snapshot (title, leader, activity, difficulty, T/H/D breakdown)
- **Outcome of each app**: accepted, declined, declined-because-full, delisted, timed out, cancelled
- **Time-to-accepted** and total session duration
- **Longest dry streak** (count and time) for the current week and all-time

#### How to use it

- **Just play.** DrySpell starts tracking automatically the moment you sign up for a group.
- **Minimap button** — left-click for full history, shift+left-click for the live current session, right-click for settings.
- **Slash commands** — `/ds` or `/dryspell` open the windows from chat.
- **Big banner on accept** — get a clear, readable confirmation of who invited you, into what, on what difficulty.
- **Survives `/reload`** — your in-flight session resumes right where it left off.

#### Configurable

- 12-hour or 24-hour time
- Six date formats (MM/DD/YYYY, ISO, `Month D, YYYY`, etc.)
- Idle grace period before a session is considered abandoned (1–60 minutes)
- Toggle the accept banner and the end-of-session summary
- Show/hide the minimap button
- Include or exclude abandoned sessions in dry-streak stats

Account-wide saved data — every character contributes to one shared history.
