export const GAME_AUDIO_STORAGE_KEY = "museum_caper.game_audio_enabled";
export const GAME_AUDIO_CHANGED_EVENT = "museum-caper:game-audio-changed";

const enabledValue = "true";

const browserStorage = () => {
  if (typeof window === "undefined") {
    return null;
  }

  try {
    return window.localStorage;
  } catch (_error) {
    return null;
  }
};

export const gameAudioEnabled = ({
  storage = browserStorage(),
  key = GAME_AUDIO_STORAGE_KEY,
} = {}) => {
  if (!storage) {
    return false;
  }

  try {
    return storage.getItem(key) === enabledValue;
  } catch (_error) {
    return false;
  }
};

const notifyGameAudioChanged = (enabled, key) => {
  if (typeof window === "undefined" || typeof window.CustomEvent === "undefined") {
    return;
  }

  window.dispatchEvent(
    new CustomEvent(GAME_AUDIO_CHANGED_EVENT, {
      detail: {enabled, key},
    })
  );
};

export const setGameAudioEnabled = (
  enabled,
  {
    storage = browserStorage(),
    key = GAME_AUDIO_STORAGE_KEY,
    dispatch = true,
  } = {}
) => {
  const normalizedEnabled = Boolean(enabled);

  if (storage) {
    try {
      storage.setItem(key, normalizedEnabled ? enabledValue : "false");
    } catch (_error) {}
  }

  if (dispatch) {
    notifyGameAudioChanged(normalizedEnabled, key);
  }

  return normalizedEnabled;
};
