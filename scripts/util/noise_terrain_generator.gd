class_name NoiseTerrainGenerator
extends RefCounted

const FOREST_THRESHOLD := 0.35
const STONE_THRESHOLD := 0.45
const COAST_EDGE_HARD := 2
const COAST_EDGE_SOFT := 5
const COAST_NOISE_THRESHOLD := 0.2

static func generate(map_size: Vector2i, world_seed: int) -> Array:
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = world_seed
	forest_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	forest_noise.frequency = 0.05
	forest_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	forest_noise.fractal_octaves = 3

	var stone_noise := FastNoiseLite.new()
	stone_noise.seed = world_seed + 1000
	stone_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	stone_noise.frequency = 0.07
	stone_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	stone_noise.fractal_octaves = 3

	var coast_noise := FastNoiseLite.new()
	coast_noise.seed = world_seed + 2000
	coast_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	coast_noise.frequency = 0.08

	var tiles: Array = []
	tiles.resize(map_size.x * map_size.y)

	for y in range(map_size.y):
		for x in range(map_size.x):
			var tile := TileRuntimeData.new()
			var edge_dist: int = mini(x, mini(y, mini(map_size.x - 1 - x, map_size.y - 1 - y)))
			var coast_value := coast_noise.get_noise_2d(x, y)

			if edge_dist < COAST_EDGE_HARD or (edge_dist < COAST_EDGE_SOFT and coast_value > COAST_NOISE_THRESHOLD):
				tile.terrain = TileRuntimeData.TerrainType.WATER
				tile.resource_amount = 0.0
			else:
				var forest_value := forest_noise.get_noise_2d(x, y)
				var stone_value := stone_noise.get_noise_2d(x, y)
				if forest_value > FOREST_THRESHOLD:
					tile.terrain = TileRuntimeData.TerrainType.FOREST
					tile.resource_amount = 1.0
				elif stone_value > STONE_THRESHOLD:
					tile.terrain = TileRuntimeData.TerrainType.STONE
					tile.resource_amount = 1.0
				else:
					tile.terrain = TileRuntimeData.TerrainType.GRASS
					tile.resource_amount = 0.0

			tiles[y * map_size.x + x] = tile

	return tiles
