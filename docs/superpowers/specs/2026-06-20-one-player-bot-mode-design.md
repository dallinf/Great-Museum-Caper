# One-Player Bot Mode Design

## Goal

Let a room with exactly one human player start a playable game by adding two automated bot players. Bots should take automatic legal turns so the solo player can continue playing without manually operating the bot seats.

## Requirements

- Show a "Start with Bots" control only to the host while the lobby has exactly one human player.
- Starting with bots adds two bot players to the game, then uses the normal game start flow for role assignment, turn order, setup, scoring, and rounds.
- Bot players must be identifiable in game state and in the player list UI.
- Bots act automatically during setup, thief entry, playing turns, and motion detector decisions.
- Bot choices can be simple and deterministic. They only need to choose legal actions and keep the game moving.
- Human-only multiplayer behavior remains unchanged.
- Existing two-player controlled-detective behavior remains unchanged when two human players start a game.

## Architecture

Add bot metadata to player maps with a boolean `bot?` field. Human players created through lobby joins have `bot?: false`; bot players created by the server have `bot?: true`. Player IDs will be deterministic per room, such as `bot-1` and `bot-2`, so tests and reconnect behavior are predictable.

The game server will expose a bot start option through `start_game/3`. When `with_bots?: true`, the server validates that the caller is the host and exactly one non-bot player is in the lobby, adds two bot players with available pawn colors, and then runs the existing start-game role assignment. Normal starts still require at least two players.

Add a `MuseumCaper.Game.Bot` decision module that returns one legal action at a time for the current bot-controlled state. The module will use existing rule APIs instead of duplicating legality:

- During setup, detective bots place locks, paintings, cameras, and detective pawns using stable candidate lists.
- During thief entry, a thief bot enters through the first available entry.
- During play, a thief bot moves to a legal destination, preferring artwork when reachable, otherwise the first legal move.
- During play, a detective bot moves to the first legal destination and spends the rolled look action with the simplest available option.
- During motion detector prompts, a thief bot allows the reading.
- When a bot turn has no remaining useful action and can legally end, it ends its turn.

The server will schedule bot work after every successful state mutation and after a bot-mode game starts. A short delayed `:run_bots` message prevents nested GenServer calls and keeps UI broadcasts visible. The server will apply bot actions while the current actor is a bot, stopping when control returns to a human, the game reaches `:game_over`, or a fixed safety step limit is reached.

## UI

The waiting-room panel keeps the existing Limited and Full Game buttons for normal multiplayer starts. With exactly one human player, those buttons stay disabled and a new enabled "Start with Bots" button appears. Bot rows in the player list show a compact "Bot" badge next to their role so the solo player can tell which seats are automated.

## Testing

- Server tests cover one-human bot start, validation failures for invalid bot starts, bot metadata, and unchanged normal start requirements.
- Bot tests cover setup progression, thief entry, detective turn progression, thief turn progression, and bot motion detector decisions.
- LiveView tests cover the one-player bot-start button, bot row badges, and no bot-start option for non-hosts or rooms with multiple human players.

