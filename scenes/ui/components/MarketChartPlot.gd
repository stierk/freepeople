## M25: scatter plot of an exchange's trade chronicle for ONE good, drawn in the look of a
## medieval economic map: parchment background, wooden frame, exclusively brown and
## beige tones. The three series are distinguished by blocky 7x7 pixel sprites, drawn
## directly from rectangles here (no atlas, so the palette matches exactly):
##   Demand = money pouch, Offer = treasure chest, Deal = wax seal.
## The crown's support price runs alongside as a step line – it's not an event but a
## state that holds until the player moves the slider.
extends Control

# --- Palette: brown/beige only, no colorful accents. The three series are distinguished
# by brightness, so they stay distinguishable even at a 7 px marker size.
const COL_PARCHMENT := Color(0.87, 0.80, 0.64)
const COL_WOOD := Color(0.28, 0.18, 0.10)
const COL_GRID := Color(0.52, 0.40, 0.26, 0.35)
const COL_TEXT := Color(0.30, 0.20, 0.11)
const COL_DEMAND := Color(0.50, 0.34, 0.18)   # money pouch – medium wood brown
const COL_SUPPLY := Color(0.73, 0.46, 0.15)   # chest – rich bronze/copper
const COL_DEAL := Color(0.10, 0.07, 0.04)     # seal – near-black, strongest contrast
## The crown's half of a deal seal. The one saturated colour in an otherwise brown/beige palette,
## and it earns the exception: it answers "did the settlement trade with itself, or did everything
## go through the crown?" at a glance, which is the question M36 turns on.
const COL_CROWN := Color(0.80, 0.60, 0.10)
const COL_BID := Color(0.60, 0.43, 0.20)      # both crown price lines (sell price dashed)

## Dash pattern of the crown's sell-price line, in pixels.
const DASH_LEN := 3.0
const DASH_GAP := 3.0
## Legend swatch width for the two line series – wider than a 7 px sprite, so the dashed
## pattern is distinguishable at this size.
const LEGEND_LINE_W := 14.0

const FONT_SIZE := 8
const MARKER := 7          # edge length of the pixel sprites
const PAD_LEFT := 30.0
const PAD_RIGHT := 8.0
const PAD_TOP := 10.0
const PAD_BOTTOM := 18.0   # axis labels
const LEGEND_H := 14.0

## Blocky 7x7 sprites. '#' = solid color, '+' = darkened outline, '.' = empty.
const SPRITE_DEMAND := [   # money pouch with drawstring
	"..+++..",
	"..#.#..",
	".#####.",
	"#######",
	"#######",
	"#######",
	".+###+.",
]
const SPRITE_SUPPLY := [   # treasure chest with lid and lock
	".+++++.",
	"#######",
	"#.....#",
	"#######",
	"##.+.##",
	"#######",
	".+###+.",
]
const SPRITE_DEAL := [     # wax seal / stamp
	"..###..",
	".#####.",
	"##.#.##",
	"###+###",
	"##.#.##",
	".#####.",
	"..###..",
]

## Ready-to-draw rectangles per sprite, computed once and then only translated.
## Without this cache, every point cost up to 49 draw_rect calls.
static var _rect_cache: Dictionary = {}

var _exchange = null
var _good: int = -1


func set_source(exchange, good: int) -> void:
	_exchange = exchange
	_good = good
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_PARCHMENT)
	_draw_frame(Rect2(Vector2.ZERO, size), COL_WOOD)

	if _exchange == null or _good < 0:
		return

	var history: MarketHistory = _exchange.history
	var events: Array = history.events(_good)
	var bids: Array = history.bid_points(_good)

	var font := get_theme_default_font()
	if not history.has_data(_good):
		draw_string(font, Vector2(0.0, size.y * 0.5), "No trade history yet",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT_SIZE, COL_TEXT)
		return

	var plot := Rect2(
		PAD_LEFT, PAD_TOP,
		maxf(10.0, size.x - PAD_LEFT - PAD_RIGHT),
		maxf(10.0, size.y - PAD_TOP - PAD_BOTTOM - LEGEND_H))

	var asks: Array = history.ask_points(_good)
	var steps: Array = bids + asks

	var day_range := _day_range(events, steps)
	var price_max := _price_max(events, steps)

	_draw_grid(plot, day_range, price_max, font)
	# Sell price first, so the support line stays on top where the two coincide (the pre-M36
	# default had them on exactly the same value).
	_draw_step_line(plot, asks, day_range, price_max, true)
	_draw_step_line(plot, bids, day_range, price_max, false)
	_draw_events(plot, events, day_range, price_max)
	_draw_legend(font)


# ---------------------------------------------------------------------------
# Axes and grid
# ---------------------------------------------------------------------------

## Day span of the data, stretched to at least half a day – otherwise a few
## points shortly after game start would all stick to the same vertical line.
##
## The window follows the EVENT scatter only. The crown's step lines are deliberately excluded
## from the lower bound: `MarketHistory._record_step` only appends on a CHANGE, so a player who
## never touches the sliders leaves a single point sitting at day 1 for the rest of the game.
## Letting that set `lo` stretched the axis across the whole run while the events – capped at
## MAX_EVENTS, so they only ever cover the recent past – were squeezed into a couple of pixels
## at the right edge. The markers had not disappeared, they were all on top of each other.
## `_draw_step_line` clips the lines into this window instead.
func _day_range(events: Array, steps: Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for e in events:
		lo = minf(lo, e["day"])
		hi = maxf(hi, e["day"])
	if lo == INF:
		# No trades yet: fall back to the step lines, so an untouched chart still has an axis.
		for b in steps:
			lo = minf(lo, b["day"])
			hi = maxf(hi, b["day"])
	# The step line keeps running until "now", so the current day belongs to the span.
	hi = maxf(hi, MarketHistory.current_day())
	if lo == INF:
		lo = 1.0
		hi = 1.5
	# Widen backwards, not forwards: "now" stays pinned to the right edge, so a fresh point
	# always appears there instead of in the middle of empty space.
	lo = minf(lo, hi - 0.5)
	return Vector2(lo, hi)


## Upper scale bound. Deliberately NOT the maximum: a single outlier point would squeeze the whole
## chart onto the bottom edge. The 95th percentile keeps the scale close to what's actually
## happening; points above it are clamped to the top edge in _draw_events.
## (The original outliers came from demand being recorded as gold-per-desired-unit; M36 records a
## real bid instead, so this may now be over-cautious — worth revisiting against a live chart.)
## Both crown lines are included uncapped – they are player values and must always stay visible.
func _price_max(events: Array, steps: Array) -> float:
	var prices: Array = []
	for e in events:
		prices.append(e["price"])
	prices.sort()
	var hi := 0.0
	if not prices.is_empty():
		hi = prices[mini(prices.size() - 1, int(prices.size() * 0.95))]
	for b in steps:
		hi = maxf(hi, b["price"])
	# A bit of headroom, so points at the maximum don't sit right on the frame.
	return maxf(1.0, hi * 1.15)


func _to_px(plot: Rect2, day: float, price: float, day_range: Vector2, price_max: float) -> Vector2:
	var tx := (day - day_range.x) / maxf(0.0001, day_range.y - day_range.x)
	var ty := price / maxf(0.0001, price_max)
	return Vector2(plot.position.x + tx * plot.size.x, plot.end.y - ty * plot.size.y)


func _draw_grid(plot: Rect2, day_range: Vector2, price_max: float, font: Font) -> void:
	# Horizontal price lines with gold labels on the left.
	var steps := 4
	for i in range(steps + 1):
		var price := price_max * float(i) / float(steps)
		var y := plot.end.y - (float(i) / float(steps)) * plot.size.y
		if i > 0:
			_draw_dashed_h(plot.position.x, plot.end.x, y, COL_GRID)
		draw_string(font, Vector2(2.0, y + 3.0), "%.1f" % price,
			HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 6.0, FONT_SIZE, COL_TEXT)

	# Vertical day marks. In long games these get thinned out, so "Day 12"
	# and "Day 13" don't overlap.
	var first_day := int(ceil(day_range.x))
	var last_day := int(floor(day_range.y))
	var span := maxi(1, last_day - first_day)
	var stride := maxi(1, int(ceil(float(span) / 6.0)))
	var d := first_day
	while d <= last_day:
		var x := _to_px(plot, float(d), 0.0, day_range, price_max).x
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 2.0), COL_WOOD, 1.0)
		draw_string(font, Vector2(x - 14.0, plot.end.y + 11.0), "Day %d" % d,
			HORIZONTAL_ALIGNMENT_CENTER, 28.0, FONT_SIZE, COL_TEXT)
		d += stride

	# Axes as bold wood-colored lines.
	draw_line(plot.position + Vector2(0.0, plot.size.y), plot.end, COL_WOOD, 1.0)
	draw_line(plot.position, plot.position + Vector2(0.0, plot.size.y), COL_WOOD, 1.0)
	draw_string(font, Vector2(2.0, PAD_TOP - 2.0), "Gold coins",
		HORIZONTAL_ALIGNMENT_LEFT, plot.size.x, FONT_SIZE, COL_TEXT)


func _draw_dashed_h(x0: float, x1: float, y: float, color: Color) -> void:
	var x := x0
	while x < x1:
		draw_line(Vector2(x, y), Vector2(minf(x + 2.0, x1), y), color, 1.0)
		x += 4.0


func _draw_frame(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, false, 1.0)


# ---------------------------------------------------------------------------
# Data series
# ---------------------------------------------------------------------------

## Crown support price as a step line: hold horizontal until it changes, then jump
## vertically. The last step runs to the right edge, because the price is valid until now.
## Draws one of the crown's two prices as a step line: hold horizontal until it changes, then jump
## vertically. The last step runs to the right edge, because the price is valid until now.
##
## Both lines share the same marker, colour and 2 px weight – the sell price is drawn dashed so
## the two stay apart without adding a colour to a deliberately brown-and-beige palette. Which is
## which also reads from position: they bracket the villager orders between them.
func _draw_step_line(plot: Rect2, points: Array, day_range: Vector2, price_max: float,
		dashed: bool) -> void:
	if points.is_empty():
		return
	# The x window is set by the events (see _day_range), so a step recorded before it – the
	# common case, since a line only gets a point when the player moves a slider – lands left
	# of the plot. Clamping into the plot keeps the segment that IS in view: the price held
	# since then still draws across the whole width, which is exactly what a step line means.
	# 2 px thick, so the lines stand out from the swarm of 7 px markers.
	var prev := _clamp_x(_to_px(plot, points[0]["day"], points[0]["price"], day_range, price_max), plot)
	for i in range(1, points.size()):
		var next := _clamp_x(_to_px(plot, points[i]["day"], points[i]["price"], day_range, price_max), plot)
		_draw_seg(prev, Vector2(next.x, prev.y), dashed)   # hold horizontal
		_draw_seg(Vector2(next.x, prev.y), next, dashed)   # jump vertical
		prev = next
	_draw_seg(prev, Vector2(plot.end.x, prev.y), dashed)


## One segment of a step line, solid or dashed. Dashes are drawn along the segment rather than
## with a shader, so they work for the vertical jumps too.
func _draw_seg(from: Vector2, to: Vector2, dashed: bool) -> void:
	if not dashed:
		draw_line(from, to, COL_BID, 2.0)
		return
	var total := from.distance_to(to)
	if total <= 0.0:
		return
	var step := DASH_LEN + DASH_GAP
	var dir := (to - from) / total
	var travelled := 0.0
	while travelled < total:
		var end := minf(travelled + DASH_LEN, total)
		draw_line(from + dir * travelled, from + dir * end, COL_BID, 2.0)
		travelled += step


func _clamp_x(p: Vector2, plot: Rect2) -> Vector2:
	return Vector2(clampf(p.x, plot.position.x, plot.end.x), p.y)


func _draw_events(plot: Rect2, events: Array, day_range: Vector2, price_max: float) -> void:
	for e in events:
		var kind: int = e["kind"]
		var left := COL_DEMAND
		var right := COL_DEMAND
		var sprite := SPRITE_DEMAND
		if kind == MarketHistory.Kind.OFFER:
			left = COL_SUPPLY
			right = COL_SUPPLY
			sprite = SPRITE_SUPPLY
		elif kind == MarketHistory.Kind.DEAL:
			sprite = SPRITE_DEAL
			# The seal is split so the counterparty is readable without a tooltip: a gold half is
			# the crown, and which side it is on gives the direction of the goods. All-black means
			# the settlement traded with itself — the thing M36 exists to produce.
			var party: int = e.get("party", MarketHistory.Deal.VILLAGER)
			left = COL_CROWN if party == MarketHistory.Deal.CROWN_SELLS else COL_DEAL
			right = COL_CROWN if party == MarketHistory.Deal.CROWN_BUYS else COL_DEAL
		var p := _to_px(plot, e["day"], e["price"], day_range, price_max)
		# Clamp points above the scale (e.g. a very rich buyer) to the top edge instead of
		# letting them run off the chart.
		p.y = clampf(p.y, plot.position.y, plot.end.y)
		_draw_sprite_split(sprite, p - Vector2(MARKER, MARKER) * 0.5, left, right)


## Draws a pixel sprite in a single colour. Horizontally contiguous blocks are merged into one
## rectangle (in the cache), so each point only costs a few draw_rect calls.
func _draw_sprite(rows: Array, origin: Vector2, color: Color) -> void:
	_draw_sprite_split(rows, origin, color, color)


## Same, but the left and right halves take different colours – used by the deal seal to show the
## counterparty. A cached rectangle can straddle the middle (runs are merged horizontally), so it
## is split at the halfway column rather than assigned to one side.
func _draw_sprite_split(rows: Array, origin: Vector2, left: Color, right: Color) -> void:
	var key := str(rows.hash())
	if not _rect_cache.has(key):
		_rect_cache[key] = _build_rects(rows)
	var mid := MARKER * 0.5
	for entry in _rect_cache[key]:
		var r: Rect2 = entry["rect"]
		var is_edge: bool = entry["edge"]
		var split := clampf(mid, r.position.x, r.end.x)
		if split > r.position.x:
			_draw_part(origin, Rect2(r.position, Vector2(split - r.position.x, r.size.y)), left, is_edge)
		if r.end.x > split:
			_draw_part(origin, Rect2(Vector2(split, r.position.y), Vector2(r.end.x - split, r.size.y)),
				right, is_edge)


## One rectangle of a sprite. `edge` pixels ('+' in the sprite art) are darkened to give the
## marker an outline.
func _draw_part(origin: Vector2, r: Rect2, color: Color, edge: bool) -> void:
	var c := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a) if edge else color
	draw_rect(Rect2(origin + r.position, r.size), c)


func _build_rects(rows: Array) -> Array:
	var out: Array = []
	for y in range(rows.size()):
		var line: String = rows[y]
		var x := 0
		while x < line.length():
			var ch := line[x]
			if ch == ".":
				x += 1
				continue
			var run := 1
			while x + run < line.length() and line[x + run] == ch:
				run += 1
			out.append({
				"rect": Rect2(float(x), float(y), float(run), 1.0),
				"edge": ch == "+",
			})
			x += run
	return out


func _draw_legend(font: Font) -> void:
	var y := size.y - LEGEND_H * 0.5
	var x := PAD_LEFT
	# Seal colours spell out the counterparty: all black = between two inhabitants, a gold half =
	# the crown, and the side it sits on gives the direction the goods moved.
	var entries := [
		[SPRITE_DEMAND, COL_DEMAND, COL_DEMAND, "Demand"],
		[SPRITE_SUPPLY, COL_SUPPLY, COL_SUPPLY, "Supply"],
		[SPRITE_DEAL, COL_DEAL, COL_DEAL, "Villager deal"],
		[SPRITE_DEAL, COL_CROWN, COL_DEAL, "Crown sold"],
		[SPRITE_DEAL, COL_DEAL, COL_CROWN, "Crown bought"],
	]
	for entry in entries:
		_draw_sprite_split(entry[0], Vector2(x, y - MARKER * 0.5), entry[1], entry[2])
		var label: String = entry[3]
		draw_string(font, Vector2(x + MARKER + 2.0, y + 3.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, 60.0, FONT_SIZE, COL_TEXT)
		x += MARKER + 4.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 8.0

	# The two crown prices, drawn with the same marker they have in the plot: solid = buy,
	# dashed = sell. Wider swatches than the sprites so a dash pattern is actually legible.
	for line_entry in [[false, "Buy price"], [true, "Sell price"]]:
		_draw_seg(Vector2(x, y), Vector2(x + LEGEND_LINE_W, y), line_entry[0])
		var label: String = line_entry[1]
		draw_string(font, Vector2(x + LEGEND_LINE_W + 2.0, y + 3.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, 60.0, FONT_SIZE, COL_TEXT)
		x += LEGEND_LINE_W + 4.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 8.0
