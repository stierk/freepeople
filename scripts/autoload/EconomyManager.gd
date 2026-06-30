extends Node

const TARGET_FOOD := 20.0
const TARGET_GRAIN := 15.0
const TARGET_FLOUR := 15.0
const TARGET_WOOD := 10.0
const TARGET_PLANKS := 10.0
const TARGET_STONE := 10.0

const RANDOM_TIEBREAK := 0.15


func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()

	var wood: float = storage.community_stock.get(Goods.GoodType.WOOD, 0.0)
	var planks: float = storage.community_stock.get(Goods.GoodType.PLANKS, 0.0)
	var stone: float = storage.community_stock.get(Goods.GoodType.STONE, 0.0)
	var food: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
	var grain: float = granary.community_stock.get(Goods.GoodType.GRAIN, 0.0)
	var flour: float = granary.community_stock.get(Goods.GoodType.FLOUR, 0.0)

	# Nahrungskette: Bauer erntet Getreide → Müller mahlt Mehl → Bäcker backt Nahrung.
	# Müller/Bäcker werden erst angeworben, wenn ihr Eingangsgut tatsächlich anfällt,
	# damit keine leerlaufenden Mühlen/Bäckereien entstehen.
	var candidates := {
		InhabitantData.Profession.FARMER: _urgency(grain, TARGET_GRAIN) * _price_weight(Goods.GoodType.GRAIN),
		InhabitantData.Profession.WOODCUTTER: _urgency(wood, TARGET_WOOD) * _price_weight(Goods.GoodType.WOOD),
		InhabitantData.Profession.QUARRY_WORKER: _urgency(stone, TARGET_STONE) * _price_weight(Goods.GoodType.STONE),
	}
	if grain > 0.0:
		candidates[InhabitantData.Profession.MILLER] = _urgency(flour, TARGET_FLOUR) * _price_weight(Goods.GoodType.FLOUR)
	if flour > 0.0:
		candidates[InhabitantData.Profession.BAKER] = _urgency(food, TARGET_FOOD) * _price_weight(Goods.GoodType.FOOD)
	# Ohne echten Lagerplatz würden Sägewerke per Rathaus-Fallback rund ums
	# Rathaus gebaut – das ist nicht gewollt. Erst zuweisen, wenn ein Lagerplatz steht.
	if BuildingManager.has_storage_yard():
		candidates[InhabitantData.Profession.SAWMILL_WORKER] = _urgency(planks, TARGET_PLANKS) * _price_weight(Goods.GoodType.PLANKS)

	var best := InhabitantData.Profession.WOODCUTTER
	var best_score := -1.0
	for profession: InhabitantData.Profession in candidates:
		var score: float = candidates[profession] + randf() * RANDOM_TIEBREAK
		if score > best_score:
			best_score = score
			best = profession
	return best


func _urgency(current: float, target: float) -> float:
	return maxf(0.0, target - current) / target


func _price_weight(good: int) -> float:
	var base: float = Goods.BASE_PRICES.get(good, 1.0)
	if base <= 0.0:
		return 1.0
	return BuildingManager.get_sell_price(good) / base
