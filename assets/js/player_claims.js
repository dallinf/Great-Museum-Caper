export const PLAYER_CLAIM_STORAGE_PREFIX = "museum_caper.player_claim.";

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

const cleanString = value => {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
};

const normalizeClaim = claim => {
  if (!claim || typeof claim !== "object") {
    return null;
  }

  const gameId = cleanString(claim.gameId);
  const playerId = cleanString(claim.playerId);

  if (!gameId || !playerId) {
    return null;
  }

  return {
    gameId,
    playerId,
    playerName: cleanString(claim.playerName),
    playerColor: cleanString(claim.playerColor),
  };
};

export const playerClaimKey = gameId => `${PLAYER_CLAIM_STORAGE_PREFIX}${gameId}`;

export const writePlayerClaim = (
  claim,
  {
    storage = browserStorage(),
  } = {}
) => {
  const normalized = normalizeClaim(claim);

  if (!storage || !normalized) {
    return null;
  }

  try {
    storage.setItem(playerClaimKey(normalized.gameId), JSON.stringify(normalized));
    return normalized;
  } catch (_error) {
    return null;
  }
};

export const readPlayerClaim = (
  gameId,
  {
    storage = browserStorage(),
  } = {}
) => {
  if (!storage) {
    return null;
  }

  try {
    const claim = normalizeClaim(JSON.parse(storage.getItem(playerClaimKey(gameId))));
    return claim?.gameId === gameId ? claim : null;
  } catch (_error) {
    return null;
  }
};

export const playerClaimForRoom = (
  gameId,
  playerIds,
  {
    storage = browserStorage(),
  } = {}
) => {
  const claim = readPlayerClaim(gameId, {storage});

  if (!claim || !playerIds.includes(claim.playerId)) {
    return null;
  }

  return claim;
};

export const rejoinPath = (gameId, playerId, {basePath} = {}) => {
  const path = cleanString(basePath) || `/game/${encodeURIComponent(gameId)}`;
  const [pathWithQuery, hash] = path.split("#", 2);
  const queryStart = pathWithQuery.indexOf("?");
  const pathname = queryStart === -1 ? pathWithQuery : pathWithQuery.slice(0, queryStart);
  const query = queryStart === -1 ? "" : pathWithQuery.slice(queryStart + 1);
  const params = new URLSearchParams(query);

  params.set("player_id", playerId);

  return `${pathname}?${params.toString()}${hash ? `#${hash}` : ""}`;
};

export const roomPlayerIds = value =>
  cleanString(value)
    .split(/\s+/)
    .filter(Boolean);

export const applyRejoinLinks = (
  root,
  {
    storage = browserStorage(),
  } = {}
) => {
  root.querySelectorAll("[data-rejoin-link]").forEach(link => {
    const claim = playerClaimForRoom(
      link.dataset.gameId,
      roomPlayerIds(link.dataset.roomPlayerIds),
      {storage}
    );

    if (claim) {
      link.href = rejoinPath(claim.gameId, claim.playerId, {
        basePath: link.getAttribute("href") || link.href,
      });
      link.dataset.rejoinPlayerId = claim.playerId;
      link.classList.remove("hidden");
    } else {
      link.classList.add("hidden");
      delete link.dataset.rejoinPlayerId;
    }
  });
};
