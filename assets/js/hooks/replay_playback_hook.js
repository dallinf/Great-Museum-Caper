import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventDuration,
  replaceReplayState,
} from "../replay_playback.js";
import {parseMovePath, pathCellId} from "../board_movement_animation.js";

const pawnClass = event =>
  `replay-pawn replay-pawn-${event.actor_role} replay-pawn-${event.actor_color || "grey"}`;

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
    this.root = this.controlRoot();
    this.handleControlClick = event => {
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
    this.bindControls();
    this.renderFrame();
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
    this.speedInput = this.el.querySelector("[data-replay-speed]");

    if (this.speedInput) {
      this.speedInput.value = `${this.state.speed}`;
    }
  },
  command(command) {
    if (command === "play") {
      this.togglePlay();
    } else if (command === "back") {
      this.stop();
      this.state = {...this.state, index: previousReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "forward") {
      this.stop();
      this.state = {...this.state, index: nextReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "restart") {
      this.stop();
      this.state = {...this.state, index: 0};
      this.renderFrame();
    } else if (command === "exit") {
      this.stop();
      this.clearLayer();

      if (this.caption) {
        this.caption.textContent = "";
      }
    }
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
    this.state = {...this.state, playing: false};
  },
  renderFrame() {
    const event = this.state.events[this.state.index];

    if (!event) {
      return;
    }

    if (this.caption) {
      this.caption.textContent = event.label || "";
    }

    this.renderPawn(event);
  },
  renderPawn(event) {
    const path = parseMovePath(event.path);
    const finalCell = path[path.length - 1];

    if (!finalCell) {
      return;
    }

    const cell = document.getElementById(pathCellId(finalCell));

    if (!cell) {
      return;
    }

    const layer = this.layer();
    const marker = document.createElement("span");
    marker.className = pawnClass(event);
    marker.textContent = event.actor_role === "thief" ? "T" : "D";

    const center = centerOf(cell);
    marker.style.left = `${center.x}px`;
    marker.style.top = `${center.y}px`;

    layer.replaceChildren(marker);
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
    this.replayLayer?.remove();
    this.replayLayer = null;
  },
};

export default ReplayPlaybackHook;
