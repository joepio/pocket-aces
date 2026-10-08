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
var dynamic: Node3D
var banner: Label
var status_label: Label
var result_label: Label
var caption: Label
var revision_seen = -1
var camera: Camera3D
var connected_phones: Dictionary = {}
var shot_at = 0.0
var test_mode = OS.get_environment("POCKET_ACES_DEMO") == "1"
var last_board_count = 0
var last_hand = -1
var last_tick_ms = 0
const COLORS = ["#62d6b2", "#ffad77", "#be9bef", "#f38eaa", "#77bcef", "#efd474"]

func _ready() -> void:
	GameNight.game_id = "pocket-aces"
	GameNight.prepared.connect(prepare)
	GameNight.started.connect(func(_id): live = true; publish())
	GameNight.resumed.connect(func(_id): live = true; publish())
	GameNight.paused.connect(func(_id): live = false; publish())
	GameNight.disposed.connect(func(_id): live = false; has_table = false)
	GameNight.companion_message.connect(phone_message)
	GameNight.companion_presence.connect(func(id, online):
		connected_phones[id] = maxi(0, connected_phones.get(id, 0) + (1 if online else -1))
		if online: send_private(id))
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
	game.setup(roster, chips, blind)
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
		if not p.bot and not p.id in ids: connected_phones.erase(p.id)

func setting_change(key: String, value: Variant) -> void:
	match key:
		"starting_chips": chips = clampi(int(value), 200, 10000)
		"big_blind": blind = clampi(int(value), 2, 100)
		"turn_seconds": timeout_seconds = clampi(int(value), 15, 120)

func send_private(id: String) -> void:
	if not has_table: return
	var view = game.private_view(id)
	if view.is_empty(): return
	view["paused"] = not live
	view["seconds"] = maxi(0, timeout_seconds - int(turn_time))
	if not live: view.actions = {}
	GameNight.send_companion_message(view, id)

func publish() -> void:
	for p in game.players:
		if not p.bot: send_private(p.id)

func phone_message(id: String, data: Variant) -> void:
	if not has_table or not data is Dictionary: return
	if data.get("action") == "sync":
		send_private(id)
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
	if live and not test_mode:
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
	else:
		caption.text = "%s's turn  ·  %ds" % [game.players[game.turn].name, maxi(0, timeout_seconds - int(turn_time))]
	if not live: caption.text = "Paused in GameNight"
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

func material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.metallic = metal
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 64
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func text3(parent: Node3D, pos: Vector3, text: String, size: int, color: Color, flat: bool = false) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.007
	label.modulate = color
	label.outline_size = 0 if flat else 3
	if not flat: label.pixel_size = 0.010
	label.position = pos
	if flat: label.rotation_degrees.x = -90
	else: label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func build_room() -> void:
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("101a31")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c2c5ef")
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_color = Color("ffe4bb")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0, 12.5, 13.5)
	camera.fov = 44
	add_child(camera)
	camera.look_at(Vector3(0, 0.7, 0))
	box(self,Vector3(0,-0.3,0),Vector3(30,0.4,24),Color("273342"))
	for i in 19: box(self,Vector3(i * 1.1 - 10, -0.085, 0),Vector3(0.025,0.025,22),Color("344453"))
	var rug = cylinder(self,Vector3(0,-0.05,0),7,0.04,Color("563d63"))
	rug.scale.z = 0.68
	var rim = cylinder(self,Vector3(0,0.9,0),5.55,0.42,Color("6b3c39"))
	rim.scale.z = 0.62
	var trim = cylinder(self,Vector3(0,1.13,0),5.28,0.07,Color("deb97f"))
	trim.scale.z = 0.61
	var felt = cylinder(self,Vector3(0,1.19,0),5.13,0.06,Color("176d65"))
	felt.scale.z = 0.60
	for x in [-3.5,3.5]: cylinder(self,Vector3(x,0.35,0),0.35,1,Color("392b39"))
	# Rooftop skyline, rail and warm lamps give the table a real setting.
	box(self,Vector3(0,0.3,-6.5),Vector3(23,0.25,0.18),Color("ddad6b"))
	for x in range(-11,12,2): box(self,Vector3(x,0,-6.5),Vector3(0.1,2,0.1),Color("a38268"))
	var random = RandomNumberGenerator.new()
	random.seed = 92
	for i in 18:
		var x = i * 1.6 - 14
		var h = random.randf_range(2,7)
		box(self,Vector3(x,h/2 - 2,-12 - (i%3)),Vector3(1.2,h,1.4),Color("1a2641") if i%2 else Color("253252"))
		for y in range(int(h)):
			if i%3 != 0: box(self,Vector3(x,y - 1.4,-11.25 - i%3),Vector3(0.3,0.2,0.03),Color("d2af78"))
	for x in [-7.5,7.5]:
		cylinder(self,Vector3(x,1.8,-3),0.06,4,Color("bf9a69"))
		sphere(self,Vector3(x,3.9,-3),0.32,Color("ffe2a0"))
		var lamp = OmniLight3D.new()
		lamp.position = Vector3(x,3.8,-3)
		lamp.light_color = Color("ffc58b")
		lamp.light_energy = 2
		lamp.omni_range = 9
		add_child(lamp)
		cylinder(self,Vector3(x,0.4,3),0.55,0.9,Color("bc7b61"))
		for j in 5:
			var leaf = sphere(self,Vector3(x+sin(j*2)*0.3,1+j*0.14,3+cos(j*2)*0.3),0.45,Color("497b69"))
			leaf.scale = Vector3(0.5,1.8,0.5)
	dynamic = Node3D.new()
	add_child(dynamic)

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
	add_child(hud)
	ui_label(hud,"POCKET ACES",Vector2(50,35),Vector2(450,50),36,Color("ffe1ae"))
	ui_label(hud,"THE ROOFTOP CLUB",Vector2(52,84),Vector2(400,35),17,Color("bcbdd3"))
	banner = ui_label(hud,"Waiting for GameNight",Vector2(500,35),Vector2(600,60),34,Color("fff3dc"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label = ui_label(hud,"",Vector2(500,99),Vector2(600,45),27,Color("83e1c3"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label = ui_label(hud,"",Vector2(180,740),Vector2(1240,50),28,Color("ffe1ae"))
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption = ui_label(hud,"Your cards and actions are on your phone",Vector2(200,812),Vector2(1200,44),23,Color("ebebf5"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_label(hud,"Fictional chips",Vector2(1370,48),Vector2(190,30),18,Color("bcbdd3"))

func card(parent: Node3D, pos: Vector3, value: int = -1, deal: bool = false) -> void:
	var root = Node3D.new()
	root.position = pos
	parent.add_child(root)
	box(root,Vector3.ZERO,Vector3(0.83,0.045,1.18),Color("fff1da") if value >= 0 else Color("244a61"))
	if value >= 0:
		var red = int(value / 13) in [1,2]
		text3(root,Vector3(0,0.036,0),Rules.card_text(value),57,Color("b73753") if red else Color("213746"),true)
	else: text3(root,Vector3(0,0.036,0),"◆",62,Color("bda179"),true)
	if deal:
		root.position = Vector3(4,1.8,-1)
		root.rotation.y = 0.4
		var tween = root.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(root,"position",pos,0.35)
		tween.tween_property(root,"rotation:y",0.0,0.35)

func refresh() -> void:
	for child in dynamic.get_children():
		dynamic.remove_child(child)
		child.queue_free()
	var state = game.public_view()
	banner.text = "Hand %d  /  %s" % [state.hand, state.street]
	status_label.text = "POT  %d" % state.pot
	result_label.text = state.result
	var new_deal = last_hand != state.hand
	if new_deal: last_board_count = 0
	for i in 5: card(dynamic,Vector3((i-2)*0.99,1.26,-0.25),state.board[i] if i < state.board.size() else -1,i >= last_board_count and i < state.board.size())
	for i in mini(12, int(state.pot/10)):
		cylinder(dynamic,Vector3(-0.7+(i%3)*0.28,1.3+int(i/3)*0.09,1.35),0.16,0.085,Color("e4b96b") if i%2 else Color("fff0cf"))
	var positions = [Vector3(-4,0,2.35),Vector3(0,0,3.65),Vector3(4,0,2.35),Vector3(4,0,-2.5),Vector3(0,0,-3.8),Vector3(-4,0,-2.5)]
	var order = [0,2,3,5] if state.players.size() == 4 else ([0,2] if state.players.size() == 2 else range(state.players.size()))
	for i in state.players.size():
		var p = state.players[i]
		var pos = positions[order[i]]
		var color = Color.from_string(p.color,Color("71d4ba"))
		if p.folded: color = color.darkened(0.48)
		cylinder(dynamic,pos+Vector3(0,0.5,0),0.57,0.2,Color("8f6669"))
		box(dynamic,pos+Vector3(0,0.45,0),Vector3(0.18,0.9,0.18),Color("34293a"))
		sphere(dynamic,pos+Vector3(0,1.0,0),0.43,color)
		sphere(dynamic,pos+Vector3(0,1.65,0),0.44,Color("e1ae80"))
		cylinder(dynamic,pos+Vector3(0,1.98,0),0.49,0.12,color)
		cylinder(dynamic,pos+Vector3(0,2.1,0),0.3,0.25,color)
		for x in [-0.14,0.14]: sphere(dynamic,pos+Vector3(x,1.72,0.39),0.052,Color("253646"))
		if p.turn:
			var marker = cylinder(dynamic,pos+Vector3(0,0.08,0),0.78,0.045,Color("f4d781"))
			marker.material_override = material(Color("f4d781"))
		text3(dynamic,pos+Vector3(0,2.9,0),p.name + (" · D" if p.dealer else ""),38,Color("ffe29e") if p.turn else Color("fff1de"))
		text3(dynamic,pos+Vector3(0,2.52,0),"%d chips  %s" % [p.chips,p.action],25,Color("c5eadc"))
		var inner = pos * 0.67
		for c in 2:
			card(dynamic,Vector3(inner.x+(c-0.5)*0.45,1.27,inner.z),p.cards[c] if p.cards.size() == 2 else -1,new_deal)
		for j in mini(8,int(p.chips/100)):
			cylinder(dynamic,Vector3(inner.x+0.7,1.28+j*0.085,inner.z),0.17,0.08,color)
		if p.paid > 0: text3(dynamic,Vector3(inner.x,1.4,inner.z-0.5),str(p.paid),28,Color("ffdf98"),true)
	last_board_count = state.board.size()
	last_hand = state.hand
