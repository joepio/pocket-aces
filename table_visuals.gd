extends Node3D
## Public table renderer. Pass only rules.public_view() data.
var camera: Camera3D
var pieces: Node3D
var materials: Dictionary = {}
var wood_materials: Dictionary = {}
const CREAM = Color("fff0ce")
const GOLD = Color("d4aa61")
const DARK = Color("241a15")
func mat(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(metallic)
	if materials.has(key): return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.68 if metallic == 0.0 else 0.35
	m.metallic = metallic
	materials[key] = m
	return m
func block(parent: Node3D, pos: Vector3, size: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mat(color, metal)
	n.position = pos
	parent.add_child(n)
	return n
func disc(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 64
	n.mesh = mesh
	n.material_override = mat(color, metal)
	n.position = pos
	parent.add_child(n)
	return n
func ring(parent: Node3D, pos: Vector3, inner: float, outer: float, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 96
	mesh.ring_segments = 12
	n.mesh = mesh
	n.material_override = mat(color)
	n.position = pos
	parent.add_child(n)
	return n
func lettering(parent: Node3D, pos: Vector3, words: String, size: int, color: Color, flat: bool = false) -> Label3D:
	var n = Label3D.new()
	n.text = words
	n.font_size = size
	n.pixel_size = 0.009
	n.modulate = color
	n.outline_size = 0 if flat else 4
	n.outline_modulate = Color("201810")
	n.position = pos
	if flat: n.rotation_degrees.x = -90
	else: n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = not flat
	parent.add_child(n)
	return n
func oval(pos: Vector3, radius: float, height: float, color: Color, depth: float = 0.59, metal: float = 0.0) -> MeshInstance3D:
	var n = disc(self, pos, radius, height, color, metal)
	n.scale.z = depth
	return n
func ball(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	n.mesh = mesh
	n.material_override = mat(color)
	n.position = pos
	parent.add_child(n)
	return n
func wood_grain(color: Color) -> ShaderMaterial:
	if wood_materials.has(color): return wood_materials[color]
	var shader = Shader.new()
	shader.code = "shader_type spatial; uniform vec4 tint: source_color; varying vec3 world; void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){float grain=sin(world.x*96.0+sin(world.z*1.7)*3.0+sin(world.x*11.0+world.z*0.6)*2.0); ALBEDO=tint.rgb*(0.96+0.04*grain); ROUGHNESS=0.8;}"
	var m = ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tint",color)
	wood_materials[color] = m
	return m
func build() -> void:
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("211b18")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e0ba84")
	world.environment.ambient_light_energy = 0.38
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -25, 0)
	sun.light_color = Color("ffe8bf")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0, 10.8, 12.4)
	camera.fov = 42
	add_child(camera)
	camera.look_at(Vector3(0, 1.0, -0.6))
	camera.current = true
	# Staggered oak boards with visible end joints.
	block(self, Vector3(0,-0.31,0), Vector3(30,0.4,24), Color("302016"))
	for row in 25:
		for col in 7:
			var shade = [Color("504031"),Color("483b2e"),Color("594836")][(row+col*2)%3]
			var board = block(self,Vector3(row*0.82-9.84,-0.09,col*3.0-9.0+(row%2)*1.5),Vector3(0.80,0.07,2.97),shade)
			board.material_override = wood_grain(shade)
	# Walnut paneling, brass moldings and a stocked back bar.
	block(self,Vector3(0,3.6,-7.6),Vector3(28,8,0.4),Color("2b2924"))
	block(self,Vector3(0,1.25,-7.32),Vector3(28,2.5,0.2),Color("3d2e26"))
	block(self,Vector3(0,2.6,-7.12),Vector3(28,0.15,0.35),Color("796143"))
	for x in range(-12,13,2):
		block(self,Vector3(x,1.25,-7.12),Vector3(0.11,2.4,0.1),Color("6b5140"))
		block(self,Vector3(x,4.5,-7.29),Vector3(0.065,3.6,0.05),Color("514132"))
	for x in [-8.7,8.7]:
		block(self,Vector3(x,3.6,-7.0),Vector3(3.2,3.3,0.25),GOLD)
		block(self,Vector3(x,3.6,-6.8),Vector3(2.97,3.08,0.12),Color("283d36"))
		for y in [2.45,3.65]:
			block(self,Vector3(x,y,-6.45),Vector3(3.4,0.14,0.75),Color("573821"))
			for j in 6:
				var p = Vector3(x-1.23+j*0.49,y+0.36,-6.48)
				disc(self,p,0.105,0.58,Color("956534") if j%3 == 0 else Color("345147"))
				disc(self,p+Vector3(0,0.36,0),0.046,0.18,Color("8b6334"))
				block(self,p+Vector3(0,0,0.107),Vector3(0.14,0.17,0.025),Color("d2b788"))
	oval(Vector3(0,-0.025,0),7.3,0.035,Color("42232b"),0.66)
	var border = ring(self,Vector3(0,0.004,0),6.92,7.0,Color("b48654"))
	border.scale.z = 0.66
	var border2 = ring(self,Vector3(0,0.006,0),6.72,6.76,Color("c69861"))
	border2.scale.z = 0.66
	for x in [-3.25,3.25]:
		disc(self,Vector3(x,0.56,0),0.38,1.15,Color("432c20"))
		block(self,Vector3(x,0.10,0),Vector3(1.6,0.16,2.1),Color("523724"))
	# Leather, walnut and brass surround textured bottle-green felt.
	oval(Vector3(0,1.02,0),6.05,0.42,Color("583927"))
	oval(Vector3(0,1.25,0),6.01,0.075,GOLD,0.59,0.6)
	oval(Vector3(0,1.36,0),5.94,0.22,Color("35251e"))
	oval(Vector3(0,1.49,0),5.57,0.045,Color("bb8b49"),0.586,0.4)
	var felt = oval(Vector3(0,1.52,0),5.48,0.045,Color("205747"),0.585)
	var fm = mat(Color("205747")).duplicate()
	var noise = FastNoiseLite.new()
	noise.frequency = 0.48
	noise.fractal_octaves = 2
	var texture = NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.as_normal_map = true
	texture.bump_strength = 0.18
	fm.normal_enabled = true
	fm.normal_texture = texture
	fm.uv1_scale = Vector3(10,10,10)
	felt.material_override = fm
	var betting_line = ring(self,Vector3(0,1.554,0),4.37,4.393,Color("62866b"))
	betting_line.scale.z = 0.56
	lettering(self,Vector3(0,1.562,-1.65),"P O C K E T   A C E S",31,Color("88a68b"),true)
	lettering(self,Vector3(0,1.562,1.84),"♠   ♥   ♣   ♦",28,Color("88a68b"),true)
	for i in 36:
		var a = TAU*i/36.0
		disc(self,Vector3(cos(a)*5.77,1.487,sin(a)*3.38),0.032,0.026,GOLD,0.7)
	for i in 6:
		var a = TAU*i/6.0+0.3
		var p = Vector3(cos(a)*5.73,1.482,sin(a)*3.35)
		disc(self,p,0.18,0.014,Color("b58b4b"),0.65)
		disc(self,p+Vector3(0,0.012,0),0.139,0.017,Color("1b1715"))
	for x in [-5.6,5.6]:
		disc(self,Vector3(x,7.1,-4.2),0.028,3.0,GOLD,0.5)
		var shade = MeshInstance3D.new()
		var cone = CylinderMesh.new()
		cone.top_radius = 0.22
		cone.bottom_radius = 1.05
		cone.height = 0.63
		shade.mesh = cone
		shade.material_override = mat(Color("244f40"),0.2)
		shade.position = Vector3(x,5.7,-4.2)
		add_child(shade)
		ring(self,Vector3(x,5.38,-4.2),0.98,1.05,GOLD)
		var light = OmniLight3D.new()
		light.position = Vector3(x,5.1,-4.0)
		light.light_color = Color("ffcd87")
		light.light_energy = 0.65
		light.omni_range = 10
		add_child(light)
	pieces = Node3D.new()
	add_child(pieces)
func chip_stack(parent: Node3D, pos: Vector3, count: int, color: Color) -> void:
	for i in count:
		var p = pos+Vector3(0,i*0.066,0)
		disc(parent,p,0.18,0.06,color)
		for j in 4:
			var a = j*PI/2.0
			var mark = block(parent,p+Vector3(cos(a)*0.155,0.005,sin(a)*0.155),Vector3(0.065,0.058,0.045),CREAM)
			mark.rotation.y = -a
	if count > 0:
		disc(parent,pos+Vector3(0,(count-1)*0.066+0.033,0),0.118,0.008,CREAM)
		disc(parent,pos+Vector3(0,(count-1)*0.066+0.039,0),0.096,0.006,color)
func card(parent: Node3D, pos: Vector3, value: int, deal: bool = false, small: bool = false) -> Node3D:
	var root = Node3D.new()
	root.position = pos
	parent.add_child(root)
	root.scale = Vector3.ONE * (0.69 if small else 1.0)
	block(root,Vector3(0,-0.02,0.025),Vector3(0.96,0.028,1.36),Color("143c30"))
	block(root,Vector3.ZERO,Vector3(0.93,0.032,1.32),CREAM)
	if value < 0:
		block(root,Vector3(0,0.02,0),Vector3(0.81,0.009,1.18),Color("7b3231"))
		for z in 5:
			for x in 3:
				var diamond = block(root,Vector3((x-1)*0.22,0.026,(z-2)*0.22),Vector3(0.095,0.003,0.095),Color("b57a54"))
				diamond.rotation.y = PI/4
	else:
		var red = int(value/13) in [1,2]
		var ink = Color("aa3334") if red else Color("25302c")
		var rank = ["2","3","4","5","6","7","8","9","10","J","Q","K","A"][value%13]
		var suit = ["♣","♦","♥","♠"][int(value/13)]
		lettering(root,Vector3(-0.29,0.025,-0.42),rank,32,ink,true)
		lettering(root,Vector3(0,0.027,0.03),suit,77,ink,true)
		var reverse = lettering(root,Vector3(0.29,0.025,0.42),rank,26,ink,true)
		reverse.rotation.y = PI
	if deal:
		root.position = Vector3(4.4,1.9,-0.6)
		var tween = root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(root,"position",pos,0.38)
	return root
func show_state(state: Dictionary, new_deal: bool = false, previous_board_count: int = 0) -> void:
	for n in pieces.get_children():
		pieces.remove_child(n)
		n.queue_free()
	for i in 5:
		if i < state.board.size():
			card(pieces,Vector3((i-2)*1.06,1.61,-0.28),state.board[i],i >= previous_board_count)
		else:
			block(pieces,Vector3((i-2)*1.06,1.552,-0.28),Vector3(0.94,0.006,1.32),Color("2b6351"))
	for i in 3:
		chip_stack(pieces,Vector3((i-1)*0.43,1.6,0.99),clampi(int(state.pot/20)-i*3,0,6),[Color("b75344"),GOLD,Color("477f9a")][i])
	var seats = [Vector3(-4.6,0,2.42),Vector3(0,0,3.74),Vector3(4.6,0,2.42),Vector3(4.6,0,-2.48),Vector3(0,0,-3.82),Vector3(-4.6,0,-2.48)]
	var arrangements = {2:[0,2], 3:[0,2,4], 4:[0,2,3,5], 5:[0,1,2,3,5], 6:[0,1,2,3,4,5]}
	var order = arrangements.get(state.players.size(), range(state.players.size()))
	for i in state.players.size():
		var p = state.players[i]
		var pos: Vector3 = seats[order[i]]
		var color = Color.from_string(p.color,Color("7ed4b4"))
		if p.folded: color = color.darkened(0.5)
		var chair = Node3D.new()
		chair.position = pos*1.16
		pieces.add_child(chair)
		chair.look_at(Vector3(0,0,0))
		disc(chair,Vector3(0,0.70,0),0.60,0.18,Color("622e29"))
		disc(chair,Vector3(0,0.59,0),0.62,0.08,Color("9b713e"))
		block(chair,Vector3(0,1.05,0.44),Vector3(0.99,0.82,0.15),Color("4e3021"))
		block(chair,Vector3(0,1.06,0.34),Vector3(0.79,0.61,0.10),Color("783b31"))
		for x in [-0.4,0.4]:
			for z in [-0.35,0.35]: block(chair,Vector3(x,0.3,z),Vector3(0.10,0.60,0.10),Color("493020"))
		# Soft toy-like saloon regulars, facing the table instead of the camera.
		var jacket = ball(chair,Vector3(0,1.03,0),0.38,color.darkened(0.23))
		jacket.scale = Vector3(1.0,1.12,0.8)
		var skin = [Color("c68e62"),Color("e1b78b"),Color("986648"),Color("cfa37b")][i%4]
		ball(chair,Vector3(0,1.61,-0.03),0.30,skin)
		disc(chair,Vector3(0,1.85,-0.03),0.43,0.065,Color("4b382a"))
		disc(chair,Vector3(0,1.97,-0.03),0.27,0.24,Color("69503a"))
		disc(chair,Vector3(0,1.90,-0.03),0.276,0.066,color.darkened(0.22))
		for eye in [-0.11,0.11]: ball(chair,Vector3(eye,1.65,-0.3),0.028,DARK)
		for side in [-1,1]:
			var arm = ball(chair,Vector3(side*0.31,1.08,-0.20),0.14,color.darkened(0.23))
			arm.scale = Vector3(1,1.2,1.7)
			ball(chair,Vector3(side*0.29,1.13,-0.4),0.11,skin)
		if p.turn: ring(pieces,pos*1.16+Vector3(0,0.035,0),0.69,0.76,GOLD)
		var inner = pos*0.77
		if not p.folded:
			for c in 2:
				var face = p.cards[c] if p.cards.size() == 2 else -1
				var held = card(pieces,Vector3(inner.x+(c-0.5)*0.48,1.6,inner.z),face,new_deal,true)
				held.rotation.y = -0.10 if c == 0 else 0.10
		chip_stack(pieces,Vector3(inner.x+0.70,1.6,inner.z+0.1),clampi(int(p.chips/120),1,7) if p.chips > 0 else 0,color)
		if p.dealer:
			disc(pieces,Vector3(inner.x-0.73,1.6,inner.z),0.2,0.08,CREAM)
			lettering(pieces,Vector3(inner.x-0.73,1.65,inner.z),"D",24,DARK,true)
		var label_pos = pos*1.13 + Vector3(0,2.7,0)
		if pos.z < 0: label_pos.y = 2.85
		lettering(pieces,label_pos,p.name,43,GOLD if p.turn else CREAM)
		lettering(pieces,label_pos+Vector3(0,-0.38,0),str(p.chips),34,color)
		if p.turn: lettering(pieces,label_pos+Vector3(0,0.34,0),"▼",28,GOLD)
		if not p.action.is_empty(): lettering(pieces,label_pos+Vector3(0,-0.72,0),str(p.action).to_upper(),20,Color("c9b99a"))
		if p.paid > 0: lettering(pieces,Vector3(inner.x,1.63,inner.z + (-0.62 if pos.z > 0 else 0.62)),str(p.paid),25,GOLD,true)




