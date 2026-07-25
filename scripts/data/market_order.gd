class_name MarketOrder
extends RefCounted

## A resting order in an exchange's (MarketExchange) order book.
## Seller orders (SELL) drift toward the floor over time, buyer orders (BUY)
## toward the ceiling. Crown backstop orders (is_crown_backstop) sit fixed at the
## respective band edge and guarantee that every order clips there at the latest.

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


static func make(p_side: int, p_good: int, p_owner_kind: int, p_owner_id: int, p_quantity: float, p_price: float) -> MarketOrder:
	var o := MarketOrder.new()
	o.side = p_side
	o.good = p_good
	o.owner_kind = p_owner_kind
	o.owner_id = p_owner_id
	o.quantity = p_quantity
	o.price = p_price
	return o
