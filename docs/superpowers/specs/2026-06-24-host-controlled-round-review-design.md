# Host Controlled Round Review Design

## Goal

Between full-game rounds, pause on a shared review screen so players can inspect the completed thief route before setup begins for the next round.

## Approved Behavior

- Non-final full-game rounds end in a `:round_review` phase.
- The latest completed thief route remains selected and visible on the board.
- All players can review the route, round report, entry label, exit label, path arrows, and numbered turn stops.
- Only the host can end the review and continue into the next setup.
- Non-host players see that the game is waiting for the host.
- Final full-game rounds still go directly to `:game_over`.
- Limited games are unchanged.

## State Transition

When a non-final full-game round ends, the game stores the same round result and updated artwork scores it stores today, but does not call the next-round setup constructor immediately. The state keeps enough information to begin the next round later:

- current `players`
- `thief_rotation`
- `round_number`
- `artwork_scores`
- `round_results`
- `host_player_id`
- completed `thief_history`

When the host continues, rules build the next round setup using the existing role-rotation and setup-reset behavior.

## UI

The sidebar shows a round review panel during `:round_review`:

- round result summary
- route selector if prior routes exist
- host-only `Start next round` button
- non-host `Waiting for host` status

The board continues to show the selected completed route.

## Testing

- Rules tests cover non-final full-game escape pausing in `:round_review`.
- Rules tests cover `start_next_round/1` moving from `:round_review` into next-round setup.
- Rules tests cover invalid `start_next_round/1` calls outside `:round_review`.
- LiveView tests cover host-only continue controls.
- LiveView tests cover host click moving the game into setup.
- Existing final-round and limited-game behavior remains covered.
