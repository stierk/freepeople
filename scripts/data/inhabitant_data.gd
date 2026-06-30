class_name InhabitantData
extends RefCounted

enum Profession { NONE, WOODCUTTER, SAWMILL_WORKER, QUARRY_WORKER, FARMER, MILLER, BAKER }
enum State {
	SEEKING_SITE,        # sucht Standort/Hütte (nur Profession == NONE, frisch erschienen)
	MOVING_TO_BUILD,     # läuft zum Standort (neue Hütte ODER bestehende Hütte mit freiem Platz)
	FETCHING_MATERIALS,  # holt Baumaterialien einzeln vom Lager und bringt sie zur Baustelle
	BUILDING,            # Bau-Timer läuft (nur bei neuer Hütte)
	WORKING,             # produziert am Arbeitsplatz (Hütte)
	DELIVERING,          # läuft zum Lagergebäude mit Output im Inventar
	RETURNING,           # läuft zurück zur Hütte nach Lieferung
	MARKET_TRIP,         # läuft zum Markt um zu kaufen/verkaufen (Nahrung etc.)
	FARM_TENDING,        # M19: Bauer läuft auf ein Feld, um Weizen zu pflanzen/ernten
	GATHERING,           # Holzfäller/Steinmetz läuft zur Ressource und erntet sie vor Ort
	HAULING_HOME,        # trägt die geerntete Ressource zurück zur eigenen Hütte
}

## M19: Was ein Bauer auf seinem Zielfeld tut, wenn er es erreicht.
enum FarmAction { NONE, PLANT, HARVEST }

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
## M18: Anzahl in Folge verpasster Mahlzeiten (Hunger-Einfärbung, Tod bei STARVATION_DEATH_MEALS)
var missed_meals: int = 0
var node_ref: Node2D = null

var target_site_cell: Vector2i = Vector2i(-1, -1)
var fetch_target_good: int = -1

## M19: Zielfeld und geplante Tätigkeit eines Bauern (Pflanzen/Ernten).
var farm_target_cell: Vector2i = Vector2i(-1, -1)
var farm_action: FarmAction = FarmAction.NONE

## Zielzelle der Ressource (Baum/Stein), die ein Holzfäller/Steinmetz abbaut.
var gather_target_cell: Vector2i = Vector2i(-1, -1)
## Verbleibende Arbeitszeit (Sim-Sekunden), bis die Ressource abgebaut ist.
var work_timer: float = 0.0
