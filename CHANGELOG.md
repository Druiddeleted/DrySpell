# Changelog

## 0.1.0-alpha1

- Initial alpha.
- LFG application tracking via `LFG_LIST_APPLICATION_STATUS_UPDATED` and `LFG_LIST_SEARCH_RESULT_UPDATED`.
- Session model with success / abandoned / manual outcomes and 20-minute idle grace.
- Session history window with this-week and all-time stat blocks (longest streak by rejections and by time).
- Live current-session window with elapsed timer and per-application list.
- Minimap button via LibDBIcon (left-click history, right-click current).
- Slash commands: `/ds`, `/ds current`, `/ds end`, `/ds minimap`, `/ds debug`, `/ds wipe`, `/ds help`.
