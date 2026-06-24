# Route Reveal Arrow Dots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace tiny completed-route direction glyphs with large directional arrows and keep turn-end stops as visible numbered dots.

**Architecture:** This is a presentation-only change inside `MuseumCaperWeb.GameLive`. Existing route mark maps already carry `kind`, `direction`, `stop`, and `label`, so the implementation only updates label generation, route marker classes, and LiveView assertions.

**Tech Stack:** Phoenix LiveView, HEEx, Tailwind CSS utility classes, ExUnit LiveView tests.

## Global Constraints

- Do not change thief route history data.
- Do not reveal active thief movement.
- Keep `data-route-direction` and `data-thief-route-stop` selectors available.
- Entry and exit badges remain text labels.
- Run `mix format`, focused tests, `mix precommit`, `mix assets.build`, and `git diff --check` before completion.

---

### Task 1: Completed Route Marker Readability

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Modify: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: route mark maps with `%{kind: "path", direction: direction}` and `%{kind: "stop", stop: index, label: label}`.
- Produces: path mark text from `route_direction_glyph/1` as `→`, `←`, `↑`, `↓`; stop marks with `data-thief-route-stop-dot` and visible turn number.

- [ ] **Step 1: Write failing LiveView assertions**

Update path assertions in `test/museum_caper_web/live/game_live_test.exs` to require arrow text:

```elixir
assert has_element?(
         thief_view,
         "#cell-1-4 [data-thief-route='path'][data-route-round='current'][data-route-direction='east']",
         "→"
       )
```

Update stop assertions to require a numbered dot marker:

```elixir
assert has_element?(
         thief_view,
         "#cell-1-5 [data-thief-route='stop'][data-route-round='current'][data-thief-route-stop='1'][data-thief-route-stop-dot]",
         "1"
       )
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: FAIL because path markers still render `>`/`<`/`^`/`v`, and stop markers do not include `data-thief-route-stop-dot`.

- [ ] **Step 3: Write minimal implementation**

In `lib/museum_caper_web/live/game_live.ex`, update the route marker span:

```elixir
data-thief-route-stop-dot={if(mark.kind == "stop", do: "")}
```

Update `route_direction_glyph/1`:

```elixir
defp route_direction_glyph("east"), do: "→"
defp route_direction_glyph("west"), do: "←"
defp route_direction_glyph("north"), do: "↑"
defp route_direction_glyph("south"), do: "↓"
defp route_direction_glyph(_direction), do: ""
```

Update `route_mark_class/1` for path and stop marks so the arrow and numbered dot are visually larger:

```elixir
defp route_mark_class(%{kind: "stop"}) do
  "absolute right-0.5 top-0.5 grid size-5 place-items-center rounded-full border-2 border-stone-950 bg-amber-100 text-[0.68rem] font-black leading-none text-stone-950 shadow-[0_0_0.55rem_rgba(251,191,36,0.65)]"
end

defp route_mark_class(%{kind: "path"}) do
  "absolute inset-0 grid place-items-center text-[1.35rem] font-black leading-none text-sky-50 drop-shadow-[0_0_0.45rem_rgba(125,211,252,0.9)]"
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: PASS.

- [ ] **Step 5: Verify project checks**

Run:

```bash
mix format
mix test test/museum_caper_web/live/game_live_test.exs
mix precommit
mix assets.build
git diff --check
```

Expected: all commands exit 0. Also run `mix credo`; if the task is unavailable, report the exact Mix error.
