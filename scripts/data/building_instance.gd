class_name BuildingInstance
extends RefCounted

## Fallback capacity for a good NOT listed in def.storage_capacity (e.g. the local
## input buffer of a production hut with storage_capacity = {}). Real storage buildings
## (storage yard/granary/town hall) define their capacity PER GOOD in their .tres file
## (storage_capacity) – that was dead data for a long time, now wired in here.
const STOCK_CAPACITY := 100.0

var id: int = -1
var def: BuildingDef
var cell: Vector2i
var node_ref: Node2D = null

var community_stock: Dictionary = {}

var occupants: Array[int] = []
var construction_timer: float = 0.0
var is_constructed: bool = true
## M21: game day of the last repair. Every REPAIR_INTERVAL_DAYS days the hut becomes
## due; if not repaired in time it falls derelict (see SimulationManager).
var last_repaired_day: int = 0
## M21: true while the hut is in the grace period waiting for a repair (tinting).
var needs_repair: bool = false
## M22: true when the hut has fallen derelict for lack of repair. It remains standing as a
## ruin (is_constructed == false, footprint occupied) and can be restored by an inhabitant
## in exchange for building material, instead of being demolished.
var is_derelict: bool = false
## Building materials still outstanding that an inhabitant must fetch from storage one at a time
var pending_build_cost: Dictionary = {}
## Countdown to the next production cycle (M7: ticked by SimulationManager)
var production_timer: float = 0.0
## Produced goods waiting for pickup by an inhabitant (M7)
var output_stock: Dictionary = {}
## Market pricing data (M8: only populated for BuildingType.MARKET)
var market_data: MarketData = null
## Buy/sell prices and tax rate (M14/M17: populated for storage yard/granary/treasury)
var trade_data: TradeData = null
## M20: order-book exchange of this storage/granary (populated for STORAGE_YARD/GRANARY).
var exchange: MarketExchange = null
## M20: global economic policy – only populated on the Town Hall instance (TOWN_HALL).
var policy: PolicyData = null


## Sum of all goods in community_stock.
func stock_count() -> float:
	var total := 0.0
	for amt in community_stock.values():
		total += amt
	return total


## Remaining free storage space FOR A SPECIFIC GOOD (never negative). Capacity comes from
## def.storage_capacity (per good, see .tres); goods not listed there fall back to the
## shared baseline STOCK_CAPACITY (e.g. the local input buffer of a hut).
func stock_space(good: int) -> float:
	var cap: float = def.storage_capacity.get(good, STOCK_CAPACITY) if def != null else STOCK_CAPACITY
	return maxf(0.0, cap - community_stock.get(good, 0.0))


## Stores as much as possible (limited by stock_space(good)) and returns the amount actually
## stored. M20: no more transaction tax – the delivery goes into the community
## stock (= the exchange's available supply).
func deliver(good: int, amount: float) -> float:
	var can := minf(amount, stock_space(good))
	if can > 0.0:
		community_stock[good] = community_stock.get(good, 0.0) + can
	return can


func withdraw_community(good: int, amount: float) -> float:
	var avail: float = community_stock.get(good, 0.0)
	var taken := minf(avail, amount)
	community_stock[good] = avail - taken
	return taken
