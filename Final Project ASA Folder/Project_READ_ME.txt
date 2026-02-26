The Adaptive Stalker Agent (ASA) project focuses on building an AI system that can learn and predict player movement between rooms in a game environment, then act determine which behavior to take based off of that information.

Variable Order Markov Model (VOMM):
Each room represents a state, and player movement is recorded as a sequence of room transitions (“A”,"A-B_#",“B”,"B-C_#",“C”,"C-A_#",“A”,"A-D_#","D") with pattern context like "calm" or "chased", then record them as an n-gram hash map;
history=(“A”,"A-B_#",“B”,"B-C_#",“C”,"C-A_#",“A”,"A-D_#","D")
model={
    "calm":
        {"A":{"B"=#, "D"=#},
        "A|B":{"C"=#},
        "A|B|C":{"A"=#},
        "A|B|C|A":{"D"=#},
        "B":{"C"=#},
        "B|C":{"A"=#},
        "B|C|A":{"D"=#},
        "C":{"A"=#},
        "C|A":{"D"=#}},
    "chased":
        {...}
}
That data can then be accessed as;   model[<pattern context>][<prefix key>][<next token>]
It will also record the frequency of door transitions between those rooms
door_frequency={
    "A|B":{"A-B_#"=#},
    "B|C":{"B-C_#"=#},
    "C|A":{"C-A_#"=#},
    "A|D":{"A-D_#"=#}
}

By analyzing the frequency of these sequences, the model will learn common paths, repeated routes, and looping behavior.
Unlike a basic first-order Markov model that only considers the last room visited, the Variable-Order approach can look at multiple previous rooms as the “context” to make more informed predictions. 
The model will use this learned information to predict future room transitions, evaluate the accuracy of those predictions.

BEHAVIOR CONTROLER:
This AI will additionally use a lite Markov Decision Process (MDP), to determine its behavioral policy based on the predictions made by the predictive model. The MDP will determine the best behavioral state/policy to take, based off of predicion accuracy, and whether or not its an effective path to take based on factors like time to intercept, player movement speed, prediction confidence, etc.
NOTE: This is designed as an action suggestor, and should NOT be implemented directly into a game entity. The MDP should act like a strategic brain that tells a finite-state-machine what the best course of action would be.

