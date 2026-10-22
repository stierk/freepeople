# Backlog

Planned changes that are **not implemented yet**. Every item is verified against the current code
(state: after M35) — line numbers may drift with later commits, the function and field names are the
reliable reference.

Open questions have already been decided; the outcomes are recorded under **Decisions**.

Items #1, #2 and #6 share a root cause: the roles of the player-placeable buildings are blurred. The
Town Hall is currently storage yard, granary, price lever *and* policy centre all at once, the
Treasury does almost nothing, and the Marketplace does literally nothing. #3 and #4 are independent
UI and market topics. #5 is a new feature and by far the largest item.

**Order:** #1 → #3 → #6 → #2 → #4 → #5. #4 before #5 because the harbour reuses the price-stepper
UI; #5 last because it is the only item that adds a new system rather than correcting an existing one.
#7 is documentation reconciliation and travels with whichever item causes each edit.

**Rule of thumb this codifies:** inhabitants trade with the Crown at exchanges (Storage Yard,
Granary, and — at game start — the Town Hall). The Crown trades with the outside world at the
harbour. The two never mix: inhabitants have nothing to do with harbour prices.

---

## 1. Remove the phantom occupancy from the four storage/trade buildings

**Problem:** Storage Yard, Granary, Treasury and Marketplace show "Occupants X / 2" in the InfoPanel
even though nobody ever moves in.

> **This is not a rule about player-placeable buildings.** Being player-placed and having occupants
> are independent properties — the Trade Harbour (#5) is player-placed *and* houses the Trader. The
> change below is scoped to these four specific buildings, which have no workplace role at all.
> `max_capacity > 0` stays the single source of truth for whether a building can be occupied.

**Finding:** The display is purely cosmetic. `occupants` is only ever filled for work huts
(`SimulationManager.gd:1215`, `:1284`, `:1301`), and `get_understaffed_hut` / `get_reclaimable_hut`
(`BuildingManager.gd:200`, `:225`) filter through `PROFESSION_TO_BUILDING_TYPE`, which none of these
four appear in. `max_capacity = 2` is a dead value on all four. The Town Hall already has
`max_capacity = 0`.

**Scope:**
- `resources/data/building_defs/{storage_yard,granary,treasury,market}.tres`: `max_capacity` → `0`.
  (If #6 lands first, `market.tres` is gone and only three files remain.)
- `scenes/ui/components/InfoPanel.gd:153`: only show the Occupants row when `def.max_capacity > 0`.
  This condition is what makes the harbour keep its row automatically once #5 adds it.
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
  Planks → Treasury, and only then may the Crown intervene. **Decided with the cost below understood
  and accepted.**
- **Tax rate lives on `BuildingInstance`**, not in `PolicyData`: a plain `tax_rate: float`, only ever
  set on the Town Hall. `PolicyData` becomes purely a Treasury concern, so neither building carries
  fields that are meaningless where they sit.
- **`TurboRunner` places a Treasury** with `basic_income = 2.0` at startup, so benchmarks stay
  meaningful (see below). It already reaches into the Town Hall this way (`TurboRunner.gd:108` sets
  the Food sell price), so this is an established dev-only intervention, not a new kind of hack.

#### ⚠ Accepted cost: the gate reintroduces the M34 death spiral

`World.gd:245` sets `town_hall.policy.basic_income = 2.0`, and `docs/GAME_DESIGN.md §6` records what
that value is worth: **without it, seed 42 died on day 22 with 10 starvation deaths and 753 Food
sitting in the granary** — gold only flowed one way, every inhabitant hit exactly 0 while the treasury
climbed 1133 → 2100. With `2.0` the same seed survives to day 60 with 0 deaths.

Moving `PolicyData` to a building that does not exist at game start makes that safety net unreachable
until the player has wood → Sawmill → Planks → Treasury. This is a deliberate design choice, not an
oversight: an unattended settlement is *supposed* to fail, and a starvation death is framed as a
foresight failure of the Crown. But it means the early game is now genuinely lethal, and the
bootstrap default in `World._place_start_buildings` has nowhere to live.

Two consequences to handle when implementing:
- **`World.gd:245-247` must go somewhere or go away.** If the Treasury does not exist at start, the
  three bootstrap policy lines (`basic_income = 2.0`, two `0.0` subsidies) have no target. Simplest:
  delete them and let `PolicyData._init` defaults stand.
- **Benchmarks would otherwise measure nothing.** `tools/bench.ps1` sweeps 5 seeds × 300 days and
  ranks on final population with cumulative deaths as the penalty (`GAME_DESIGN §9`). Turbo runs are
  unattended by definition and never build a Treasury, so every run would collapse around day 22 and
  every profession strategy would score identically zero. The `TurboRunner` Treasury above is what
  keeps the harness usable; it simulates a competent player, while normal play keeps the gate.
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
- Percentage tax: new `tax_rate: float` on `BuildingInstance`, set only on the Town Hall. Editor in
  `InfoPanel._add_trade_data_editors` (`:223`) for TOWN_HALL, evaluation in
  `SimulationManager._process_daily_tax()` (`:690`): `inh.gold * rate` instead of a fixed amount.
- `World._place_start_buildings` (`World.gd:245-247`): drop the three bootstrap policy lines — their
  target no longer exists at start (see the accepted-cost box above).
- `TurboRunner`: place a Treasury with `basic_income = 2.0` at startup, dev-only.
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

> **Done differently (2026-10-21):** no `-1` sentinel. `TradeData.buy_disabled` / `sell_disabled`
> (good → true) are toggled by tapping the Buy/Sell price in the trade table, and honoured only in
> `MarketExchange.crown_buys` / `crown_sells` (+ `sell_to_crown_now`). The price is kept, so turning
> a side back on restores it. Both sides start **disabled** for every good in a new game. Not done: chart gap for a disabled side; `_willingness_to_pay` still
> starts from `crown_ask` as a reference price. The site table below predates M36.

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

## 5. Trade Harbour, Trader profession, and an outside world market

The settlement currently trades only with itself: inhabitants sell to the Crown at the exchanges, the
Crown resells to inhabitants. A surplus cannot be turned into gold, and gold cannot be turned into a
missing good — a grain glut stays a grain glut.

The **Trade Harbour** adds a second, entirely separate market: the outside world. **The Crown is the
counterparty there**, a **Trader** inhabitant works the harbour and physically hauls the cargo, and
ships arrive at random intervals. Inhabitants have nothing to do with harbour prices.

### Two findings that shape the work

- **The coast already exists.** `NoiseTerrainGenerator`
  (`scripts/util/noise_terrain_generator.gd:6`, `:39`) makes every cell within
  `COAST_EDGE_HARD = 2` of the map border water unconditionally, plus a noisy band out to
  `COAST_EDGE_SOFT = 5`. Every generated map is an island with a guaranteed water ring. **No
  generator change is needed** — only a water-adjacency check on placement.
- **Goods are not global** (gold is). Every building holds its own `community_stock`
  (`building_instance.gd:15`); `GlobalInventory.get_community_total()` (`:41`) is a read-only sum,
  not a pool. This is why the Trader has to haul cargo himself and why the harbour needs its own
  stock.

### Decisions

| Topic | Decision |
|---|---|
| Cargo movement | The Trader physically hauls between Storage Yard/Granary and the harbour |
| Export source | **Crown remainder only** — see the consequence below |
| Ship trade volume | Each ship has a fixed cargo capacity; trades execute automatically while the price matches |
| Trader | A normal profession picked via `EconomyManager`; 10 Gold/day flat wage; he also does the hauling |
| World prices | Pure random walk, hard-clamped to a wide band (0.2× – 5× base price) |
| Placement | Must be adjacent to water (the guaranteed coast ring) |
| Price UI | One stepper per good: positive = Crown buys (import), negative = Crown sells (export), **0 = not traded** |
| Hauling trigger | The Trader only starts hauling once a ship has docked |
| Ship dwell time | Fixed, ~1 game day |
| Subsidies/tariffs | Do **not** apply at the harbour |
| Maintenance | **Exempt from repair**, like the storages and the Treasury — the player paid for it, and a decaying harbour would strand the Trader mid-trade |
| Fiction | Ships come from **"the outside world"** — no names, no regions, no relations. One sentence in the `CLAUDE.md` Story section, nothing more |

Deliberate divergence: `0 = not traded` here, while item #4 uses `-1 = X` for the villager-facing
trade table. Different UI, different meaning — at the harbour the sign carries the buy/sell
direction, so 0 is the only free value left.

**Consequence of "crown remainder only" — worth understanding before balancing.** Crown remainder is
the part of an exchange's `community_stock` not covered by producer lots
(`MarketExchange.crown_remainder`, used by `GlobalInventory.gd:52-57`): the starting stock, plus
everything the crown backstop bought up at the support price. The Trader must not touch
producer-owned lots. So **export volume is gated on the player running a Buy Price high enough to
buy stock up** — the support price stops being a pure welfare lever and becomes the tap that feeds
foreign trade. A player who never sets one has nothing to export beyond the starting stock. That is
a good loop, but it means the harbour is useless until the player understands the support price.

### Scope

**New:** `scripts/autoload/WorldMarket.gd` (random-walk prices + ship scheduling, registered in
`project.godot [autoload]`), `scripts/data/harbour_data.gd`,
`resources/data/building_defs/trade_harbour.tres`, harbour sprite entry in `World.gd`.

`HarbourData` mirrors `TradeData` in shape and lifecycle:

```
var trade_price: Dictionary = {}   # good -> float; >0 crown buys, <0 crown sells, 0 not traded
```

**Enums — append only** (serialized as ints): `TRADE_HARBOUR` after `HUNTER_HUT`
(`building_def.gd:5-9`), `TRADER` after `HUNTER` and the new Trader states after `HUNTING`
(`inhabitant_data.gd:5`, `:6-20`).

**Modified:** `BuildingManager.gd` (def path in `BUILDING_DEF_PATHS` `:32-45`, `TRADER →
TRADE_HARBOUR` in `PROFESSION_TO_BUILDING_TYPE` `:5-13`, `harbour_data` in `register_building()`
`:59-97`), `SimulationManager.gd` (Trader FSM, daily wage next to `_process_basic_income()` `:710`),
`scripts/economy/strategy_urgency.gd` (Trader scoring), `SaveLoadManager.gd` (`harbour_data`
alongside `trade_data`/`policy`, `:117-134` / `:280-309`), `Main.gd` (water-adjacency check on
placement — reuse `_is_adjacent_to` from `scripts/util/site_selection.gd:191`), `InfoPanel.gd`
(harbour panel, reusing the `_add_trade_table` column constants `:36-40`), `docs/GAME_DESIGN.md` and
the `CLAUDE.md` glossary.

**Notes:**
- The harbour is **player-placed and occupied**: the player builds it, the Trader lives and works in
  it (`max_capacity = 1`). It is the case that shows why #1 is scoped to four named buildings rather
  than to "player-placeable" as a category. Its Occupants row must show, which the
  `def.max_capacity > 0` condition from #1 already handles.
- The Trader is **not** assigned by the Crown — he is picked like any other profession through
  `EconomyManager.pick_best_profession()`. The 10 Gold/day wage is the incentive. This keeps the
  fiction intact: a uniform standing wage offer, not a posting. The scoring strategy needs a term for
  him, since he produces no good and the existing appeal formula is built on production flow.
- Movement, pathing and carry limits reuse the existing helpers; the Trader is subject to
  `goods_space()` (`inhabitant_data.gd:219`), so the food reserve still protects him on a haul.
- `RunRecorder.record("harbour_trade", {...})` per executed trade — this is the milestone's main
  balance lever and has to be traceable in `user://runs`.
- **Delete the four dead export constants** while here: `MARKET_SURPLUS_THRESHOLD`,
  `MARKET_SELL_FRACTION`, `MARKET_FOOD_IMPORT_SHARE` and `TITHE_SALE_INTERVAL` in
  `SimulationManager` are each referenced exactly once, by their own declaration. Their names describe
  an automatic crown-exports-surplus system, which is *not* what the harbour does, so `WorldMarket`
  gets fresh constants rather than reusing them. The "There is no export mechanic" box in
  `GAME_DESIGN §6` is replaced by the harbour section.
- **Fiction:** `CLAUDE.md` states that no lore beyond Commonhurst itself is established and to "keep
  it that way unless a specific feature needs it". The harbour needs exactly the minimum: an unnamed
  outside world that ships arrive from. No named partners, no regions, no diplomatic relations — that
  keeps the rule satisfied rather than broken. The harbour is also in-fiction as a Crown lever: the
  player sets uniform per-good prices, never a deal with a named party.
- Turbo runs never build the harbour (it is player-placeable), so it stays invisible to the
  benchmark — the same structural blind spot the Storage Yard already has.

### Balance starting points

With `DAY_LENGTH_SECONDS = 60`, `TILE_SIZE = 16` and `BASE_MOVE_SPEED = 24` px/s an inhabitant covers
**1.5 tiles/s on grass, i.e. ~90 tiles per game day** (more on roads). A harbour 20 tiles from the
nearest storage means a ~27 s round trip, so a 1-day dwell allows roughly **two round trips ≈ 20
units per ship**.

| Constant | Proposal |
|---|---|
| `SHIP_CAPACITY` | 30 units (so dwell time, not the hold, is usually the binding limit) |
| `SHIP_DWELL_SECONDS` | `DAY_LENGTH_SECONDS` (1 day) |
| Ship interval | random 3–7 days |
| `TRADER_DAILY_WAGE` | 10.0, from `GlobalInventory.gold`, only for a Trader occupying a constructed harbour |
| Price band | `0.2 ×` to `5.0 ×` `Goods.BASE_PRICES` |
| Random walk step | ±5 % per day |

Because the Trader only starts hauling on arrival, **harbour placement is the player's real
decision** — a harbour far from the storages moves almost nothing. That is intended. If a
well-placed harbour trivially outearns every profession, pull `SHIP_CAPACITY` first, then dwell time.

---

## 6. Remove the Marketplace

> **Done in M37 (2026-10-21)** as scoped below; old saves drop a Marketplace on load and free its
> 1×2 footprint.

`BuildingType.MARKET` is dead mechanics. `MarketData` (`scripts/data/market_data.gd`) is created in
`BuildingManager.gd:68` and serialized (`SaveLoadManager.gd:117-121`, `:280-286`), but
`update_prices()`, `record_sale()` and `record_purchase()` are **never called from anywhere**. The
building costs 10 Wood + 10 Stone + 10 Gold and does nothing at all.

Inhabitants trade at the exchanges (`MarketManager._market_buildings()` `:68-74` — Storage Yard,
Granary, Town Hall), never at the Marketplace.

**Scope:** remove `market.tres`, `market_data.gd`, the `market_data` field on `BuildingInstance`
(`:36`), its creation in `BuildingManager.register_building()` (`:68-69`), `get_market()`
(`BuildingManager.gd:193`) and the save/load branches. **Keep the `MARKET` enum value reserved** —
enum values are serialized as ints and must never be reordered or reused (`goods.gd` note).

Old saves may contain a Marketplace building; loading must skip it gracefully rather than crash.

**Possible follow-up (not decided):** the name is worth reviving later for a genuine
inhabitant-to-inhabitant market, as opposed to today's inhabitant-to-Crown exchanges.

---

## 7. Documentation reconciliation

Found while checking this backlog against `docs/GAME_DESIGN.md` and `CLAUDE.md`. Two entries are
**wrong today**, independently of every other item, and can be fixed immediately. The rest are
follow-on edits that belong with the item that causes them — listed here so nothing is missed.

### Wrong right now (fix independently)

- **§5 building table, Treasury:** "build cost 20 gold". The `.tres` has `build_cost_gold = 20.0`
  **plus** `build_cost = {2: 20.0}` — 20 Gold **and 20 Stone**.
- **§5 building table, Marketplace:** "build cost 10 gold". Actually 10 Wood + 10 Stone + 10 Gold.

### Follows from item #1 (occupancy)

- §5 table: the "cap 2" notes on Storage Yard, Granary, Treasury and Marketplace become cap 0.

### Follows from item #2 (policy split)

- §5 blockquote calls the Town Hall the only "storage/exchange/**policy**" building an unattended run
  will have. After #2 it is no longer a policy building at all.
- §5 states `TRADE_BUILDING_TYPES` carries a second meaning, "first building of this type is free".
  #2 removes that rule, so the array means only "has `TradeData`".
- §6 subsidy and basic-income bullets say "set at the Town Hall" throughout — both move to the
  Treasury.
- §6 ends the basic-income bullet by noting a negative value is "mechanically identical to the
  Treasury's `daily_tax`". That comparison dies with `daily_tax`.
- §6 "Bootstrap policy defaults (M27, corrected M34)" documents in detail the fix that #2 deliberately
  undoes. It must be rewritten to record the *history* plus the accepted new cost, not deleted —
  losing the measurement is how this regression gets re-litigated later.
- `CLAUDE.md` glossary: **Subsidy/Tariff** and **Basic income** point at the Town Hall; **Local tax**
  describes `TradeData.daily_tax`, which is removed entirely.

### Follows from item #5 (harbour)

- §3 state machine table: the new Trader states.
- §4 profession table: add Trader. Note explicitly that he produces no good, which the documented
  `appeal(P)` formula does not handle — the formula description needs the Trader's wage term.
- §5 building table and repair-exemption list: add the Trade Harbour, exempt from repair.
- §6: replace the "There is no export mechanic" box with the harbour, and state the split plainly —
  inhabitants trade with the Crown at the exchanges, the Crown trades with the outside world at the
  harbour.
- `CLAUDE.md`: add `WorldMarket` to the autoload table, and one sentence to Story & Setting
  establishing the unnamed outside world.

### Follows from item #6 (Marketplace)

- §5 table: drop the Marketplace row; §5 blockquote lists it among the player-placed buildings; the
  repair-exemption list names "market".

---

## Verification (all items)

- `--turbo=<days>` headless run (`TurboRunner`) before and after the change, comparing the KPI CSVs
  under `user://runs`. Mandatory for #2, #4 and #5 — all three can tip the balance. For #5
  specifically, watch population and food: the Trader competes for bodies with the food chain and
  10 Gold/day is a strong pull.
- Load an old `savegame.json` and check that prices and subsidies survive (#2), and that a save
  containing a Marketplace still loads (#6).
- Manually: open the panel, scroll, let the simulation keep running — the position holds (#3).
- Harbour (#5): placement must be rejected inland and accepted on the coast ring across several
  seeds; set Grain negative, wait for a ship, and confirm via the `harbour_trade` events that the
  Trader hauled and gold reached the Crown treasury; set a positive price on a missing good and
  confirm it lands in the right storage building; a good left at 0 must never appear in a
  transaction; save with a ship docked, reload, and confirm prices survive and the Trader resumes.
