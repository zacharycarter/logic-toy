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

  # Check if fact already exists
  let exists = vm.states[stateIndex].facts[predicate].anyIt(it == factToAdd)

  if not exists:
    vm.states[stateIndex].facts[predicate].add(factToAdd)
    debug("Added fact: ", factToAdd.relation.predicate, " at time ", factToAdd.time)
    debug("  State[", stateIndex, "] now has ", vm.states[stateIndex].facts.len, " predicates")
    for pred, facts in vm.states[stateIndex].facts:
      debug("    ", pred, ": ", facts.len, " facts")

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

  # Clear the state we'll use for the next time step
  vm.states[nextStateIndex].facts.clear()
  vm.states[nextStateIndex].time = vm.currentTime + 1

  debug("Cleared state[", nextStateIndex, "] for next time step")

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
  var numNewFactsDerived = 0
  var trial = 0

  # Try to derive new facts
  while true:
    numNewFactsDerived = 0
    for rule in vm.rules:
      if trial < rule.maxEvalCountPerTime:
        let newFacts = evaluateRule(rule, vm.currentTime, vm.states)
        for fact in newFacts:
          # Check if fact already exists
          let stateIndex = vm.currentTime mod vm.states.len
          let predicate = fact.relation.predicate

          if not vm.states[stateIndex].facts.hasKey(predicate) or
             not vm.states[stateIndex].facts[predicate].anyIt(it == fact):
            vm.addFact(fact)
            numNewFactsDerived += 1
    trial += 1
    if not (numNewFactsDerived > 0 and trial < 100):  # Limit iterations
      break

  # Prepare for next time step
  vm.deleteOldFacts()
  vm.currentTime += 1
