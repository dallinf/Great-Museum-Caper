import {movementDuration, parseMovePath} from "./board_movement_animation.js";

const NON_MOVEMENT_DURATION_MS = 700;
const SPEED_SLOWDOWN_FACTOR = 2;
const PAWN_COLORS = ["purple", "green", "blue", "white", "red", "yellow"];

const playableReplayEvent = event => event?.type !== "setup" && event?.actor_role !== "museum";

export const replayStartIndex = events => {
  const index = events.findIndex(playableReplayEvent);

  return index === -1 ? 0 : index;
};

export const initialReplayState = events => ({
  events,
  index: replayStartIndex(events),
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

const playableReplayIndexes = events =>
  events.reduce(
    (indexes, event, index) => (playableReplayEvent(event) ? [...indexes, index] : indexes),
    []
  );

export const nextReplayIndex = state => {
  const indexes = playableReplayIndexes(state.events);

  return indexes.find(index => index > state.index) ??
    indexes[indexes.length - 1] ??
    replayStartIndex(state.events);
};

export const previousReplayIndex = state => {
  const previousIndexes = playableReplayIndexes(state.events).filter(index => index < state.index);

  return previousIndexes[previousIndexes.length - 1] ?? replayStartIndex(state.events);
};

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

const actorFromEvent = event => {
  if (event?.actor_role === "museum") {
    return null;
  }

  const actorId = event?.actor_id;
  const path = replayEventPath(event);
  const position = path[path.length - 1];

  if (!actorId || !position) {
    return null;
  }

  return {
    actor_id: actorId,
    actor_role: event.actor_role,
    actor_color: event.actor_color,
    position,
  };
};

const putActor = (actors, actor) =>
  actor
    ? {
        ...actors,
        [actor.actor_id]: actor,
      }
    : actors;

const controlledDetectiveInfo = actorId => {
  const match = `${actorId}`.match(/^(?<controller>.+):detective-(?<index>\d+)$/);

  return match
    ? {
        controller: match.groups.controller,
        index: Number.parseInt(match.groups.index, 10),
      }
    : null;
};

const controlledDetectiveColor = (baseColor, index) => {
  if (index <= 1) {
    return baseColor || "grey";
  }

  const alternateColors = PAWN_COLORS.filter(color => color !== baseColor);

  return alternateColors[index - 2] || baseColor || "grey";
};

const normalizeControlledDetectiveColors = actors => {
  const controlledGroups = Object.values(actors).reduce((groups, actor) => {
    const info = controlledDetectiveInfo(actor.actor_id);

    if (!info || actor.actor_role !== "detective") {
      return groups;
    }

    return {
      ...groups,
      [info.controller]: [...(groups[info.controller] || []), {...actor, controlledIndex: info.index}],
    };
  }, {});

  return Object.values(controlledGroups).reduce((normalizedActors, group) => {
    const baseColor =
      group.find(actor => actor.controlledIndex === 1)?.actor_color ||
      group[0]?.actor_color ||
      "grey";

    return group.reduce(
      (nextActors, actor) => ({
        ...nextActors,
        [actor.actor_id]: {
          ...nextActors[actor.actor_id],
          actor_color: controlledDetectiveColor(baseColor, actor.controlledIndex),
        },
      }),
      normalizedActors
    );
  }, actors);
};

const initialReplayActors = events =>
  events.reduce((actors, event) => {
    const actor = actorFromEvent(event);

    return event?.type === "setup" && actor?.actor_role === "detective"
      ? putActor(actors, actor)
      : actors;
  }, {});

export const replayFrameActors = (events, index) =>
  normalizeControlledDetectiveColors(
    events
      .slice(0, Math.max(index + 1, 0))
      .reduce(
        (actors, event) => putActor(actors, actorFromEvent(event)),
        initialReplayActors(events)
      )
  );

const objectKey = (kind, id, position) =>
  `${kind}:${id || (position ? `${position.row}-${position.col}` : "unknown")}`;

const objectFromEvent = event => {
  const path = replayEventPath(event);
  const position = path[path.length - 1];

  if (!position) {
    return null;
  }

  if (event?.type === "artwork") {
    return {
      id: event.object_id || event.object_label,
      kind: "artwork",
      label: event.object_label || event.object_id || "Artwork",
      position,
      status: event.result || "present",
    };
  }

  if (event?.type === "camera") {
    return {
      id: event.object_id || event.object_label,
      kind: "camera",
      label: event.object_label || event.object_id || "Camera",
      position,
      status: event.result || "active",
    };
  }

  if (event?.type === "steal") {
    return {
      id: event.object_id || event.object_label,
      kind: "artwork",
      label: event.object_label || event.object_id || "Artwork",
      position,
      status: "removed",
    };
  }

  return null;
};

const initialObject = object =>
  (object.kind === "artwork" && object.status === "present") ||
  (object.kind === "camera" && object.status === "active");

const putObject = (objects, event, incomingObject) => {
  let object = incomingObject;

  if (!object) {
    return objects;
  }

  if (event?.type === "steal" && !event.object_id && !event.object_label) {
    const matchingArtwork = Object.values(objects).find(
      existing =>
        existing.kind === "artwork" &&
        sameCell(existing.position, object.position)
    );

    if (matchingArtwork) {
      object = {
        ...object,
        id: matchingArtwork.id,
        label: matchingArtwork.label,
      };
    }
  }

  return {
    ...objects,
    [objectKey(object.kind, object.id, object.position)]: object,
  };
};

const initialReplayObjects = events =>
  events.reduce((objects, event) => {
    const object = objectFromEvent(event);

    return object && initialObject(object) ? putObject(objects, event, object) : objects;
  }, {});

export const replayFrameObjects = (events, index, baselineObjects = {}) =>
  events
    .slice(0, Math.max(index + 1, 0))
    .reduce(
      (objects, event) => putObject(objects, event, objectFromEvent(event)),
      {...baselineObjects, ...initialReplayObjects(events)}
    );

export const replayEventDuration = (event, speed = 1) => {
  const parsedPath = replayEventPath(event);
  const baseDuration =
    parsedPath.length > 1 ? movementDuration(parsedPath) : NON_MOVEMENT_DURATION_MS;

  const parsedSpeed = Number.parseFloat(speed || 1);
  const safeSpeed = Number.isFinite(parsedSpeed) && parsedSpeed > 0 ? parsedSpeed : 1;

  return Math.round((baseDuration * SPEED_SLOWDOWN_FACTOR) / safeSpeed);
};
