class_name TradeData
extends RefCounted

## M14/M17: Spielerseitig editierbare An-/Verkaufspreise und Steuersatz
## fuer Lagerplatz/Kornspeicher/Schatzkammer. Startwerte aus Goods.BASE_PRICES.

var buy_price: Dictionary = {}
var sell_price: Dictionary = {}
var daily_tax: float = 0.0


func _init() -> void:
	for good in Goods.GoodType.values():
		buy_price[good] = Goods.BASE_PRICES[good]
		sell_price[good] = Goods.BASE_PRICES[good]
