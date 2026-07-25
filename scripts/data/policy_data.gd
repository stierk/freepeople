class_name PolicyData
extends RefCounted

## Global economic policy that the player sets at the Town Hall.
## Applies equally to all exchanges (storage/granary).
##
## - subsidy[good]: surcharge on every producer sale of this good. Positive = subsidy
##   (the crown pays extra per unit), negative = tariff (the crown collects per unit). M26: really
##   settled in gold from the global crown pool GlobalInventory.gold (see
##   MarketExchange._apply_subsidy); also steers profession choice (EconomyManager._price_weight).
## - basic_income: flat daily payment from the crown pool GlobalInventory.gold to every
##   inhabitant (safety net against the death spiral). Negative = flat daily head tax instead
##   (collected from every inhabitant into the crown pool), not scaled to individual income.

var subsidy: Dictionary = {}
var basic_income: float = 0.0


func _init() -> void:
	for good in Goods.GoodType.values():
		subsidy[good] = 0.0
