# Route Reveal Arrow And Stop Dot Design

## Goal

Make completed thief routes easier to read at board scale. The previous direction glyphs were small and visually quiet, so detectives could miss the path even when the reveal was technically present.

## Approved Visual Direction

- Path cells show a large directional arrow: `→`, `←`, `↑`, or `↓`.
- The arrow is centered in the board cell, high contrast, and large enough to scan quickly.
- Turn-end cells show a dot marker with the turn number visible.
- Entry and exit labels remain text badges, such as `ENTRY D2` and `EXIT W1`.
- Markers still only render for completed route histories. Active thief movement remains hidden.

## Interaction And Data

No game-state contract changes are needed. The existing route marks already include:

- `kind: "path"` with `direction`
- `kind: "stop"` with `stop` and `label`
- `kind: "entry"` and `kind: "exit"` labels

This pass changes only rendering helpers and tests.

## Testing

LiveView tests should assert:

- Path markers render real arrow characters for each direction.
- Stop markers keep the turn number visible.
- Existing selectors for route direction and stop index remain available.
- Entry and exit badges are unchanged.

## Out Of Scope

- Changing the route history data model.
- Drawing continuous SVG lines between cells.
- Revealing any active, in-progress thief route.
