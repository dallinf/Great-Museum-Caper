import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventPath,
  replayEventDuration,
  replayFrameActors,
  replayFrameObjects,
  replayStartIndex,
  replaceReplayState,
} from "../replay_playback.js";
import {pathCellId} from "../board_movement_animation.js";

const pawnClass = event =>
  `replay-pawn replay-pawn-${event.actor_role} replay-pawn-${event.actor_color || "grey"}`;

const pawnText = actor => (actor.actor_role === "thief" ? "T" : "");

const replayObjectKey = object =>
  `${object.kind}:${object.id || `${object.position.row}-${object.position.col}`}`;

const replayCaption = event => (event.type === "setup" ? "" : event.label || "");

const replayModeButtonActiveClass = "bg-sky-300 text-slate-950 border-sky-200";

const centerOf = element => {
  const rect = element.getBoundingClientRect();

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
};

const ReplayPlaybackHook = {
  mounted() {
    this.replayEventsJSON = this.el.dataset.replayEvents || "[]";
    this.state = initialReplayState(this.eventsFromJSON(this.replayEventsJSON));
    this.mode = "path";
    this.root = this.controlRoot();
    this.handleControlClick = event => {
      const modeButton = event.target.closest("[data-replay-mode]");

      if (modeButton && this.root.contains(modeButton)) {
        this.setMode(modeButton.dataset.replayMode);
        return;
      }

      const button = event.target.closest("[data-replay-command]");

      if (!button || !this.root.contains(button)) {
        return;
      }

      this.command(button.dataset.replayCommand);
    };
    this.handleChange = event => {
      if (!event.target.matches("[data-replay-speed]")) {
        return;
      }

      this.state = {...this.state, speed: Number.parseFloat(event.target.value || "1")};
    };
    this.root.addEventListener("click", this.handleControlClick);
    this.root.addEventListener("change", this.handleChange);
    this.reducedMotion =
      typeof window !== "undefined" &&
      window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
    this.bindControls();
    this.setMode("path");
  },
  updated() {
    this.bindControls();

    const replayEventsJSON = this.el.dataset.replayEvents || "[]";

    if (replayEventsJSON === this.replayEventsJSON) {
      return;
    }

    this.replayEventsJSON = replayEventsJSON;
    this.stop();
    this.state = replaceReplayState(this.state, this.eventsFromJSON(replayEventsJSON));
    this.renderFrame();
  },
  destroyed() {
    this.stop();
    this.clearLayer();
    this.setBoardReplayMode("path");
    this.root?.removeEventListener("click", this.handleControlClick);
    this.root?.removeEventListener("change", this.handleChange);
  },
  events() {
    return this.eventsFromJSON(this.el.dataset.replayEvents || "[]");
  },
  eventsFromJSON(replayEventsJSON) {
    try {
      return JSON.parse(replayEventsJSON || "[]");
    } catch (_error) {
      return [];
    }
  },
  controlRoot() {
    return this.el.closest("#replay-panel") || this.el.parentElement || this.el;
  },
  bindControls() {
    this.caption = this.el.querySelector("[data-replay-caption]");
    this.playButton = this.root.querySelector?.("[data-replay-command='play']");
    this.playIcon = this.playButton?.querySelector?.("[data-replay-play-icon]");
    this.pauseIcon = this.playButton?.querySelector?.("[data-replay-pause-icon]");
    this.pathModeButton = this.root.querySelector?.("[data-replay-mode='path']");
    this.replayModeButton = this.root.querySelector?.("[data-replay-mode='replay']");
    this.speedInput = this.el.querySelector("[data-replay-speed]");

    if (this.speedInput) {
      this.speedInput.value = `${this.state.speed}`;
    }

    this.updateControlState();
    this.updateModeControls();
  },
  command(command) {
    if (command === "play") {
      this.setMode("replay");
      this.togglePlay();
    } else if (command === "back") {
      this.setMode("replay");
      this.stop();
      this.state = {...this.state, index: previousReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "forward") {
      this.setMode("replay");
      this.stop();
      this.state = {...this.state, index: nextReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "restart") {
      this.setMode("replay");
      this.stop();
      this.state = {...this.state, index: replayStartIndex(this.state.events)};
      this.renderFrame();
    } else if (command === "exit") {
      this.setMode("path");
    }
  },
  setMode(mode) {
    const nextMode = mode === "replay" ? "replay" : "path";

    if (nextMode === "path") {
      this.stop();
      this.mode = "path";
      this.setBoardReplayMode("path");
      this.clearLayer();

      if (this.caption) {
        this.caption.textContent = "";
      }

      this.updateModeControls();
      return;
    }

    this.mode = "replay";
    this.setBoardReplayMode("replay");
    this.updateModeControls();
    this.renderFrame();
  },
  togglePlay() {
    if (this.state.playing) {
      this.stop();
    } else {
      this.state = {...this.state, playing: true};
      this.playCurrent();
    }
  },
  playCurrent() {
    this.renderFrame();

    if (!this.state.playing || this.state.index >= this.state.events.length - 1) {
      this.state = {...this.state, playing: false};
      this.updateControlState();
      return;
    }

    const event = this.state.events[this.state.index];
    const duration = replayEventDuration(event, this.state.speed);

    this.timer = setTimeout(() => {
      this.state = {...this.state, index: nextReplayIndex(this.state)};
      this.playCurrent();
    }, duration);
  },
  stop() {
    clearTimeout(this.timer);
    this.timer = null;
    this.cancelAnimations();
    this.state = {...this.state, playing: false};
    this.updateControlState();
  },
  renderFrame() {
    if (this.mode !== "replay") {
      this.clearLayer();
      return;
    }

    const event = this.state.events[this.state.index];

    if (!event) {
      this.clearLayer();
      return;
    }

    if (this.caption) {
      this.caption.textContent = replayCaption(event);
    }

    this.renderReplayLayer(event);
    this.updateControlState();
  },
  renderReplayLayer(currentEvent) {
    const layer = this.layer();
    const actors = replayFrameActors(this.state.events, this.state.index);
    const objects = replayFrameObjects(
      this.state.events,
      this.state.index,
      this.boardBaselineObjects()
    );
    this.renderObjects(layer, objects);
    this.renderPawns(layer, actors, currentEvent);
  },
  boardBaselineObjects() {
    if (typeof document === "undefined") {
      return {};
    }

    return Array.from(
      document.querySelectorAll("#museum-board [data-board-mark-layer='objects'] [data-board-mark]")
    ).reduce((objects, mark) => {
      const object = this.baselineObjectFromMark(mark);

      return object ? {...objects, [replayObjectKey(object)]: object} : objects;
    }, {});
  },
  baselineObjectFromMark(mark) {
    const cell = mark.closest?.("[id^='cell-']");
    const match = `${cell?.id || ""}`.match(/^cell-(\d+)-(\d+)$/);
    const label = `${mark.textContent || ""}`.trim();

    if (!match || !label) {
      return null;
    }

    const position = {row: Number.parseInt(match[1], 10), col: Number.parseInt(match[2], 10)};

    if (mark.dataset.boardMark === "painting") {
      return {
        id: label,
        kind: "artwork",
        label,
        position,
        status: "present",
      };
    }

    if (mark.dataset.boardMark === "camera") {
      return {
        id: label,
        kind: "camera",
        label,
        position,
        status: "active",
      };
    }

    return null;
  },
  renderPawns(layer, actors, currentEvent) {
    const actorIds = new Set(Object.keys(actors));

    this.cancelAnimations();

    Object.values(actors).forEach(actor => {
      const marker = this.markerForActor(layer, actor);
      this.placeMarker(marker, actor.position);

      if (actor.actor_id === currentEvent.actor_id) {
        this.animateMarker(marker, replayEventPath(currentEvent));
      }
    });

    layer.querySelectorAll("[data-replay-actor-id]").forEach(marker => {
      if (!actorIds.has(marker.dataset.replayActorId)) {
        marker.remove();
      }
    });
  },
  renderObjects(layer, objects) {
    const objectKeys = new Set(Object.keys(objects));

    Object.entries(objects).forEach(([key, object]) => {
      const marker = this.markerForObject(layer, key, object);
      this.placeMarker(marker, object.position);
    });

    layer.querySelectorAll("[data-replay-object-key]").forEach(marker => {
      if (!objectKeys.has(marker.dataset.replayObjectKey)) {
        marker.remove();
      }
    });
  },
  markerForActor(layer, actor) {
    const escape =
      typeof CSS !== "undefined" && CSS.escape ? CSS.escape : value => `${value}`.replaceAll('"', '\\"');
    const selector = `[data-replay-actor-id="${escape(actor.actor_id)}"]`;
    let marker = layer.querySelector(selector);

    if (!marker) {
      marker = document.createElement("span");
      marker.dataset.replayActorId = actor.actor_id;
      layer.appendChild(marker);
    }

    marker.className = pawnClass(actor);
    marker.textContent = pawnText(actor);
    marker.title =
      actor.actor_role === "thief"
        ? "Thief"
        : `${actor.actor_color || "Detective"} detective`;

    return marker;
  },
  markerForObject(layer, key, object) {
    const escape =
      typeof CSS !== "undefined" && CSS.escape ? CSS.escape : value => `${value}`.replaceAll('"', '\\"');
    const selector = `[data-replay-object-key="${escape(key)}"]`;
    let marker = layer.querySelector(selector);

    if (!marker) {
      marker = document.createElement("span");
      marker.dataset.replayObjectKey = key;
      layer.appendChild(marker);
    }

    marker.className = `replay-object replay-object-${object.kind} replay-object-${object.status}`;
    marker.textContent = object.kind === "camera" ? object.label.replace("Camera ", "C") : object.label;
    marker.title = `${object.label} ${object.status}`;

    return marker;
  },
  placeMarker(marker, position) {
    const center = this.centerForCell(position);

    if (!center) {
      return;
    }

    marker.style.left = `${center.x}px`;
    marker.style.top = `${center.y}px`;
  },
  animateMarker(marker, path) {
    if (this.reducedMotion || !this.state.playing || path.length < 2 || !marker.animate) {
      return;
    }

    const keyframes = path
      .map(position => this.centerForCell(position))
      .filter(Boolean)
      .map(center => ({
        left: `${center.x}px`,
        top: `${center.y}px`,
      }));

    if (keyframes.length < 2) {
      return;
    }

    const animation = marker.animate(keyframes, {
      duration: replayEventDuration(
        {path: path.map(({row, col}) => `${row}-${col}`).join(" ")},
        this.state.speed
      ),
      easing: "ease-in-out",
      fill: "both",
    });

    this.animations = [...(this.animations || []), animation];
  },
  centerForCell(position) {
    const cell = document.getElementById(pathCellId(position));

    return cell ? centerOf(cell) : null;
  },
  cancelAnimations() {
    (this.animations || []).forEach(animation => animation.cancel?.());
    this.animations = [];
  },
  updateControlState() {
    if (!this.playButton) {
      return;
    }

    const label = this.state.playing ? "Pause replay" : "Play replay";
    this.playButton.setAttribute("aria-label", label);
    this.playButton.setAttribute("aria-pressed", this.state.playing ? "true" : "false");
    this.playIcon?.classList.toggle("hidden", this.state.playing);
    this.pauseIcon?.classList.toggle("hidden", !this.state.playing);
  },
  updateModeControls() {
    [
      [this.pathModeButton, "path"],
      [this.replayModeButton, "replay"],
    ].forEach(([button, mode]) => {
      if (!button) {
        return;
      }

      const active = this.mode === mode;
      button.setAttribute("aria-pressed", active ? "true" : "false");
      replayModeButtonActiveClass.split(" ").forEach(token => {
        button.classList.toggle(token, active);
      });
    });
  },
  setBoardReplayMode(mode) {
    if (typeof document === "undefined") {
      return;
    }

    document.getElementById("museum-board")?.classList.toggle("replay-mode-active", mode === "replay");
  },
  layer() {
    if (!this.replayLayer) {
      this.replayLayer = document.createElement("div");
      this.replayLayer.id = "replay-board-layer";
      this.replayLayer.className = "replay-board-layer";
      document.body.appendChild(this.replayLayer);
    }

    return this.replayLayer;
  },
  clearLayer() {
    this.cancelAnimations();
    this.replayLayer?.remove();
    this.replayLayer = null;
  },
};

export default ReplayPlaybackHook;
