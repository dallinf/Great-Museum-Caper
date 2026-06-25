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
  replayFrameObjects,
} from "./replay_playback.js";

const events = [
  {type: "enter", path: "6-1 6-2"},
  {type: "move", path: "6-2 6-3 6-4"},
  {type: "lock_check", path: "6-4"},
];

const eventsWithSetup = [
  {
    type: "setup",
    actor_id: "player-dad:detective-1",
    actor_role: "detective",
    actor_color: "purple",
    path: "7-6",
    label: "Unknown player started at 7-6.",
  },
  {
    type: "setup",
    actor_id: "player-dad:detective-2",
    actor_role: "detective",
    actor_color: "purple",
    path: "2-7",
    label: "Unknown player started at 2-7.",
  },
  {
    type: "enter",
    actor_id: "player-russ",
    actor_role: "thief",
    actor_color: "grey",
    path: "4-1",
    label: "Russ entered through W4.",
  },
  {
    type: "move",
    actor_id: "player-russ",
    actor_role: "thief",
    actor_color: "grey",
    path: "4-1 3-1",
    label: "Russ moved 1 space.",
  },
];

test("initialReplayState starts paused at the first event", () => {
  assert.deepEqual(initialReplayState(events), {
    events,
    index: 0,
    playing: false,
    speed: 1,
  });
});

test("initialReplayState skips setup events for playback", () => {
  assert.deepEqual(initialReplayState(eventsWithSetup), {
    events: eventsWithSetup,
    index: 2,
    playing: false,
    speed: 1,
  });
});

test("nextReplayIndex stops at the final event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(nextReplayIndex(state), 2);
  assert.equal(nextReplayIndex({...state, index: 2}), 2);
});

test("nextReplayIndex and previousReplayIndex skip setup events", () => {
  const state = initialReplayState(eventsWithSetup);

  assert.equal(previousReplayIndex({...state, index: 2}), 2);
  assert.equal(nextReplayIndex({...state, index: 0}), 2);
  assert.equal(nextReplayIndex({...state, index: 2}), 3);
});

test("previousReplayIndex stops at the first event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(previousReplayIndex(state), 0);
  assert.equal(previousReplayIndex({...state, index: 0}), 0);
});

test("replayEventDuration scales movement duration by speed", () => {
  assert.equal(replayEventDuration(events[1], 1), 480);
  assert.equal(replayEventDuration(events[1], 2), 240);
  assert.equal(replayEventDuration(events[1], 0.5), 960);
  assert.equal(replayEventDuration(events[2], 1), 1400);
});

test("replaceReplayState resets playback while preserving selected speed", () => {
  const nextEvents = [
    {type: "setup", actor_role: "detective", path: "1-1"},
    {type: "move", path: "1-1 1-2"},
  ];
  const state = {...initialReplayState(events), index: 2, playing: true, speed: 2};

  assert.deepEqual(replaceReplayState(state, nextEvents), {
    events: nextEvents,
    index: 1,
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

  assert.deepEqual(replayFrameActors(actorEvents, 0), {
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
  });

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

test("replayFrameActors normalizes controlled detective pawn colors", () => {
  const actorEvents = [
    {
      type: "setup",
      actor_id: "bob:detective-1",
      actor_role: "detective",
      actor_color: "purple",
      path: "3-9",
      from: "3-9",
      to: "3-9",
    },
    {
      type: "setup",
      actor_id: "bob:detective-2",
      actor_role: "detective",
      actor_color: "purple",
      path: "9-5",
      from: "9-5",
      to: "9-5",
    },
  ];

  assert.deepEqual(replayFrameActors(actorEvents, 0), {
    "bob:detective-1": {
      actor_id: "bob:detective-1",
      actor_role: "detective",
      actor_color: "purple",
      position: {row: 3, col: 9},
    },
    "bob:detective-2": {
      actor_id: "bob:detective-2",
      actor_role: "detective",
      actor_color: "green",
      position: {row: 9, col: 5},
    },
  });
});

test("replayFrameObjects keeps camera and artwork state through replay", () => {
  const objectEvents = [
    {
      type: "artwork",
      object_id: "A1",
      object_label: "A1",
      path: "3-7",
      from: "3-7",
      to: "3-7",
      result: "present",
    },
    {
      type: "camera",
      object_id: "1",
      object_label: "Camera 1",
      path: "4-6",
      from: "4-6",
      to: "4-6",
      result: "active",
    },
    {
      type: "artwork",
      object_id: "A2",
      path: "5-7",
      from: "5-7",
      to: "5-7",
      result: "present",
    },
    {
      type: "artwork",
      object_id: "A1",
      object_label: "A1",
      path: "3-7",
      from: "3-7",
      to: "3-7",
      result: "targeted",
    },
    {
      type: "camera",
      object_id: "1",
      object_label: "Camera 1",
      path: "4-6",
      from: "4-6",
      to: "4-6",
      result: "disabled",
    },
    {
      type: "steal",
      actor_id: "t",
      actor_role: "thief",
      path: "3-7",
      from: "3-7",
      to: "3-7",
      result: "stolen",
    },
  ];

  assert.deepEqual(replayFrameObjects(objectEvents, 0), {
    "artwork:A1": {
      id: "A1",
      kind: "artwork",
      label: "A1",
      position: {row: 3, col: 7},
      status: "present",
    },
    "camera:1": {
      id: "1",
      kind: "camera",
      label: "Camera 1",
      position: {row: 4, col: 6},
      status: "active",
    },
    "artwork:A2": {
      id: "A2",
      kind: "artwork",
      label: "A2",
      position: {row: 5, col: 7},
      status: "present",
    },
  });

  assert.equal(replayFrameObjects(objectEvents, 4)["artwork:A1"].status, "targeted");
  assert.equal(replayFrameObjects(objectEvents, 4)["camera:1"].status, "disabled");
  assert.equal(replayFrameObjects(objectEvents, 5)["artwork:A1"].status, "removed");
});

const buildHookFixture = replayEventsJSON => {
  const listeners = {};
  const caption = {textContent: ""};
  const speedInput = {value: "1"};
  const modeButtons = {
    path: {
      attributes: {},
      classList: {
        values: new Set(),
        toggle(token, force) {
          if (force) {
            this.values.add(token);
          } else {
            this.values.delete(token);
          }
        },
      },
      setAttribute(name, value) {
        this.attributes[name] = value;
      },
    },
    replay: {
      attributes: {},
      classList: {
        values: new Set(),
        toggle(token, force) {
          if (force) {
            this.values.add(token);
          } else {
            this.values.delete(token);
          }
        },
      },
      setAttribute(name, value) {
        this.attributes[name] = value;
      },
    },
  };
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
      if (selector === "[data-replay-command='play']") {
        return playButton;
      }

      const modeMatch = selector.match(/\[data-replay-mode='(path|replay)'\]/);
      if (modeMatch) {
        return modeButtons[modeMatch[1]];
      }

      return null;
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

  return {caption, hook, listeners, modeButtons, pauseIcon, playButton, playIcon, root, speedInput};
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

  assert.equal(hook.renderFrameCalls, 1);
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

test("ReplayPlaybackHook starts in finished path mode and switches into replay mode", () => {
  const {hook, listeners, modeButtons} = buildHookFixture(JSON.stringify(events));
  let cleared = false;
  let rendered = false;

  hook.clearLayer = () => {
    cleared = true;
  };
  hook.renderFrame = () => {
    rendered = true;
  };
  hook.setBoardReplayMode = mode => {
    hook.lastBoardMode = mode;
  };

  hook.mounted();

  assert.equal(hook.mode, "path");
  assert.equal(hook.lastBoardMode, "path");
  assert.equal(cleared, true);
  assert.equal(modeButtons.path.attributes["aria-pressed"], "true");

  listeners.click({
    target: {
      isReplayControl: true,
      dataset: {replayMode: "replay"},
      closest(selector) {
        return selector === "[data-replay-mode]" ? this : null;
      },
    },
  });

  assert.equal(hook.mode, "replay");
  assert.equal(hook.lastBoardMode, "replay");
  assert.equal(rendered, true);
  assert.equal(modeButtons.replay.attributes["aria-pressed"], "true");
});

test("ReplayPlaybackHook restarts at the first playable replay event", () => {
  const {hook} = buildHookFixture(JSON.stringify(eventsWithSetup));

  hook.renderFrame = () => {};
  hook.mounted();
  hook.state = {...hook.state, index: 3};

  hook.command("restart");

  assert.equal(hook.state.index, 2);
});

test("ReplayPlaybackHook reads board object marks as active replay baseline", () => {
  const {hook} = buildHookFixture(JSON.stringify(events));
  const originalDocument = globalThis.document;
  const paintingMark = {
    dataset: {boardMark: "painting", markStatus: "removed"},
    textContent: "A4",
    closest(selector) {
      return selector === "[id^='cell-']" ? {id: "cell-3-3"} : null;
    },
  };
  const cameraMark = {
    dataset: {boardMark: "camera", markStatus: "disabled"},
    textContent: "C2",
    closest(selector) {
      return selector === "[id^='cell-']" ? {id: "cell-4-6"} : null;
    },
  };

  globalThis.document = {
    querySelectorAll(selector) {
      assert.equal(selector, "#museum-board [data-board-mark-layer='objects'] [data-board-mark]");
      return [paintingMark, cameraMark];
    },
  };

  try {
    assert.deepEqual(hook.boardBaselineObjects(), {
      "artwork:A4": {
        id: "A4",
        kind: "artwork",
        label: "A4",
        position: {row: 3, col: 3},
        status: "present",
      },
      "camera:C2": {
        id: "C2",
        kind: "camera",
        label: "C2",
        position: {row: 4, col: 6},
        status: "active",
      },
    });
  } finally {
    globalThis.document = originalDocument;
  }
});

test("ReplayPlaybackHook renders detective replay pawns as color-only dots", () => {
  const {hook} = buildHookFixture(JSON.stringify(events));
  const marker = {
    dataset: {},
    className: "",
    textContent: "P",
    title: "",
  };
  const layer = {
    querySelector() {
      return null;
    },
    appendChild(child) {
      this.child = child;
    },
  };
  const originalDocument = globalThis.document;

  globalThis.document = {
    createElement() {
      return marker;
    },
  };

  try {
    hook.markerForActor(layer, {
      actor_id: "bob:detective-2",
      actor_role: "detective",
      actor_color: "green",
    });
  } finally {
    globalThis.document = originalDocument;
  }

  assert.equal(layer.child, marker);
  assert.match(marker.className, /replay-pawn-green/);
  assert.equal(marker.textContent, "");
  assert.equal(marker.title, "green detective");
});
