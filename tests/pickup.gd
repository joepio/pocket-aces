extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var pickup = load("res://phone_pickup.gd").new()
	var room := {"room":{"pending":[{"id":"clover","profile":{"display_name":"Clover"}}, {"id":"fig","profile":{"display_name":"Fig"}}]},"linked":[]}
	pickup.update_links(room)
	check(pickup.input_for_player("one", {"buttons":1}, true).is_empty(), "Held launch button cannot claim a phone")
	pickup.input_for_player("one", {"buttons":0}, true)
	pickup.input_for_player("two", {"buttons":0}, true)
	pickup.input_for_player("two", {"buttons":1 << 13}, true)
	check(pickup.choice("one").id == "clover" and pickup.choice("two").id == "fig", "Controllers have independent profile selections")
	check(pickup.input_for_player("two", {"buttons":1}, true) == "fig", "A claims the profile selected by that controller")
	pickup.start("fig", "two")
	check(pickup.input_for_player("one", {"buttons":1}, true).is_empty(), "Parallel claims wait for confirmation")
	pickup.update_links({"room":{"pending":[room.room.pending[0]]},"linked":["two"]})
	check(pickup.busy_ticket.is_empty(), "Claim ends only when linked and waiting ticket is removed")
	pickup.input_for_player("two", {"buttons":0}, true)
	check(pickup.input_for_player("two", {"buttons":1}, true).is_empty(), "Already linked controller cannot take someone else's profile")
	pickup.input_for_player("one", {"buttons":0}, false)
	check(pickup.input_for_player("one", {"buttons":1}, false).is_empty(), "Ineligible seat cannot claim")
	pickup.reset_inputs()
	check(pickup.input_for_player("one", {"buttons":1}, true).is_empty(), "Resume requires release before pickup")
	pickup.start("clover", "one")
	pickup.deadline = 0
	pickup.poll_timeout()
	check(pickup.busy_player.is_empty() and pickup.notice.contains("try again"), "Timed-out claim visibly recovers")
	print("POCKET_ACES_PICKUP_", "PASS" if failures == 0 else "FAIL")
	quit(failures)
