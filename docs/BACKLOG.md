# Backlog

Planned changes that are **not implemented yet**. Every item is verified against the current code
(state: after M35) — line numbers may drift with later commits, the function and field names are the
reliable reference.

Open questions have already been decided; the outcomes are recorded under **Decisions**.

Items #1 and #2 share a root cause: the roles of the player-placeable buildings are blurred. The
Town Hall is currently storage yard, granary, price lever *and* policy centre all at once, while the
Treasury does almost nothing. #3 and #4 are independent UI and market topics.

**Order:** #1 → #3 → #2 → #4. #4 last, because #2 reshuffles the price UI anyway.

---

## 1. No occupancy on player-placeable buildings

**Problem:** Storage Yard, Granary, Treasury and Marketplace show "Occupants X / 2" in the InfoPanel
even though nobody ever moves in.

**Finding:** The display is purely cosmetic. `occupants` is only ever filled for work huts
(`SimulationManager.gd:1215`, `:1284`, `:1301`), and `get_understaffed_hut` / `get_reclaimable_hut`
(`BuildingManager.gd:200`, `:225`) filter through `PROFESSION_TO_BUILDING_TYPE`, which does not
contain player-placeable buildings at all. `max_capacity = 2` is a dead value on all four. The Town
Hall already has `max_capacity = 0`.

**Scope:**
- `resources/data/building_defs/{storage_yard,granary,treasury,market}.tres`: `max_capacity` → `0`.
- `scenes/ui/components/InfoPanel.gd:153`: only show the Occupants row when `def.max_capacity > 0`.
- Worth reading along: `_append_production_metrics` (`InfoPanel.gd:186`) accesses
  `building.occupants[0]`, but is already guarded against an empty list.

**Risk:** low. Save compatibility unaffected (`occupants` stays serialized).

---

## 2. Split the policy levers: Town Hall = tax, Treasury = subsidies + basic income

**Target state:**

| Building | Levers |
|---|---|
| Town Hall | tax **only**, as a percentage — new, does not exist today |
| Treasury | per-good subsidies/tariffs **and** basic income |
| Treasury cost | **20 Planks** (instead of today's 20 Gold + 20 Stone) |

### Decisions

- **Tax base: `inh.gold` only.** A daily percentage of gold wealth — no goods value, no property.
  Capped by the inhabitant's own wealth like today's head tax: whoever has nothing pays nothing.
- **Head tax is dropped.** `TradeData.daily_tax` goes away entirely; the Town Hall percentage tax is
  the only tax lever. A negative basic income remains as a second fallback anyway. The "Local tax"
  entry in the `CLAUDE.md` glossary has to go with it.
- **Sawmill prerequisite stays purely economic.** No `requires_building` mechanism, no disabled
  button. Without a Sawmill there are no Planks, so no Treasury in practice. This is also the
  in-fiction variant: a uniform cost rule instead of a special-case check.
- **No Treasury means no economic lever at all.** A deliberate progression gate: wood → Sawmill →
  Planks → Treasury, and only then may the Crown intervene. ⚠ This makes the early game noticeably
  harder — the death-spiral fallback (basic income) only becomes available late. Compare a turbo run
  against the current state after implementing.
- **The free-first-building rule is removed completely** (see below).

### Finding (current state)

- `PolicyData` (`scripts/data/policy_data.gd`) holds `subsidy{}` + `basic_income` and is created
  **exclusively** on the Town Hall instance (`BuildingManager.gd:94`). It is read through
  `BuildingManager.get_subsidy()` / `get_basic_income()` (`:297`, `:304`), both of which call
  `get_town_hall()` directly.
- The UI keys off `building.policy != null` (`InfoPanel.gd:315` `_add_policy_editors`), so it moves
  along automatically as soon as `policy` is instantiated elsewhere.
- Tax today: `TradeData.daily_tax` is a **flat per-head amount**, editable only at the Treasury
  (`InfoPanel.gd:228`), read via `BuildingManager.get_daily_tax()` (`:265`), applied in
  `SimulationManager._process_daily_tax()` (`:690`, daily accumulator at `:486-489`). Exactly the
  inverse of the target state.
- Treasury cost today: `build_cost_gold = 20.0` **plus** `build_cost = {2: 20.0}` (GoodType 2 =
  STONE).

### ⚠ Removing the free-first-building rule — watch the side effect

`Main.gd:76` `_is_first_of_type()`: the *first* building of every type in `TRADE_BUILDING_TYPES`
(Storage Yard, Granary, Treasury) is free — which would make the first Treasury free even at 20
Planks. **Decision: remove the rule entirely**, every building always costs.

This affects more than the Treasury. The other starting costs:

| Building | Cost after removing the rule |
|---|---|
| Storage Yard | 20 Wood + 20 Stone |
| Granary | 20 Wood + 10 Stone |
| Marketplace | 10 Wood + 10 Stone + 10 Gold (was never free anyway) |
| Treasury | 20 Planks (new) |

So the player has to accumulate wood **and stone** before any storage building can go up at all, and
stone needs a Quarry Hut. That is a substantially different opening — verify with a turbo run that
the settlement survives long enough without a Storage Yard/Granary before committing to it.
(`_can_afford_build_cost` / `_pay_build_cost` in `Main.gd:53` / `:66` fall back through
`get_storage_for_good()` to the Town Hall, which serves as storage at the start, so the stock is
reachable.)

### Scope

- `building_defs/treasury.tres`: `build_cost_gold = 0.0`, `build_cost = {1: 20.0}` (1 = PLANKS).
- `BuildingManager.register_building()` (`:91-95`): move `policy = PolicyData.new()` from the
  TOWN_HALL branch to the TREASURY branch. Point `get_subsidy` / `get_basic_income` at
  `get_treasury()`, with a `0.0` fallback when no Treasury exists — which is now the normal case at
  game start.
- Percentage tax: a new field on `PolicyData` (the Town Hall then still needs a `PolicyData`
  instance, just with different content — alternatively a small dedicated field directly on
  `BuildingInstance`). Editor in `InfoPanel._add_trade_data_editors` (`:223`) for TOWN_HALL,
  evaluation in `SimulationManager._process_daily_tax()` (`:690`): `inh.gold * rate` instead of a
  fixed amount.
- Remove `TradeData.daily_tax` and `BuildingManager.get_daily_tax()` (`:265`), plus the Treasury
  branch in `InfoPanel.gd:228`.
- **Save migration:** `SaveLoadManager.gd:129-134` (save) / `:301-309` (load) serializes `policy` per
  building. Old saves carry it on the Town Hall entry — remap it onto the Treasury on load, or the
  configured subsidies are lost, or land on a building that no longer reads them. If an old save has no
  Treasury the values are simply gone; that is consistent with the new gate, but should be a
  conscious call.
- Update `docs/GAME_DESIGN.md` and the `CLAUDE.md` glossary (Basic income / Subsidy / Local tax).

---

## 3. Scrolling jumps back to the top on refresh

**Problem:** While scrolling, the periodic refresh snaps the view back to the top.

**Finding — unambiguous cause:** `InfoPanel._refresh()` (`InfoPanel.gd:126`) ends with
`call_deferred("_reset_scroll")`, and `_reset_scroll()` (`:137`) sets `scroll.scroll_vertical = 0`.
Refreshes are triggered by `GlobalInventory.resources_changed` and applied every `REFRESH_INTERVAL`
(0.3 s) (`:101-116`) — effectively continuously while the simulation runs.

On top of that, `_clear_content()` (`:486`) tears down all children via `queue_free()` and rebuilds
them, which can lose the scroll position on its own.

**Note:** "all UI windows" is in practice exactly one — `InfoPanel.tscn:90` is the only
`ScrollContainer` in the project. The fix is correspondingly narrow.

**Scope (recommendation: 1 + 2 together):**
1. Take `call_deferred("_reset_scroll")` out of `_refresh()` and only call it when the displayed
   object actually changes (`show_building` / `show_inhabitant`).
2. Additionally remember `scroll_vertical` before `_clear_content()` and restore it deferred.
3. *Optional, larger:* update value labels in place instead of rebuilding. This would also remove
   the flicker and the `Input.is_mouse_button_pressed` workaround in `_process` (`:110`), which only
   exists so buttons are not recycled away between mouse-down and mouse-up. Only worth doing if the
   panel gets reworked anyway.

---

## 4. Price at −1 = "X" = the Crown does not trade this good

**Goal:** the buy or sell price can be set to `-1`, the UI shows `X`. The Crown then neither buys nor
sells that good — the price forms organically among the inhabitants.

### Decisions

- **Buy and sell are disabled independently.** "I no longer support wood, but I still sell it" has
  to work. Same implementation effort, more control.
- **Food when FOOD sell price is X:** inhabitants pay the cheapest producer lot price
  (`exchange.get_price()`), i.e. the real organic market price. No fallback to `BASE_PRICES` and no
  full lockout of the Crown's remainder stock — otherwise the settlement starves over a missing
  price.
- **Sentinel `-1.0` as the stored value**, but wrapped in two helpers on `MarketExchange`
  (`crown_sells(good) -> bool` / `crown_buys(good) -> bool`), so the `< 0.0` condition is not spelled
  out eleven times across the codebase.

### Finding

There is **no** sentinel mechanism today. Both prices are hard-clamped at `0.0`:
`MarketExchange.crown_ask()` (`market_exchange.gd:54`) → `maxf(0.0, c)`, `crown_bid()` (`:63`) →
`maxf(0.0, f)`. The UI steppers use `min_val = 0.0` (`InfoPanel.gd:285`, `:287`, default in
`_make_stepper` `:451`).

### Every site that has to honour the sentinel

This is where the actual work is — price formation hangs off those two functions in many places.

| Site | Role | Behaviour at "X" |
|---|---|---|
| `market_exchange.gd:72` `get_price()` | offers crown remainder at `crown_ask` | ignore the remainder, price from producer lots only |
| `market_exchange.gd:118` `offer()` | support price on delivery | no support price |
| `market_exchange.gd:179` `_purchase()` | sells crown remainder to consumers | remainder stays put |
| `market_exchange.gd:298` `_seller_offer_price()` | clamps the desired price to `[bid, ask]` | do **not** clamp — this is exactly where the organic price comes from |
| `market_exchange.gd:373` `history.record_bid()` | support-price line in the chart | draw a gap instead of −1 |
| `market_exchange.gd:390` `_run_crown_backstop()` | buys up drifted-down lots | do not run at all |
| `MarketManager.gd:65` | `maxf(crown_bid, crown_ask)` | the sentinel must not win as the maximum |
| `SimulationManager.gd:913` `_haggle` | starting price = `crown_ask` | fall back to `get_price()` |
| `SimulationManager.gd:1812` food purchase | `get_sell_price(FOOD)` | fall back to `exchange.get_price()` (see decision) |
| `BuildingManager.gd:249` / `:257` `get_buy_price` / `get_sell_price` | fallback to `BASE_PRICES` | must not turn "X" back into a real price |
| `InfoPanel.gd:285` / `:287` + `_make_stepper` | steppers | `min_val = -1.0`, render `"X"` instead of `"-1.0"` |

**Save/load:** uncritical. `buy_price` / `sell_price` are serialized as a generic dictionary
(`SaveLoadManager.gd:125-126`, `:291-292`); `-1` passes straight through.

---

## Verification (all items)

- `--turbo=<days>` headless run (`TurboRunner`) before and after the change, comparing the KPI CSVs
  under `user://runs`. Mandatory for #2 and #4 — both can tip the balance.
- Load an old `savegame.json` and check that prices and subsidies survive (#2).
- Manually: open the panel, scroll, let the simulation keep running — the position holds (#3).
