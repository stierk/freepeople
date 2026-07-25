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
const COL_DEAL := Color(0.22, 0.13, 0.06)     # seal – darkest brown, strongest contrast
const COL_BID := Color(0.60, 0.43, 0.20)      # support price line

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

	var day_range := _day_range(events, bids)
	var price_max := _price_max(events, bids)

	_draw_grid(plot, day_range, price_max, font)
	_draw_bid_line(plot, bids, day_range, price_max)
	_draw_events(plot, events, day_range, price_max)
	_draw_legend(font)


# ---------------------------------------------------------------------------
# Axes and grid
# ---------------------------------------------------------------------------

## Day span of the data, stretched to at least half a day – otherwise a few
## points shortly after game start would all stick to the same vertical line.
func _day_range(events: Array, bids: Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for e in events:
		lo = minf(lo, e["day"])
		hi = maxf(hi, e["day"])
	for b in bids:
		lo = minf(lo, b["day"])
		hi = maxf(hi, b["day"])
	# The step line keeps running until "now", so the current day belongs to the span.
	hi = maxf(hi, MarketHistory.current_day())
	if lo == INF:
		lo = 1.0
		hi = 1.5
	if hi - lo < 0.5:
		hi = lo + 0.5
	return Vector2(lo, hi)


## Upper scale bound. Deliberately NOT the maximum: demand is recorded as gold per desired
## unit, so a rich buyer with small need easily produces a point far beyond any real price.
## Scaled to the maximum, a single such outlier would squeeze the whole chart onto the
## bottom edge. The 95th percentile keeps the scale close to what's actually happening;
## points above it are clamped to the top edge in _draw_events.
## The support price is included uncapped – it's a player value and should always stay visible.
func _price_max(events: Array, bids: Array) -> float:
	var prices: Array = []
	for e in events:
		prices.append(e["price"])
	prices.sort()
	var hi := 0.0
	if not prices.is_empty():
		hi = prices[mini(prices.size() - 1, int(prices.size() * 0.95))]
	for b in bids:
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
func _draw_bid_line(plot: Rect2, bids: Array, day_range: Vector2, price_max: float) -> void:
	if bids.is_empty():
		return
	# 2 px thick, so the line stands out from the swarm of 7 px markers – in a pure
	# brown/beige palette, color alone doesn't carry this distinction.
	var prev := _to_px(plot, bids[0]["day"], bids[0]["price"], day_range, price_max)
	for i in range(1, bids.size()):
		var next := _to_px(plot, bids[i]["day"], bids[i]["price"], day_range, price_max)
		draw_line(prev, Vector2(next.x, prev.y), COL_BID, 2.0)   # hold horizontal
		draw_line(Vector2(next.x, prev.y), next, COL_BID, 2.0)   # jump vertical
		prev = next
	draw_line(prev, Vector2(plot.end.x, prev.y), COL_BID, 2.0)


func _draw_events(plot: Rect2, events: Array, day_range: Vector2, price_max: float) -> void:
	for e in events:
		var kind: int = e["kind"]
		var color := COL_DEMAND
		var sprite := SPRITE_DEMAND
		if kind == MarketHistory.Kind.OFFER:
			color = COL_SUPPLY
			sprite = SPRITE_SUPPLY
		elif kind == MarketHistory.Kind.DEAL:
			color = COL_DEAL
			sprite = SPRITE_DEAL
		var p := _to_px(plot, e["day"], e["price"], day_range, price_max)
		# Clamp points above the scale (e.g. a very rich buyer) to the top edge instead of
		# letting them run off the chart.
		p.y = clampf(p.y, plot.position.y, plot.end.y)
		_draw_sprite(sprite, p - Vector2(MARKER, MARKER) * 0.5, color)


## Draws a pixel sprite. Horizontally contiguous blocks are merged into one rectangle
## (in the cache), so each point only costs a few draw_rect calls.
func _draw_sprite(rows: Array, origin: Vector2, color: Color) -> void:
	var key := str(rows.hash())
	if not _rect_cache.has(key):
		_rect_cache[key] = _build_rects(rows)
	var dark := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)
	for entry in _rect_cache[key]:
		var r: Rect2 = entry["rect"]
		draw_rect(Rect2(origin + r.position, r.size), dark if entry["edge"] else color)


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
	var entries := [
		[SPRITE_DEMAND, COL_DEMAND, "Demand"],
		[SPRITE_SUPPLY, COL_SUPPLY, "Supply"],
		[SPRITE_DEAL, COL_DEAL, "Deal"],
	]
	for entry in entries:
		_draw_sprite(entry[0], Vector2(x, y - MARKER * 0.5), entry[1])
		draw_string(font, Vector2(x + MARKER + 2.0, y + 3.0), entry[2],
			HORIZONTAL_ALIGNMENT_LEFT, 60.0, FONT_SIZE, COL_TEXT)
		x += MARKER + 4.0 + font.get_string_size(entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 8.0

	draw_line(Vector2(x, y), Vector2(x + MARKER, y), COL_BID, 2.0)
	draw_string(font, Vector2(x + MARKER + 2.0, y + 3.0), "Buy price",
		HORIZONTAL_ALIGNMENT_LEFT, 60.0, FONT_SIZE, COL_TEXT)
