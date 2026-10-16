extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	var seats := [{"index":0,"occupant":{"kind":"human","player_id":"one"}}, {"index":1,"occupant":{"kind":"human","player_id":"two"}}]
	var profiles := [{"id":"one","name":"Clover"},{"id":"two","name":"Peaches"}]
	main.prepare("ready-test",seats,profiles)
	main.live = true
	main.roster_change(seats, [{"id":"one","name":"Picked Clover","color":"#abcdef"}], [])
	check(main.game.players[0].name == "Picked Clover" and main.game.players[0].color == "#abcdef", "Pickup refreshes the public profile without replacing the seat")
	check(main.game.hand == 0 and main.game.pot() == 0, "No deal or blinds before phones ready")
	check(main.game.players.all(func(p): return p.cards.is_empty()), "No private cards exist before ready")
	main.phone_message("one", {"action":"ready","ready":true})
	check(main.ready_count() == 0,"Offline ready messages cannot start a seat")
	main.phone_presence("one",true)
	main.phone_presence("two",true)
	main.phone_message("stranger", {"action":"ready","ready":true})
	check(main.ready_count() == 0,"Unknown sender cannot ready someone else")
	main.phone_message("one", {"action":"ready","ready":true})
	check(main.game.hand == 0,"One ready phone cannot start table")
	main.phone_presence("one",false)
	check(main.ready_count() == 0,"Final socket disconnect clears readiness")
	main.phone_presence("one",true)
	main.live = false
	for id in ["one","two"]: main.phone_message(id,{"action":"ready","ready":true})
	check(main.game.hand == 0,"Host pause blocks deal even when all ready")
	main.live = true
	main.begin_if_ready()
	check(main.game.hand == 1 and main.game.pot() == 30,"All ready starts exactly one hand with blinds")
	main.begin_if_ready()
	check(main.game.hand == 1,"Repeated ready evaluation does not redeal")
	main.phone_presence("one",false)
	var revision: int = main.game.revision
	main.phone_message("two", {"action":"fold","revision":revision})
	check(main.game.revision == revision,"Missing phone blocks bets")
	var before: float = main.turn_time
	main.last_tick_ms = Time.get_ticks_msec() - 1000
	main._process(1.0)
	check(main.turn_time == before,"Disconnected table freezes turn clock")
	main.phone_presence("one",true)
	check(main.all_connected() and main.game.revision == revision,"Reconnect preserves current hand")
	print("POCKET_ACES_READINESS_", "PASS" if failures == 0 else "FAIL")
	main.free()
	quit(failures)
