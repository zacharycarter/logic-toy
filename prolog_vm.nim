import std/[logging, tables, sets, hashes, sequtils],
       rule_eval, rule_parser, vm_types

type
  # The virtual Prolog machine
  VirtualPrologMachine* = object
    currentTime*: int
    states*: seq[State]
    rules*: seq[Rule]
    lookbackWindow*: int

# Create a new virtual Prolog machine
proc newVirtualPrologMachine*(lookbackWindow: int = 2): VirtualPrologMachine =
  result = VirtualPrologMachine(
    currentTime: 0,
    lookbackWindow: lookbackWindow,
    rules: @[]
  )

  # Initialize states based on lookback window
  result.states = newSeq[State](lookbackWindow)
  for i in 0..<lookbackWindow:
    result.states[i] = State(
      time: 0,  # Set initial time to 0 for all states
      facts: initTable[string, seq[Fact]]()
    )

# Add fact to the current state
proc addFact*(vm: var VirtualPrologMachine, fact: Fact) =
  let stateIndex = vm.currentTime mod vm.states.len
  let predicate = fact.relation.predicate

  # Initialize the predicate's fact list if needed
  if not vm.states[stateIndex].facts.hasKey(predicate):
    vm.states[stateIndex].facts[predicate] = @[]

  # Set the fact's time if not explicitly set
  var factToAdd = fact
  if factToAdd.time == -1:
    factToAdd.time = vm.currentTime

  # Generate hash for quick lookup
  let factKey = factHash(factToAdd)

  # Check for duplicate using the hash index
  if not vm.states[stateIndex].factIndex.hasKey(predicate) or
     not vm.states[stateIndex].factIndex[predicate].contains(factKey):
    # Add to main storage
    vm.states[stateIndex].facts[predicate].add(factToAdd)

    # Add to index
    if not vm.states[stateIndex].factIndex.hasKey(predicate):
      vm.states[stateIndex].factIndex[predicate] = initHashSet[string]()
    vm.states[stateIndex].factIndex[predicate].incl(factKey)

    debug("Added fact: ", factToAdd.relation.predicate, " at time ", factToAdd.time)

# Add a rule to the VM
proc addRule*(vm: var VirtualPrologMachine, rule: Rule) =
  vm.rules.add(rule)

# Parse and add a rule from string
proc addRuleFromString*(vm: var VirtualPrologMachine, ruleStr: string) =
  let rule = parseRule(ruleStr)
  vm.addRule(rule)

# Delete facts that are too old and prepare for next time step
proc deleteOldFacts*(vm: var VirtualPrologMachine) =
  # The next state index (for the future time step) is the one we'll clear
  let nextStateIndex = (vm.currentTime + 1) mod vm.states.len
  let currentStateIndex = vm.currentTime mod vm.states.len

  # Clear the state we'll use for the next time step
  vm.states[nextStateIndex].facts.clear()
  vm.states[nextStateIndex].time = vm.currentTime + 1

  # Propagate facts with default persistence behavior
  for predicate, facts in vm.states[currentStateIndex].facts:
    for fact in facts:
      # Create a new fact with updated time
      var newFact = fact
      newFact.time = vm.currentTime + 1

      # Add the fact to the next state
      if not vm.states[nextStateIndex].facts.hasKey(predicate):
        vm.states[nextStateIndex].facts[predicate] = @[]

      # Avoid duplicates
      let isDuplicate = vm.states[nextStateIndex].facts[predicate].anyIt(
        it.relation.predicate == newFact.relation.predicate and
        it.relation.args.len == newFact.relation.args.len and
        (block:
          var match = true
          for i in 0..<it.relation.args.len:
            if it.relation.args[i] != newFact.relation.args[i]:
              match = false
              break
          match
        )
      )

      if not isDuplicate:
        vm.states[nextStateIndex].facts[predicate].add(newFact)

  debug("Prepared state[", nextStateIndex, "] for next time step with persisted facts")

# Main update loop
proc update*(vm: var VirtualPrologMachine) =
  # Debug state before evaluation
  debug("Before evaluation at time ", vm.currentTime, ":")
  for i in 0..<vm.states.len:
    debug("  State[", i, "] time=", vm.states[i].time, " has ",
         vm.states[i].facts.len, " predicates")
    for pred, facts in vm.states[i].facts:
      debug("    ", pred, ": ", facts.len, " facts")

  # Evaluate rules until no more new facts can be derived
  var totalNewFacts = 0
  var iteration = 0
  const maxIterations = 10  # Avoid infinite loops

  while iteration < maxIterations:
    var numNewFactsDerived = 0

    # Evaluate each rule
    for rule in vm.rules:
      let newFacts = evaluateRule(rule, vm.currentTime, vm.states)
      for fact in newFacts:
        # Check if fact already exists
        let stateIndex = vm.currentTime mod vm.states.len
        let predicate = fact.relation.predicate

        if not vm.states[stateIndex].facts.hasKey(predicate) or
           not vm.states[stateIndex].facts[predicate].anyIt(it == fact):
          vm.addFact(fact)
          numNewFactsDerived += 1

    totalNewFacts += numNewFactsDerived
    iteration += 1

    if numNewFactsDerived == 0:
      break

  debug("Total new facts derived: ", totalNewFacts, " in ", iteration, " iterations")

  # Prepare for next time step
  vm.deleteOldFacts()
  vm.currentTime += 1
