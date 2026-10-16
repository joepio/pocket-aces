extends RefCounted
## Controller-selected public profiles. Never handles private phone URLs/cards.
var pending: Array = []
var linked: Array = []
var selected: Dictionary = {}
var previous: Dictionary = {}
var busy_player := ""
var busy_ticket := ""
var deadline := 0
var notice := ""

func update_links(data: Dictionary) -> void:
	pending = data.get("room", {}).get("pending", [])
	linked = data.get("linked", [])
	if not busy_ticket.is_empty() and busy_player in linked:
		if pending.all(func(t): return str(t.get("id", "")) != busy_ticket):
			busy_ticket = ""
			busy_player = ""
			notice = "Connected. Open the game on your phone."
	for id in selected:
		if pending.all(func(t): return str(t.get("id", "")) != str(selected[id])):
			selected.erase(id)

func choice(id: String) -> Dictionary:
	if pending.is_empty(): return {}
	for ticket in pending:
		if str(ticket.get("id", "")) == str(selected.get(id, "")): return ticket
	return pending[0]

func reset_inputs() -> void:
	previous.clear()

func input_for_player(id: String, frame: Dictionary, eligible: bool) -> String:
	var buttons := int(frame.get("buttons", 0))
	var axes: Array = frame.get("axes", [])
	var axis := float(axes[0]) / 32767.0 if not axes.is_empty() else 0.0
	var direction := -1 if axis < -0.5 or buttons & (1 << 12) else (1 if axis > 0.5 or buttons & (1 << 13) else 0)
	var old: Dictionary = previous.get(id, {"buttons": buttons, "direction": direction})
	previous[id] = {"buttons": buttons, "direction": direction}
	# Require release after starting/resuming. Never claim on a held play button.
	if not eligible or id in linked or pending.is_empty() or not busy_ticket.is_empty(): return ""
	var ticket := choice(id)
	if direction != 0 and direction != int(old.direction):
		var index := pending.find(ticket)
		ticket = pending[posmod(index + direction, pending.size())]
	selected[id] = str(ticket.get("id", ""))
	if buttons & 1 and not (int(old.buttons) & 1):
		return str(selected[id])
	return ""

func start(ticket: String, player: String) -> void:
	busy_ticket = ticket
	busy_player = player
	deadline = Time.get_ticks_msec() + 12000
	notice = "Connecting your phone…"

func fail() -> void:
	busy_ticket = ""
	busy_player = ""
	notice = "Could not connect. Press A to try again."

func poll_timeout() -> void:
	if not busy_ticket.is_empty() and Time.get_ticks_msec() >= deadline: fail()
