# Two-Player Full Game Design

## Goal

When a Full Game starts with exactly two human players, one player is the thief and the other controls two detective pawns. Rounds still rotate thief ownership so each player plays thief once. Limited Game behavior stays unchanged.

## Requirements

- Apply the special two-player behavior only when `game_mode` is `:full` and the lobby has exactly two players.
- Keep scores, winners, host ownership, reconnects, and thief rotation keyed by human player IDs.
- Represent the two detective turns as pawn turns so the existing movement, dice, look, and turn-order rules remain natural.
- Let the detective controller place, move, look from, and end turns for both controlled detective pawns.
- Keep three- and four-player games unchanged.
- Keep Limited Game with two players unchanged.

## Architecture

The game state will add a `detective_controllers` map keyed by detective pawn ID and valued by the human player ID that controls the pawn. Normal games map each detective pawn to itself. Two-player full rounds create two synthetic detective pawn IDs for the non-thief player and map both back to that player.

Turn order remains pawn-based: `[detective_pawn_1, thief_player, detective_pawn_2, thief_player]`. LiveView translates the current pawn turn into a human controller when deciding whether a browser session can act. Server and rules APIs continue accepting a `detective_id`; the UI will pass the active controlled pawn ID.

When a two-player full round ends, the next round rebuilds state from the same two human players, swaps thief/controller roles, recreates two detective pawns for the new controller, and preserves player-based score data.

## Testing

- State and server tests cover two-player Full Game setup, Limited Game staying unchanged, and next-round role swap.
- Rules tests cover capture and turn advancement with synthetic detective pawn IDs.
- LiveView tests cover player list de-duplication, detective pawn placement by one controller, and controlled pawn movement.
