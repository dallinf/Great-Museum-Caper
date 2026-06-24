# Route Arrow Contrast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make completed-route arrows readable over every board cell color by rendering white arrows with a dark outline.

**Architecture:** Keep route data unchanged. Add a path-only data attribute/class in `MuseumCaperWeb.GameLive`, then style that class in `assets/css/app.css` using white text, black stroke, and layered text-shadow.

**Tech Stack:** Phoenix LiveView, HEEx, Tailwind classes, raw CSS, ExUnit LiveView tests.

## Global Constraints

- Do not change route history data.
- Do not affect entry, exit, or stop marker styling.
- Do not reveal active thief movement.
- Keep existing direction glyph text and `data-route-direction` selectors.

---

### Task 1: High Contrast Route Arrows

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Modify: `assets/css/app.css`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Produces: path marks include `data-thief-route-arrow-outline`.
- Produces: `.route-path-arrow` CSS class.

- [ ] **Step 1: Write failing LiveView assertions**

Add `data-thief-route-arrow-outline` to existing path marker assertions.

- [ ] **Step 2: Run failing test**

Run `mix test test/museum_caper_web/live/game_live_test.exs`.

Expected: FAIL because path marks do not yet include the outline hook.

- [ ] **Step 3: Implement marker and CSS**

Add a path-only data attribute to `thief_route_cell_overlay/1`, add `route-path-arrow` to the path marker class, and define CSS for white text with a black outline.

- [ ] **Step 4: Verify**

Run `mix format`, focused LiveView tests, `mix precommit`, `mix assets.build`, and `git diff --check`. Run `mix credo`; if unavailable, report the exact error.
