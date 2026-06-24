# Route Reveal Annotations Design

## Goal

Make completed thief routes easier to read on the board. Detectives should immediately see where the thief entered, where each thief turn ended, which direction the thief traveled, and where the thief exited if an escape happened.

## Approved Direction

Use the board as the primary reveal surface.

- Mark the entry point clearly with an `ENTRY` badge on the door/window label cell and the entry label, such as `D2`.
- Mark the exit clearly with an `EXIT` badge on the door/window label cell when the thief escaped through a door or window.
- Keep the last inside square as a final stop marker, so detectives can see where the thief stood before checking or exiting.
- Add directional cues along the route so the path reads like movement, not only highlighted squares.
- Add per-turn stop markers for every committed thief move.

## Visual Treatment

The overlay should read as a route drawn over a museum map, not as extra pawns.

- Entry marker: cyan badge labeled `ENTRY D2` or `ENTRY W1`.
- Exit marker: amber badge labeled `EXIT W1` or `EXIT D3`.
- Path cells: a narrow route trace with directional arrow glyphs or arrowheads that point toward the next cell.
- Turn stops: numbered stop chips, such as `1`, `2`, `3`, placed on the final cell of each committed thief turn.
- Final stop before escape: use the last stop marker plus the separate `EXIT` badge on the actual exit cell.

The existing latest-by-default round selector remains unchanged.

## Data Flow

The current `thief_history` shape already stores entry and per-turn movement paths. It needs one small extension for exits:

```elixir
%{
  entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
  exit: %{id: :window_1_5, label: "W1", position: {1, 5}} | nil,
  moves: [%{path: [{6, 2}, {5, 2}, {4, 2}]}]
}
```

Rules should set `exit` only when the thief actually escapes. Locked checks and failed/unfinished escape choices must not create an exit marker.

## Hidden Information

No route annotations are shown during an active thief round. Entry, movement direction, stops, and exit are shown only from completed route history:

- full-game completed rounds through `round_results`
- full-game final report through selected completed round history
- limited-game game over through `game_state.thief_history`

## Testing

Add or update tests for:

- completed full-game routes show an `ENTRY` badge on the entry label cell
- completed escape routes show an `EXIT` badge on the actual exit/window/door cell
- non-escaped or locked-check routes do not show an exit badge
- path cells include directional route metadata
- each committed thief turn endpoint shows a numbered stop marker
- active thief movement still does not show completed-route annotations
