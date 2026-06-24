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

const sameCell = (a, b) => a && b && a.row === b.row && a.col === b.col;

const firstParsedCell = value => parseMovePath(value)[0];

export const replayEventPath = event => {
  const parsedPath = parseMovePath(event?.path);

  if (parsedPath.length > 1) {
    return parsedPath;
  }

  const from = firstParsedCell(event?.from);
  const to = firstParsedCell(event?.to);

  if (from && to) {
    return sameCell(from, to) ? [to] : [from, to];
  }

  if (parsedPath.length === 1) {
    return parsedPath;
  }

  if (to) {
    return [to];
  }

  if (from) {
    return [from];
  }

  return [];
};

export const replayFrameActors = (events, index) =>
  events.slice(0, Math.max(index + 1, 0)).reduce((actors, event) => {
    const actorId = event?.actor_id;
    const path = replayEventPath(event);
    const position = path[path.length - 1];

    if (!actorId || !position) {
      return actors;
    }

    return {
      ...actors,
      [actorId]: {
        actor_id: actorId,
        actor_role: event.actor_role,
        actor_color: event.actor_color,
        position,
      },
    };
  }, {});

export const replayEventDuration = (event, speed = 1) => {
  const parsedPath = replayEventPath(event);
  const baseDuration =
    parsedPath.length > 1 ? movementDuration(parsedPath) : NON_MOVEMENT_DURATION_MS;

  const parsedSpeed = Number.parseFloat(speed || 1);
  const safeSpeed = Number.isFinite(parsedSpeed) && parsedSpeed > 0 ? parsedSpeed : 1;

  return Math.round(baseDuration / safeSpeed);
};
