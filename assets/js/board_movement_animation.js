const STEP_DURATION_MS = 120;
const MIN_DURATION_MS = 180;
const MAX_DURATION_MS = 900;

export const parseMovePath = path => {
  if (!path) {
    return [];
  }

  return path
    .trim()
    .split(/\s+/)
    .map(token => {
      const match = token.match(/^(\d+)-(\d+)$/);

      if (!match) {
        return null;
      }

      return {
        row: Number.parseInt(match[1], 10),
        col: Number.parseInt(match[2], 10),
      };
    })
    .filter(Boolean);
};

export const movementDuration = path => {
  const steps = Math.max(path.length - 1, 0);

  if (steps === 0) {
    return 0;
  }

  return Math.min(MAX_DURATION_MS, Math.max(MIN_DURATION_MS, steps * STEP_DURATION_MS));
};

export const pathCellId = ({row, col}) => `cell-${row}-${col}`;
