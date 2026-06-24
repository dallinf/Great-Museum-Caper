# Full Game Replay Design

## Summary

Detectives can watch a fully revealed animated replay after each full-game round and at final game over. The replay shows detective pawns and the thief moving through the museum in the original turn order, with the thief visible because the round is complete. Replay is not available during live play.

## Goals

- Preserve a complete ordered replay timeline while the round is played.
- Show replay controls during `:round_review` and `:game_over` only.
- Animate all pawn movement paths using the existing board movement animation primitives.
- Include important non-movement events in the replay timeline so the viewer understands why the round ended.
- Keep hidden information hidden until the round is over.

## Non-Goals

- No live-game replay or partial replay while a round is still in progress.
- No video export.
- No reconstruction of historical games that were played before this feature exists.
- No speculative replay derived from incomplete state. The server timeline is authoritative.

## Data Model

Add a replay timeline to game state:

```elixir
replay_events: []
```

Each replay event is a map with a stable shape:

```elixir
%{
  id: positive_integer(),
  round_number: positive_integer(),
  turn_index: non_neg_integer(),
  actor_id: String.t(),
  actor_role: :thief | :detective,
  actor_label: String.t(),
  type: atom(),
  path: [{integer(), integer()}],
  from: {integer(), integer()} | nil,
  to: {integer(), integer()} | nil,
  result: atom() | nil,
  label: String.t() | nil
}
```

The first implementation should support these event types:

- `:enter` for the thief entry point.
- `:move` for thief and detective movement.
- `:lock_check` for window and external door lock checks.
- `:steal` for artwork theft.
- `:power` for power being turned on or off.
- `:capture` when detectives catch the thief.
- `:escape` when the thief exits, including the exit id and result.
- `:round_end` as the final summary event.

The event schema should remain map-based instead of introducing a new struct at first. This matches the current state style and keeps serialization simple for LiveView assigns.

## Recording Rules

The rules layer records replay events at the same point it mutates authoritative game state.

- `enter_museum/2` appends `:enter` with a path containing the entry door/window cell and resulting thief position.
- `move_thief/2` and `move_detective/3` append or update one pending movement event for the current turn, matching the existing ability to revise movement before ending the turn.
- `end_turn/1` finalizes the current turn's replay movement so the timeline matches the final chosen path.
- `try_escape/2` appends `:lock_check`, then `:escape` only when the thief actually escapes.
- Existing theft, power, capture, and round end logic append their corresponding events when those outcomes are resolved.

The replay timeline for the active round lives on `State`. When a round ends, the completed `round_result` stores:

```elixir
%{
  ...,
  replay_events: state.replay_events
}
```

Starting the next round resets `replay_events` to an empty list.

## Hidden Information

Replay data may be recorded during live play, but it is not rendered to detectives during `:playing`. The LiveView only exposes replay controls and replay event payloads when:

- `state.phase == :round_review`
- `state.phase == :game_over`

In those phases the thief is fully revealed in replay mode. Normal board rendering outside replay mode continues to use the existing projection rules.

## Replay UI

Add a replay panel alongside the route review controls during round review and game over.

Controls:

- `Play/Pause`
- `Step back`
- `Step forward`
- `Restart`
- Speed selector with `0.5x`, `1x`, `2x`
- `Exit replay`

Default behavior:

- The latest completed round is selected by default, matching the existing route selector.
- Opening replay starts paused at the first event.
- Pressing play animates through events in order.
- The board returns to the normal round-review/game-over board when replay exits.

The replay surface should reuse the existing board, not create a separate board. In replay mode, pawn positions come from the replay frame instead of live game state. The existing thief route overlay can remain visible when replay is not active, but replay mode should prefer animated pawns and a concise event caption over static route marks.

## Client Animation

Use a dedicated LiveView hook for replay playback, for example `ReplayPlaybackHook`.

Responsibilities:

- Keep local playback state: selected event index, playing/paused, speed.
- Receive the server-provided replay event list from data attributes or pushed events.
- Animate pawn movement along each event path using the same DOM-cell path format used by `board_movement_animation.js`.
- Update frame captions and control states.
- Respect reduced motion by stepping frames without animated travel.

The server remains authoritative for the replay data. The client only controls playback of already revealed events.

## Board Rendering

Replay mode needs a derived board view:

- At frame 0, show initial detective pawn setup and thief entry.
- For each movement event, animate from `from` to `to` along `path`.
- After an event completes, place the pawn at `to`.
- For lock, steal, power, capture, and escape events, keep pawn positions stable and update the caption.

The first implementation can compute replay frames in Elixir and send a compact list to the hook. That keeps the JavaScript focused on playback mechanics rather than game interpretation.

## UX Copy

Use plain game-language labels:

- Button: `Replay round`
- Caption examples:
  - `Theo entered through D2.`
  - `Alice moved 3 spaces.`
  - `Theo checked the W1 lock. It was locked.`
  - `Theo stole A4.`
  - `Detectives caught Theo.`
  - `Theo escaped through W1.`

The replay panel should avoid instructional text during normal use. Controls should be self-explanatory and compact.

## Testing Strategy

Rules tests:

- Entering the museum records an `:enter` replay event.
- Detective movement records the final movement path for the turn.
- Thief movement records the final movement path and supports movement revision before end turn.
- Locked escape records `:lock_check` but not `:escape`.
- Successful escape records `:lock_check`, `:escape`, and stores replay events on the round result.
- Starting the next round resets active `replay_events`.

LiveView tests:

- Replay controls are absent during `:playing`.
- Replay controls are present during `:round_review`.
- Replay controls are present at `:game_over`.
- Latest completed round is selected by default.
- Selecting a previous round loads that round's replay event payload.
- Replay mode renders the thief visibly after the round is complete.

JavaScript tests:

- Replay playback advances through events in order.
- Pause freezes the current frame.
- Step forward/back updates the frame index.
- Speed changes the effective event duration.
- Reduced motion mode skips travel animation while preserving frame order.

## Migration Notes

There is no database migration because the game state is in memory. Existing in-progress games started before this feature has no replay timeline; the UI should simply hide replay controls when a completed round has no `replay_events`.

## Rollout

Implement in three stages:

1. Record replay events in the rules layer and attach them to round results.
2. Render replay availability and frame payloads in LiveView after completed rounds.
3. Add the playback hook and controls for animated replay.
