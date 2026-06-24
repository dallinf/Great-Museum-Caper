import assert from "node:assert/strict";
import test from "node:test";

import {
  GAME_AUDIO_STORAGE_KEY,
  gameAudioEnabled,
  setGameAudioEnabled,
} from "./game_audio_preference.js";

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

test("game audio is disabled when no browser preference is stored", () => {
  assert.equal(gameAudioEnabled({storage: memoryStorage()}), false);
});

test("game audio persists enabled and disabled states", () => {
  const storage = memoryStorage();

  setGameAudioEnabled(true, {storage});
  assert.equal(storage.getItem(GAME_AUDIO_STORAGE_KEY), "true");
  assert.equal(gameAudioEnabled({storage}), true);

  setGameAudioEnabled(false, {storage});
  assert.equal(storage.getItem(GAME_AUDIO_STORAGE_KEY), "false");
  assert.equal(gameAudioEnabled({storage}), false);
});

test("game audio falls back to disabled when browser storage is blocked", () => {
  const originalWindow = globalThis.window;

  globalThis.window = {
    get localStorage() {
      throw new Error("storage blocked");
    },
  };

  try {
    assert.equal(gameAudioEnabled(), false);
  } finally {
    if (originalWindow === undefined) {
      delete globalThis.window;
    } else {
      globalThis.window = originalWindow;
    }
  }
});
