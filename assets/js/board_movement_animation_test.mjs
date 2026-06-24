import assert from "node:assert/strict";
import test from "node:test";

import {
  movementDuration,
  parseMovePath,
  pathCellId,
} from "./board_movement_animation.js";

test("parseMovePath converts row-column tokens into ordered cells", () => {
  assert.deepEqual(parseMovePath("2-4 3-4 3-5"), [
    {row: 2, col: 4},
    {row: 3, col: 4},
    {row: 3, col: 5},
  ]);
});

test("parseMovePath ignores malformed cells", () => {
  assert.deepEqual(parseMovePath("2-4 nope 3-x 3-5"), [
    {row: 2, col: 4},
    {row: 3, col: 5},
  ]);
});

test("movementDuration is quick per step and capped for long routes", () => {
  assert.equal(movementDuration([{row: 1, col: 1}]), 0);
  assert.equal(movementDuration([{row: 1, col: 1}, {row: 1, col: 2}]), 180);
  assert.equal(movementDuration(parseMovePath("1-1 1-2 1-3 1-4")), 360);
  assert.equal(movementDuration(parseMovePath("1-1 1-2 1-3 1-4 1-5 1-6 1-7 1-8 1-9 1-10")), 900);
});

test("pathCellId matches the board cell DOM id convention", () => {
  assert.equal(pathCellId({row: 6, col: 3}), "cell-6-3");
});
