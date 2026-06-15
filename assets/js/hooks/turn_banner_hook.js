const TurnBannerHook = {
  mounted() {
    this.currentKey = null;
    this.showIfNew();
  },
  updated() {
    this.showIfNew();
  },
  destroyed() {
    clearTimeout(this.timer);
  },
  showIfNew() {
    const key = this.el.dataset.turnBannerKey;

    if (key === this.currentKey) {
      return;
    }

    this.currentKey = key;
    this.show();
  },
  show() {
    const panel = this.panel();
    clearTimeout(this.timer);

    panel.style.transition = "none";
    panel.style.opacity = "0";
    panel.style.transform = "translateY(1rem) scale(0.95)";

    requestAnimationFrame(() => {
      panel.style.transition = this.prefersReducedMotion()
        ? "none"
        : "opacity 0.2s ease-out, transform 0.2s ease-out";
      panel.style.opacity = "1";
      panel.style.transform = "translateY(0) scale(1)";
    });

    this.timer = setTimeout(() => this.hide(), this.duration());
  },
  hide() {
    const panel = this.panel();
    panel.style.transition = this.prefersReducedMotion()
      ? "none"
      : "opacity 0.28s ease-in, transform 0.28s ease-in";
    panel.style.opacity = "0";
    panel.style.transform = "translateY(-0.5rem) scale(0.98)";
  },
  panel() {
    return this.el.querySelector("[data-turn-banner-panel]") || this.el;
  },
  duration() {
    return Number.parseInt(this.el.dataset.turnBannerDuration || "3000", 10);
  },
  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
};

export default TurnBannerHook;
