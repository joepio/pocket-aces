extends Node3D
const Rules = preload("res://rules.gd")
var game = Rules.new()
var live = false
var has_table = false
var turn_time = 0.0
var between_time = 0.0
var bot_time = 0.0
var timeout_seconds = 45
var chips = 1000
var blind = 20
var table_visuals: Node3D
var hud_layer: CanvasLayer
var banner: Label
var status_label: Label
var result_label: Label
var caption: Label
var revision_seen = -1
var camera: Camera3D
var connected_phones: Dictionary = {}
var ready_phones: Dictionary = {}
var waiting_for_phones := false
var setup_ui: Control
var links_request := HTTPRequest.new()
var links_base := ""
var links_elapsed := 5.0
var shot_at = 0.0
var test_mode = OS.get_environment("POCKET_ACES_DEMO") == "1"
var last_board_count = 0
var last_hand = -1
var last_tick_ms = 0
const COLORS = ["#62d6b2", "#ffad77", "#be9bef", "#f38eaa", "#77bcef", "#efd474"]

func _ready() -> void:
	GameNight.game_id = "pocket-aces"
	GameNight.prepared.connect(prepare)
	GameNight.started.connect(func(_id): live = true; begin_if_ready(); publish())
	GameNight.resumed.connect(func(_id): live = true; begin_if_ready(); publish())
	GameNight.paused.connect(func(_id): live = false; publish())
	GameNight.disposed.connect(func(_id): live = false; has_table = false)
	GameNight.companion_message.connect(phone_message)
	GameNight.companion_presence.connect(phone_presence)
	GameNight.roster_changed.connect(roster_change)
	GameNight.setting_changed.connect(setting_change)
	GameNight.declare_settings([
		{"key":"starting_chips", "label":"Starting chips (next session)", "kind":"number", "default":1000,"min":200,"max":10000},
		{"key":"big_blind", "label":"Big blind (next hand)", "kind":"number", "default":20,"min":2,"max":100},
		{"key":"turn_seconds", "label":"Seconds per turn", "kind":"number", "default":45,"min":15,"max":120}])
	# Exported PCK resources aren't normal files. Publish only the phone bundle.
	DirAccess.make_dir_recursive_absolute("user://phone")
	for name in ["index.html", "phone.css", "phone.js"]:
		var f = FileAccess.open("user://phone/" + name, FileAccess.WRITE)
		f.store_string(FileAccess.get_file_as_string("res://phone/" + name))
	var phone_root = ProjectSettings.globalize_path("user://phone")
	# Development only: a Windows game with a WSL host needs a host-visible
	# path to the exact same phone bundle. Normal installations use user://.
	if not OS.get_environment("POCKET_ACES_COMPANION_ROOT").is_empty():
		phone_root = OS.get_environment("POCKET_ACES_COMPANION_ROOT")
	GameNight.declare_companion(phone_root, "index.html")
	build_room()
	build_hud()
	setup_ui = preload("res://setup_ui.gd").new()
	var setup_layer := CanvasLayer.new()
	setup_layer.layer = 5
	add_child(setup_layer)
	setup_layer.add_child(setup_ui)
	add_child(links_request)
	links_request.timeout = 3
	links_request.request_completed.connect(room_links_received)
	links_base = OS.get_environment("GAMENIGHT_LINKS_URL")
	if links_base.is_empty(): links_base = "http://127.0.0.1:7913"
	if not links_base.begins_with("http://127.0.0.1:"): links_base = ""
	if not GameNight.launched_by_daemon:
		var roster: Array = []
		for i in 4: roster.append({"id":"demo-%d" % i,"name":["Clover","Peaches","Fig","Mochi"][i],"color":COLORS[i],"bot":true})
		game.setup(roster, chips, blind, 420 if test_mode else -1)
		has_table = true
		live = true
		if test_mode:
			# Reproducible public mid-hand scene. No private cards in the TV view.
			for i in 4:
				game.act(game.players[game.turn].id,{"action":"call" if game.legal(game.turn).call > 0 else "check","revision":game.revision})
		refresh()

func prepare(session: String, seats: Array, profiles: Array) -> void:
	var roster: Array = []
	for seat in seats:
		var occupant = seat.get("occupant", {})
		if occupant.get("kind", "empty") == "empty": continue
		var id = str(occupant.get("player_id", "bot-%d" % seat.index))
		var entry = {"id":id, "name":"House bot", "bot":occupant.get("kind") == "ai", "color":COLORS[roster.size() % 6]}
		for p in profiles:
			if str(p.id) == id:
				entry.name = p.name
				entry.color = p.get("color", entry.color)
		roster.append(entry)
	while roster.size() < 2:
		roster.append({"id":"house-%d" % roster.size(),"name":"Clover (bot)","bot":true,"color":COLORS[roster.size()]})
	game.setup(roster, chips, blind, -1, false)
	waiting_for_phones = true
	ready_phones.clear()
	has_table = true
	live = false
	turn_time = 0
	between_time = 0
	refresh()
	GameNight.notify_ready(session)

func roster_change(seats: Array, _profiles: Array, _presence: Array) -> void:
	# Keep chip ownership stable for this session. Departed players time out safely.
	var ids: Array = []
	for seat in seats: ids.append(str(seat.get("occupant", {}).get("player_id", "")))
	for p in game.players:
		if not p.bot and not p.id in ids:
			connected_phones.erase(p.id)
			ready_phones.erase(p.id)
	publish()

func phone_presence(id: String, online: bool) -> void:
	connected_phones[id] = maxi(0, connected_phones.get(id, 0) + (1 if online else -1))
	if connected_phones[id] == 0: ready_phones.erase(id)
	begin_if_ready()
	publish()

func phone_seats() -> Array:
	var seats: Array = []
	for p in game.players:
		seats.append({"id":p.id, "name":p.name, "color":p.color, "bot":p.bot, "connected":p.bot or connected_phones.get(p.id, 0) > 0, "ready":p.bot or ready_phones.get(p.id, false)})
	return seats

func human_count() -> int:
	return game.players.filter(func(p): return not p.bot).size()

func ready_count() -> int:
	return phone_seats().filter(func(p): return not p.bot and p.connected and p.ready).size()

func all_connected() -> bool:
	return phone_seats().all(func(p): return p.connected)

func begin_if_ready() -> void:
	if not has_table or not waiting_for_phones or not live: return
	if not all_connected() or ready_count() != human_count(): return
	waiting_for_phones = false
	game.new_hand()
	changed()

func room_links_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary: setup_ui.set_room(data.get("room", {}))

func setting_change(key: String, value: Variant) -> void:
	match key:
		"starting_chips": chips = clampi(int(value), 200, 10000)
		"big_blind": blind = clampi(int(value), 2, 100)
		"turn_seconds": timeout_seconds = clampi(int(value), 15, 120)

func send_private(id: String) -> void:
	if not has_table: return
	var view = game.private_view(id)
	if view.is_empty(): return
	view.you["id"] = id
	view["paused"] = not live
	view["setup"] = {"waiting": waiting_for_phones, "ready": ready_phones.get(id, false), "players": phone_seats(), "count": ready_count(), "total": human_count()}
	view["connection_wait"] = not waiting_for_phones and not all_connected()
	view["seconds"] = maxi(0, timeout_seconds - int(turn_time))
	if not live or waiting_for_phones or not all_connected(): view.actions = {}
	if waiting_for_phones: view["seconds"] = 0
	GameNight.send_companion_message(view, id)

func publish() -> void:
	for p in game.players:
		if not p.bot: send_private(p.id)

func phone_message(id: String, data: Variant) -> void:
	if not has_table or not data is Dictionary: return
	if data.get("action") == "sync":
		send_private(id)
		return
	if data.get("action") == "ready":
		if waiting_for_phones and connected_phones.get(id, 0) > 0:
			for p in game.players:
				if p.id == id and not p.bot:
					ready_phones[id] = data.get("ready", false) == true
					begin_if_ready()
					publish()
		return
	if waiting_for_phones or not all_connected():
		GameNight.send_companion_message({"type":"error","text":"Waiting for everyone's phone."}, id)
		return
	if not live:
		GameNight.send_companion_message({"type":"error","text":"The table is paused."}, id)
		return
	var error = game.act(id, data)
	if not error.is_empty():
		GameNight.send_companion_message({"type":"error","text":error}, id)
		send_private(id)
	else: changed()

func changed() -> void:
	turn_time = 0
	bot_time = 0
	if game.over:
		between_time = 0
		if not GameNight.session.is_empty(): GameNight.notify_finished(GameNight.session)
	refresh()
	publish()

func _process(_dt: float) -> void:
	# Godot clamps frame delta on very slow renderers. Turn clocks use elapsed
	# wall time instead, sampled even while paused so resume never catches up.
	var now = Time.get_ticks_msec()
	var dt = minf(1.0, float(now - last_tick_ms) / 1000.0) if last_tick_ms > 0 else 0.0
	last_tick_ms = now
	if not has_table: return
	if live and not waiting_for_phones and all_connected() and not test_mode:
		if game.over:
			between_time += dt
			if between_time >= 10:
				game.blind = blind
				game.new_hand()
				changed()
		else:
			var previous_second = int(turn_time)
			turn_time += dt
			if int(turn_time) != previous_second: publish()
			bot_time += dt
			var p = game.players[game.turn]
			if p.bot and bot_time >= 1.8:
				bot_act()
			elif turn_time >= timeout_seconds:
				var action = "check" if game.legal(game.turn).check else "fold"
				game.act(p.id, {"action":action,"revision":game.revision})
				changed()
	if game.over:
		caption.text = "Next hand in %d  ·  Free chips if you bust" % maxi(0, 10 - int(between_time))
	elif game.turn >= 0:
		caption.text = "%s's turn  ·  %ds" % [game.players[game.turn].name, maxi(0, timeout_seconds - int(turn_time))]
	if not live: caption.text = "Paused in GameNight"
	hud_layer.visible = not waiting_for_phones and all_connected()
	setup_ui.update_setup(phone_seats(), waiting_for_phones, not all_connected(), live)
	links_elapsed += dt
	if GameNight.launched_by_daemon and links_elapsed >= 3 and not links_base.is_empty() and links_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		links_elapsed = 0
		links_request.request(links_base + "/api/player-links")
	if OS.get_environment("POCKET_ACES_CAPTURE") != "" and shot_at < 2:
		shot_at += dt
		if shot_at >= 2:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("POCKET_ACES_CAPTURE"))

func bot_act() -> void:
	var options = game.legal(game.turn)
	var action = "check" if options.check else "call"
	# A deliberately modest opponent, using only its own hand and public cards.
	var own = game.players[game.turn]
	var strength = maxi(own.cards[0] % 13, own.cards[1] % 13)
	var roll = game.rng.randf()
	if options.raise and roll < (0.3 if strength >= 10 else 0.12): action = "raise"
	elif options.call > own.chips * 0.3 and roll < 0.35: action = "fold"
	game.act(own.id, {"action":action,"amount":options.min,"revision":game.revision})
	changed()

func build_room() -> void:
	table_visuals = preload("res://table_visuals.gd").new()
	add_child(table_visuals)
	table_visuals.build()
	camera = table_visuals.camera

func ui_label(parent: Node, text: String, pos: Vector2, size: Vector2, font: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size",font)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.5))
	label.add_theme_constant_override("shadow_offset_y",2)
	parent.add_child(label)
	return label

func build_hud() -> void:
	var hud = CanvasLayer.new()
	hud_layer = hud
	add_child(hud)
	ui_label(hud,"POCKET ACES",Vector2(50,35),Vector2(450,50),36,Color("ffe1ae"))
	ui_label(hud,"THE SALOON",Vector2(52,84),Vector2(400,35),17,Color("bcbdd3"))
	banner = ui_label(hud,"Waiting for GameNight",Vector2(500,35),Vector2(600,60),34,Color("fff3dc"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label = ui_label(hud,"",Vector2(500,99),Vector2(600,45),27,Color("83e1c3"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label = ui_label(hud,"",Vector2(180,740),Vector2(1240,50),28,Color("ffe1ae"))
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption = ui_label(hud,"Your cards and actions are on your phone",Vector2(200,812),Vector2(1200,44),23,Color("ebebf5"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_label(hud,"Fictional chips",Vector2(1370,48),Vector2(190,30),18,Color("bcbdd3"))

func refresh() -> void:
	hud_layer.visible = not waiting_for_phones
	var state = game.public_view()
	banner.text = "Hand %d  /  %s" % [state.hand, state.street]
	status_label.text = "POT  %d" % state.pot
	result_label.text = state.result
	var new_deal = last_hand != state.hand
	if new_deal: last_board_count = 0
	table_visuals.show_state(state, new_deal, last_board_count)
	last_board_count = state.board.size()
	last_hand = state.hand
