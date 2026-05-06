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
