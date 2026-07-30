# Freepeople — Game Design & Current State

This document is the detailed, **on-demand** reference for what *Freepeople* is and how it currently
works — it is **not** auto-loaded; open it when you need mechanics depth. For the always-in-context
architecture map, conventions, and the canonical **Story & Setting**, see [CLAUDE.md](../CLAUDE.md)
(auto-loaded every session). For a short pitch see the [README](../README.md).

Values in this document are pulled from source. Where a constant is named, its file is given so
the doc doubles as a balance reference. Engine: **Godot 4.6** (Mobile renderer, landscape),
package `de.hirth.freepeople`, entry scene `scenes/main/Main.tscn`.

---

## 1. Overview & win/lose

Freepeople is a **self-organizing village economy simulation**. The player does **not** directly
command individual people. Instead, autonomous inhabitants (agents) each decide what to do: they
pick a profession, build or reclaim a hut, gather resources, run production chains, sell their
goods on a market, buy food, and — if they can't eat — starve and die.

- **Goal:** keep the village alive. There is no explicit victory; the challenge is survival and
  a growing, self-sustaining economy.
- **Game over:** fires when the population reaches 0. `GameState.game_over(days_survived)` reports
  how many in-game days the settlement lasted.
- **Population growth is enabled** (`SimulationManager.POP_GROWTH_ENABLED = true`, M27): once
  community food stock exceeds `POP_GROWTH_FOOD_THRESHOLD`, a new colonist spawns every
  `POP_GROWTH_INTERVAL`, up to `POP_MAX = 32`, costing `POP_GROWTH_FOOD_COST` food from the
  granary. Every death is otherwise still permanent — growth is a slow, food-gated replacement
  mechanism, not a guarantee.
  > **Known mismatch (M34):** the intent was that this threshold sits *above* the Town Hall's own
  > starting food stock, so growth requires a genuine produced surplus rather than coasting on the
  > founding stockpile. It currently does not: `POP_GROWTH_FOOD_THRESHOLD = 1000.0` against a
  > starting stock of `1150.0` (`World.gd`), so growth fires immediately on founding stock. Left as
  > a tuning decision rather than silently changed.

---

## 2. World & tiles

The world is a fixed **64×64** grid of 16 px tiles (`WorldGrid.MAP_SIZE`, `TILE_SIZE`), generated
from a seed by `NoiseTerrainGenerator`. Each cell is a `TileRuntimeData` (`scripts/data/tile_data.gd`).

- **Terrain** (`TerrainType`): `GRASS`, `FOREST`, `STONE`, `WATER`. Water is impassable
  (`is_walkable`) and marked solid in the A* grid.
- **Paths** (`PathType`): `NONE`, `DESIRE_PATH`, `ROAD`. Movement speed multipliers:
  grass `1.0`, desire path `1.4`, road `1.8` (`SPEED_GRASS/DESIRE_PATH/ROAD`).
- **Emergent desire paths:** repeated foot traffic wears a cell (`WEAR_PER_STEP`, threshold
  `WEAR_THRESHOLD = 10`), promoting grass into a faster desire path; unused wear decays
  (`WEAR_DECAY_PER_TICK`). Crop fields are exempt from wear so farmers don't trample their own land.
- **Pathfinding:** `AStarGrid2D`, 4-directional (no diagonals), Manhattan heuristic.
  `find_path` resolves the nearest walkable start/target.
- **Resource depletion & regen:** harvesting depletes a tile's `resource_amount`
  (`RESOURCE_DEPLETION_PER_HARVEST`); tiles slowly regenerate (`RESOURCE_REGEN_INTERVAL/AMOUNT/CHANCE`).
- **Tree spread:** empty grass can spontaneously grow forest, with probability rising exponentially
  per adjacent tree (`TREE_SPREAD_BASE_CHANCE`, `TREE_SPREAD_GROWTH`, capped at `TREE_SPREAD_MAX_CHANCE`);
  occupied cells (building/road/crop/field) never spawn trees.
- **Crop fields:** a finished Farm House designates the ring of cells within `FARM_FIELD_RADIUS = 3`
  around it as farmland (`designate_farm_field`). See §7.

---

## 3. Inhabitants & the state machine

Inhabitants are plain data objects (`InhabitantData`, `scripts/data/inhabitant_data.gd`) ticked by
`SimulationManager`. Their visual node is `scenes/agents/Inhabitant.gd` (MinifVillagers sprite
sheets, per-profession walk/work animation rows; hunger tints the sprite; the dead become graves).

Per-inhabitant state:
- **Profession** (`Profession`): `NONE, WOODCUTTER, SAWMILL_WORKER, QUARRY_WORKER, FARMER, MILLER,
  BAKER, HUNTER` (M29 appended `HUNTER`; enum values are serialized as ints, so only ever append).
- **Inventory:** capacity **10** total goods (`INVENTORY_CAPACITY`); gold is separate and unlimited.
  `FOOD_RESERVE = 2` slots are kept free for food when loading trade goods (`goods_space()`), so an
  inhabitant on a long errand can still buy food and not starve with a full pack.
- **Gold, hunger, missed meals**, plus market bookkeeping (personal margin, last sale/food price,
  break-even, unprofitable streak — see §6).

### State machine (`SimulationManager._process_inhabitant_state`)

| State | Meaning / trigger | Handler |
|---|---|---|
| `SEEKING_SITE` | Fresh/unemployed or newly homeless: pick a profession and a hut/build site | `_handle_seeking_site` |
| `MOVING_TO_BUILD` | Walking to a new site or an existing hut with a free slot | `_handle_moving_to_build` |
| `FETCHING_MATERIALS` | Hauling build materials from storage to the site, one load at a time | `_handle_fetching_materials` |
| `BUILDING` | Construction timer running | `_handle_building` |
| `WORKING` | Producing at the workplace (dispatches to farmer/gatherer/producer logic) | `_handle_working` |
| `DELIVERING` | Carrying output to a storage/granary/market to sell | `_handle_delivering` |
| `RETURNING` | Walking back to the home hut after an errand; resumes `resume_state` | `_handle_returning` |
| `MARKET_TRIP` | Going to a market/granary to buy food (interrupts any activity) | `_handle_market_trip` |
| `FARM_TENDING` | Farmer walking onto a field to plant or harvest | `_handle_farm_tending` |
| `GATHERING` | Woodcutter/quarry worker mining a resource on-site | `_handle_gathering` |
| `HAULING_HOME` | Carrying gathered resource back to the home hut | `_handle_hauling_home` |
| `FETCHING_INPUT` | Producer (sawmill/windmill/bakery) buying its raw input at a storage | `_handle_fetching_input` |

Movement (`_process_movement`) advances along the path at `move_speed_base` × terrain speed
multiplier. Expensive idle searches (site/resource/field scans) are throttled by
`IDLE_RETRY_INTERVAL = 0.75 s` — this was the main performance bottleneck and is deliberately rate-limited.

---

## 4. Professions & production chains

Goods (`scripts/data/goods.gd`, `GoodType`): `WOOD, PLANKS, STONE, FOOD, GRAIN, FLOUR` (enum values
0–5, appended in that order — never reorder, saves store the int).

| Profession | Building | Input | Output | Notes |
|---|---|---|---|---|
| Woodcutter | Woodcutter's Hut | — | Wood | walks to forest, fells trees on-site |
| Sawmill worker | Sawmill | Wood | Planks | buys wood input if local buffer runs low |
| Quarry worker | Quarry Hut | — | Stone | mines stone tiles on-site |
| Farmer | Farm House | — | Grain | plants & harvests crops on surrounding fields |
| Miller | Windmill | Grain | Flour | |
| Baker | Bakery | Flour | Food | end of the food chain |
| Hunter | Hunter's Tent | — | Food | roams forest cells, hunts prey on-site; a hunted cell is prey-free for `HUNT_REPLENISH_DAYS` (4) days |

**Food chain:** Farmer harvests **Grain** → Windmill grinds **Flour** → Bakery bakes **Food** →
inhabitants eat Food. Two independent material chains feed construction: Woodcutter → **Wood** →
Sawmill → **Planks**, and Quarry → **Stone**. The Hunter (M29) is a separate, parallel Food source
with no inputs, feeding the same community Food pool as the Baker.

**Profession assignment** (`EconomyManager.pick_best_profession` → `profession_scores`): a new or
job-switching inhabitant picks the profession with the highest **appeal**, which is *additive*
(M31 — it used to be a multiplicative `urgency × price`, which was a hard gate: a good at or above
its target had urgency 0, so no price or subsidy could ever wake a non-scarce profession):

```
appeal(P)  = urgency_scale · urgency_of(good) + PROFIT_WEIGHT · profit + IDLE_BASELINE
score(P)   = appeal(P) / (1 + CROWD_WEIGHT · workers_already_in_P) + randf() · RANDOM_TIEBREAK
profit     = max(0, (market price + get_subsidy) / base price − 1)      # _price_weight
```

`IDLE_BASELINE` is the floor every available profession keeps at zero scarcity, so surplus labour can
spread; the crowding divisor is what makes each additional colonist prefer the next-best trade.
`urgency_scale` is 1.0 except for the Hunter (`HUNT_FOOD_WEIGHT`, see below) and weights the scarcity
term **only**, never the profit term or the baseline.

**Urgency is demand-relative, not stock-vs-target (M34).** `EconomyManager.urgency_of(good)` returns
`[0,1]` from two independent signals, combined as a probabilistic OR so either alone can raise it:

- **flow gap** — how far production is running short of demand (`FLOW_WEIGHT`). This is what makes a
  large stockpile with no domestic producers read as a deficit.
- **cover gap** — how far the stock is below `TARGET_COVER_DAYS` of that demand, i.e. an imminent
  stock-out even while production keeps up.

Demand (`demand_rate`) is the larger of *installed* capacity (analytic: eaters' appetite, each
constructed consumer's input rate, and each unfinished building's outstanding material cost amortised
over `BUILD_DEMAND_DAYS`) and *measured* consumption from a rolling 3-day flow window
(`FLOW_BUCKETS` × `FLOW_BUCKET_SECONDS`, fed by `note_production`/`note_consumption` from the
exchange and the population-growth food withdrawal). Counting installed demand analytically is what
keeps the signal from being circular — a starved mill still declares its appetite, and a settlement
too poor to buy wood still registers demand for wood.

An intermediate additionally inherits `CHAIN_PROPAGATION` of its downstream good's urgency
(`DOWNSTREAM_GOOD`: Grain → Flour → Food), damped by how well it already covers its own installed
consumers — so the chain staffs itself back-to-front from real end-product scarcity and stops
recruiting once the bottleneck has demonstrably moved downstream.

The pre-M34 fixed `TARGET_*` stock levels are gone. They were wrong in both directions: Grain/Flour
are intermediates whose stock says nothing about whether anyone needs more, and Food sat far above
`TARGET_FOOD` while draining with zero domestic production.

**Preferring an existing hut.** An active, understaffed hut of the inhabitant's *own* profession is
always the first choice (`get_understaffed_hut` — no build, shared workplace). Reclaiming a vacant or
derelict hut of a **different** trade rewrites the profession, so since M34 it is gated on appeal
(`CROSS_TRADE_REUSE_RATIO`, see `SimulationManager._reuse_allowed_types`): before that, the reuse
bonus was compared against site scores on a completely different scale and therefore always won,
silently discarding the economic decision that had just been made.

See also `RunRecorder`'s `appeal_<PROF>` / `scarce_<GOOD>` metrics columns, which record this signal
per game day — reading them against `prof_<PROF>` is how you tell "the score chose badly" apart from
"something downstream overrode the score".

---

## 5. Buildings

Definitions live in `resources/data/building_defs/*.tres` (`BuildingDef`,
`scripts/data/building_def.gd`; `BuildingType` enum values in brackets). Runtime state is
`BuildingInstance` (`scripts/data/building_instance.gd`), managed by `BuildingManager`.

| Building [type] | Role | Notes |
|---|---|---|
| Storage Yard [0] | Community stock for Wood/Planks/Stone; hosts a market exchange | starter building, cap 2 |
| Granary [1] | Community stock for Food/Grain/Flour; hosts a market exchange | cap 2 |
| Treasury [2] | Trade building: editable buy/sell prices & head tax (the crown gold pool itself lives in `GlobalInventory.gold`, not here) | build cost 20 gold, cap 2 |
| Marketplace [3] | Trading venue | build cost 10 gold, cap 2 |
| Woodcutter's Hut [4] | Woodcutter workplace | carry 8, **build cost `{}` since M35** (see the milestone log) |
| Sawmill [5] | Wood → Planks | carry 1 |
| Quarry Hut [6] | Stone extraction | carry 4 |
| Farm House [7] | Farmer home; designates surrounding farmland | carry 3, cap 1 |
| Road [8] | Speeds movement | — |
| Town Hall [9] | Central hub | non-worker (cap 0) |
| Windmill [10] | Grain → Flour | carry 1 |
| Bakery [11] | Flour → Food | carry 1 |
| Hunter's Tent [12] | Hunter workplace | carry 6, cap 1, not player-placeable |

Key `BuildingDef` fields: `footprint_size`, `max_capacity`, `build_time_seconds`, `build_cost`
(goods) / `build_cost_gold`, `storage_capacity`, `output_good`/`output_amount`/`output_interval`,
`input_good`/`input_amount`, `carry_capacity`. Storages/granaries/treasuries are the
**trade buildings** (`BuildingManager.TRADE_BUILDING_TYPES`) with player-editable buy/sell prices
and a tax rate (`TradeData`). Multi-cell footprints are supported (`WorldGrid` footprint helpers, M11).

> Storage Yard, Granary, Marketplace and Treasury are **player-placed only** (`is_player_placeable
> = true`, built via the BuildMenu) — no autonomous code path ever constructs them. In an
> unattended game the Town Hall is therefore not a transitional fallback but the **only**
> storage/exchange/policy building that will ever exist for the whole run, which is why its
> per-good `storage_capacity` (M27: wired into `BuildingInstance.stock_space(good)`, previously a
> dead field — every building fell back to a shared flat 100-unit cap regardless of what its
> `.tres` declared) is what actually bounds the community stockpile, and why the Treasury's head
> tax (`get_daily_tax`) is structurally unreachable without a player building one (see §6).
>
> For exactly this reason the Town Hall **also carries `TradeData`** since M34, even though it is not
> in `TRADE_BUILDING_TYPES` (that array additionally means "first building of this type is free", and
> the Town Hall is not player-placeable). Withholding it had meant an unattended settlement had no
> reachable price lever whatsoever. Defaults come from `Goods.BASE_PRICES`, so the fixed-average
> behaviour it used to have still holds until the player moves a stepper.

### Maintenance / decay

Work huts become due for repair every `REPAIR_INTERVAL_DAYS = 10` days. A hut resident then fetches
repair material from storage (cost = `REPAIR_MATERIAL_FRACTION = 0.5` of build cost, min 1 per good).
If not repaired within `REPAIR_GRACE_DAYS = 10` (no material/nobody home) the hut falls derelict and
disappears; during the grace period it gets a brown/grey tint. Only worker huts are repairable
(`REPAIRABLE_BUILDING_TYPES`); infrastructure (roads, storages, granary, treasury, town hall, market)
is exempt. Homeless inhabitants prefer to **reclaim** empty/derelict huts over building new ones
(reuse scoring `REUSE_BONUS_EMPTY`/`REUSE_BONUS_DERELICT`, M22/M23), which fights sprawl and revives
abandoned huts.

---

## 6. Economy & market

The market is **decentralized**: every Storage Yard and Granary hosts a `MarketExchange`
(`scripts/data/market_exchange.gd`), coordinated by `MarketManager`. Ticks every
`MARKET_TICK_INTERVAL = 5 s` do order matching and price drift. Since M34 the Town Hall counts as a
full exchange here too (`BuildingManager.get_all_storages_for_good` matches on which goods an
exchange *carries*, not on building type) — it is the only exchange an unattended run ever has.

> **There is no export mechanic.** This section used to claim market ticks also do "exports"; no such
> code exists. `MARKET_SURPLUS_THRESHOLD`, `MARKET_SELL_FRACTION`, `MARKET_FOOD_IMPORT_SHARE` and
> `TITHE_SALE_INTERVAL` in `SimulationManager` are dead constants — each is referenced exactly once,
> by its own declaration.

- **Best-market choice** (`MarketManager.pick_best_market`): sellers maximize price minus travel
  cost, buyers minimize price plus travel cost; `DIST_COST_PER_CELL = 0.05` gold per cell (Manhattan
  estimate first, real path only for the chosen target).
- **Individual pricing:** each inhabitant has a random personal `margin` set at spawn. Their
  reservation price = break-even × (1 + margin × `MARGIN_SCALE = 0.5`). Break-even rises with
  `time_since_last_sale`, so unsold goods gradually get cheaper.
- **Stale inventory:** a producer carrying goods unsold for `STALE_INVENTORY_SECONDS` (1 day) will
  deliver a partial load instead of waiting for a full carry (catches the non-hungry farmer who never
  makes a food trip).
- **Profitability-driven job switching:** after `UNPROFITABLE_SWITCH_STREAK = 5` (M27: raised from
  3 — more patience per profession before giving up on it) consecutive sales below break-even, an
  inhabitant switches to a better profession. `time_since_last_sale` (which drives break-even, see
  above) is reset on every switch (M27), so a freshly-switched inhabitant gets a full grace window
  before being judged again, instead of inheriting an already-inflated break-even from the job they
  just left.
  **Scarcity guard:** a producer whose good is currently scarce is never judged unprofitable — a food
  producer must not quit during a food shortage. M34 made "scarce" mean
  `EconomyManager.urgency_of(good) >= SCARCE_URGENCY_THRESHOLD`, i.e. **the same signal the
  recruiting side reads**, so pull and hold can no longer disagree. The previous fixed-target version
  was structurally asymmetric: Grain/Flour sat below their target often enough that Farmers and
  Millers were effectively unfireable, while Food at 1150 was never below its target, so Bakers and
  Hunters had no protection at all.
- **Resource-stall bypass (M33):** the scarcity guard in the bullet above (a currently-scarce good
  never triggers a switch, so a producer isn't judged unprofitable during a shortage) can itself
  strand a woodcutter or quarry worker whose hut's nearby forest/stone has been fully harvested out:
  producing nothing means the good never stops reading as scarce, so the switch never fires and the
  inhabitant idles near the hut forever. A separate, narrower counter
  (`InhabitantData.resource_stall_retries`, reset whenever a resource cell is found or on any
  profession switch) counts consecutive failed on-site resource searches in
  `SimulationManager._handle_gatherer_working`; at `RESOURCE_STALL_RETRIES = 160` failed searches in a
  row (~2 real minutes at the existing `IDLE_RETRY_INTERVAL = 0.75s` throttle — deliberately
  wall-clock bound rather than sim-time, so it fires regardless of game speed) it forces
  `try_switch_unprofitable` regardless of scarcity — the same market-driven reassignment as above,
  just with its own trigger condition.
- **Base prices** (`Goods.BASE_PRICES`): Wood 2, Planks 4, Stone 3, Food 2, Grain 1, Flour 1.5.
- **Crown policy — subsidy / tariff** (`PolicyData.subsidy[good]`, set at the Town Hall, applied by
  `MarketExchange._apply_subsidy`, M26): a per-good, per-unit levy on **every** producer sale
  (consumer purchase, crown backstop buy, and direct-sell-to-crown). Positive = **subsidy** — the
  crown pays the producer extra per unit **out of `GlobalInventory.gold`** (capped by the pool).
  Negative = **tariff** — the crown deducts per unit from the producer (capped by their gold) and
  collects it into the pool. So a subsidy is a real, ongoing drain on the shared crown gold, a
  tariff a real inflow — not just a behavioural nudge. The same rate also steers profession choice
  via `EconomyManager._price_weight` (see §4). Ownerless crown remainder is never subsidized/taxed.
- **Basic income** (`PolicyData.basic_income`): a single flat lever, one value for all inhabitants.
  Positive = every inhabitant receives that amount daily from the crown pool
  `GlobalInventory.gold` (capped by the pool) — a safety net against the death spiral. Negative =
  a flat daily head tax instead, deducting the same amount from every inhabitant (capped by their
  own gold) into the crown pool. Not scaled to individual income either way
  (`SimulationManager._process_basic_income`). A negative value here is mechanically identical to
  the Treasury's `daily_tax` head tax (§5) — same per-inhabitant, capped-by-own-gold deduction into
  the crown pool — but reachable straight from the Town Hall, without a player-built Treasury.
- **Bootstrap policy defaults (M27, corrected M34):** `subsidy` and `basic_income` default to `0.0`
  and are otherwise only ever set by a player clicking the Town Hall UI — in an unattended game the
  safety net is then completely inert. M27 claimed to have fixed this; it had not. The values in
  `World._place_start_buildings` were still literally `0.0`, and the measured consequence was exactly
  the death spiral this bullet warns about: at `--turbo-seed=42` the settlement died on **day 22 with
  10 starvation deaths and 753 food still in the granary**, because gold only ever flows one way —
  eating pays `crown_ask` into the treasury (which rose 1133 → 2100) while a producer's goods sit on
  consignment until a buyer takes them, so every inhabitant's gold reached exactly 0.
  **M34 sets `basic_income = 2.0`** (the same seed then survives to day 60 with 0 deaths). It is
  sized as a safety net, not a wage: an inhabitant eats ~2.1 food/day at base price 2.0, so this
  covers about half a day's rations and keeps money circulating rather than pooling in the treasury.
  The Food subsidy and Stone tariff remain `0.0` for now — they only became meaningful once M34
  connected the price signal to profession scoring (§4), so they are worth tuning separately.
  With `basic_income` positive, the crown has no *default* income source; a negative `basic_income`
  (above) is the Town-Hall-native head tax, while the Treasury's own `daily_tax` stays structurally
  gated behind a player build (see §5). All still player-editable at any time via the existing UI.

---

## 7. Farming detail

Crops live on farmland tiles (`crop_stage`, `crop_timer`, `crop_field_owner` on `TileRuntimeData`).
Only the owning farmer's field is tracked; `WorldGrid.crop_cells` lists active crop tiles for cheap
ticking (`SimulationManager._update_crops`, every `CROP_UPDATE_INTERVAL = 1 s`).

Lifecycle (`CropStage`): `NONE → STAGE_1 → STAGE_2 → STAGE_3 (ripe) → DEAD → cleared`.

| Transition | Constant | Value |
|---|---|---|
| STAGE_1 → 2, STAGE_2 → 3 | `CROP_GROW_INTERVAL` | 60 s each (~2 days to ripen) |
| STAGE_3 ripe window (→ DEAD) | `CROP_RIPE_LIFETIME` | `DAY_LENGTH_SECONDS * 10` = **600 s (10 days)** |
| DEAD → cleared | `CROP_DEAD_LIFETIME` | 60 s (1 day) |
| Harvest yield | `CROP_HARVEST_YIELD` | 1 Grain per ripe cell |

Task selection (`_find_farm_task`): scan the hut's field; **harvest** the nearest ripe (STAGE_3) cell
first, otherwise **plant** the nearest empty plantable cell. Harvesting (`_handle_farm_tending`) only
happens when the farmer stands exactly on the target cell and it is still ripe **and** the grain fits
in inventory; the field is cleared **only** after the grain is actually added, so a harvest can never
add nothing while clearing the crop. Harvest is instantaneous (no work timer, unlike gathering).
Grain accumulates up to the Farm House `carry_capacity` (3), then the farmer delivers it to a granary.

> Note: the 10-day ripe window was widened (from 1 day) so a single farmer has time to harvest a whole
> field before ripe cells wither unharvested. `farmer_hut.tres` lists `output_good = 3 (Food)` but the
> farmer's real runtime output is **Grain** via the harvest path, not the passive producer path.

---

## 8. Time, hunger & survival

- **Time:** 1 day = `DAY_LENGTH_SECONDS = 60 s` at normal speed. Speed modes (`SimulationManager.SpeedMode`):
  `PAUSED (0×), NORMAL (1×), FAST (2×), FASTEST (5×)`.
- **Eating:** each inhabitant consumes `FOOD_PER_INHABITANT_PER_TICK = 0.35` food (1.0 → 0.7 in M28,
  0.7 → 0.35 in M35 — see §12 and the milestone log) times their Speed/Frugality trait multiplier, every
  `FOOD_CONSUMPTION_INTERVAL = DAY_LENGTH_SECONDS / 3` (3 meals/day). A working inhabitant carrying
  fewer than `FOOD_RESTOCK_THRESHOLD = 2` food will start a buy-food trip at a free decision point.
- **Starvation:** a missed meal increments `missed_meals`; after `STARVATION_DEATH_MEALS = 4`
  consecutive misses the inhabitant dies. Hunger tints the sprite; on death the node becomes a grave.

---

## 9. Persistence & telemetry

- **Save/Load** (`SaveLoadManager`): serializes world tiles, crops, buildings, inhabitants, market
  exchanges, gold, and `EconomyManager`'s flow window (M34, additive `"flow"` key — absent in older
  saves, which then simply start with an empty window). Enum values are stored as ints — this is why
  `GoodType`/`BuildingType`/`State` values must only ever be **appended**, never reordered.
  Autoload state survives `reload_current_scene()`, so every manager with run state needs a
  `reset_state()` called from `restart_game` — `EconomyManager` included since M34, or a restarted
  run inherits the previous one's production history.
- **RunRecorder** (`scripts/autoload/RunRecorder.gd`): writes per-run KPI CSV + events JSONL under
  `user://runs` for post-hoc analysis of a settlement's trajectory. Columns are **only ever appended
  at the tail**, so existing column positions stay stable across milestones. Beyond the raw counts
  (`prof_<PROF>`, `bld_<TYPE>`, per-good `community_`/`crown_`/`price_`/`tradevol_`, gold spread,
  building health) M34 added `appeal_<PROF>` and `scarce_<GOOD>`, which record the *decision signal*
  rather than its outcome. Reading `appeal_<PROF>` against `prof_<PROF>` is how you tell "the score
  chose badly" apart from "something downstream overrode the score" — a low appeal with a stubbornly
  high headcount means the latter.
- **TurboRunner** (`--turbo=<days>`): dev-only headless fast-forward. `--turbo-seed=<n>` (M34) makes
  a run bit-reproducible — without it `World` seeds terrain from an engine-autoseeded `randi()`, so
  two runs of identical code are not comparable and any A/B is reading noise. `--turbo-step`,
  `--turbo-storage` (place a Storage Yard + Granary as a foresightful player would),
  `--turbo-food-price=<x>` (set the crown's Food Sell price, to test the policy lever headlessly) and
  `--turbo-strategy=<name>` (M35, see below) round it out. Behaviour-neutral refactors should be
  verified as a byte-identical CSV diff at a fixed seed; behaviour-changing ones need a spread of
  seeds, since single runs mislead badly.
  Reproducibility is load-bearing and slightly fragile: `TurboRunner` disables `SimulationManager`'s
  engine-driven `_process` **synchronously** in `_ready()` (M35) because `MessageQueue` flushes
  `call_deferred` *after* the `_process` dispatch, so a deferred disable could let one wall-clock
  delta into `sim_time`. A full audit found **zero** `RandomNumberGenerator.new()` instances and no
  `randomize()` anywhere, so every draw is covered by the global `seed()`.
  Turbo also suppresses `SaveLoadManager`'s auto-save timer (M35) — it used to re-create
  `savegame.json` from turbo state mid-run, leaving a stale save the next normal launch would load.
- **GlobalInventory** exposes aggregate community stock and emits change notifications for the UI.

### Swappable profession strategies + benchmark (M35)

Profession choice decides whether the food chain staffs itself or the roster freezes (§4), and it had
been evaluated by eyeballing one turbo run at a time. That misled outright during M34: the inspected
seed turned out to be the *worst* of five for the change under test, and the single-seed read
suggested a regression the 5-seed mean contradicted.

The algorithm therefore lives behind `ProfessionStrategy` (`scripts/economy/profession_strategy.gd`),
a `RefCounted` declaring exactly four entry points — `assign_profession_for_new_inhabitant`,
`pick_best_profession`, `profession_scores`, `is_good_scarce` — plus `strategy_name()`. Base
implementations `push_error` rather than returning a plausible value, so a half-implemented strategy
fails loudly instead of quietly biasing a benchmark.

- **`profession_scores` (pull) and `is_good_scarce` (hold) must be implemented by the same strategy.**
  They read one signal; splitting them across strategies reintroduces exactly the pull/hold
  disagreement M34 fixed, where Farmer/Miller were effectively unfireable while Baker/Hunter had no
  protection at all.
- `profession_scores` must be **deterministic and must not draw from the global RNG** — it is sampled
  once per game day into the `appeal_<PROF>` columns and read by the hut-reuse gate, so drawing there
  would shift a seeded run.
- **What is *not* strategy:** `EconomyManager`'s rolling production/consumption flow tracker is shared
  infrastructure. The seam is narrow — a strategy needs only `EconomyManager.supply_rate(good)` and
  `measured_consumption_rate(good)` back.
- A strategy's tuning constants live **in the strategy class**, deliberately against the usual
  "constants at the top of their manager" convention: they are the algorithm, and leaving them in
  `EconomyManager` would make the next strategy silently inherit them.

Adding a candidate: subclass `ProfessionStrategy`, return a new `strategy_name()`, and add one arm to
the `match` in `EconomyManager._make_strategy`. An unknown `--turbo-strategy=` is `push_error` +
exit 2, never a silent fallback to the default.

**Benchmark.** Every finished turbo run appends one row to `user://runs/bench.csv` (accumulated
across runs, unlike the per-run files), written by `RunRecorder.append_bench_row` so it reuses the
same `avg_hunger` / `inhabitants_gold` / `_cumulative_deaths` definitions as the metrics CSV:

```
strategy,seed,days,survived,population,deaths,avg_hunger,inhabitants_gold,crown_gold,prof_entropy
```

`prof_entropy` is the Shannon entropy of the final profession distribution in **bits (log2), with
`NONE` excluded** — the direct measurement of the roster-freeze failure mode (8 farmers → 0.000; one
of each of the 7 professions → 2.807). `NONE` is excluded on purpose: counting unemployment as a
category would make a decaying settlement read as "diverse".

`tools/bench.ps1` sweeps `seeds × strategies` (defaults: 5 seeds × 300 days) and prints a
per-strategy mean and sample stddev. **Ranking is on final population, with cumulative deaths as the
penalty; `prof_entropy` and `avg_hunger` are diagnostics, not targets** — a settlement can be
perfectly diverse and still starve. There is deliberately no single composite score.

Two operational notes the script encodes, both learned the hard way:
- Runs are **sequential**: `RunRecorder` names per-run files from a second-resolution timestamp, so
  two runs starting in the same second collide.
- On Windows the **`_console` Godot build is required**. Launched from PowerShell, the GUI build
  produces no stdout *and the run does not execute at all* (no `RESULT=` line, no bench row). The
  script auto-corrects a GUI path to its `_console` sibling.
- It refuses to run while a non-headless instance of the project is open (`-Force` overrides), and in
  that case deliberately does **not** back up/restore `savegame.json`: that process owns the file and
  rewrites it on a timer, so restoring a copy would roll the player's session back.

---

## 10. UI

`scenes/ui/` — **HUD** (day, gold, population, stock, speed controls, restart, plus economy shortcut
buttons — *Policies* → Town Hall, *Treasury*, and *Market* → Storage Yard — that open the relevant
building's InfoPanel; previously these levers were only reachable by clicking the building in the
world), **BuildMenu**
(placement), **InfoPanel** (click-to-inspect an inhabitant or building: profession, state, resume
state, home, missed meals, carried inventory, storage/market/trade details), **MarketChartPanel /
MarketChartPlot** (price history charts). Camera pan/zoom: `scenes/camera/CameraController.gd`.
Click selection is routed from `Main.gd` through `GameState` to the InfoPanel (M16).

---

## 11. Milestone log (mined from `Mxx` code comments)

Approximate feature timeline reconstructed from inline milestone tags; useful as a changelog spine,
not an exact history.

- **M7** — Production: huts, output goods, on-site resource gathering.
- **M8** — Population, food, and the base market loop; inhabitant spawning.
- **M10** — Save / load.
- **M11** — Multi-cell building footprints.
- **M12** — Free starter building bootstrap.
- **M13/M14** — Build costs paid in goods; trade buildings with editable buy/sell prices and tax.
- **M15** — Site selection scoring.
- **M16** — Click-to-select inspection; manual/driven profession switching.
- **M17** — Day/time system and price plumbing.
- **M18** — Hunger, food consumption, starvation death, grain→flour→food chain, game-over.
- **M19** — Farming: crop fields, growth stages, plant/harvest.
- **M20** — Market economy: per-exchange order books, individual margins/break-even, distance costs.
- **M21** — Producers buy their raw input on-site; building maintenance groundwork.
- **M22** — Food reserve, hut reclamation, repair/decay of huts.
- **M23** — Reuse-vs-rebuild scoring for homeless inhabitants.
- **M24** — Hunger emergency sale: a broke but laden inhabitant sells carried goods (except food)
  for cash before buying food, instead of starving with a full pack.
- **M25** — Market history & price chart: per-exchange trade chronicle (`MarketHistory`) plus a
  fullscreen price-chart overlay opened by clicking a good's "Now" price in the InfoPanel.
- **M26** — Crown subsidy/tariff moves real gold: `policy.subsidy[good]` now pays producers a
  per-unit bonus from `GlobalInventory.gold` (or collects a tariff) on every sale, not just tilting
  profession choice. Also adds HUD *Policies* / *Treasury* / *Market* shortcut buttons that open the
  Town Hall, Treasury and Storage Yard InfoPanels directly, and retires the dead `crown_stock`
  legacy (the "Kronenrest" telemetry now reads the real crown remainder from the exchanges).
- **M27** — Rebalance for unattended 1000-day survival (no player input). Added a dev-only headless
  turbo test harness (`TurboRunner`, `--turbo=<days>` CLI flag) and richer `RunRecorder` telemetry
  (per-inhabitant gold spread, building-health counts, cause-of-death detail) to make long
  unattended runs empirically testable. Fixed a real bug where `BuildingDef.storage_capacity`
  (per-good caps authored in every `.tres`) was dead data — every building silently fell back to a
  shared flat 100-unit cap; now wired into `BuildingInstance.stock_space(good)`. Cut the Town Hall's
  bootstrap stock from 1000/1000/1000/10000 (Wood/Planks/Stone/Food) to 300/0/200/3000, and colonist
  starting gold from 100 to 20 — small enough to matter, sized empirically (via repeated turbo runs)
  to cover the volatile early game rather than guessed. Gave the Town Hall non-zero default policy
  (basic income, a Food subsidy, a Stone tariff) so the existing safety-net mechanics are live from
  day one instead of requiring a player click.
  > **Corrections found in M34:** neither of the last two claims held in the shipped code. Colonist
  > starting gold is `100.0` (`GameState.gd`), not 20. And all three policy defaults were literally
  > `0.0` in `World.gd` — the safety net had never actually been live, despite this entry and §6
  > both arguing from it. M34 set `basic_income = 2.0`; the two subsidies remain `0.0`. Fixed a state-machine bug where a market-driven
  profession switch (e.g. Farmer→Miller) was immediately undone by unconditionally reclaiming any
  vacant hut of any profession before ever attempting to build the newly-chosen one — this is why
  Windmills/Bakeries essentially never got built before this fix. Fixed `time_since_last_sale` not
  resetting on a profession switch (inflated break-even during the whole build/establish period,
  triggering premature re-switching) and a timing race in Miller/Baker candidacy
  (`has_active_producer` required a hut occupied at the exact instant of the check;
  `has_building_of_type` requires only that a finished hut of that type exists). Raised
  `TARGET_FOOD` (20→120) and `UNPROFITABLE_SWITCH_STREAK` (3→5) to make the Baker profession
  attractive earlier and reduce profession churn. Re-enabled `POP_GROWTH_ENABLED` (was permanently
  off — every death was final), with its food threshold set above the new bootstrap stock so growth
  requires a genuine production surplus, not just an unspent founding stock.
- **M28** — Evolutionary traits (see §12) and a food-duration rebalance: lowered
  `FOOD_PER_INHABITANT_PER_TICK` (1.0→0.7) so carried food lasts longer and buy-food trips are
  less frequent, reducing gold pressure without changing the meal cadence or starvation thresholds.
- **M29** — Hunting: a new Hunter profession/Hunter's Tent (not player-placeable). The hunter walks
  to a forest cell and rolls for prey (`HUNT_SUCCESS_CHANCE = 0.4`); the tree stays standing (no
  `remove_tree`) — only the prey is temporarily gone, so a hunted cell is prey-free for
  `HUNT_REPLENISH_DAYS = 4` days, which makes multiple hunters sharing a forest naturally block
  each other. A successful catch always yields a guaranteed `HUNT_FOOD_BASE = 3.0` food floor, plus
  a bonus (up to `FOOD_PER_CATCH - HUNT_FOOD_BASE = 2.0`) scaled by the M28 Frugality yield
  drawback — unlike wood/stone/grain gathering, where the drawback scales the *entire* harvested
  amount, here it only shrinks the bonus, capping the effective catch penalty at ~6% instead of
  ~15% (see §12).
- **M30** — Translated every inline code comment and debug/log string from German to English
  across the whole codebase (the project's own convention had called for German comments up to
  this point). No logic changes; purely a language pass.
- **M31** — Profession-scoring rework: appeal is now ADDITIVE (scarcity + weighted profit + idle
  baseline) instead of the previous scheme, with a crowding penalty that divides a profession's
  appeal by how many inhabitants already hold it, and GRAIN is damped for FARMER until a downstream
  WINDMILL exists (no point overproducing grain nobody can mill yet). Introduced a personal price
  ceiling (willingness to pay, capped at the inhabitant's own gold) for building/repair material and
  profession raw-material purchases, rising with how long the inhabitant has been stalled waiting to
  buy; the market tie-break at an equal price now strictly prefers a producer's own lot over the
  crown's, so a producer can actually recoup costs instead of being undercut by crown stock parity.
  Also cut the Town Hall's bootstrap Food buffer from 3000 to a much smaller cushion so early
  scarcity/pricing signals are real instead of masked by a huge founding stockpile.
- **M32** — Hunters (and woodcutters) now roam from forest cell to forest cell within a single trip
  (`HUNT_CELLS_PER_TRIP = 5`) instead of one roll per outing, rolling for prey independently at each
  cell until the carry load is full or the per-trip cell budget is spent — this spreads the search
  outward and raises the catch chance per outing. A path worn across forest by a woodcutter/hunter
  passing through no longer tramples the tree away (only felling does), so scouting/hunting traffic
  doesn't accidentally clear-cut the forest.
- **M33** — Bounded resource-stall recovery: a woodcutter/quarry worker whose hut's nearby forest/
  stone had been fully harvested out could get stuck standing near the hut forever — producing
  nothing meant the good never registered as non-scarce, which blocked the existing unprofitability
  switch (§6) indefinitely. Added `resource_stall_retries` (reset on any resource-cell find or
  profession switch); at `RESOURCE_STALL_RETRIES = 160` consecutive failed searches
  (`_handle_gatherer_working`) the inhabitant is forced through the normal
  `try_switch_unprofitable` → `pick_best_profession` path, same mechanism as any other market-driven
  job change.
- **M34** — Profession diversity & the signals behind it. Symptom: the roster froze at ~8 Farmers
  with no Bakers and no Hunters, and a raised Food Sell price changed nothing. Four independent
  causes, each fixed and measured separately:
  1. **Reproducibility first.** `World` seeds terrain from an engine-autoseeded `randi()`, so no two
     turbo runs were comparable and every earlier balance pass had to argue from variance across
     runs. Added `--turbo-seed=<n>` (and `--turbo-food-price=<x>`), plus deterministic
     `EconomyManager.profession_scores()` and `appeal_<PROF>`/`scarce_<GOOD>` metrics columns, so the
     choice signal itself is recorded rather than inferred from headcounts.
  2. **The reuse bonus overruled the score.** `REUSE_BONUS_EMPTY = 1000.0` was compared against
     `SiteSelection.score_site` values in the −5…−60 range — a unit mismatch, so any vacant hut
     always won and `_reassign_to_hut_profession` then overwrote the freshly-chosen profession. The
     new columns proved it: `appeal_FARMER` fell to **0.011**, the lowest of every profession, while
     8 farmers persisted for a whole 60-day run. Cross-trade reclaim is now gated on appeal
     (`CROSS_TRADE_REUSE_RATIO`); same-profession reuse was already handled by `get_understaffed_hut`.
  3. **The price lever was not connected.** The Town Hall was deliberately denied `TradeData`, and
     `get_all_storages_for_good` filtered on Granary/Storage-Yard type with no Town Hall fallback —
     so in a run without a player-built Granary there was no settable price at all and
     `get_market_price` returned the flat base price forever (`price_FOOD` = 2.00 on every recorded
     row), pinning `_appeal`'s profit term at exactly 0. Both fixed; behaviour is unchanged at
     defaults because `TradeData` seeds from `BASE_PRICES`. Verified against the closed form: at
     Sell price 4.0 the Hunter's raw appeal is 0.521 vs. 0.520 predicted. The lever cuts both ways —
     a Food price of 6.0 bankrupts the eaters and kills the settlement by day 25.
  4. **Urgency was stock-vs-fixed-target.** Replaced by the demand-relative `urgency_of()` in §4,
     backed by a rolling production/consumption tracker. `TARGET_*`, `GOOD_TARGETS` and
     `FARMER_NO_CHAIN_FACTOR` are deleted; `is_good_scarce` now reads the same signal the recruiting
     side uses, which makes the old retention asymmetry (Farmer/Miller effectively unfireable while
     Baker/Hunter had no protection at all) structurally impossible rather than merely retuned.
     `HUNT_FOOD_WEIGHT` now scales the urgency term only — multiplying the whole appeal had also
     shrunk the Hunter's `IDLE_BASELINE` to 0.12, the only profession sitting *below* the 0.15
     `RANDOM_TIEBREAK`, i.e. a lottery it was rigged to lose.

  Also fixed two bugs specific to the professions whose product **is** the consumed good: Hunters
  dumped their own eating reserve into the hut pile (forcing a granary run after every hunt) and
  Bakers/Hunters consigned their rations unpaid and then bought food back for cash on the same trip.
  Bakery/Windmill `carry_capacity` 1.0 → 5.0 (it divides break-even, and gated the mill to fetching
  one grain per trip). And `basic_income` was finally set non-zero: at seed 42 the settlement went
  from dying on day 22 with 10 starvation deaths and 753 food still in the granary — gold flows one
  way, eating pays the treasury while production sells on consignment — to surviving day 60 with 0.

  Aggregate effect over 5 seeds × 60 days: food at day 60 203 → 266, `build_aborted` 128 → 63,
  `jobchange` 21 → 3, derelict buildings 18 → 11, survival 5/5 throughout.

  **Still open — capital formation.** Builders cannot afford materials: a Windmill needs 20 wood
  while ~90 sits unsold in the Town Hall, but the builder holds ~2 gold and the willingness-to-pay
  ceiling is capped by their own gold. Stalled sites are retried and re-aborted in a loop while the
  crown treasury saturates around 2078. This is why food production shifts toward Hunters (no input
  chain, no funded building) rather than the Farmer→Miller→Baker chain.
- **M35** — The wood dead end. Symptom: from ~day 24 woodcutters and hunters stand around without a
  hut, apparently idle. They are not idle — they sit in `FETCHING_MATERIALS` at the Town Hall
  waiting to buy Wood that no longer exists anywhere in the settlement. Measured at seed 42, 30
  days: community Wood 300 (start) → 170 (day 2) → 94 (day 14) → **0 from day 24 on, permanently**;
  18 `build_aborted` events, 12 of them the *same* Woodcutter's Hut retried by the *same*
  inhabitant. Gold was never the constraint (one of the stuck woodcutters held 62.6).

  Root cause is a bootstrap circularity: every workplace is paid for in Wood (Woodcutter's Hut 20,
  Hunter's Tent 15, Quarry Hut 20, Farm House 10 + 10 Stone, Sawmill 30 + 10 Stone), but Wood only
  enters the settlement through a woodcutter **working from a finished hut**. The 300 starting Wood
  is therefore a strictly finite budget, and once it is spent the settlement can never build
  anything again — least of all the one building that would produce more Wood.

  Fix: the Woodcutter's Hut has `build_cost = {}` — a woodcutter raises their shack from the trees
  they fell. Wood is now genuinely renewable: whenever the stock hits zero, a woodcutter can still
  build and restart the flow. Every code path already handled an empty build cost, and each now
  fires for real: `_start_new_build` goes straight to `BUILDING` (no material trip),
  `_repair_material_cost` returns `{}` so `_try_start_repair` performs a free instant repair, and a
  derelict hut restores itself in `build_time_seconds` with no fetch.

  Deliberately **not** fixed here (all still open, all observed in the same run): a stalled build
  that aborts resets `pending_build_cost` to the *full* cost in `_derelict_building`, destroying
  material already delivered; `get_understaffed_hut` re-offers the very ruin the inhabitant just
  failed to finish, with no cooldown and no check that the material exists, so the
  abort → reclaim → stall loop spins indefinitely; and `price_WOOD` stayed flat at 2.00 across the
  whole run even at zero stock, so scarcity never reached profession scoring in time for anyone to
  become a woodcutter while Wood was still buildable-with.

  **Hunters and woodcutters working their own hut.** Second M35 symptom, same run: hunters and
  woodcutters stand next to their hut flipping `WORKING` ↔ `HUNTING`/`GATHERING` every frame
  without ever moving. Counted at seed 42 over 40 days: **4017 of 4041 hunt legs and 848 of 852
  gather legs** aborted without a single step taken.

  Huts are routinely built directly onto forest — `is_footprint_buildable` only rejects water and
  occupied cells, and `SiteSelection` deliberately seeks forest proximity — and the terrain under a
  hut stays `FOREST`. `_tile_huntable` and `_find_resource_cell_near` tested terrain and
  cooldown/`resource_amount` but never `building_id`, so a worker's own hut, at distance 0, won the
  nearest-cell search every time. Because a building footprint is solid in A\*,
  `WorldGrid.find_path` resolved it to a neighbour (`_resolve_walkable_target`) and returned a path
  of length 1 — the cell the worker already stood on. They "arrived", the on-site handler saw
  `cell != gather_target_cell`, bounced back to `WORKING`, and picked the same cell again. The trip
  never completed, so the hunting cooldown was never set and the tree never felled: the loop was
  self-sustaining.

  Two fixes, both in `SimulationManager`:
  - `_tile_workable()` — a work target must be free of buildings (any hut, not just one's own).
    A path across a **forest** tile disqualifies it too; worn desire paths already convert forest to
    grass (M32) and regrowth skips path cells, so that half is a consistency guard covering
    pre-M32 saves. Non-forest resources are exempt: a track worn to a quarry face does not remove
    the stone. Wired into `_tile_huntable`, `_find_resource_cell_near` and `_handle_gathering`'s
    on-arrival re-check.
  - `_path_reaches()` — `_start_hunt_leg`/`_start_gather_leg` now return `bool` and only enter
    `HUNTING`/`GATHERING` when the route provably ends on the target cell; otherwise they throttle
    via `idle_retry_timer` and stay in `WORKING`. This is the backstop for every *other*
    unreachable target (forest across water, a cell walled in by huts), which would otherwise spin
    the identical busy loop. Mid-trip, a hunter who cannot reach the next cell now hauls their
    catch home instead of standing.

  Effect at seed 42: 0 broken legs on both seeds; hunt legs 4041 → 441 in 40 days, all of them
  real work. Food at day 60 451 → 791 (seed 42) and 430 → 703 (seed 7), Wood at day 40
  17.7 → 99.6 and rising instead of collapsing, population peaking at 13 instead of a flat 11.

  > **New pressure, not yet addressed.** Real production moved gold the other way: inhabitant gold
  > at day 40 rose 504 → 2021 while the Crown treasury fell 1488 → **0** by day 60 on seed 42 (the
  > crown backstop now actually buys the goods being produced, and `basic_income = 2.0` is paid to
  > a larger population). The seed-42 run ends with **2 starvation deaths** between day 45 and 60,
  > where it previously had none — an empty treasury cannot pay the safety net. Seed 7 still ends
  > at 770.5 with 0 deaths. This is the M34 "capital formation" note reappearing from the other
  > side and wants a balance pass, not another bug fix.

  **Swappable profession strategy + benchmark harness.** Third M35 strand, and the reason the two
  above could be measured at all. Profession choice had only ever been evaluated by eyeballing a
  single turbo run, which misled outright in M34: the inspected seed turned out to be the *worst* of
  five for the change under test, so the single-seed read suggested a regression the 5-seed mean
  contradicted.

  - **Determinism gate first.** Verified at `--turbo=100 --turbo-seed=42` before touching anything:
    same seed twice → metrics CSV *and* events JSONL byte-identical; seed 42 vs seed 7 → different.
    An audit found **zero** `RandomNumberGenerator.new()` instances and no `randomize()` anywhere, so
    the global `seed()` covers every draw, and `NoiseTerrainGenerator` derives all three noise seeds
    from its argument. Two latent hazards were hardened anyway: `TurboRunner` now disables
    `SimulationManager`'s engine `_process` **synchronously** (`MessageQueue` flushes `call_deferred`
    *after* the `_process` dispatch, so a deferred disable could leak one wall-clock delta into
    `sim_time`), and `SaveLoadManager` skips its auto-save timer under `--turbo=` (it used to
    re-create `savegame.json` from turbo state mid-run, leaving a stale save the next normal launch
    would load). Both confirmed behaviour-neutral by byte-diff.
  - **Extraction (pure refactor).** The M34 algorithm moved verbatim into
    `scripts/economy/strategy_urgency.gd` behind `ProfessionStrategy`; `EconomyManager` keeps the flow
    tracker and delegates. Proven byte-identical at a fixed seed — including that an explicit
    `--turbo-strategy=urgency` matches the implicit default, that an unknown name exits 2, and that a
    normal launch still boots. See §9 for the interface contract and how to add a candidate.
  - **Measurement.** Each finished turbo run appends a row to `user://runs/bench.csv`;
    `tools/bench.ps1` sweeps seeds × strategies and prints per-strategy mean/stddev
    (`-SummaryOnly` re-reads the file without re-running the sweep, which takes the better part of an
    hour). Ranking is on final population with deaths as the penalty; `prof_entropy` (bits, `NONE`
    excluded) is a diagnostic for the roster-freeze mode, not a target.

  **Baseline — `urgency`, 5 seeds × 300 days.** Every later candidate is compared against this:

  | seed | survived | pop | deaths | inh. gold | crown gold | entropy |
  |---|---|---|---|---|---|---|
  | 7 | yes | 9 | 2 | 2100 | 0 | 2.419 |
  | 42 | yes | 7 | 6 | 2300 | 0 | 1.449 |
  | 123 | yes | 5 | 6 | 2100 | 0 | 0.971 |
  | 999 | yes | 7 | 5 | 2200 | 0 | 2.236 |
  | 2024 | yes | 8 | 5 | 2300 | 0 | 2.500 |
  | **mean** | **5/5** | **7.20** ±1.48 | **4.80** ±1.64 | | | **1.915** ±0.672 |

  Two things stand out and are *not* strategy problems, so no candidate should be expected to fix
  them alone. **The Crown treasury is empty on every seed** — the inverse of the M34 capital-formation
  note: production now works, so the crown backstop keeps buying, while `basic_income` keeps paying
  out to a population that no longer earns it back. And the settlement **shrinks** on every seed
  (10 colonists → 5–9, with 2–6 starvation deaths) even though all five formally survive. Survival is
  currently a weak discriminator; population and deaths carry the signal.

  Entropy spread is wide (0.971–2.500 across seeds at identical code), which is the quantitative
  restatement of the M34 lesson: **a single seed cannot tell you whether a strategy diversifies the
  roster.**

  No behaviour change in this strand — writing an actual *second* strategy is deliberately left as
  follow-up work, so that a candidate's numbers can be attributed to the candidate rather than to the
  refactor.

- **M36** — Double-auction order book. ⚠ **Not verified — do not treat as finished.** Symptom: in the
  price chart the demand cloud sits far above the supply cloud, yet every deal is with the Crown.

  **Two findings, both confirmed.** First, the chart never showed bids at all:
  `MarketExchange` recorded `payer.gold / want` as its DEMAND series — a purse divided by a
  wish, not a price — which is why `MarketChartPlot._price_max` already scaled to the 95th
  percentile to stop one rich buyer flattening the plot. Second, villagers *structurally could
  not* trade with each other: `TradeData` seeded `buy_price == sell_price == BASE_PRICES`, so
  `_seller_offer_price`'s clamp to `[bid, ask]` collapsed onto a single point, every lot landed
  exactly on the Crown's bid, and the backstop bought it out within one market tick.

  **The rewrite** replaces consignment with an order book (`MarketOrder`, dead since it was first
  drafted, finished here): villagers post SELL and BUY orders priced by `ReservationPricing` from
  a market anchor, sellers drifting down and buyers up. The Crown becomes two standing orders at
  the band edges instead of a special case in the purchase loop.

  **Four measured failures, kept here because each one cost a 5-seed sweep and the reasoning that
  produced them was wrong in an instructive way.** Against the M35 baseline (pop 7.20, deaths 4.80,
  5/5):

  | change | pop | deaths | survived | what it actually showed |
  |---|---|---|---|---|
  | 0.7/1.3 spread only | 6.80 | 5.20 | 4/5 | roughly neutral; helps 4 seeds, kills one |
  | + order book | 1.80 | 10.20 | 3/5 | `p2p_share` 0.03–0.09: the Crown still had >90% of volume and now charged a spread for it |
  | + resting bids | 2.60 | 9.40 | 5/5 | `p2p_share` *fell* over 300 days — it drops when the settlement shrinks, so it is partly an effect, not only a cause |
  | spread back to 1.0/1.0 | ~0.5 | ~12 | 2/4 | **refuted the spread hypothesis**: identical Crown prices to M35, catastrophically different outcome |

  Two real defects surfaced along the way, both from reading an inhabitant's own state as a price
  source without checking how it behaves over time. `seller_floor` was `break_even × greed`, and
  `break_even_unit` is `cost_of_living × time_since_last_sale` — so an unsold order's floor *rose*
  while its price drifted down, the two crossed without meeting the Crown, and the order could never
  clear. And `sell_anchor` was the seller's own last sale price with a fixed markup on top: sell at
  2.0 → open at 2.6 → fill → open at 3.38. One inhabitant ratcheted up to **58% of all gold in the
  settlement** (1315 of 2278, seed 42 day 90) while everyone else sat at 2 gold and starved. The
  anchor is now `MarketHistory.recent_deal_price` — what the market actually paid, across all
  sellers, which no single participant can move.

  **The root cause was never the prices.** A 100-day instrumented run showed `tradevol_villager`
  at exactly **0.0 for 57 days**, turning non-zero on the very day the treasury hit 0. The Crown
  starts holding practically the whole food stock (817 of 835) and offers it at `crown_ask`
  forever, so no villager can be the cheapest seller — and any who drifts low enough to be
  interesting is bought out by the Crown's own bid first. M35 avoided this by accident: its clamp
  pinned every ask to exactly `crown_ask`, and M31's tie-break preferred the villager lot on a
  **tie**. Ranking by price turned a tie the villager wins into a race the Crown wins.

  `_match` therefore uses a **priority ladder, not price priority**: villager-to-villager first
  even when the Crown is cheaper, then the Crown as buyer of last resort, then as seller of last
  resort. Price priority applies only *among* villagers. `_settlement_price` follows normal
  exchange practice — the resting order names the price, the arriving one accepts; the midpoint
  applies only when both have waited and drifted into each other (splitting unconditionally made a
  hungry buyer with a 3× walk-away price pay 4.3 against an ask of 2.6).

  **State at hand-off.** The ladder restores villager trade immediately (`tradevol_villager`
  non-zero from day 6, exceeding Crown volume by day 18), but the 60-day smoke test **ends before
  the cliff** — in the comparison run the deaths came on days 64–66. `crown_gold` still drains to
  0 and `gold_min` still pins at 2.0, both unchanged. `TradeData` is left at the diagnostic
  `1.0/1.0`, not a shipping value. **A full 5-seed sweep is the next step, and a rollback is a
  legitimate outcome.**

  **Kept regardless of that outcome:** `RunRecorder.p2p_share` plus the `tradevol_villager` /
  `tradevol_crown` metrics columns (without them this would have read as "order book broken"
  rather than "order book half-finished"); `MarketHistory.recent_deal_price`; and the honest
  DEMAND series. ⚠ **Never rank on `p2p_share` alone** — it looks healthy in a dying settlement,
  because a village of two has nobody left to trade with. Read it beside population.

  **Also confirmed as pre-existing, independent of M36:** `crown_gold` reaches 0 in all five *M35
  baseline* runs too. The Crown buys up surpluses nobody buys back, so gold flows one way. That is
  the mechanism behind the reported symptom and is worth its own milestone.

---

## 12. Evolutionary traits (M28)

Every inhabitant spawns with **six personality traits**, each a random `[0,1]` float rolled once
at spawn (`GameState.add_inhabitant`). `0.0` means the trait is not expressed (neutral — neither
its benefit nor its drawback applies); `1.0` means it is fully expressed (full benefit **and**
full drawback). Every trait carries exactly one of each — there is no free lunch. Fields and
multiplier functions live in `scripts/data/inhabitant_data.gd`; derived stats (move speed, carry
capacity) are (re)computed by `recompute_derived_stats()`, called at spawn and after load.

| Trait | Field | Benefit | Drawback |
|---|---|---|---|
| **Speed** (Tempo) | `trait_speed` | up to **+25%** move speed | up to **+30%** personal food need |
| **Strength** (Kraft) | `trait_strength` | up to **+4** inventory capacity (base 10) | up to **-20%** move speed |
| **Frugality** (Genügsamkeit) | `trait_frugality` | up to **-25%** personal food need | up to **-15%** yield per gather/harvest action |
| **Diligence** (Fleiß) | `trait_diligence` | up to **+25%** work speed (build/gather timers) | up to **+40%** hunger increase on a missed meal |
| **Resilience** (Widerstandskraft) | `trait_resilience` | up to **+2** extra missed meals tolerated before starving | up to **-20%** work speed |
| **Greed** (Gier) | `margin` (M20, reused) | higher personal sell margin (existing) | pays up to **+25%** premium on food purchases (`GREED_BUY_PREMIUM_SCALE`) |

Notes on interactions (deliberate cross-trait tension, not a bug):
- **Move speed** = Speed's benefit × Strength's drawback (`InhabitantData.move_speed_multiplier`) —
  fast-and-light vs. strong-and-slow.
- **Personal food need** = Frugality's benefit × Speed's drawback (`food_need_multiplier`) — feeds
  into `_feed_inhabitant`, `recompute_break_even` and the food-duration tuning below.
- **Work speed** (construction timer, on-site gather timer) = Diligence's benefit × Resilience's
  drawback (`work_speed_multiplier`) — workaholic vs. steady/methodical. At both traits maxed out
  the two roughly cancel (1.25 × 0.8 = 1.0), so extremes aren't strictly dominant.
- **Greed** doubles as both the pre-existing M20 sell-margin stat and the 6th trait, to avoid a
  redundant duplicate field; its drawback is charged in `SimulationManager._charge_greed_premium`,
  called from `_buy_food_at` (paid to the crown treasury, not destroyed — conserves total gold).
- **Frugality's yield drawback on hunting (M29) is an exception** to the table's "up to -15% yield"
  claim: a hunter's catch always has a guaranteed `HUNT_FOOD_BASE` floor that Frugality can't touch,
  so only the smaller bonus portion is scaled down — the effective penalty on a catch tops out
  around -6%, not -15%. Wood/stone/grain gathering still scale the full harvested amount.

**Future work (not yet implemented):** the fields are plain `[0,1]` floats specifically so a later
reproduction mechanic can average two parents' traits (+ small mutation) into a new colonist's
genes when population growth spawns someone, instead of the current uniform `randf()` roll. This
would make traits a real evolutionary pressure (bad combinations die out via starvation; the
survivors' genes propagate) rather than pure per-spawn noise. No parent-selection or crossover
code exists yet — `_process_population_growth` still spawns with fresh random traits.

**Food-duration tuning:** `SimulationManager.FOOD_PER_INHABITANT_PER_TICK` was lowered from `1.0`
to `0.7` (a flat ~30% cut, independent of traits) so a carried food stock lasts longer and
buy-food trips (which cost work time and gold) happen less often — directly reducing the
settlement's gold pressure without touching the 3-meals/day cadence or the starvation thresholds.
