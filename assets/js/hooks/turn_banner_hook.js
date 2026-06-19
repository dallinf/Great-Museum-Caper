const DEFAULT_DURATION_MS = 3000;
const LOUD_CHIME_VOLUME = 0.42;

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

    this.playChime();
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
    const duration = Number.parseInt(this.el.dataset.turnBannerDuration || `${DEFAULT_DURATION_MS}`, 10);
    return Number.isFinite(duration) && duration > 0 ? duration : DEFAULT_DURATION_MS;
  },
  playChime() {
    if (this.el.dataset.turnBannerChime !== "loud") {
      return;
    }

    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) {
        return;
      }

      this.audioContext = this.audioContext || new AudioContext();
      const context = this.audioContext;
      const start = () => this.startLoudChime(context);

      if (context.state === "suspended") {
        context.resume().then(start).catch(() => {});
      } else {
        start();
      }
    } catch (_error) {
      // Audio can be blocked by the browser before the player interacts with the page.
    }
  },
  startLoudChime(context) {
    const now = context.currentTime;
    const master = context.createGain();
    const volume = this.chimeVolume();

    master.gain.setValueAtTime(0.0001, now);
    master.gain.exponentialRampToValueAtTime(volume, now + 0.03);
    master.gain.exponentialRampToValueAtTime(0.0001, now + 0.72);
    master.connect(context.destination);

    [
      {frequency: 659.25, delay: 0, duration: 0.28},
      {frequency: 987.77, delay: 0.08, duration: 0.34},
      {frequency: 1318.51, delay: 0.2, duration: 0.38}
    ].forEach(({frequency, delay, duration}) => {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      const start = now + delay;
      const stop = start + duration;

      oscillator.type = "triangle";
      oscillator.frequency.setValueAtTime(frequency, start);
      gain.gain.setValueAtTime(0.0001, start);
      gain.gain.exponentialRampToValueAtTime(1, start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, stop);
      oscillator.connect(gain).connect(master);
      oscillator.start(start);
      oscillator.stop(stop + 0.02);
    });

    window.setTimeout(() => master.disconnect(), 900);
  },
  chimeVolume() {
    const volume = Number.parseFloat(this.el.dataset.turnBannerChimeVolume || `${LOUD_CHIME_VOLUME}`);
    return Number.isFinite(volume) && volume > 0 ? volume : LOUD_CHIME_VOLUME;
  },
  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
};

export default TurnBannerHook;
