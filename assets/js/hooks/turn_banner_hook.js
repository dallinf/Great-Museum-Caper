import {
  GAME_AUDIO_CHANGED_EVENT,
  gameAudioEnabled,
} from "../game_audio_preference";

const DEFAULT_DURATION_MS = 3000;
const LOUD_CHIME_VOLUME = 0.18;

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
  if (!gameAudioEnabled()) {
    return;
  }

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

window.addEventListener(GAME_AUDIO_CHANGED_EVENT, event => {
  if (event.detail?.enabled) {
    unlockTurnAudio();
  }
});

const playTone = (context, frequency, startTime, duration, volume, type = "sine") => {
  const oscillator = context.createOscillator();
  const gain = context.createGain();

  oscillator.type = type;
  oscillator.frequency.setValueAtTime(frequency, startTime);
  gain.gain.setValueAtTime(0.0001, startTime);
  gain.gain.exponentialRampToValueAtTime(volume, startTime + 0.03);
  gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + duration + 0.04);
};

const scheduleTurnChime = (context, chime) => {
  const startTime = context.currentTime + 0.03;

  if (chime === "loud") {
    playTone(context, 659.25, startTime, 0.28, LOUD_CHIME_VOLUME, "triangle");
    playTone(context, 987.77, startTime + 0.08, 0.34, LOUD_CHIME_VOLUME * 0.78, "triangle");
    playTone(context, 1318.51, startTime + 0.2, 0.38, LOUD_CHIME_VOLUME * 0.62, "triangle");
  } else {
    playTone(context, 659.25, startTime, 0.18, 0.045);
    playTone(context, 987.77, startTime + 0.11, 0.26, 0.035);
  }
};

const resumeAndScheduleTurnChime = (context, chime) => {
  context.resume()
    .then(() => {
      if (context.state !== "suspended") {
        scheduleTurnChime(context, chime);
      }
    })
    .catch(() => {});
};

const playTurnChime = chime => {
  const context = getAudioContext();

  if (!context) {
    return;
  }

  if (context.state === "suspended") {
    resumeAndScheduleTurnChime(context, chime);
    return;
  }

  scheduleTurnChime(context, chime);
};

const TurnBannerHook = {
  mounted() {
    installAudioUnlock();
    this.currentKey = null;
    this.dismissBanner = event => {
      event.preventDefault();
      this.hide();
    };
    this.handleDismissKeydown = event => {
      if (["Enter", " ", "Escape"].includes(event.key)) {
        this.dismissBanner(event);
      }
    };
    this.bindDismiss();
    this.showIfNew();
  },
  updated() {
    this.bindDismiss();
    this.showIfNew();
  },
  destroyed() {
    clearTimeout(this.timer);
    this.unbindDismiss();
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
    this.hidden = false;
    panel.style.pointerEvents = "auto";
    panel.tabIndex = 0;

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
    const chime = this.el.dataset.turnBannerChime;

    if (!gameAudioEnabled()) {
      return;
    }

    if (["loud", "true"].includes(chime)) {
      playTurnChime(chime);
    }
  },
  hide() {
    if (this.hidden) {
      return;
    }

    this.hidden = true;
    clearTimeout(this.timer);

    const panel = this.panel();
    panel.style.pointerEvents = "none";
    panel.tabIndex = -1;
    panel.style.transition = this.prefersReducedMotion()
      ? "none"
      : "opacity 0.28s ease-in, transform 0.28s ease-in";
    panel.style.opacity = "0";
    panel.style.transform = "translateY(-0.5rem) scale(0.98)";
  },
  bindDismiss() {
    const panel = this.panel();

    if (this.dismissPanel === panel) {
      return;
    }

    this.unbindDismiss();
    this.dismissPanel = panel;
    this.dismissPanel.addEventListener("click", this.dismissBanner);
    this.dismissPanel.addEventListener("keydown", this.handleDismissKeydown);
  },
  unbindDismiss() {
    if (!this.dismissPanel) {
      return;
    }

    this.dismissPanel.removeEventListener("click", this.dismissBanner);
    this.dismissPanel.removeEventListener("keydown", this.handleDismissKeydown);
    this.dismissPanel = null;
  },
  panel() {
    return this.el.querySelector("[data-turn-banner-panel]") || this.el;
  },
  duration() {
    const duration = Number.parseInt(this.el.dataset.turnBannerDuration || `${DEFAULT_DURATION_MS}`, 10);
    return Number.isFinite(duration) && duration > 0 ? duration : DEFAULT_DURATION_MS;
  },
  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
};

export default TurnBannerHook;
