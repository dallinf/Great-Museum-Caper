let audioContext = null;
let audioUnlockInstalled = false;

const getAudioContext = () => {
  const AudioContext = window.AudioContext || window.webkitAudioContext;

  if (!AudioContext) {
    return null;
  }

  try {
    audioContext = audioContext || new AudioContext();
    return audioContext;
  } catch (_error) {
    return null;
  }
};

const unlockTurnAudio = () => {
  const context = getAudioContext();

  if (!context || context.state !== "suspended") {
    return;
  }

  context.resume().catch(() => {});
};

const installAudioUnlock = () => {
  if (audioUnlockInstalled) {
    return;
  }

  audioUnlockInstalled = true;

  ["pointerdown", "touchstart", "click", "keydown"].forEach(eventName => {
    window.addEventListener(eventName, unlockTurnAudio, {passive: true});
  });
};

const playTone = (context, frequency, startTime, duration, volume) => {
  const oscillator = context.createOscillator();
  const gain = context.createGain();

  oscillator.type = "sine";
  oscillator.frequency.setValueAtTime(frequency, startTime);
  gain.gain.setValueAtTime(0.0001, startTime);
  gain.gain.exponentialRampToValueAtTime(volume, startTime + 0.03);
  gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + duration + 0.04);
};

const scheduleTurnChime = context => {
  const startTime = context.currentTime + 0.03;
  playTone(context, 659.25, startTime, 0.18, 0.045);
  playTone(context, 987.77, startTime + 0.11, 0.26, 0.035);
};

const resumeAndScheduleTurnChime = context => {
  context.resume()
    .then(() => {
      if (context.state !== "suspended") {
        scheduleTurnChime(context);
      }
    })
    .catch(() => {});
};

const playTurnChime = () => {
  const context = getAudioContext();

  if (!context) {
    return;
  }

  if (context.state === "suspended") {
    resumeAndScheduleTurnChime(context);
    return;
  }

  scheduleTurnChime(context);
};

const TurnBannerHook = {
  mounted() {
    installAudioUnlock();
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
    this.playChime();
  },
  playChime() {
    if (this.el.dataset.turnBannerChime === "true") {
      playTurnChime();
    }
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
