const seenRevealKeys = new Set();

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

    if (!key || seenRevealKeys.has(key) || key === this.currentKey) {
      return;
    }

    seenRevealKeys.add(key);
    this.currentKey = key;
    this.show();
  },
  show() {
    clearTimeout(this.timer);

    this.stack()?.classList.add("board-reveal-stack-active");
    this.el.classList.remove("board-reveal-mark-active");

    requestAnimationFrame(() => {
      this.el.classList.add("board-reveal-mark-active");
    });

    this.timer = setTimeout(() => this.clearReveal(), this.duration());
  },
  clearReveal() {
    this.el.classList.remove("board-reveal-mark-active");
    this.stack()?.classList.remove("board-reveal-stack-active");
  },
  stack() {
    return this.el.closest("[data-board-mark-stack]");
  },
  duration() {
    return Number.parseInt(this.el.dataset.revealDuration || "3000", 10);
  }
};

export default BoardRevealHook;
