extends Node
class_name ASA

# The "Adaptive Stalker Agent"

""" Variable order markov model (VOMM)
for determining player movement through rooms
takes room transitions from "inputTransition", looks through it removing any poisonous patterns 
"""
"""______________________________________________________________________________________________________"""
signal roomTransition(name: String, context: String)

@export var max_order : int = 5 # maximum size of a pattern
@export var decay_rate : float = 0.995 # decays patterns
@export var decay_period : float = 60*30*1*1 # (frame<=60)*(sec<=60)*(min<=60)*(hr<24)
var decay_timer := decay_period # active timer for decaying data
@export var min_stability_threshold : float = 0.6 # minimum amount needed for confidence of interception
@export var min_observations : int = 2 # minimum before is begins taking the pattern into account

var _is_decaying : bool
var _is_inserting : bool

var _contextList:=["calm", "chase", "Trash"]

# the input of rooms and doors
var _input := []

func inputTransition(name: String, context: String="calm"):
	if not _contextList.has(context):
		push_warning("given context \""+context+"\" not found, defaulting to \"Trash\"")
	
	if _input[-1]!=name: # just in case of [A,A-B_#,A-B_#] or [A,A-B_#,B,B]
		_input.append(name)
		_input=_clean_with_rewind(_input, context)
	if _input.size()>=30:
		var insertion=_input.slice(0,5)
		_input=_input.slice(_input.size()-24, _input.size())
	pass

""" cuts out poisonous patterns
['?','?-A_#','A','A-B_#','B','A-B_#','A'] --(cut)--> ['?','?-A_#','A']
	      ['?','?-A_#','A', 'A-B_#', 'A'] --(cut)--> ['?','?-A_#','A']
					['?','?-A_#','A','A'] --(cut)--> ['?','?-A_#','A'] (if it gets through the first check)
					['?','?-A_#','?-A_#'] --(cut)--> ['?','?-A_#'] (if it gets through the first check)
"""
func _clean_with_rewind(input:Array, context: String) -> Array:
	var path:=input.duplicate(true) #deep copy the input list into it
	
	if path.size()>=2 && path[-1]==path[-2]: # cuts out [A,A] or [A-B_#,A-B_#]
		path=path.slice(0,path.size()-1)
	
	if path[-1].contains("-"): #checks if the input is a room transition (door/teleporter)
		return path
	
	if path.size()>=5 && path[-1]==path[-5]: # cuts out [A,A-B,B,A-B,A]
		if context=="chase" && path[-2]!=path[-4]: # tell the nemesis that it's being looped
			print("loop") # placeholder
			pass # NEEDS IMPLEMENTATION OF MDP
		elif context=="chase" && path[-2]==path[-4]:
			path=path.slice(0, path.size()-4)
		elif context=="calm":
			path=path.slice(0, path.size()-4)
	elif path.size()>=3 && path[-1]==path[-3]: # cuts out [A,A-B,A] repeats
		path=path.slice(0,path.size()-2)
	
	return path


# stores door history to support ambush/interception faculties
var DoorHistory := {}
""" the structure ▼
{
	'A|B':{"A-B_1":#, "A-B_2":#}
}
"""
func _record_DoorHistory():
	pass

# previous room history; should use this for prediction and insertion
var History := []

# model[context][prefix][next_token] = float_count
# EX:  model['calm']['E|D|C|B']['A'] = float_count
var model := {}

""" the structure ▼
{
'calm':{
	'A':{B=#},
	'B|A':{C=#},
	'C|B|A':{D=#},
	'D|C|B|A':{E=#},
	'E|D|C|B|A':{F=#}
	'B':{C=#},
	'C|B':{D=#}
	...},
'chasing':
	'G':{},
	'R|G':{},
	'P|R|G':{},
	'T':{},
	'M|T':{},
	...
}
"""

# track total transitions per prefix
var prefix_totals := {}

# runs every frame; decay
func _process(delta: float) -> void:
	if _is_inserting || _is_decaying:
		return
	if decay_timer <= 0:
		_decay_all()
		print("decayed") # TESTING
		decay_timer=decay_period
	decay_timer=decay_timer-1

# turns the list of rooms into a prefix key 
func _make_key(prefix: Array) -> String:
	return "|".join(prefix)

# inserting data into the context array
#		need to figure out how to ensure that movement data during combat data doesn't get recorded
func _insert(sequence: Array, context: String = "calm", weight: float = 1.0) -> void:
	_is_inserting=true
	if sequence.size() < max_order-1:
		return
	
	if not model.has(context):
		model[context] = {}
		prefix_totals[context] = {}
	
	for order in range(1, min(max_order, sequence.size())):
		var prefix = sequence.slice(sequence.size() - order - 1, sequence.size() - 1)
		var next_token = sequence[-1]
		
		var key = _make_key(prefix)
		
		if not model[context].has(key):
			model[context][key] = {}
			prefix_totals[context][key] = 0.0
		
		model[context][key][next_token] = \
			model[context][key].get(next_token, 0.0) + weight
		
		prefix_totals[context][key] += weight
	_is_inserting=false

# gets the probability of that room being next
func _compute_probabilities(context: String, key: String) -> Dictionary:
	# gets the count of each prefix's token and then divides equaliy by the total tokens in the dict
	var result := {}
	
	var total = prefix_totals[context][key]
	
	if total <= 0:
		return result
	
	for token in model[context][key]:
		result[token] = model[context][key][token] / total
	
	return result

# predicts the very next room based on the context(calm, chasing, combat)
func predict(history: Array, context: String = "calm") -> Dictionary:
	if not model.has(context):
		return {}
	
	var prediction:={}
	var weight_total:=0.0
	
	# max_depth = whichever is smaller, the history size or the max order
	var max_depth = min(max_order, history.size())
	
	# goes through the history to find matching patterns throughout the whole depth
	for order in range(1, max_depth+1):
		var prefix = history.slice(history.size() - order, history.size())
		var key = _make_key(prefix)
		
		if model[context].has(key):
			var probs = _compute_probabilities(context, key)
			
			# higher orders have heavier weight
			var weight=float(order)/float(max_depth)
			# var weight=stability(prefix) * (order/max_depth) # do not use yet NOT IMPLEMENTED
			weight *= clamp(prefix_totals[context][key]/min_observations, 0, 1)
			
			# 
			for token in probs: 
				prediction[token] = prediction.get(token, 0.0) + probs[token] * weight
			
			weight_total+=weight
	
	if weight_total > 0:
		for token in prediction:
			prediction[token]/=weight_total
	return prediction

# predicts the most likely future muvements the player will make up to <steps>
func predict_n_steps(history: Array, steps: int, context: String = "calm") -> Array:
	var simulated_history = history.duplicate()
	var result := []
	
	for i in range(steps):
		var probs = predict(simulated_history, context)
		
		if probs.is_empty():
			break
		
		var next_token = _get_highest_probability(probs)
		
		result.append(next_token)
		simulated_history.append(next_token)
		
		if simulated_history.size() > max_order:
			simulated_history.pop_front()
	
	return result

# takes in an array of key: probability and selects the best one
#		needs work to make it so it doesn't choose the FIRST highest probability
func _get_highest_probability(prob_dict: Dictionary) -> String:
	var best_token := ""
	var best_value := -1.0
	
	for token in prob_dict:
		if prob_dict[token] > best_value:
			best_value = prob_dict[token]
			best_token = token
	
	return best_token

# how confident is the model that the next move is actually predictable
func _get_stability(context: String, history: Array) -> float:
	"""
	dominance = max_probability
	entropy = -Σ(p * log(p))
	normalized_entropy = entropy / log(n)
	confidence = 1 - normalized_entropy
	stability = dominance * confidence
	"""
	
	if not model.has(context):
		return 0.0

	var probs = predict(history, context)
	if probs.is_empty():
		return 0.0

	var dominance := 0.0
	var entropy := 0.0
	var n := probs.size()

	for token in probs:
		var p = probs[token]
		dominance = max(dominance, p)
		if p > 0:
			entropy -= p * log(p)

	if n <= 1:
		return dominance

	var max_entropy = log(n)
	var normalized_entropy = entropy / max_entropy

	var confidence = 1.0 - normalized_entropy

	return dominance * confidence


# method to handle decaying all of the hashmap values
#		decays patterns that arent used
func _decay_all():
	_is_decaying = true
	
	var contexts = model.keys()
	for context in contexts: # loop through contexts "calm" "chased"
		var prefixes = model[context].keys()
		for key in prefixes: # loop through the prefix keys "A" "A|B"
			
			var tokens = model[context][key].keys()
			
			var new_total := 0.0
			
			for token in tokens:
				model[context][key][token] *= decay_rate
				
				if model[context][key][token] / prefix_totals[context][key] < 0.01:
					model[context][key].erase(token)
				else:
					new_total += model[context][key][token]
			
			# update prefix total safely
			prefix_totals[context][key] = new_total
			
			# if prefix empty → remove it
			if model[context][key].is_empty():
				model[context].erase(key)
				prefix_totals[context].erase(key)
		
		# if context empty → remove it
		if model[context].is_empty():
			model.erase(context)
			prefix_totals.erase(context)
	
	_is_decaying = false
