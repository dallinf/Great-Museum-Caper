import {
  movementDuration,
  parseMovePath,
  pathCellId,
} from "../board_movement_animation";

const seenRevealKeys = new Set();

const centerOf = element => {
  const rect = element.getBoundingClientRect();

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
};

const createTrailLayer = (centers, duration) => {
  const layer = document.createElement("div");
  layer.className = "board-move-trail-layer";
  layer.style.setProperty("--board-move-duration", `${duration + 260}ms`);

  centers.forEach(({x, y}) => {
    const dot = document.createElement("span");
    dot.className = "board-move-trail-dot";
    dot.style.left = `${x}px`;
    dot.style.top = `${y}px`;
    layer.appendChild(dot);
  });

  centers.slice(1).forEach((center, index) => {
    const previous = centers[index];
    const dx = center.x - previous.x;
    const dy = center.y - previous.y;
    const segment = document.createElement("span");
    segment.className = "board-move-trail-segment";
    segment.style.left = `${previous.x}px`;
    segment.style.top = `${previous.y}px`;
    segment.style.width = `${Math.hypot(dx, dy)}px`;
    segment.style.transform = `rotate(${Math.atan2(dy, dx)}rad)`;
    layer.appendChild(segment);
  });

  document.body.appendChild(layer);
  return layer;
};

const BoardRevealHook = {
  mounted() {
    this.currentKey = null;
    this.showIfNew();
  },
  updated() {
    this.showIfNew();
  },
  destroyed() {
    this.clearReveal();
    clearTimeout(this.timer);
  },
  showIfNew() {
    const key = this.el.dataset.revealKey;
    const revealOnce = this.el.dataset.revealOnce !== "false";

    if (!key || key === this.currentKey || (revealOnce && seenRevealKeys.has(key))) {
      return;
    }

    if (revealOnce) {
      seenRevealKeys.add(key);
    }

    this.currentKey = key;
    this.show();
  },
  show() {
    clearTimeout(this.timer);

    this.stack()?.classList.add("board-reveal-stack-active");
    this.el.classList.remove("board-reveal-mark-active");

    if (this.canAnimateMovement()) {
      this.showMovement();
      return;
    }

    this.showLandingReveal();
    this.timer = setTimeout(() => this.clearReveal(), this.duration());
  },
  showLandingReveal() {
    requestAnimationFrame(() => {
      this.el.classList.add("board-reveal-mark-active");
    });
  },
  showMovement() {
    const path = parseMovePath(this.el.dataset.movePath);
    const cells = path.map(cell => document.getElementById(pathCellId(cell)));

    if (cells.some(cell => cell == null)) {
      this.showLandingReveal();
      this.timer = setTimeout(() => this.clearReveal(), this.duration());
      return;
    }

    const centers = cells.map(centerOf);
    const duration = movementDuration(path);
    const ghost = this.el.cloneNode(true);
    ghost.removeAttribute("id");
    ghost.removeAttribute("phx-hook");
    ghost.setAttribute("aria-hidden", "true");
    ghost.classList.add("board-moving-pawn-ghost");
    ghost.style.left = `${centers[0].x}px`;
    ghost.style.top = `${centers[0].y}px`;
    ghost.style.width = `${this.el.offsetWidth}px`;
    ghost.style.height = `${this.el.offsetHeight}px`;

    this.movementGhost = ghost;
    this.movementTrail = createTrailLayer(centers, duration);
    this.el.classList.add("board-moving-pawn-hidden");
    document.body.appendChild(ghost);

    const finish = () => {
      this.clearMovementOverlay();
      this.showLandingReveal();
    };

    if (typeof ghost.animate !== "function" || duration === 0) {
      finish();
    } else {
      this.movementAnimation = ghost.animate(
        centers.map(({x, y}) => ({left: `${x}px`, top: `${y}px`})),
        {
          duration,
          easing: "cubic-bezier(0.22, 1, 0.36, 1)",
          fill: "forwards",
        }
      );

      this.movementAnimation.finished.then(finish).catch(() => {});
    }

    this.timer = setTimeout(() => this.clearReveal(), duration + this.duration());
  },
  clearReveal() {
    this.clearMovementOverlay();
    this.el.classList.remove("board-reveal-mark-active");
    this.el.classList.remove("board-moving-pawn-hidden");
    this.stack()?.classList.remove("board-reveal-stack-active");
  },
  clearMovementOverlay() {
    this.movementAnimation?.cancel();
    this.movementAnimation = null;
    this.movementGhost?.remove();
    this.movementGhost = null;
    this.movementTrail?.remove();
    this.movementTrail = null;
    this.el.classList.remove("board-moving-pawn-hidden");
  },
  canAnimateMovement() {
    return this.el.dataset.animationKind === "move" &&
      parseMovePath(this.el.dataset.movePath).length > 1 &&
      !this.prefersReducedMotion();
  },
  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  },
  stack() {
    return this.el.closest("[data-board-mark-stack]");
  },
  duration() {
    return Number.parseInt(this.el.dataset.revealDuration || "3000", 10);
  }
};

export default BoardRevealHook;
