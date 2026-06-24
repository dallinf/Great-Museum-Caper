# End-Round Board Route Reveal Design

## Goal

After a thief round ends, detectives should inspect the thief's actual route on the museum board instead of reading a list of coordinate chips. The reveal must continue to obey hidden-information rules: no thief path is shown while that round is still active.

## Recommended Interaction

The main board becomes the reveal surface for completed thief routes.

- In full-game mode, the latest completed round is selected by default as soon as the game advances to the next setup round.
- Detectives can switch completed rounds with compact round selector buttons in the full-game score panel.
- In game-over state, the same selected completed round route remains visible on the board, with the final report still showing round summary text.
- In limited-game mode, the game-over board shows the completed thief route from that game.
- The current text-heavy route history is reduced to a concise route summary so the board remains the primary explanation.

## Board Overlay

The overlay renders inside the existing board cells so it scales with the board and works on mobile and desktop.

- Entry cell: a small numbered or labeled badge marks where the thief entered.
- Path cells: each traversed cell gets a subtle route marker.
- Consecutive path cells: short connector segments draw the visible trail between neighboring cells.
- Final cell: a stronger marker shows the route endpoint or exit attempt.

The overlay should sit above room backgrounds and below active pawn/artwork marks where possible, so it reads as a route layer rather than a new pawn.

## State And Data Flow

The existing `thief_history` and `round_results[*].thief_history` data remain the source of truth.

- The LiveView tracks a selected revealed round number.
- When a new round result appears, selection defaults to the latest completed round.
- Selecting a round only changes the reveal overlay; it does not mutate game rules state.
- The selected history is converted into board route marks by flattening the entry and all committed movement paths while preserving path order.

## Hidden Information

The overlay is only built from completed history:

- Full-game setup after a completed round may show the selected completed route.
- Full-game game-over may show any completed round route via selectors.
- Limited-game game-over may show the completed route.
- Active thief movement during play continues to use the existing movement animation, and no completed-route overlay is shown for an active round.

## Testing

Add LiveView tests for:

- A full-game round ending shows the selected route on board cells by default.
- Round selector buttons switch the rendered board route.
- The route overlay is absent during active play before a round is completed.
- Limited-game game over shows the route overlay on the board.

Keep existing rules tests for history recording; this feature should not require changing route recording semantics unless a test exposes missing data.
