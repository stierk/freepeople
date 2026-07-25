extends Node2D

const FRAME_SIZE := 32  # MinifVillagers frames are 32x32
const IDLE_ROW := 0     # row 0 is the idle animation on every sheet
const MOVE_EPSILON := 0.15  # px/frame threshold to count as "moving"

## MinifVillagers character sheet + animation rows per profession. The sheets have no
## uniform layout, so for each profession we record which row holds the walk
## ("walk") resp. work animation ("work"). Idle is always row 0.
## work = -1 → no work animation (plain villager). The frame count per
## row is auto-detected from the sheet (_count_row_frames).
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
		# walk = row 3 (pickaxe on the shoulder, clean walk); row 1 was a
		# forward swing and looked like chopping while walking. work = row 5 (mining swing).
		"sheet": preload("res://assets/minif_villagers/MiniMiner.png"), "walk": 3, "work": 5,
	},
	InhabitantData.Profession.FARMER: {
		"sheet": preload("res://assets/minif_villagers/MiniGatherer.png"), "walk": 1, "work": 2,
	},
	# Miller/baker work passively inside the building (milling/baking) and deliver –
	# plain villager sheets, no dedicated work animation needed.
	InhabitantData.Profession.MILLER: {
		"sheet": preload("res://assets/minif_villagers/MiniWorker.png"), "walk": 1, "work": -1,
	},
	InhabitantData.Profession.BAKER: {
		"sheet": preload("res://assets/minif_villagers/MiniPeasant.png"), "walk": 1, "work": -1,
	},
	# M29: hunter uses the (already existing) MiniHunter sheet. work = row 3: the bow-draw
	# + release ("going on a hunt"), the most fitting hunting action on the sheet
	# (row 5 was a crouching dagger slash and read wrong).
	InhabitantData.Profession.HUNTER: {
		"sheet": preload("res://assets/minif_villagers/MiniHunter.png"), "walk": 1, "work": 3,
	},
}

## Freshly spawned / unemployed inhabitants (Profession.NONE) get one of several
## plain villagers (based on their ID) so the crowd looks varied. As soon as they
## take up a profession, they switch to the profession sheet.
const NONE_VARIANTS := [
	{"sheet": preload("res://assets/minif_villagers/MiniVillagerMan.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniVillagerWoman.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniPeasant.png"), "walk": 1, "work": -1},
	{"sheet": preload("res://assets/minif_villagers/MiniOldMan.png"), "walk": 1, "work": -1},
]

## Professions and the state in which their work animation plays (when the
## inhabitant is not currently walking): woodcutter/quarry worker while mining the
## resource, farmer in the field, sawmill worker (blacksmith) at the hut.
const WORK_STATE := {
	InhabitantData.Profession.WOODCUTTER: InhabitantData.State.GATHERING,
	InhabitantData.Profession.QUARRY_WORKER: InhabitantData.State.GATHERING,
	InhabitantData.Profession.FARMER: InhabitantData.State.FARM_TENDING,
	InhabitantData.Profession.SAWMILL_WORKER: InhabitantData.State.WORKING,
	InhabitantData.Profession.HUNTER: InhabitantData.State.HUNTING,  # M29: hunting animation at the forest cell
}

const COLOR_HUNGRY := Color(0.82, 0.51, 0.27, 1.0)
const COLOR_STARVED := Color(0.35, 0.2, 0.12, 1.0)
const COLOR_GRAVE := Color(0.45, 0.45, 0.45, 0.85)
const COLOR_LERP_SPEED := 2.0

## Shared SpriteFrames cache per character sheet – each sheet is analyzed only once
## and the result is shared by all inhabitants who use it.
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


## Chooses the character sheet + animation rows for this inhabitant. Unemployed (NONE)
## inhabitants get one of several plain villager variants based on their ID.
func _resolve_cfg() -> Dictionary:
	var prof := data.profession if data else InhabitantData.Profession.NONE
	if prof == InhabitantData.Profession.NONE:
		return NONE_VARIANTS[data.id % NONE_VARIANTS.size()] if data else NONE_VARIANTS[0]
	return PROFESSION_ANIM.get(prof, NONE_VARIANTS[0])


## Returns the (cached) SpriteFrames for a sheet configuration (cache per sheet).
static func _get_frames(cfg: Dictionary) -> SpriteFrames:
	var sheet: Texture2D = cfg["sheet"]
	if _frames_cache.has(sheet):
		return _frames_cache[sheet]
	var frames := _build_frames(cfg)
	_frames_cache[sheet] = frames
	return frames


## Builds a SpriteFrames with "idle", "walk" and (if present) "work" animation
## from the character sheet's 32x32 grid. The frame count per row is auto-detected,
## since the sheets have varying numbers of frames per animation.
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
	# Last row is the death/collapse animation (for graves, non-looping).
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


## Counts the contiguous, non-empty 32x32 frames of a row (from the left).
## The animations are packed left-aligned, so the row ends at the first
## fully transparent frame.
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

	# Debug profiling: measure our own cost and attribute it to the perf report (only when active).
	var _pt: int = Time.get_ticks_usec() if SimulationManager.DEBUG_PERF else 0

	gold_label.text = str(int(data.gold))

	if data.profession != _last_profession:
		_update_sprite()

	# Detect movement: if the inhabitant is currently walking, "walk" animation, otherwise
	# work or idle animation depending on state.
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

	if SimulationManager.DEBUG_PERF:
		SimulationManager.report_inhabitant_process_usec(Time.get_ticks_usec() - _pt)


## Is the inhabitant currently (standing) performing their profession-typical work?
func _is_working() -> bool:
	return WORK_STATE.has(data.profession) and data.state == WORK_STATE[data.profession]


## M21: Shows a short-lived, rising +/- gold number above the inhabitant (green =
## income, red = expense). Makes it visible that the budget is really used on
## buy/sell/tax/repair. Tiny amounts are ignored to avoid spam.
func show_gold_delta(amount: float) -> void:
	if is_grave:
		return
	var n := int(roundf(amount))
	if n == 0:
		return
	var popup := Label.new()
	popup.text = "+%d" % n if n > 0 else str(n)
	popup.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if n > 0 else Color(0.95, 0.4, 0.35))
	popup.add_theme_font_size_override("font_size", 8)
	popup.z_index = 20
	popup.position = Vector2(-6.0, -22.0)
	add_child(popup)
	var tween := create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 12.0, 0.8)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	tween.tween_callback(popup.queue_free)


## M18: inhabitant has died - node remains standing as a grave, no further updates.
## The death animation plays once and then holds the final lying-down frame.
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
