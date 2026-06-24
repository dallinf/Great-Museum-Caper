import assert from "node:assert/strict";
import test from "node:test";

import ReplayPlaybackHook from "./hooks/replay_playback_hook.js";
import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventPath,
  replayEventDuration,
  replayFrameActors,
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

test("replayEventPath falls back to from and to when the serialized path is incomplete", () => {
  assert.deepEqual(
    replayEventPath({
      type: "escape",
      path: "10-6",
      from: "10-6",
      to: "11-6",
    }),
    [
      {row: 10, col: 6},
      {row: 11, col: 6},
    ]
  );

  assert.deepEqual(
    replayEventPath({
      type: "escape",
      path: "1-5",
      from: "1-5",
      to: "1-5",
    }),
    [{row: 1, col: 5}]
  );
});

test("replayFrameActors preserves every actor position through the event timeline", () => {
  const actorEvents = [
    {
      type: "setup",
      actor_id: "d1",
      actor_role: "detective",
      actor_color: "red",
      path: "3-9",
      from: "3-9",
      to: "3-9",
    },
    {
      type: "setup",
      actor_id: "d2",
      actor_role: "detective",
      actor_color: "blue",
      path: "9-5",
      from: "9-5",
      to: "9-5",
    },
    {
      type: "enter",
      actor_id: "t",
      actor_role: "thief",
      actor_color: "grey",
      path: "6-1 6-2",
      from: "6-1",
      to: "6-2",
    },
    {
      type: "move",
      actor_id: "d1",
      actor_role: "detective",
      actor_color: "red",
      path: "3-9 3-8",
      from: "3-9",
      to: "3-8",
    },
  ];

  assert.deepEqual(replayFrameActors(actorEvents, 2), {
    d1: {
      actor_id: "d1",
      actor_role: "detective",
      actor_color: "red",
      position: {row: 3, col: 9},
    },
    d2: {
      actor_id: "d2",
      actor_role: "detective",
      actor_color: "blue",
      position: {row: 9, col: 5},
    },
    t: {
      actor_id: "t",
      actor_role: "thief",
      actor_color: "grey",
      position: {row: 6, col: 2},
    },
  });

  assert.deepEqual(replayFrameActors(actorEvents, 3).d1.position, {row: 3, col: 8});
  assert.deepEqual(replayFrameActors(actorEvents, 3).d2.position, {row: 9, col: 5});
  assert.deepEqual(replayFrameActors(actorEvents, 3).t.position, {row: 6, col: 2});
});

const buildHookFixture = replayEventsJSON => {
  const listeners = {};
  const caption = {textContent: ""};
  const speedInput = {value: "1"};
  const playIcon = {
    classList: {
      values: new Set(),
      add(...tokens) {
        tokens.forEach(token => this.values.add(token));
      },
      remove(...tokens) {
        tokens.forEach(token => this.values.delete(token));
      },
      toggle(token, force) {
        if (force === undefined) {
          if (this.values.has(token)) {
            this.values.delete(token);
          } else {
            this.values.add(token);
          }

          return this.values.has(token);
        }

        if (force) {
          this.values.add(token);
        } else {
          this.values.delete(token);
        }

        return force;
      },
      contains(token) {
        return this.values.has(token);
      },
    },
  };
  const pauseIcon = {
    classList: {
      values: new Set(["hidden"]),
      add(...tokens) {
        tokens.forEach(token => this.values.add(token));
      },
      remove(...tokens) {
        tokens.forEach(token => this.values.delete(token));
      },
      toggle(token, force) {
        if (force === undefined) {
          if (this.values.has(token)) {
            this.values.delete(token);
          } else {
            this.values.add(token);
          }

          return this.values.has(token);
        }

        if (force) {
          this.values.add(token);
        } else {
          this.values.delete(token);
        }

        return force;
      },
      contains(token) {
        return this.values.has(token);
      },
    },
  };
  const playButton = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    querySelector(selector) {
      if (selector === "[data-replay-play-icon]") {
        return playIcon;
      }

      if (selector === "[data-replay-pause-icon]") {
        return pauseIcon;
      }

      return null;
    },
  };
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
    querySelector(selector) {
      return selector === "[data-replay-command='play']" ? playButton : null;
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

  return {caption, hook, listeners, pauseIcon, playButton, playIcon, root, speedInput};
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

test("ReplayPlaybackHook updates the visible play icon state when playback toggles", () => {
  const {hook, pauseIcon, playButton, playIcon} = buildHookFixture(JSON.stringify(events));

  hook.mounted();
  assert.equal(playButton.attributes["aria-label"], "Play replay");
  assert.equal(playButton.attributes["aria-pressed"], "false");
  assert.equal(playIcon.classList.contains("hidden"), false);
  assert.equal(pauseIcon.classList.contains("hidden"), true);

  hook.state = {...hook.state, playing: true};
  hook.updateControlState();

  assert.equal(playButton.attributes["aria-label"], "Pause replay");
  assert.equal(playButton.attributes["aria-pressed"], "true");
  assert.equal(playIcon.classList.contains("hidden"), true);
  assert.equal(pauseIcon.classList.contains("hidden"), false);
});
