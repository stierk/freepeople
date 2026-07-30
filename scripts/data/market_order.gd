class_name MarketOrder
extends RefCounted

## A resting order in an exchange's (MarketExchange) order book.
## Seller orders (SELL) drift toward the floor over time, buyer orders (BUY)
## toward the ceiling. Crown backstop orders (is_crown_backstop) sit fixed at the
## respective band edge and guarantee that every order clips there at the latest.
##
## M36: completed and put to use. The class was written when the order book was first
## planned, then left unreferenced while the consignment model was built in MarketExchange
## instead. Three fields were missing to actually run it: where an order started
## (`reservation`), how far it may give way (`limit`), and how long it has been waiting
## (`age`).
##
## The direction of "giving way" is the one thing an order knows about itself that the
## exchange would otherwise have to re-derive per side on every tick, so `drift()` lives
## here rather than in the matching loop.

## ⚠ Serialized as ints in the save game (SaveLoadManager) – only ever APPEND new values,
## never reorder or insert (same rule as Goods.GoodType, see the note in goods.gd).
enum Side { SELL, BUY }
## Who placed the order – determines how a fill is booked.
enum OwnerKind { VILLAGER, BUILDING, CROWN }

var side: int = Side.SELL
var good: int = -1
var owner_kind: int = OwnerKind.VILLAGER
## Inhabitant ID (VILLAGER) or building ID (BUILDING); -1 for CROWN.
var owner_id: int = -1
var quantity: float = 0.0
var price: float = 0.0
var is_crown_backstop: bool = false

## The price this order was placed at. Kept separately from `price`, which drift moves:
## without it there is no way to tell after the first tick how far an order has already
## given way, or to redraw the concession from its origin.
var reservation: float = 0.0
## How far `price` may drift: the floor for a SELL, the ceiling for a BUY. Set to the crown's
## band edge (SELL → crown_bid, BUY → crown_ask), so an order that nobody takes ends up
## meeting the crown rather than drifting indefinitely.
var limit: float = 0.0
## Sim seconds this order has rested in the book. Drives the drift and makes "how long has
## this been unsold" readable for telemetry.
var age: float = 0.0


static func make(p_side: int, p_good: int, p_owner_kind: int, p_owner_id: int,
		p_quantity: float, p_price: float, p_limit: float) -> MarketOrder:
	var o := MarketOrder.new()
	o.side = p_side
	o.good = p_good
	o.owner_kind = p_owner_kind
	o.owner_id = p_owner_id
	o.quantity = p_quantity
	o.price = p_price
	o.reservation = p_price
	o.limit = p_limit
	return o


## Crown backstop order at a band edge: unlimited patience, no drift, no negotiation. `limit`
## equals the price, so drift() is a no-op even if it is called.
static func make_crown(p_side: int, p_good: int, p_quantity: float, p_price: float) -> MarketOrder:
	var o := make(p_side, p_good, OwnerKind.CROWN, -1, p_quantity, p_price, p_price)
	o.is_crown_backstop = true
	return o


## Lets the order give way by `step` toward its limit and ages it by `seconds`. A SELL comes
## down, a BUY goes up; neither ever overshoots `limit`. Crown orders hold their price.
func drift(step: float, seconds: float) -> void:
	age += seconds
	if is_crown_backstop or step <= 0.0:
		return
	if side == Side.SELL:
		price = maxf(limit, price - step)
	else:
		price = minf(limit, price + step)


## True once the order has given way as far as it is allowed to. At that point a SELL sits on
## the crown's bid and a BUY on the crown's ask, so the crown order is guaranteed to take it.
func at_limit() -> bool:
	return absf(price - limit) <= 0.0001
