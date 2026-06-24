import {movementDuration, parseMovePath} from "./board_movement_animation.js";

const NON_MOVEMENT_DURATION_MS = 700;

export const initialReplayState = events => ({
  events,
  index: 0,
  playing: false,
  speed: 1,
});

export const replaceReplayState = (state, events) => ({
  ...initialReplayState(events),
  speed:
    state && Number.isFinite(Number.parseFloat(state.speed))
      ? Number.parseFloat(state.speed)
      : 1,
});

export const nextReplayIndex = state =>
  Math.min(state.index + 1, Math.max(state.events.length - 1, 0));

export const previousReplayIndex = state => Math.max(state.index - 1, 0);

export const replayEventDuration = (event, speed = 1) => {
  const parsedPath = parseMovePath(event?.path);
  const baseDuration =
    parsedPath.length > 1 ? movementDuration(parsedPath) : NON_MOVEMENT_DURATION_MS;

  return Math.round(baseDuration / Number.parseFloat(speed || 1));
};
