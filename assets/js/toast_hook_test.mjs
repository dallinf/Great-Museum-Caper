import assert from "node:assert/strict";
import test from "node:test";

import {toastDuration} from "./hooks/toast_hook.js";

test("toastDuration reads a per-toast display duration", () => {
  assert.equal(toastDuration({dataset: {toastDuration: "9000"}}), 9000);
});

test("toastDuration falls back to the default for missing or invalid values", () => {
  assert.equal(toastDuration({dataset: {}}), 4000);
  assert.equal(toastDuration({dataset: {toastDuration: "0"}}), 4000);
  assert.equal(toastDuration({dataset: {toastDuration: "later"}}), 4000);
});
