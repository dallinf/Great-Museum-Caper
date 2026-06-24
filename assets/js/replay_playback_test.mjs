import assert from "node:assert/strict";
import test from "node:test";

import ReplayPlaybackHook from "./hooks/replay_playback_hook.js";
import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventDuration,
  replaceReplayState,
} from "./replay_playback.js";

const events = [
  {type: "enter", path: "6-1 6-2"},
  {type: "move", path: "6-2 6-3 6-4"},
  {type: "lock_check", path: "6-4"},
];

test("initialReplayState starts paused at the first event", () => {
  assert.deepEqual(initialReplayState(events), {
    events,
    index: 0,
    playing: false,
    speed: 1,
  });
});

test("nextReplayIndex stops at the final event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(nextReplayIndex(state), 2);
  assert.equal(nextReplayIndex({...state, index: 2}), 2);
});

test("previousReplayIndex stops at the first event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(previousReplayIndex(state), 0);
  assert.equal(previousReplayIndex({...state, index: 0}), 0);
});

test("replayEventDuration scales movement duration by speed", () => {
  assert.equal(replayEventDuration(events[1], 1), 240);
  assert.equal(replayEventDuration(events[1], 2), 120);
  assert.equal(replayEventDuration(events[1], 0.5), 480);
  assert.equal(replayEventDuration(events[2], 1), 700);
});

test("replaceReplayState resets playback while preserving selected speed", () => {
  const nextEvents = [{type: "move", path: "1-1 1-2"}];
  const state = {...initialReplayState(events), index: 2, playing: true, speed: 2};

  assert.deepEqual(replaceReplayState(state, nextEvents), {
    events: nextEvents,
    index: 0,
    playing: false,
    speed: 2,
  });
});

const buildHookFixture = replayEventsJSON => {
  const listeners = {};
  const caption = {textContent: ""};
  const speedInput = {value: "1"};
  const root = {
    addEventListener(type, handler) {
      listeners[type] = handler;
    },
    removeEventListener(type, handler) {
      if (listeners[type] === handler) {
        delete listeners[type];
      }
    },
    contains(element) {
      return Boolean(element?.isReplayControl);
    },
  };
  const el = {
    dataset: {replayEvents: replayEventsJSON},
    closest(selector) {
      return selector === "#replay-panel" ? root : null;
    },
    parentElement: root,
    querySelector(selector) {
      if (selector === "[data-replay-caption]") {
        return caption;
      }

      if (selector === "[data-replay-speed]") {
        return speedInput;
      }

      return null;
    },
  };
  const hook = {
    ...ReplayPlaybackHook,
    el,
    renderFrameCalls: 0,
    renderFrame() {
      this.renderFrameCalls += 1;
    },
  };

  return {caption, hook, listeners, root, speedInput};
};

test("ReplayPlaybackHook binds replay commands from the surrounding replay panel", () => {
  const {hook, listeners} = buildHookFixture(JSON.stringify(events));
  let receivedCommand = null;
  const replayButton = {
    isReplayControl: true,
    dataset: {replayCommand: "restart"},
    closest(selector) {
      return selector === "[data-replay-command]" ? this : null;
    },
  };

  hook.command = command => {
    receivedCommand = command;
  };

  hook.mounted();
  listeners.click({target: replayButton});

  assert.equal(receivedCommand, "restart");
});

test("ReplayPlaybackHook reloads replay events on LiveView update and keeps speed", () => {
  const {hook} = buildHookFixture(JSON.stringify(events));
  const nextEvents = [{type: "lock_check", path: "4-4", label: "Fresh payload"}];

  hook.mounted();
  hook.state = {...hook.state, index: 2, playing: true, speed: 2};
  hook.el.dataset.replayEvents = JSON.stringify(nextEvents);

  hook.updated();

  assert.equal(hook.renderFrameCalls, 2);
  assert.deepEqual(hook.state, {
    events: nextEvents,
    index: 0,
    playing: false,
    speed: 2,
  });
});
