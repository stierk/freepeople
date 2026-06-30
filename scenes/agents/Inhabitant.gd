extends Node2D

const FRAME_SIZE := 32  # MinifVillagers frames are 32x32
const IDLE_ROW := 0     # Bildzeile 0 ist auf allen Bögen die Idle-Animation
const MOVE_EPSILON := 0.15  # px/frame threshold to count as "moving"

## MinifVillagers-Charakterbogen + Animationszeilen pro Beruf. Die Bögen haben kein
## einheitliches Layout, daher wird pro Beruf angegeben, in welcher Bildzeile die
## Lauf- ("walk") bzw. Arbeitsanimation ("work") liegt. Idle ist immer Zeile 0.
## work = -1 → keine Arbeitsanimation (einfache Dorfbewohner). Die Anzahl der Frames
## je Zeile wird automatisch aus dem Bogen erkannt (_count_row_frames).
const PROFESSION_ANIM := {
	InhabitantData.Profession.NONE: {
		"sheet": preload("res://assets/minif_villagers/MiniVillagerMan.png"), "walk": 1, "work": -1,
	},
	InhabitantData.Profession.WOODCUTTER: {
		"sheet": preload("res://assets/minif_villagers/MiniLumberjack.png"), "walk": 1, "work": 5,
	},
	InhabitantData.Profession.SAWMILL_WORKER: {
		"sheet": preload("res://assets/minif_villagers/MiniBlacksmith.png"), "walk": 3, "work": 1,
	},
	InhabitantData.Profession.QUARRY_WORKER: {
		# walk = Zeile 3 (Pickel auf der Schulter, sauberer Lauf); Zeile 1 war ein
		# Vorwärts-Hieb und sah beim Laufen wie Hacken aus. work = Zeile 5 (Abbau-Schlag).
		"sheet": preload("res://assets/minif_villagers/MiniMiner.png"), "walk": 3, "work": 5,
	},
	InhabitantData.Profession.FARMER: {
		"sheet": preload("res://assets/minif_villagers/MiniGatherer.png"), "walk": 1, "work": 2,
	},
	# Müller/Bäcker arbeiten passiv im Gebäude (Mahlen/Backen) und liefern aus –
	# schlichte Dorfbewohner-Bögen, keine eigene Arbeitsanimation nötig.
	InhabitantData.Profession.MILLER: {
		"sheet": preload("res://assets/minif_villagers/MiniWorker.png"), "walk": 1, "work": -1,
	},
	InhabitantData.Profession.BAKER: {
		"sheet": preload("res://assets/minif_villagers/MiniPeasant.png"), "walk": 1, "work": -1,
	},
}

## Frisch erschienene / arbeitslose Bewohner (Profession.NONE) bekommen einen von
## mehreren schlichten Dorfbewohnern (anhand ihrer ID), damit die Menge abwechslungs-
## reich aussieht. Sobald sie einen Beruf annehmen, wechseln sie auf den Berufsbogen.
const NONE_VARIANTS := [
	{"sheet": preload("res://assets/minif_villagers/MiniVillagerMan.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniVillagerWoman.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniPeasant.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniOldMan.png"), "walk": 1, "work": -1},
]

## Berufe und der Zustand, in dem ihre Arbeitsanimation gespielt wird (wenn der
## Bewohner gerade nicht läuft): Holzfäller/Steinmetz beim Abbau an der Ressource,
## Bauer auf dem Feld, Sägewerker (Schmied) an der Hütte.
const WORK_STATE := {
	InhabitantData.Profession.WOODCUTTER: InhabitantData.State.GATHERING,
	InhabitantData.Profession.QUARRY_WORKER: InhabitantData.State.GATHERING,
	InhabitantData.Profession.FARMER: InhabitantData.State.FARM_TENDING,
	InhabitantData.Profession.SAWMILL_WORKER: InhabitantData.State.WORKING,
}

const COLOR_HUNGRY := Color(0.82, 0.51, 0.27, 1.0)
const COLOR_STARVED := Color(0.35, 0.2, 0.12, 1.0)
const COLOR_GRAVE := Color(0.45, 0.45, 0.45, 0.85)
const COLOR_LERP_SPEED := 2.0

## Gemeinsamer SpriteFrames-Cache je Charakterbogen – jeder Bogen wird nur einmal
## analysiert und das Ergebnis von allen Bewohnern geteilt, die ihn verwenden.
static var _frames_cache: Dictionary = {}

var data: InhabitantData
var is_grave: bool = false
var _last_profession: int = -1
var _last_pos: Vector2 = Vector2.ZERO
var _current_anim: StringName = &"idle"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gold_label: Label = $GoldLabel


func setup(inhabitant_data: InhabitantData) -> void:
	data = inhabitant_data
	position = data.world_pos
	_last_pos = position
	_update_sprite()


func _update_sprite() -> void:
	_last_profession = data.profession if data else InhabitantData.Profession.NONE
	sprite.sprite_frames = _get_frames(_resolve_cfg())
	if not sprite.sprite_frames.has_animation(_current_anim):
		_current_anim = &"idle"
	sprite.play(_current_anim)


## Wählt Charakterbogen + Animationszeilen für diesen Bewohner. Arbeitslose (NONE)
## erhalten anhand ihrer ID eine von mehreren schlichten Dorfbewohner-Varianten.
func _resolve_cfg() -> Dictionary:
	var prof := data.profession if data else InhabitantData.Profession.NONE
	if prof == InhabitantData.Profession.NONE:
		return NONE_VARIANTS[data.id % NONE_VARIANTS.size()] if data else NONE_VARIANTS[0]
	return PROFESSION_ANIM.get(prof, NONE_VARIANTS[0])


## Liefert das (gecachte) SpriteFrames für eine Bogen-Konfiguration (Cache je Bogen).
static func _get_frames(cfg: Dictionary) -> SpriteFrames:
	var sheet: Texture2D = cfg["sheet"]
	if _frames_cache.has(sheet):
		return _frames_cache[sheet]
	var frames := _build_frames(cfg)
	_frames_cache[sheet] = frames
	return frames


## Baut ein SpriteFrames mit "idle"-, "walk"- und (falls vorhanden) "work"-Animation
## aus dem 32x32-Raster des Charakterbogens. Die Framezahl je Zeile wird automatisch
## erkannt, da die Bögen unterschiedlich viele Frames pro Animation haben.
static func _build_frames(cfg: Dictionary) -> SpriteFrames:
	var sheet: Texture2D = cfg["sheet"]
	var img := sheet.get_image()
	var max_cols := int(sheet.get_width() / FRAME_SIZE)

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_anim(frames, &"idle", sheet, img, IDLE_ROW, max_cols, 5.0)
	_add_anim(frames, &"walk", sheet, img, int(cfg["walk"]), max_cols, 10.0)
	if int(cfg["work"]) >= 0:
		_add_anim(frames, &"work", sheet, img, int(cfg["work"]), max_cols, 8.0)
	# Letzte Bildzeile ist die Sterbe-/Zusammenbruch-Animation (für Gräber, nicht loopend).
	var last_row := int(sheet.get_height() / FRAME_SIZE) - 1
	if last_row > IDLE_ROW:
		_add_anim(frames, &"death", sheet, img, last_row, max_cols, 8.0, false)
	return frames


static func _add_anim(frames: SpriteFrames, name: StringName, sheet: Texture2D, img: Image,
		row: int, max_cols: int, speed: float, loop: bool = true) -> void:
	frames.add_animation(name)
	frames.set_animation_loop(name, loop)
	frames.set_animation_speed(name, speed)
	var count := maxi(1, _count_row_frames(img, row, max_cols))
	for i in range(count):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame(name, atlas)


## Zählt die zusammenhängenden, nicht-leeren 32x32-Frames einer Zeile (von links).
## Die Animationen sind linksbündig gepackt, daher endet die Zeile beim ersten
## komplett transparenten Frame.
static func _count_row_frames(img: Image, row: int, max_cols: int) -> int:
	if img == null or (row + 1) * FRAME_SIZE > img.get_height():
		return 0
	var count := 0
	for c in range(max_cols):
		var filled := false
		var x0 := c * FRAME_SIZE
		var y0 := row * FRAME_SIZE
		for y in range(y0, y0 + FRAME_SIZE, 2):
			for x in range(x0, x0 + FRAME_SIZE, 2):
				if img.get_pixel(x, y).a > 0.0:
					filled = true
					break
			if filled:
				break
		if not filled:
			break
		count += 1
	return count


func _process(delta: float) -> void:
	if is_grave or data == null:
		return

	gold_label.text = str(int(data.gold))

	if data.profession != _last_profession:
		_update_sprite()

	# Bewegung erkennen: läuft der Bewohner gerade, "walk"-Animation, sonst Arbeits-
	# oder Idle-Animation je nach Zustand.
	var moved := position.distance_to(_last_pos) > MOVE_EPSILON
	if moved and absf(position.x - _last_pos.x) > 0.05:
		sprite.flip_h = position.x < _last_pos.x
	_last_pos = position

	var desired_anim: StringName = &"idle"
	if moved:
		desired_anim = &"walk"
	elif _is_working() and sprite.sprite_frames.has_animation(&"work"):
		desired_anim = &"work"

	if desired_anim != _current_anim:
		_current_anim = desired_anim
		sprite.play(_current_anim)

	var target := Color.WHITE
	if data.missed_meals >= 3:
		target = COLOR_STARVED
	elif data.missed_meals >= 1:
		target = COLOR_HUNGRY
	modulate = modulate.lerp(target, minf(1.0, delta * COLOR_LERP_SPEED))


## Verrichtet der Bewohner gerade (stehend) seine berufstypische Arbeit?
func _is_working() -> bool:
	return WORK_STATE.has(data.profession) and data.state == WORK_STATE[data.profession]


## M18: Bewohner ist verstorben - Node bleibt als Grab stehen, keine weiteren Updates.
## Die Sterbe-Animation läuft einmalig durch und hält dann den liegenden Frame.
func mark_as_grave() -> void:
	is_grave = true
	modulate = COLOR_GRAVE
	if sprite.sprite_frames.has_animation(&"death"):
		sprite.play(&"death")
	else:
		sprite.stop()
		if sprite.sprite_frames.has_animation(&"idle"):
			sprite.play(&"idle")
	data = null
