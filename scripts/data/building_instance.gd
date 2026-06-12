class_name BuildingInstance
extends RefCounted

const CROWN_SHARE := 0.10

var id: int = -1
var def: BuildingDef
var cell: Vector2i
var node_ref: Node2D = null

var community_stock: Dictionary = {}
var crown_stock: Dictionary = {}

var occupants: Array[int] = []
var construction_timer: float = 0.0
var is_constructed: bool = true
## Countdown bis zur nächsten Produktion (M7: wird von SimulationManager getaktet)
var production_timer: float = 0.0
## Erzeugte Güter die auf Abholung durch einen Bewohner warten (M7)
var output_stock: Dictionary = {}
## Markt-Preisbildungs-Daten (M8: nur bei BuildingType.MARKET befüllt)
var market_data: MarketData = null


func deliver(good: int, amount: float) -> void:
	var crown_cut := amount * CROWN_SHARE
	var community_cut := amount - crown_cut
	community_stock[good] = community_stock.get(good, 0.0) + community_cut
	crown_stock[good] = crown_stock.get(good, 0.0) + crown_cut


func withdraw_community(good: int, amount: float) -> float:
	var avail: float = community_stock.get(good, 0.0)
	var taken := minf(avail, amount)
	community_stock[good] = avail - taken
	return taken


func sell_crown_stock(good: int, amount: float) -> float:
	var avail: float = crown_stock.get(good, 0.0)
	var sold := minf(avail, amount)
	crown_stock[good] = avail - sold
	return sold
