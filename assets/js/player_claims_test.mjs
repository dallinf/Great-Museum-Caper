import assert from "node:assert/strict";
import test from "node:test";

import {
  playerClaimForRoom,
  playerClaimKey,
  readPlayerClaim,
  rejoinPath,
  writePlayerClaim,
} from "./player_claims.js";

const memoryStorage = () => {
  const values = new Map();

  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, value);
    },
  };
};

test("player claims persist a browser player id per game", () => {
  const storage = memoryStorage();

  writePlayerClaim(
    {
      gameId: "game-1",
      playerId: "player-alice-secret",
      playerName: "Alice",
      playerColor: "red",
    },
    {storage}
  );

  assert.deepEqual(readPlayerClaim("game-1", {storage}), {
    gameId: "game-1",
    playerId: "player-alice-secret",
    playerName: "Alice",
    playerColor: "red",
  });
});

test("player claims ignore missing, invalid, and mismatched stored values", () => {
  const storage = memoryStorage();

  assert.equal(readPlayerClaim("game-1", {storage}), null);

  storage.setItem(playerClaimKey("game-1"), "{nope");
  assert.equal(readPlayerClaim("game-1", {storage}), null);

  storage.setItem(playerClaimKey("game-1"), JSON.stringify({gameId: "game-2", playerId: "p1"}));
  assert.equal(readPlayerClaim("game-1", {storage}), null);
});

test("playerClaimForRoom only returns claims that match the room roster", () => {
  const storage = memoryStorage();

  writePlayerClaim({gameId: "game-1", playerId: "player-alice-secret"}, {storage});

  assert.equal(playerClaimForRoom("game-1", ["player-bob-secret"], {storage}), null);

  assert.equal(
    playerClaimForRoom("game-1", ["player-alice-secret", "player-bob-secret"], {storage})
      .playerId,
    "player-alice-secret"
  );
});

test("rejoinPath links directly to the claimed player id", () => {
  assert.equal(
    rejoinPath("game-1", "player-alice-secret"),
    "/game/game-1?player_id=player-alice-secret"
  );
});
