extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.prepare("preview", [{"index":0,"occupant":{"kind":"human","player_id":"one"}}, {"index":1,"occupant":{"kind":"human","player_id":"two"}}], [{"id":"one","name":"Clover","color":"#62d6b2"},{"id":"two","name":"Peaches","color":"#ffad77"}])
	main.live = true
	main.phone_presence("one", true)
	main.phone_message("one", {"action":"ready","ready":true})
	var room_file := OS.get_environment("POCKET_ACES_ROOM_FIXTURE")
	if not room_file.is_empty(): main.setup_ui.set_room(JSON.parse_string(FileAccess.get_file_as_string(room_file)))
	main.setup_ui.update_setup(main.phone_seats(), true, true, true)
	main.pickup.update_links({"room":{"pending":[{"id":"sample-fig","profile":{"display_name":"Fig"}}]},"linked":["one"]})
	main.setup_ui.set_pickup(main.pickup)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("POCKET_ACES_CAPTURE"))
	quit()
