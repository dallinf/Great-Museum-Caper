import assert from "node:assert/strict";
import test from "node:test";

import {
  applyRejoinLinks,
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

test("rejoinPath preserves the Phoenix-generated base path", () => {
  assert.equal(
    rejoinPath("game-1", "player-alice-secret", {
      basePath: "/museum_caper/game/game-1",
    }),
    "/museum_caper/game/game-1?player_id=player-alice-secret"
  );
});

test("applyRejoinLinks keeps the Phoenix-generated rejoin href prefix", () => {
  const storage = memoryStorage();
  writePlayerClaim({gameId: "game-1", playerId: "player-alice-secret"}, {storage});

  const removedClasses = [];
  const link = {
    dataset: {
      gameId: "game-1",
      roomPlayerIds: "player-alice-secret",
    },
    href: "/museum_caper/game/game-1",
    getAttribute(name) {
      return name === "href" ? this.href : null;
    },
    classList: {
      remove(name) {
        removedClasses.push(name);
      },
      add() {},
    },
  };

  applyRejoinLinks(
    {
      querySelectorAll(selector) {
        assert.equal(selector, "[data-rejoin-link]");
        return [link];
      },
    },
    {storage}
  );

  assert.equal(link.href, "/museum_caper/game/game-1?player_id=player-alice-secret");
  assert.equal(link.dataset.rejoinPlayerId, "player-alice-secret");
  assert.deepEqual(removedClasses, ["hidden"]);
});
