import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(join(__dirname, "../css/app.css"), "utf8");
const routePathArrowRule =
  css.match(/\.route-path-arrow\s*\{(?<body>[\s\S]*?)\}/)?.groups?.body ?? "";
const replayModePawnLayerRule =
  css.match(
    /\.replay-mode-active\s+\[data-board-mark-layer="pawns"\]\s*\{(?<body>[\s\S]*?)\}/
  )?.groups?.body ?? "";
const replayModeObjectLayerRule =
  css.match(
    /\.replay-mode-active\s+\[data-board-mark-layer="objects"\]\s*\{(?<body>[\s\S]*?)\}/
  )?.groups?.body ?? "";
const boardObjectMarkRule =
  css.match(/\.board-object-mark\s*\{(?<body>[\s\S]*?)\}/)?.groups?.body ?? "";
const boardObjectCameraRule =
  css.match(/\.board-object-mark-camera\s*\{(?<body>[\s\S]*?)\}/)?.groups?.body ?? "";
const endTurnReadyPulseRule =
  css.match(/\.end-turn-ready-pulse\s*\{(?<body>[\s\S]*?)\}/)?.groups?.body ?? "";
const reducedMotionRule =
  css.match(
    /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{(?<body>[\s\S]*?)\n\}/
  )?.groups?.body ?? "";

test("route arrows use a clean outline without diagonal tip pooling", () => {
  assert.match(routePathArrowRule, /color:\s*#ffffff;/);
  assert.match(routePathArrowRule, /-webkit-text-stroke:\s*0\.75px/);
  assert.doesNotMatch(routePathArrowRule, /1px 1px 0/);
  assert.doesNotMatch(routePathArrowRule, /-1px 1px 0/);
  assert.doesNotMatch(routePathArrowRule, /1px -1px 0/);
  assert.doesNotMatch(routePathArrowRule, /-1px -1px 0/);
});

test("replay mode hides the live board pawn layer", () => {
  assert.match(replayModePawnLayerRule, /display:\s*none;/);
});

test("replay mode hides the live board object layer", () => {
  assert.match(replayModeObjectLayerRule, /display:\s*none;/);
});

test("board object marks keep stable mobile badge dimensions", () => {
  assert.match(boardObjectMarkRule, /box-sizing:\s*border-box;/);
  assert.match(boardObjectMarkRule, /flex:\s*0\s+0\s+auto;/);
  assert.doesNotMatch(boardObjectMarkRule, /max-width:\s*100%;/);
  assert.doesNotMatch(boardObjectMarkRule, /overflow:\s*hidden;/);
});

test("board camera marks stay circular on mobile", () => {
  assert.match(boardObjectCameraRule, /aspect-ratio:\s*1\s*\/\s*1;/);
  assert.match(boardObjectCameraRule, /min-width:\s*1\.25rem;/);
  assert.match(boardObjectCameraRule, /padding:\s*0;/);
});

test("ready end turn button pulses and respects reduced motion", () => {
  assert.match(endTurnReadyPulseRule, /animation:\s*end-turn-ready-pulse\s+900ms/);
  assert.match(css, /@keyframes\s+end-turn-ready-pulse/);
  assert.match(css, /transform:\s*scale\(1\.06\);/);
  assert.match(css, /0\s+0\s+0\s+0\.82rem\s+rgba\(251,\s*191,\s*36,\s*0\)/);
  assert.match(reducedMotionRule, /\.end-turn-ready-pulse\s*\{[\s\S]*animation:\s*none;/);
});
