import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(join(__dirname, "../css/app.css"), "utf8");
const routePathArrowRule =
  css.match(/\.route-path-arrow\s*\{(?<body>[\s\S]*?)\}/)?.groups?.body ?? "";

test("route arrows use a clean outline without diagonal tip pooling", () => {
  assert.match(routePathArrowRule, /color:\s*#ffffff;/);
  assert.match(routePathArrowRule, /-webkit-text-stroke:\s*0\.75px/);
  assert.doesNotMatch(routePathArrowRule, /1px 1px 0/);
  assert.doesNotMatch(routePathArrowRule, /-1px 1px 0/);
  assert.doesNotMatch(routePathArrowRule, /1px -1px 0/);
  assert.doesNotMatch(routePathArrowRule, /-1px -1px 0/);
});
