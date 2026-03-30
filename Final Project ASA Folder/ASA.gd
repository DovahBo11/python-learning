class_name ASA
extends Node

""" The "Adaptive Stalker Agent"
this AI can be used 2 ways
		1: assign as a global script; 
				simple, one brain for one enemy or multiple enemeies to share
		2: make an instance for multiple stalker enemies; 
				varied intellegance, but each takes processing power"""


""" Variable order markov model (VOMM)
for determining player movement through rooms
takes room transitions from "inputTransition", looks through it removing any poisonous/redundant patterns"""
"""_______________________________________________________________________________________________________"""

##max_order controls the maximum (n-gram) depth of a pattern that is saved into the [code]VOMM_model[/code] 
##[br]Default: 6 -> "A|B|C|D|E|F":{"G":#}
@export var max_order : int = 6
##the amount patterns decay by for every [member decay_period] 
##[br] float 0.0 - 1.0 
##[br] default: 0.995 
@export var decay_rate : float = 0.995
##the time in frames for every decay instance 
##[br] [code]decay period = (frame<=60)*(sec<=60)*(min<=60)*(hr<24)[/code]
##[br]default: 60*30*1*1 = 30 seconds
@export var decay_period : float = 60*30*1*1 # (frame<=60)*(sec<=60)*(min<=60)*(hr<24)
##the active internal timer for decaying
##to reset timer: [code]decay_timer=decay_period[/code]
var decay_timer := decay_period
@export var min_stability_threshold : float = 0.6 # minimum amount needed for confidence of interception
@export var min_observations : int = 2 # minimum before is begins taking the pattern into account

##variable to delay behavior & reduce corruption
var _is_decaying : bool
##variable to delay behavior & reduce corruption
var _is_inserting : bool


##the list of available contexts
var _contextList:=["calm", "chase", "Trash"]
##adding a context state for the player in [code]_contextList[/code]
func add_context(new_ContextName: String):
	if _contextList.has(new_ContextName):
		push_error("added context: \""+new_ContextName+"\" already exists in list of contexts")
		return
	_contextList.append(new_ContextName)
##removing a context state for the player from [code]_contextList[/code]
func remove_context(target_ContextName: String):
	if _contextList.is_empty():
		push_error("context list is empty, cannot remove something that doesn't exist")
	if not _contextList.has(target_ContextName):
		push_error("target context: \""+target_ContextName+"\" does not exist in list of contexts")
	_contextList.erase(target_ContextName)

## array used for inputting, verifying, and then inserting transitions
##[br]DO NOT USE DIRECTLY use: [member inputTransition]
var _input := []
##used to input the room and door transitions into [member _input]
func inputTransition(TransitionName: String, context: String="calm"):
	if not _contextList.has(context):
		push_warning("given context: \""+context+"\" not found, defaulting to \"Trash\"")
	
	if _input.is_empty() || _input[-1]!=TransitionName: # just in case of [A,A-B_#,A-B_#] or [A,A-B_#,B,B]
		_input.append(TransitionName)
		_input=_clean_with_rewind(_input, context)
		if _input_rolledBack==false && _insert_delay<=0 && _input.size()>2 && not _input[-1].contains("-"): 
			_insert_DoorHistory(_input[-3],_input[-2],_input[-1]) # prevRoom, door, currentRoom
			if _input.size() >= max(max_order, 5):
				_insert_Input(_input.slice(0, _input.size()-max_order), context)
	if _input.size()>=20:
		_input=_input.slice(_input.size()-20, _input.size())

##delays the insert when [member _input] is [member _clean_with_rewind]
var _insert_delay := 0
##bool variable to check if [member _input] was rolled back during [member _clean_with_rewind]
var _input_rolledBack : bool # checks if it was rolled back so that it doesn't insert arbitrary patterns
##cuts out poisonous patterns and then rewinds the input ▼
##[br]['?','?-A_#','A','A-B_#','B','A-B_#','A'] --(cut)--> ['?','?-A_#','A']
##[br]		   ['?','?-A_#','A', 'A-B_#', 'A'] --(cut)--> ['?','?-A_#','A']
##[br]					 ['?','?-A_#','A','A'] --(cut)--> ['?','?-A_#','A'] (if it gets through the first check)
##[br]					 ['?','?-A_#','?-A_#'] --(cut)--> ['?','?-A_#'] (if it gets through the first check)
##[br]the only exceptions are for rooms with dead ends
func _clean_with_rewind(input:Array, context: String) -> Array:
	var path:=input.duplicate(true) #deep copy the input list into it
	
	if path.size()>=2 && path[-1]==path[-2]: # cuts out [A,A]->[A] in case it somehow makes it past first check
		path=path.slice(0,path.size()-1)
		_input_rolledBack=true
	
	if path[-1].contains("-"): #checks if the input is a room transition (door/teleporter)
		return path
	
	if path.size()>=5 && path[-1]==path[-5] && _is_dead_end(path[-3])==false: # sees [A,A-B_#,B,A-B_#,A]
		if context=="chase" && path[-2]!=path[-4]: # [A,A-B_1,B,A-B_2,A]
			print("loop detected in VOMM") # placeholder
			pass # NEEDS IMPLEMENTATION OF MDP
		elif context=="chase" && path[-2]==path[-4]:
			path=path.slice(0, path.size()-4)
			_input_rolledBack=true
			_insert_delay=5
		elif context=="calm":
			path=path.slice(0, path.size()-4)
			_input_rolledBack=true
			_insert_delay=5
			
	if path.size()>=3 && path[-1]==path[-3]: # cuts out [A,A-B,A] repeats
		path=path.slice(0,path.size()-2)
		_input_rolledBack=true
		_insert_delay=3
	
	_input_rolledBack=false
	_insert_delay-=1
	return path

##used for insurting veryfied and cleaned sequences into the [member VOMM_model] with [member _insert]
var _History := []
# inserts the good cleaned sequences
##inserts the cleaned sequences into [member _History]
func _insert_Input(sequence: Array, context: String):
	var path := []
	
	for token in sequence:
		if not token.contains("-"):
			path.append(token)
	_History=path.duplicate(true)
	
	_insert(_History, context)

##stores door history to support ambush/interception faculties
##[br]the structure ▼
##[br]{
##[br]	'A|B':{"A-B_1":#, "A-B_2":#},
##[br]	'B|R':{"R-B_1":#}
##[br]	'MainHall|2ndMainHall':{"MainHall-2ndMainHall_Staircase1":#, "MainHall-2ndMainHall_Staircase2":#}
##[br]	'2ndMainHall|MainHall':{"MainHall-2ndMainHall_Staircase1":#, "MainHall-2ndMainHall_Staircase2":#}
##[br]}
var _DoorHistory := {}
## inserts the [code]prevRoom[/code] & [code]door[/code] & [code]currentRoom[/code] into [member _DoorHistory]
##[br] "prevRoom|currentRoom":{"door"=#}
func _insert_DoorHistory(prevRoom,door,currentRoom):
	var key=prevRoom+"|"+currentRoom
	
	if not _DoorHistory.has(key):
		_DoorHistory[key]={}
	
	_DoorHistory[key][door]=\
		_DoorHistory.get(door,0)+1


## the array contains the patterns and the number of times they have been used
##[br] VOMM_model[context][prefix][next_token] = float_count
## EX:  VOMM_model['calm']['E|D|C|B']['A'] = float_count
##[br] the structure ▼
##[br]{
##[br]'calm':{
##[br]	"A":{"A-Z":#},
##[br]	"B|A":{},
##[br]	"C|B|A":{},
##[br]	"D|C|B|A":{},
##[br]	"E|D|C|B|A":{}
##[br]	...},
##[br]'chasing':{
##[br]	"G":{""},
##[br]	"R|G":{},
##[br]	"P|R|G":{},
##[br]	...}
##[br]}
var VOMM_model := {}

##works in tandem with the [member VOMM_model], tracks total transitions per prefix
var prefix_totals := {}

# runs every frame; decay
func _process(_delta: float) -> void:
	if _is_inserting || _is_decaying:
		return
	if decay_timer <= 0:
		_decay_all()
		print("decayed") # TESTING
		decay_timer=decay_period
	decay_timer=decay_timer-1

## turns the list of rooms into a prefix key
##[br]used for both making new saved patterns and searching for saved patterns
##[br] [code]VOMM_model[context][prefix]={"future"=#}[/code]
func _make_key(prefix: Array) -> String:
	return "|".join(prefix)

## inserting data into the [member VOMM_model]
#		need to figure out how to ensure that movement data during combat data doesn't get recorded
func _insert(sequence: Array, context: String = "calm", weight: float = 1.0) -> void:
	_is_inserting=true
	if sequence.size() < max_order-1:
		return
	
	if not VOMM_model.has(context):
		VOMM_model[context] = {}
		prefix_totals[context] = {}
	
	for order in range(1, min(max_order, sequence.size())):
		var arr_prefix = sequence.slice(sequence.size() - order - 1, sequence.size() - 1)
		var next_token = sequence[-1]
		
		var prefix = _make_key(arr_prefix)
		
		if not VOMM_model[context].has(prefix):
			VOMM_model[context][prefix] = {}
			prefix_totals[context][prefix] = 0.0
		
		VOMM_model[context][prefix][next_token] = \
			VOMM_model[context][prefix].get(next_token, 0.0) + weight
		
		prefix_totals[context][prefix] += weight
	_is_inserting=false

## gets the probability of that room being next
func _compute_probabilities(context: String, prefix: String) -> Dictionary:
	# gets the count of each prefix's token and then divides equaliy by the total tokens in the dict
	var result := {}
	
	var total = prefix_totals[context][prefix]
	
	if total <= 0:
		return result
	
	for token in VOMM_model[context][prefix]:
		result[token] = VOMM_model[context][prefix][token] / total
	
	return result

## predicts the very next room based on the context
func predict(history: Array = _History, context: String = "calm") -> Dictionary:
	if not VOMM_model.has(context):
		return {}
	
	var prediction:={}
	var weight_total:=0.0
	
	# max_depth = whichever is smaller, the history size or the max order
	var max_depth = min(max_order, history.size())
	
	# goes through the history to find matching patterns throughout the whole depth
	for order in range(1, max_depth+1):
		var arr_prefix = history.slice(history.size() - order, history.size())
		var prefix = _make_key(arr_prefix) #NOTE! key is the prefix that has been turned into string
		
		if VOMM_model[context].has(prefix):
			var probs = _compute_probabilities(context, prefix)
			
			# higher orders have heavier weight
			var weight=_get_stability(prefix, context) * (order/float(max_depth))
			weight *= clamp(prefix_totals[context][prefix]/min_observations, 0, 1)
			
			for token in probs: 
				prediction[token] = prediction.get(token, 0.0) + probs[token] * weight
			
			weight_total+=weight
	
	if weight_total > 0:
		for token in prediction:
			prediction[token]/=weight_total
	return prediction

## predicts the most likely future movements the player will make up to [code]steps[/code]
func predict_n_steps(history: Array = _History, steps: int = 6, context: String = "calm") -> Array:
	
	var simulated_history = history.duplicate(true)
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

## takes in an array of (key:probability) and selects the best one
#		needs work to make it so it doesn't choose the FIRST highest probability
func _get_highest_probability(prob_dict: Dictionary) -> String:
	var best_token := ""
	var best_value := -1.0
	
	for token in prob_dict:
		if prob_dict[token] > best_value:
			best_value = prob_dict[token]
			best_token = token
	
	return best_token

## how confident is the model that the next move is actually predictable, 
## uses [member _History] 
## calculations ▼
##[br]dominance = max_probability
##[br]entropy = -Σ(p * log(p))
##[br]normalized_entropy = entropy / log(n)
##[br]confidence = 1 - normalized_entropy
##[br]stability = dominance * confidence
func _get_stability(prefix: String, context: String) -> float:
	""" calculations ▼
	dominance = max_probability
	entropy = -Σ(p * log(p))
	normalized_entropy = entropy / log(n)
	confidence = 1 - normalized_entropy
	stability = dominance * confidence
	"""
	
	if not VOMM_model.has(context) or not VOMM_model[context].has(prefix):
		return 0.0

	var outcomes = VOMM_model[context][prefix]
	var totalOutcomes:=0.0
	for token in outcomes:
		totalOutcomes += outcomes[token]
	if totalOutcomes==0.0: return 0.0

	var dominance := 0.0
	var entropy := 0.0
	var n = outcomes.size()

	for token in outcomes:
		var p = outcomes[token] / totalOutcomes
		dominance = max(dominance, p)
		if p > 0:
			entropy -= p * log(p)

	if n <= 1:
		return dominance

	var max_entropy = log(n)
	var normalized_entropy = entropy / max_entropy
	var confidence = 1.0 - normalized_entropy

	return dominance * confidence


##method to handle decaying all of the hashmap values
##[br]decays patterns that arent used
func _decay_all():
	_is_decaying = true
	
	var contexts = VOMM_model.keys()
	for context in contexts: # loop through contexts "calm" "chased"
		var prefixes = VOMM_model[context].keys()
		for key in prefixes: # loop through the prefix keys "A" "A|B"
			
			var tokens = VOMM_model[context][key].keys()
			
			var new_total := 0.0
			
			for token in tokens:
				VOMM_model[context][key][token] *= decay_rate
				
				if VOMM_model[context][key][token] / prefix_totals[context][key] < 0.01:
					VOMM_model[context][key].erase(token)
				else:
					new_total += VOMM_model[context][key][token]
			
			# update prefix total safely
			prefix_totals[context][key] = new_total
			
			# if prefix empty → remove it
			if VOMM_model[context][key].is_empty():
				VOMM_model[context].erase(key)
				prefix_totals[context].erase(key)
		
		# if context empty → remove it
		if VOMM_model[context].is_empty():
			VOMM_model.erase(context)
			prefix_totals.erase(context)
	
	_is_decaying = false


"""Markov Decision Process (MDP)
"""
"""_______________________________________________________________________________________________________"""


enum Actions{
	IDLE,
	IDLE_AT_HIGH_TRAFFIC,
	CHASE,
	INTERCEPT,
	INTERCEPT_AMBUSH,# stays and waits
	INTERCEPT_SEARCH,# moves down the predicted path meet up with the target
	SEARCH
}



"""Topology
an additive feature to allow the Agent the ability to understand it's environment"""
"""_______________________________________________________________________________________________________"""
##the AI's knowledge of its surroundings
var _Topology := {
	"rooms":{}, #room name -> { connections: [], tags: {} }
	"doors":{} #door name -> {connections: [], tags: {}}
}
##used to register a room or door into the topology
func register_topology(Name:String, connections:Array=[], tags:Dictionary={}):
	if Name.is_empty():
		push_error("attempting to insert a room with no name")
		return
	if Name.contains("-"):
		if _Topology.doors.has(Name):
			return
		_Topology.doors[Name] = {
			"connections": connections.duplicate(true),
			"tags": tags.duplicate(true)
		}
		return
	elif not Name.contains("-"):
		if _Topology.rooms.has(Name):
			return
		_Topology.rooms[Name] = {
			"connections": connections.duplicate(true),
			"tags": tags.duplicate(true)
		}
		return
	else:
		push_error("attempting to insert a room with invalid name")
##used to delete a registered room or door from the topology
func delete_topology(Name:String):
	if Name.is_empty():
		push_error("attempting to delete a room with no name")
		return
	if _Topology.rooms.contains(Name): 
		_Topology.rooms[Name].erase()
		return
	if _Topology.doors.contains(Name):
		_Topology.doors[Name].erase()
		return
	push_error("attempting to erase a room that does not exist")
##changes the connections and or the tags of a target room
##[br]CURRENTLY NOT IMPLEMENTED
func change_topology(Name:String, connections:Array, tags:Dictionary={}):
	pass
##used to check if that room token is a dead end so the inputted pattern isn't arbitrarily deleted in [member _clean_with_rewind]
func _is_dead_end(room:String):
	if not _Topology.rooms.has(room):
		return false
	if _Topology.rooms[room]["tags"].has("dead_end") && _Topology.rooms[room]["tags"]["dead_end"]==true:
		return true
	if _Topology.rooms[room]["connections"] <= 1:
		return true 
	return false
