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
  community food stock exceeds `POP_GROWTH_FOOD_THRESHOLD` (deliberately set *above* the Town
  Hall's own starting food stock, so growth requires the settlement to have produced a genuine
  surplus, not just be coasting on its founding stock), a new colonist spawns every
  `POP_GROWTH_INTERVAL`, up to `POP_MAX = 32`. Every death is otherwise still permanent — growth
  is a slow, food-gated replacement mechanism, not a guarantee.

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
- **Profession** (`Profession`): `NONE, WOODCUTTER, SAWMILL_WORKER, QUARRY_WORKER, FARMER, MILLER, BAKER`.
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

**Profession assignment** (`EconomyManager.pick_best_profession`): a new or job-switching inhabitant
picks the scarcest *and* most valuable profession — urgency (how far current community stock is below
the `TARGET_*` levels) weighted by good price **plus the crown subsidy/tariff for that good**
(`_price_weight` ≈ (market price + `get_subsidy`) / base price), with a small random tie-break (`RANDOM_TIEBREAK`).
An already-active, understaffed hut of that profession is preferred over building anew.

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
| Woodcutter's Hut [4] | Woodcutter workplace | carry 8 |
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
`MARKET_TICK_INTERVAL = 5 s` do order matching, price drift, and exports.

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
- **Bootstrap policy defaults (M27):** all of the above (`subsidy`, `basic_income`) used to default
  to `0.0` and were only ever set by a player clicking the Town Hall UI — in an unattended game this
  safety net was completely inert. `World.gd` now sets sensible non-zero defaults at world creation
  (a small flat basic income, a small Food subsidy, a small Stone tariff). At these bootstrap values
  the Stone tariff is the only *default* crown income source, but it's no longer the only *possible*
  one without a Treasury: a negative `basic_income` (above) is an equally Town-Hall-native head tax.
  Only the Treasury's own `daily_tax` field remains structurally gated behind a player build (see
  §5). Still fully player-editable at any time via the existing UI,
  exactly like every other policy value.

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
- **Eating:** each inhabitant consumes `FOOD_PER_INHABITANT_PER_TICK = 1` food every
  `FOOD_CONSUMPTION_INTERVAL = DAY_LENGTH_SECONDS / 3` (3 meals/day). A working inhabitant carrying
  fewer than `FOOD_RESTOCK_THRESHOLD = 2` food will start a buy-food trip at a free decision point.
- **Starvation:** a missed meal increments `missed_meals`; after `STARVATION_DEATH_MEALS = 4`
  consecutive misses the inhabitant dies. Hunger tints the sprite; on death the node becomes a grave.

---

## 9. Persistence & telemetry

- **Save/Load** (`SaveLoadManager`): serializes world tiles, crops, buildings, inhabitants, market
  exchanges and gold. Enum values are stored as ints — this is why `GoodType`/`BuildingType`/`State`
  values must only ever be **appended**, never reordered.
- **RunRecorder** (`scripts/autoload/RunRecorder.gd`): writes per-run KPI CSV + events JSONL under
  `user://runs` for post-hoc analysis of a settlement's trajectory.
- **GlobalInventory** exposes aggregate community stock and emits change notifications for the UI.

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
  day one instead of requiring a player click. Fixed a state-machine bug where a market-driven
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
