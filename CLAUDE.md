# CLAUDE.md

*Freepeople* — a self-organizing village economy simulation in **Godot 4.6** (Mobile renderer,
landscape; package `de.hirth.freepeople`). Autonomous inhabitants pick professions, build, run
production chains, trade on a decentralized market, eat, and can starve. Survive by keeping the
population above zero. Entry scene: `scenes/main/Main.tscn`.

> **This file is the always-in-context map** — Claude Code auto-loads it every session, so keep it
> short. It holds the architecture map, conventions, and the canonical **Story & Setting** (the
> fiction lives here). For deep mechanics & current state read
> [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) (not auto-loaded — open on demand). README covers the
> Android build.

## Story & Setting

Freepeople takes place in a low-fantasy medieval frontier settlement called **Commonhurst**. This
section is the canonical fiction — `story-keeper` judges every change against it; other docs and
agent prompts should point here rather than restate it.

**The player is the Crown.** Commonhurst's inhabitants are literally "free people": the Crown is
constitutionally incapable of commanding any of them directly. This isn't backstory (no
escape-from-tyranny narrative) — it's a structural rule that mirrors the simulation's actual
design: the player never hires, fires, relocates, or routes an individual. The Crown governs only
through uniform policy that applies to a good, a building type, or the settlement as a whole —
never to a named inhabitant.

**Litmus test:** a change is in-fiction if it's a rule applied uniformly (a new subsidy/tariff, a
price cap, a building permit, a zoning rule, ...). It's a violation if it targets one named
inhabitant specifically, no matter how it's implemented. Concrete hard-no's:
- Forcing a specific inhabitant's profession/job assignment directly.
- Forcibly relocating or demolishing an occupied hut.
- Directing a specific inhabitant's movement or actions (click-to-command).

**Tone: hopeful nation-building, under a deliberately narrow hand.** The Crown's reach is limited
by design — foresight, not micromanagement, is the player's real skill. A starvation death is
framed as a **systemic foresight failure** (policy arrived too late, or was misjudged), not random
bad luck or an individually "deserved" outcome — this keeps the Crown accountable and keeps the
tone from turning arbitrarily cruel.

**Glossary** (canonical terms — use consistently in docs and agent prompts):

| Term | Refers to |
|---|---|
| **the Crown** | The player. |
| **Crown treasury** | `GlobalInventory.gold` — the shared gold pool. |
| **Freepeople** | The inhabitants (`InhabitantData`) — autonomous by constitutional design, not by circumstance. |
| **Subsidy / Tariff** | `PolicyData.subsidy[good]` — a positive per-unit top-up (subsidy) or negative deduction (tariff) on a good, paid to/from the Crown treasury. Global, applies to every exchange. |
| **Basic income** | `PolicyData.basic_income` — a flat daily Crown payment to every Freeperson (settlement's safety net against a death spiral); a negative value instead levies a flat daily head tax on every Freeperson into the Crown treasury, uniform and not scaled to individual income. |
| **Local tax** | `TradeData.daily_tax` — a flat daily head tax, but only ever read from the **Treasury** (`BuildingManager.get_daily_tax`); the field also exists on Storage Yard/Granary but isn't read there, so it has no effect. Mechanically identical to a negative Basic income (same per-inhabitant, capped-by-own-gold deduction into the Crown treasury) — the difference is reach, not shape: this lever needs a player-built Treasury, negative Basic income doesn't. Still legitimate: uniform per building/settlement, not targeted at an individual. |
| **Commonhurst** | The settlement itself. No further lore (region, calendar, neighbors) is established — keep it that way unless a specific feature needs it. |

## Architecture (autoloads, in `scripts/autoload/`, registered in `project.godot [autoload]`)

| Autoload | Responsibility |
|---|---|
| `WorldGrid` | 64×64 tile map, terrain, roads + emergent desire paths, A* pathing, crops, resource regen |
| `GameState` | Inhabitant roster, population count, spawning, `game_over` signal |
| `SimulationManager` | Master tick loop + inhabitant FSM; time/speed, hunger, farming, gathering — the big one |
| `BuildingManager` | Building instances, profession↔building mapping, trade-building set, maintenance |
| `EconomyManager` | Profession assignment by scarcity × price (`pick_best_profession`), stock targets |
| `MarketManager` | Decentralized exchanges (+ `scripts/data/market_exchange.gd`), matching, pricing, exports |
| `SaveLoadManager` | Serialize/restore world, buildings, inhabitants, market, gold |
| `RunRecorder` | Per-run KPI CSV + events JSONL under `user://runs` |
| `GlobalInventory` | Aggregate community stock + UI change notifications |
| `TurboRunner` | Dev-only headless fast-forward test harness (`--turbo=<days>`); inert in normal play |

Data model (`scripts/data/`): `goods.gd` (`GoodType`: WOOD, PLANKS, STONE, FOOD, GRAIN, FLOUR),
`building_def.gd` (`BuildingType`) with `.tres` in `resources/data/building_defs/`,
`inhabitant_data.gd` (profession, state machine, inventory cap 10 + food reserve 2, gold, hunger),
`tile_data.gd` (terrain/path/crop enums). UI in `scenes/ui/`, agent visuals in `scenes/agents/`.

**Evolutionary traits (M28):** every inhabitant spawns with six random `[0,1]` traits, each with
exactly one benefit and one drawback — Speed (+move speed / +food need), Strength (+carry capacity
/ -move speed), Frugality (-food need / -gather yield), Diligence (+work speed / +hunger-on-miss),
Resilience (+starvation tolerance / -work speed), Greed (+sell margin / +food-purchase premium,
reuses the existing `margin` field). Fields/formulas in `inhabitant_data.gd`; full table and
future-reproduction notes → **[`docs/GAME_DESIGN.md` §12](docs/GAME_DESIGN.md#12-evolutionary-traits-m28)**.

## Conventions

- **GDScript**, typed variables. Inline comments and in-game display strings are both **English**
  (comments were translated from German in M30 — see the milestone log).
- **Save compatibility:** enums (`GoodType`, `BuildingType`, `State`, `CropStage`, …) are serialized as
  ints. **Only append** new enum values — never reorder or insert (see the note in `goods.gd`).
- Features are tagged with milestone markers `Mxx` (M7–M32) in comments; grep them to trace when/why
  a system was added. A milestone log is in `docs/GAME_DESIGN.md`.
- Tuning constants live at the top of their manager (`SimulationManager` holds most balance values:
  `DAY_LENGTH_SECONDS`, crop timers, hunger/starvation, market margins, repair, throttles).
