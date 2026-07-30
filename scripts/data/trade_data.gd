class_name TradeData
extends RefCounted

## M14/M17: player-editable buy/sell prices and tax rate
## for storage yard/granary/treasury. Starting values from Goods.BASE_PRICES, spread apart
## by the two factors below.

## M36: the crown's default spread — it buys below and sells above the base price.
##
## Deliberately NOT 1.0 / 1.0 (the value up to M35). At a zero spread the crown buys and sells
## a good at the SAME price, and two things follow that between them made villager-to-villager
## trade impossible:
##  - The negotiating band collapses to a point. Every villager order clips straight onto the
##    crown's price, so break-even and margin stop mattering and no price can form.
##  - A market maker with a zero spread but running costs (subsidies, basic income) is
##    structurally insolvent. The M35 baseline confirms it: all five seeds end 300 days with
##    crown_gold == 0, at which point the support price silently stops working entirely.
##
## The spread is what gives producers and consumers room to meet in between, and what keeps the
## treasury solvent enough to still act as a backstop late in a run.
const DEFAULT_BID_FACTOR := 1.0
const DEFAULT_ASK_FACTOR := 1.0

var buy_price: Dictionary = {}
var sell_price: Dictionary = {}
var daily_tax: float = 0.0


func _init() -> void:
	for good in Goods.GoodType.values():
		buy_price[good] = Goods.BASE_PRICES[good] * DEFAULT_BID_FACTOR
		sell_price[good] = Goods.BASE_PRICES[good] * DEFAULT_ASK_FACTOR
