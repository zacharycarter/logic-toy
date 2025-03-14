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

# Main update loop
proc update*(vm: var VirtualPrologMachine) =
  # First, increment the current time
  vm.currentTime += 1

  # Prepare the current state
  let stateIndex = vm.currentTime mod vm.states.len
  vm.states[stateIndex].facts.clear()
  if len(vm.states[stateIndex].factIndex) > 0:
    vm.states[stateIndex].factIndex.clear()
  vm.states[stateIndex].time = vm.currentTime

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
  vm.currentTime += 1
