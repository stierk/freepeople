class_name InhabitantData
extends RefCounted

enum Profession { NONE, WOODCUTTER, SAWMILL_WORKER, QUARRY_WORKER, FARMER }
enum State {
	SEEKING_SITE,      # sucht Standort/Hütte (nur Profession == NONE, frisch erschienen)
	MOVING_TO_BUILD,   # läuft zum Standort (neue Hütte ODER bestehende Hütte mit freiem Platz)
	BUILDING,          # Bau-Timer läuft (nur bei neuer Hütte)
	WORKING,           # produziert am Arbeitsplatz (Hütte)
	DELIVERING,        # läuft zum Lagergebäude mit Output im Inventar
	RETURNING,         # läuft zurück zur Hütte nach Lieferung
	MARKET_TRIP,       # läuft zum Markt um zu kaufen/verkaufen (Nahrung etc.)
}

var id: int = -1
var profession: Profession = Profession.NONE
var state: State = State.SEEKING_SITE
var home_building_id: int = -1

var cell: Vector2i = Vector2i.ZERO
var world_pos: Vector2 = Vector2.ZERO
var path: PackedVector2Array = []
var path_index: int = 0
var move_speed_base: float = 24.0

var inventory: Dictionary = {}
var gold: float = 0.0
var production_timer: float = 0.0

var hunger: float = 0.0
var node_ref: Node2D = null

var target_site_cell: Vector2i = Vector2i(-1, -1)
