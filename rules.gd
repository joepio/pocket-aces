extends RefCounted
## Authoritative no-limit Hold'em. Never expose `players` directly to a client.
const STREETS = ["Pre-flop", "Flop", "Turn", "River"]
const HANDS = ["High card", "One pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"]
var players: Array = []
var board: Array = []
var deck: Array = []
var dealer = -1
var turn = -1
var street = 0
var hand = 0
var revision = 0
var bet = 0
var min_raise = 20
var blind = 20
var starting_chips = 1000
var pending: Array = []
var may_raise: Array = []
var acted_at: Dictionary = {}
var over = true
var result = ""
var payouts: Dictionary = {}
var rng = RandomNumberGenerator.new()

func setup(roster: Array, chips: int = 1000, big_blind: int = 20, seed_value: int = -1, deal_now: bool = true) -> void:
	players.clear()
	starting_chips = chips
	blind = big_blind
	dealer = -1
	hand = 0
	revision = 0
	turn = -1
	board.clear()
	deck.clear()
	pending.clear()
	result = ""
	over = true
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	for p in roster.slice(0, 6):
		players.append({"id":str(p.id), "name":str(p.get("name", "Guest")).left(32), "color":p.get("color", "#71d4ba"), "bot":p.get("bot", false), "chips":chips, "cards":[], "folded":false, "paid":0, "total":0, "action":""})
	assert(players.size() >= 2)
	if deal_now: new_hand()

func new_hand() -> void:
	if not over: return
	hand += 1
	revision += 1
	dealer = (dealer + 1) % players.size()
	board.clear()
	deck = range(52)
	for i in range(51, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	for p in players:
		# Casual table: busted players buy back in with free, fictional chips.
		if p.chips == 0: p.chips = starting_chips
		p.cards = [deck.pop_back(), deck.pop_back()]
		p.folded = false
		p.paid = 0
		p.total = 0
		p.action = ""
	street = 0
	over = false
	result = ""
	payouts.clear()
	min_raise = blind
	acted_at.clear()
	var sb = dealer if players.size() == 2 else (dealer + 1) % players.size()
	var bb = (sb + 1) % players.size()
	pay(sb, mini(int(blind / 2), players[sb].chips))
	pay(bb, mini(blind, players[bb].chips))
	players[sb].action = "Small blind"
	players[bb].action = "Big blind"
	bet = blind
	pending = actionable()
	may_raise = pending.duplicate()
	turn = next_in(bb, pending)
	advance_if_done()

func pay(i: int, amount: int) -> void:
	players[i].chips -= amount
	players[i].paid += amount
	players[i].total += amount

func actionable() -> Array:
	var out: Array = []
	for i in players.size():
		if not players[i].folded and players[i].chips > 0: out.append(i)
	return out

func alive() -> Array:
	var out: Array = []
	for i in players.size():
		if not players[i].folded: out.append(i)
	return out

func next_in(after: int, choices: Array) -> int:
	for d in range(1, players.size() + 1):
		var i = (after + d) % players.size()
		if i in choices: return i
	return -1

func legal(i: int) -> Dictionary:
	if over or i != turn: return {}
	var p = players[i]
	var cost = maxi(0, bet - p.paid)
	var opponents = actionable()
	opponents.erase(i)
	var reopened = i in may_raise or bet - int(acted_at.get(i, bet)) >= min_raise
	var can_raise = reopened and not opponents.is_empty() and p.chips > cost
	var maximum = p.paid + p.chips
	return {"fold":true, "check":cost == 0, "call":mini(cost, p.chips), "raise":can_raise, "min":mini(bet + min_raise, maximum), "max":maximum}

func act(id: String, data: Variant) -> String:
	if not data is Dictionary: return "Invalid action."
	if over: return "Wait for the next hand."
	if turn < 0 or players[turn].id != id: return "It is not your turn."
	if data.get("revision", -1) != revision: return "The table changed. Try again."
	var a = str(data.get("action", ""))
	var i = turn
	var p = players[i]
	var options = legal(i)
	match a:
		"fold":
			p.folded = true
			p.action = "Fold"
		"check":
			if not options.check: return "You must call or fold."
			p.action = "Check"
		"call":
			if options.call <= 0: return "There is nothing to call."
			pay(i, options.call)
			p.action = "Call %d" % options.call
		"raise":
			var amount: Variant = data.get("amount")
			if not (amount is int or amount is float): return "Choose a whole chip amount."
			if not is_finite(float(amount)) or float(amount) != floor(float(amount)): return "Choose a whole chip amount."
			if not options.raise or amount < options.min or amount > options.max: return "That raise is not allowed."
			var increment = int(amount) - bet
			if increment >= min_raise:
				min_raise = increment
				may_raise = actionable()
				may_raise.erase(i)
			pay(i, int(amount) - p.paid)
			bet = int(amount)
			pending = actionable()
			p.action = "Raise to %d" % bet
		_:
			return "Unknown action."
	if p.chips == 0 and not p.folded: p.action = "All in"
	pending.erase(i)
	may_raise.erase(i)
	acted_at[i] = bet
	revision += 1
	turn = next_in(i, pending)
	advance_if_done()
	return ""

func advance_if_done() -> void:
	if alive().size() == 1:
		settle()
		return
	var active = actionable()
	# Nobody can bet against an all-in player. Only an outstanding call remains.
	if active.size() <= 1:
		var actual_bet = 0
		for p in players: actual_bet = maxi(actual_bet, p.paid)
		bet = actual_bet
		if active.size() == 1 and players[active[0]].paid < bet and active[0] in pending:
			turn = active[0]
			return
		while board.size() < 5: board.append(deck.pop_back())
		settle()
		return
	if not pending.is_empty(): return
	if street == 3:
		settle()
		return
	street += 1
	for n in (3 if street == 1 else 1): board.append(deck.pop_back())
	for p in players:
		p.paid = 0
		p.action = "All in" if p.chips == 0 else ("Fold" if p.folded else "")
	bet = 0
	min_raise = blind
	acted_at.clear()
	pending = actionable()
	may_raise = pending.duplicate()
	turn = next_in(dealer, pending)

func pot() -> int:
	var total = 0
	for p in players: total += p.total
	return total

func settle() -> void:
	# Layered contribution caps cover side pots and return unmatched overbets.
	var levels: Array = []
	for p in players:
		if p.total > 0 and not p.total in levels: levels.append(p.total)
	levels.sort()
	var prev = 0
	var winners: Array = []
	for level in levels:
		var contributors: Array = []
		var eligible: Array = []
		for i in players.size():
			if players[i].total >= level:
				contributors.append(i)
				if not players[i].folded: eligible.append(i)
		var amount = (level - prev) * contributors.size()
		prev = level
		if contributors.size() == 1:
			players[contributors[0]].chips += amount
			continue
		var best = -1
		var tied: Array = []
		for i in eligible:
			var rank = score(players[i].cards + board) if eligible.size() > 1 else 0
			if rank > best:
				best = rank
				tied = [i]
			elif rank == best: tied.append(i)
		assert(not tied.is_empty())
		var share = int(amount / tied.size())
		var extra = amount % tied.size()
		# Odd chips go clockwise from the dealer.
		for d in range(1, players.size() + 1):
			var i = (dealer + d) % players.size()
			if not i in tied: continue
			var award = share + int(extra > 0)
			extra = maxi(0, extra - 1)
			players[i].chips += award
			payouts[players[i].id] = payouts.get(players[i].id, 0) + award
			if not i in winners: winners.append(i)
	var lines: PackedStringArray = []
	for i in winners:
		lines.append("%s +%d" % [players[i].name, payouts[players[i].id]])
	result = " · ".join(lines)
	if alive().size() > 1 and winners.size() == 1:
		result += "  /  " + hand_name(players[winners[0]].cards + board)
	over = true
	turn = -1
	revision += 1

func public_view() -> Dictionary:
	var seats: Array = []
	for i in players.size():
		var p = players[i]
		# Only showdown reveals non-folded hands. Uncontested hands stay hidden.
		var reveal = over and alive().size() > 1 and not p.folded
		seats.append({"id":p.id, "name":p.name, "color":p.color, "chips":p.chips, "paid":p.paid, "folded":p.folded, "action":p.action, "cards":p.cards.duplicate() if reveal else [], "dealer":i == dealer, "turn":i == turn})
	return {"type":"state", "revision":revision, "hand":hand, "street":"Showdown" if over else STREETS[street], "players":seats, "board":board.duplicate(), "pot":pot(), "over":over, "result":result, "turn":players[turn].name if turn >= 0 else "", "blind":blind}

func private_view(id: String) -> Dictionary:
	var view = public_view()
	# Phones get their hand only; even showdown opponent cards remain on the TV.
	for p in view.players: p.erase("cards")
	for i in players.size():
		if players[i].id == id:
			view["you"] = {"name":players[i].name, "chips":players[i].chips, "cards":players[i].cards.duplicate(), "folded":players[i].folded}
			view["actions"] = legal(i)
			return view
	return {}

static func card_text(card: int) -> String:
	return ["2","3","4","5","6","7","8","9","10","J","Q","K","A"][card % 13] + ["♣","♦","♥","♠"][int(card / 13)]

static func hand_name(cards: Array) -> String:
	return HANDS[int(score(cards) / 759375)]

static func score(cards: Array) -> int:
	var best = -1
	for a in range(cards.size() - 4):
		for b in range(a + 1, cards.size() - 3):
			for c in range(b + 1, cards.size() - 2):
				for d in range(c + 1, cards.size() - 1):
					for e in range(d + 1, cards.size()):
						best = maxi(best, score_five([cards[a],cards[b],cards[c],cards[d],cards[e]]))
	return best

static func score_five(cards: Array) -> int:
	var counts: Dictionary = {}
	var ranks: Array = []
	var flush = true
	for c in cards:
		var rank = c % 13 + 2
		counts[rank] = counts.get(rank, 0) + 1
		ranks.append(rank)
		if int(c / 13) != int(cards[0] / 13): flush = false
	ranks.sort()
	ranks.reverse()
	var straight = 0
	if counts.size() == 5:
		if ranks[0] - ranks[4] == 4: straight = ranks[0]
		elif ranks == [14,5,4,3,2]: straight = 5
	var groups: Array = counts.keys()
	groups.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else a > b)
	var category = 0
	var tie = ranks
	if flush and straight > 0:
		category = 8
		tie = [straight]
	elif counts[groups[0]] == 4:
		category = 7
		tie = groups
	elif counts[groups[0]] == 3 and counts[groups[1]] == 2:
		category = 6
		tie = groups
	elif flush: category = 5
	elif straight > 0:
		category = 4
		tie = [straight]
	elif counts[groups[0]] == 3:
		category = 3
		tie = groups
	elif counts[groups[0]] == 2:
		category = 2 if counts[groups[1]] == 2 else 1
		tie = groups
	var value = category
	for i in 5: value = value * 15 + (tie[i] if i < tie.size() else 0)
	return value
