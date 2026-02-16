The Adaptive Stalker Agent (ASA) project focuses on building an AI system that can learn and predict player movement between rooms in a game environment.
In this project, each room represents a state, and player movement is recorded as a sequence of room transitions (“A”, “B”, “C”, “A”).
By analyzing these sequences, the model will learn common paths, repeated routes, and looping behavior.
Unlike a basic first-order Markov model that only considers the last room visited, the Variable-Order approach can look at multiple previous rooms as the “context” to make more informed predictions. 
The AI will use this learned information to predict future room transitions, evaluate the accuracy of those predictions, and determine chase and intercept behavioral states based off of whether it determines if it’s an effective path to take based off environmental gameplay factors like time to intercept, player movement speed, prediction confidence, etc.
