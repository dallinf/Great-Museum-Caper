import {
  GAME_AUDIO_CHANGED_EVENT,
  GAME_AUDIO_STORAGE_KEY,
  gameAudioEnabled,
  setGameAudioEnabled,
} from "../game_audio_preference";

const enabledLabelClasses = ["border-amber-300/60", "text-amber-100"];
const disabledLabelClasses = ["border-stone-700", "text-stone-400"];

const setClasses = (element, enabled, enabledClasses, disabledClasses) => {
  if (!element) {
    return;
  }

  element.classList.toggle("bg-amber-300/10", enabled);
  enabledClasses.forEach(className => element.classList.toggle(className, enabled));
  disabledClasses.forEach(className => element.classList.toggle(className, !enabled));
};

const GameAudioPreferenceHook = {
  mounted() {
    this.handleClick = () => this.toggleAudio();
    this.handlePreferenceChanged = event => {
      if (!event.detail || event.detail.key === this.storageKey()) {
        this.render(this.enabled());
      }
    };
    this.handleStorageChanged = event => {
      if (event.key === this.storageKey()) {
        this.render(this.enabled());
      }
    };

    this.el.addEventListener("click", this.handleClick);
    window.addEventListener(GAME_AUDIO_CHANGED_EVENT, this.handlePreferenceChanged);
    window.addEventListener("storage", this.handleStorageChanged);
    this.render(this.enabled());
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
    window.removeEventListener(GAME_AUDIO_CHANGED_EVENT, this.handlePreferenceChanged);
    window.removeEventListener("storage", this.handleStorageChanged);
  },
  storageKey() {
    return this.el.dataset.audioStorageKey || GAME_AUDIO_STORAGE_KEY;
  },
  enabled() {
    return gameAudioEnabled({key: this.storageKey()});
  },
  toggleAudio() {
    setGameAudioEnabled(!this.enabled(), {key: this.storageKey()});
  },
  render(enabled) {
    this.el.setAttribute("aria-pressed", enabled ? "true" : "false");
    this.el.dataset.audioEnabled = enabled ? "true" : "false";

    const stateLabel = this.el.querySelector("[data-audio-state-label]");
    if (stateLabel) {
      stateLabel.textContent = enabled ? "On" : "Off";
      setClasses(stateLabel, enabled, enabledLabelClasses, disabledLabelClasses);
    }

    this.el
      .querySelector("[data-audio-enabled-icon]")
      ?.classList.toggle("hidden", !enabled);
    this.el
      .querySelector("[data-audio-disabled-icon]")
      ?.classList.toggle("hidden", enabled);
  },
};

export default GameAudioPreferenceHook;
