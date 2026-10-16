extends Control
## TV onboarding contains only public room information, never profile links/cards.
var seats: Array = []
var waiting := false
var reconnecting := false
var running := false
var room: Dictionary = {}
var qr: Texture2D
var pickup_rows: Dictionary = {}
var pickup_notice := ""
var font := ThemeDB.fallback_font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_setup(players: Array, initial: bool, missing: bool, live: bool) -> void:
	var changed := seats != players or waiting != initial or reconnecting != missing or running != live
	seats = players
	waiting = initial
	reconnecting = missing
	running = live
	visible = initial or missing
	if changed: queue_redraw()

func set_room(data: Dictionary) -> void:
	if room == data: return
	room = data
	qr = null
	var svg: String = room.get("qr_svg", "")
	var image := Image.new()
	if not svg.is_empty() and svg.length() < 200000 and image.load_svg_from_string(svg, 3.0) == OK:
		qr = ImageTexture.create_from_image(image)
	queue_redraw()

func set_pickup(state) -> void:
	var rows: Dictionary = {}
	for p in seats:
		if p.bot or p.connected or p.id in state.linked: continue
		var ticket: Dictionary = state.choice(p.id)
		if not ticket.is_empty():
			rows[p.id] = {"name": str(ticket.get("profile", {}).get("display_name", "Player")), "busy": state.busy_player == p.id}
	if rows == pickup_rows and pickup_notice == state.notice: return
	pickup_rows = rows
	pickup_notice = state.notice
	queue_redraw()

func panel(rect: Rect2, color: Color, radius := 20) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func text(value: String, pos: Vector2, size: int, color := Color("fff0d4"), width := -1.0) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)

func _draw() -> void:
	if not visible: return
	draw_rect(Rect2(0, 0, 1600, 900), Color(0.015, 0.025, 0.021, 0.72))
	panel(Rect2(175, 132, 1250, 638), Color("192c28"), 30)
	text("Grab your phone" if waiting else "Waiting for a phone", Vector2(230, 212), 48)
	text("Scan. Pick your name with your controller. Ready on your phone." if waiting else "The hand is paused. Reconnect to continue.", Vector2(232, 254), 24, Color("bdc9b8"))
	panel(Rect2(230, 290, 310, 310), Color.WHITE, 14)
	if qr != null:
		draw_texture_rect(qr, Rect2(248, 308, 274, 274), false)
	else:
		text("Open GameNight", Vector2(255, 422), 27, Color("192c28"))
		text("on your phone", Vector2(270, 462), 24, Color("192c28"))
	var code: String = str(room.get("room_code", room.get("code", "")))
	text("ROOM  " + code if not code.is_empty() else "Use the room QR in the lobby", Vector2(232, 640), 24, Color("e6c78c"))
	text("Already joined? Open the Game tab.", Vector2(232, 687), 20, Color("bdc9b8"))
	var humans := seats.filter(func(p): return not p.bot)
	var count := humans.filter(func(p): return p.connected and p.ready).size()
	text("%d / %d READY" % [count, humans.size()] if waiting else "YOUR TABLE", Vector2(625, 314), 23, Color("e6c78c"))
	for i in seats.size():
		var p: Dictionary = seats[i]
		var y := 344.0 + i * 56
		panel(Rect2(610, y - 21, 755, 51), Color("263c34"), 9)
		draw_circle(Vector2(637, y + 2), 9, Color.from_string(p.color, Color.WHITE))
		text(str(p.name).left(18), Vector2(660, y + 10), 23)
		var status := "House bot" if p.bot else ("Ready" if p.ready and p.connected else ("Tap Ready on phone" if p.connected else "Connect phone"))
		if not waiting and not p.bot: status = "Connected" if p.connected else "Reconnecting…"
		if pickup_rows.has(p.id):
			var row: Dictionary = pickup_rows[p.id]
			status = "Connecting…" if row.busy else "‹  %s  ›   A · Pick up" % row.name.left(18)
		text(status, Vector2(925, y + 10), 21, Color("99d2ad") if p.connected else Color("e6c78c"), 425)
	var hint := "Use left / right, then A on your own controller." if not pickup_rows.is_empty() else "Cards stay hidden until you tap them."
	text(pickup_notice if not pickup_notice.is_empty() else hint, Vector2(625, 712), 22, Color("bdc9b8"), 735)
	if not running: text("Paused in GameNight", Vector2(625, 747), 18, Color("e6c78c"))
