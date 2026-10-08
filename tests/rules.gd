extends SceneTree
const Rules = preload("res://rules.gd")
var checks = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL: " + label)
		quit(1)
		assert(ok, label)

func roster(count: int) -> Array:
	var out: Array = []
	for i in count: out.append({"id":str(i),"name":"Player %d" % i})
	return out

func action(g, kind: String, amount: int = 0) -> String:
	return g.act(g.players[g.turn].id,{"action":kind,"amount":amount,"revision":g.revision})

func _initialize() -> void:
	# Encodings: clubs 0..12, diamonds 13..25, hearts 26..38, spades 39..51.
	var hands = [
		[0,3,7,22,37], [12,25,3,7,34], [12,25,11,24,3], [12,25,38,3,7],
		[12,0,14,28,42], [0,3,7,9,12], [12,25,38,3,16], [12,25,38,51,0], [8,9,10,11,12]]
	for i in hands.size():
		check(int(Rules.score(hands[i]) / 759375) == i, "hand class %d" % i)
		if i > 0: check(Rules.score(hands[i]) > Rules.score(hands[i-1]),"hand ranking")
	check(Rules.score([12,0,14,28,42]) < Rules.score([0,14,28,42,4]),"wheel is five high")
	check(Rules.score([12,25,11,7,3]) > Rules.score([12,25,10,7,3]),"pair kicker")
	check(Rules.score([8,9,10,11,12,25,38]) == Rules.score(hands[8]),"best five from seven")
	var g = Rules.new()
	g.setup(roster(2),1000,20,1)
	check(g.turn == g.dealer,"heads up dealer acts first")
	check(g.pot() == 30,"blinds")
	check(g.act("stranger",{"action":"fold","revision":g.revision}) != "","reject unknown player")
	check(action(g,"check") != "","cannot check facing blind")
	check(action(g,"raise",21) != "","minimum raise")
	check(action(g,"raise",1001) != "","insufficient chips")
	check(g.act(g.players[g.turn].id,{"action":"raise","amount":40.5,"revision":g.revision}) != "","fractional chips")
	var old = g.revision
	check(action(g,"call") == "","call")
	check(g.act(g.players[g.turn].id,{"action":"check","revision":old}) != "","replayed action rejected")
	check(action(g,"check") == "","big blind option")
	check(g.board.size() == 3 and g.turn != g.dealer,"flop and heads up order")
	for p in g.public_view().players: check(p.cards.is_empty(),"public hand hidden")
	var private = g.private_view("0")
	check(private.you.cards == g.players[0].cards,"own private hand")
	for p in private.players: check(not p.has("cards"),"no opponent cards on phone")
	check(g.private_view("outsider").is_empty(),"no outsider view")
	# Short all-in raises don't reopen betting for a player who already acted.
	g.setup(roster(3),1000,20,2)
	g.players[2].chips = 45 # BB already contributed 20, total cap 65.
	check(action(g,"raise",60) == "","full raise")
	check(action(g,"call") == "","caller")
	check(action(g,"raise",65) == "","short all-in raise")
	check(not g.legal(g.turn).raise,"short raise does not reopen original raiser")
	check(action(g,"call") == "","short raise call")
	check(not g.legal(g.turn).raise,"short raise does not reopen caller")
	g.setup(roster(4),1000,20,2)
	g.players[1].chips = 70
	g.players[2].chips = 80
	check(action(g,"raise",60) == "","raise before cumulative short raises")
	check(action(g,"call") == "","caller before cumulative short raises")
	check(action(g,"raise",80) == "","first short raise")
	check(action(g,"raise",100) == "","second short raise")
	check(g.legal(g.turn).raise,"cumulative full raise reopens betting")
	# Side pots: short stack wins main, medium stack wins side, unmatched returned.
	g.setup(roster(3),1000,20,3)
	g.board = [0,14,28,46,9]
	g.players[0].cards = [12,25]
	g.players[1].cards = [11,24]
	g.players[2].cards = [10,23]
	for i in 3:
		g.players[i].total = [100,200,300][i]
		g.players[i].chips = 1000-g.players[i].total
	g.settle()
	check(g.players[0].chips == 1200,"main pot winner")
	check(g.players[1].chips == 1000,"side pot winner")
	check(g.players[2].chips == 800,"uncalled excess returned")
	# Board plays: ties split, odd chip left of dealer.
	g.setup(roster(3),1000,20,4)
	g.board = [8,9,10,11,12]
	for i in 3:
		g.players[i].cards = [13+i*2,14+i*2]
		g.players[i].chips = 999
		g.players[i].total = 1
	g.players[2].folded = true
	g.settle()
	check(g.players[0].chips == 1000 and g.players[1].chips == 1001,"odd chip ordering")
	# Fast fold ends without exposing the winner's cards.
	g.setup(roster(2),1000,20,5)
	action(g,"fold")
	check(g.over,"uncontested pot ends hand")
	for p in g.public_view().players: check(p.cards.is_empty(),"uncontested hand stays hidden")
	g.new_hand()
	check(g.hand == 2 and not g.over,"continuous play")
	# Hundreds of full random hands: legal choices terminate, chips conserved.
	var rng = RandomNumberGenerator.new()
	rng.seed = 87
	for n in range(2,7):
		for seed_value in 80:
			g.setup(roster(n),1000,20,seed_value)
			var used: Array = []
			for p in g.players: used.append_array(p.cards)
			var moves = 0
			while not g.over and moves < 400:
				var options = g.legal(g.turn)
				var kind = "check" if options.check else "call"
				var roll = rng.randf()
				if roll < 0.15: kind = "fold"
				elif roll < 0.4 and options.raise: kind = "raise"
				var amount = options.max if roll < 0.2 else options.min
				check(action(g,kind,amount) == "","generated legal move")
				moves += 1
			check(g.over,"hand terminates")
			var total = 0
			for p in g.players:
				total += p.chips
				check(p.chips >= 0,"nonnegative chips")
			check(total == n*1000,"chip conservation")
			used.append_array(g.board)
			var unique = {}
			for c in used: unique[c] = true
			check(unique.size() == used.size(),"no duplicate cards")
	print("POCKET_ACES_RULES_PASS: %d checks, 400 complete random hands" % checks)
	quit(0)
