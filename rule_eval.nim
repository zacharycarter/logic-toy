import std/[logging, tables, sets],
       vm_types

# Environment for rule evaluation - tracks variables and bindings
type
  Binding = object
    variable: string
    value: Term

  Environment = seq[Binding]

# Check if a variable is bound in the environment
proc isBound(env: Environment, varName: string): bool =
  for binding in env:
    if binding.variable == varName:
      return true
  return false

# Get the value of a bound variable
proc getValue(env: Environment, varName: string): Term =
  for binding in env:
    if binding.variable == varName:
      return binding.value
  raise newException(ValueError, "Variable not bound: " & varName)

# Add a new binding
proc addBinding(env: var Environment, varName: string, value: Term): bool =
  # Check if already bound to a different value
  if isBound(env, varName):
    let existingValue = getValue(env, varName)
    if existingValue.kind == tkConstant and value.kind == tkConstant and
       existingValue.value != value.value:
      return false  # Inconsistent binding
    return true  # Already bound to same value

  # Add new binding
  env.add(Binding(variable: varName, value: value))
  return true

# Match a term against a fact term
proc matchTerm(term: Term, factTerm: Term, env: var Environment): bool =
  case term.kind:
  of tkVariable:
    # Variable can match anything if not already bound differently
    if isBound(env, term.name):
      let boundValue = getValue(env, term.name)
      return matchTerm(boundValue, factTerm, env)
    else:
      return addBinding(env, term.name, factTerm)
  of tkConstant:
    # Constants must match exactly
    if factTerm.kind != tkConstant:
      return false
    return term.value == factTerm.value

# Match a relation against a fact
proc matchRelation(relation: Relation, fact: Fact, env: var Environment): bool =
  # Debug output
  debug("  Matching relation ", relation.predicate, " against fact ", fact.relation.predicate)

  # Print arguments
  debug("  Relation args (", relation.args.len, "):")
  for i, arg in relation.args:
    case arg.kind:
    of tkConstant:
      debug("    ", i, ": Const ", arg.value)
    of tkVariable:
      debug("    ", i, ": Var ", arg.name)

  debug("  Fact args (", fact.relation.args.len, "):")
  for i, arg in fact.relation.args:
    case arg.kind:
    of tkConstant:
      debug("    ", i, ": Const ", arg.value)
    of tkVariable:
      debug("    ", i, ": Var ", arg.name)

  # Predicate must match
  if relation.predicate != fact.relation.predicate:
    debug("  Predicates don't match")
    return false

  # Arguments must match
  if relation.args.len != fact.relation.args.len:
    debug("  Argument counts don't match: ", relation.args.len, " vs ", fact.relation.args.len)
    return false

  # Match each argument
  var tempEnv = env  # Use temp environment to avoid partial matches
  for i in 0..<relation.args.len:
    if not matchTerm(relation.args[i], fact.relation.args[i], tempEnv):
      debug("    Arg ", i, " doesn't match")
      return false

  # Debug the environment
  debug("    Match successful! Env: ", tempEnv)

  # Copy successful bindings
  env = tempEnv
  return true

# Evaluate a rule against current facts
# # Add these for debugging
proc evaluateRule*(rule: Rule, currentTime: int, states: seq[State]): seq[Fact] =
  result = @[]
  debug("Evaluating rule with conclusion: ", rule.conclusion.predicate)

  # Debug current state
  let stateIndex = currentTime mod states.len
  debug("Current time: ", currentTime, " using state index: ", stateIndex)
  debug("State contains predicates: ")
  for pred, facts in states[stateIndex].facts:
    debug("  ", pred, ": ", facts.len, " facts")

  # Start with empty environment
  var initialEnv: Environment = @[]

  # Recursive function to match conditions
  proc matchConditions(condIndex: int, env: Environment, currTime: int,
                    stateSeq: seq[State]): seq[Environment] =
    if condIndex >= rule.conditions.len:
      debug("  All conditions matched with env: ", env)
      return @[env]  # All conditions matched

    let condition = rule.conditions[condIndex]
    debug("  Trying condition[", condIndex, "]: ", condition.predicate,
         " with ", condition.args.len, " args")
    var matchedEnvs: seq[Environment] = @[]

    # Get time offset for this condition
    let timeOffset = condition.timeOffset
    let targetTime = currTime + timeOffset
    debug("    Target time: ", targetTime)
    let stateIndex = targetTime mod stateSeq.len

    # Skip if time is out of range
    if targetTime < 0 or stateIndex >= stateSeq.len:
      debug("    Time out of range")
      return @[]

    # Check if predicate exists
    if not stateSeq[stateIndex].facts.hasKey(condition.predicate):
      debug("    No facts for predicate: ", condition.predicate)
      if condition.isNegated:
        # Negated condition succeeds if predicate doesn't exist
        return matchConditions(condIndex + 1, env, currTime, stateSeq)
      else:
        return @[]  # No facts for this predicate

    # Try to match against each fact
    var anyMatched = false
    debug("    Examining ", stateSeq[stateIndex].facts[condition.predicate].len, " facts")
    for fact in stateSeq[stateIndex].facts[condition.predicate]:
      # Skip facts from wrong time
      if fact.time != targetTime:
        debug("    Skipping fact with wrong time: ", fact.time)
        continue

      debug("    Trying to match fact: ", fact.relation.predicate)
      # Try to match
      var newEnv = env
      if matchRelation(condition, fact, newEnv):
        debug("      Matched! New env: ", newEnv)
        anyMatched = true
        # Continue with next condition
        let nextMatches = matchConditions(condIndex + 1, newEnv, currTime, stateSeq)
        for nextEnv in nextMatches:
          matchedEnvs.add(nextEnv)
      else:
        debug("      No match")

    # Handle negated conditions
    if condition.isNegated:
      if not anyMatched:
        return matchConditions(condIndex + 1, env, currTime, stateSeq)
      else:
        return @[]

    return matchedEnvs

  # Match all conditions
  let matchedEnvs = matchConditions(0, initialEnv, currentTime, states)
  debug("Found ", matchedEnvs.len, " matching environments")

  # For each matching environment, create a new fact
  for env in matchedEnvs:
    var newFact = Fact(
      relation: Relation(
        predicate: rule.conclusion.predicate,
        args: @[],
        timeOffset: rule.conclusion.timeOffset
      ),
      time: currentTime + rule.conclusion.timeOffset
    )

    # Substitute variables in conclusion
    for arg in rule.conclusion.args:
      case arg.kind:
      of tkVariable:
        if isBound(env, arg.name):
          newFact.relation.args.add(getValue(env, arg.name))
        else:
          # Unbound variables in conclusion become new constants
          newFact.relation.args.add(Term(kind: tkConstant, value: "_" & arg.name))
      of tkConstant:
        newFact.relation.args.add(arg)

    # Add fact to results
    debug("  Creating new fact: ", newFact.relation.predicate)
    result.add(newFact)
