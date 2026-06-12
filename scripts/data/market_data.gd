class_name MarketData
extends RefCounted

const DEMAND_DECAY := 0.9
const PRICE_UPDATE_INTERVAL := 20.0

var prices: Dictionary = {}
var demand_counter: Dictionary = {}
var supply_counter: Dictionary = {}


func _init() -> void:
	for g in Goods.GoodType.values():
		prices[g] = Goods.BASE_PRICES[g]
		demand_counter[g] = 0.0
		supply_counter[g] = 1.0


func record_sale(good: int, amount: float) -> void:
	supply_counter[good] += amount


func record_purchase(good: int, amount: float) -> void:
	demand_counter[good] += amount


func update_prices() -> void:
	for g in prices.keys():
		var d: float = demand_counter[g]
		var s: float = maxf(supply_counter[g], 0.01)
		var ratio := clampf(d / s, 0.5, 2.0)
		prices[g] = Goods.BASE_PRICES[g] * ratio
		demand_counter[g] *= DEMAND_DECAY
		supply_counter[g] *= DEMAND_DECAY
