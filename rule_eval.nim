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
  # Predicate must match
  if relation.predicate != fact.relation.predicate:
    debug("  Predicates don't match")
    return false

  # Arguments must match
  if relation.args.len != fact.relation.args.len:
    debug("  Argument counts don't match")
    return false

  # Match each argument
  var tempEnv = env  # Use temp environment to avoid partial matches
  for i in 0..<relation.args.len:
    if not matchTerm(relation.args[i], fact.relation.args[i], tempEnv):
      debug("    Arg ", i, " doesn't match")
      return false

  # Success! Copy the environment
  env = tempEnv
  return true
# Evaluate a rule against current facts
proc evaluateRule*(rule: Rule, currentTime: int, states: seq[State]): seq[Fact] =
  result = @[]
  debug("Evaluating rule with conclusion: ", rule.conclusion.predicate)
  debug("  Rule has ", rule.conditions.len, " conditions")

  for i, condition in rule.conditions:
    debug("  Condition ", i, ": ", condition.predicate,
          " (negated: ", condition.isNegated, ")",
          " timeOffset: ", condition.timeOffset)

  # Start with empty environment
  var initialEnv: Environment = @[]

  # Recursive function to match conditions
  proc matchConditions(condIndex: int, env: Environment, currTime: int,
                    stateSeq: seq[State]): seq[Environment] =
    # Early termination for complete match
    if condIndex >= rule.conditions.len:
      debug("  All conditions matched with env: ", env)
      return @[env]  # All conditions matched

    let condition = rule.conditions[condIndex]
    debug("  Trying condition[", condIndex, "]: ", condition.predicate,
         " (negated: ", condition.isNegated, ")",
         " with ", condition.args.len, " args")
    var matchedEnvs: seq[Environment] = @[]

    # Get time offset for this condition
    let timeOffset = condition.timeOffset
    let targetTime = currTime + timeOffset
    debug("    Target time: ", targetTime)
    let stateTime = targetTime
    var stateIndex = -1
    for i in 0..<stateSeq.len:
      if stateSeq[i].time == stateTime:
        stateIndex = i
        break
    debug("    Looking for state with time=", stateTime, " found at index ", stateIndex)

    # Skip if stateIndex is out of range
    if stateIndex >= stateSeq.len or stateIndex < 0:
      debug("    State index out of range")
      return @[]

    # Check if predicate exists
    if not stateSeq[stateIndex].facts.hasKey(condition.predicate):
      debug("    No facts for predicate: ", condition.predicate)
      if condition.isNegated:
        # For negated conditions, no facts means condition is satisfied
        debug("    Negated condition with no facts - condition satisfied")
        return matchConditions(condIndex + 1, env, currTime, stateSeq)
      else:
        return @[]  # No facts for this predicate

    # If we already have variable bindings, pre-filter facts based on them
    var potentialFacts: seq[Fact] = @[]

    # For each argument that's a bound variable, find facts with matching values
    var boundArgIndices: seq[tuple[index: int, value: string]] = @[]

    for i, arg in condition.args:
      if arg.kind == tkVariable and isBound(env, arg.name):
        let boundValue = getValue(env, arg.name)
        if boundValue.kind == tkConstant:
          boundArgIndices.add((i, boundValue.value))

    # If we have bound arguments, filter by them
    if boundArgIndices.len > 0:
      for fact in stateSeq[stateIndex].facts[condition.predicate]:
        # Skip facts from wrong time
        if fact.time != targetTime:
          continue

        var matches = true

        # Check if fact matches bound variable constraints
        for (idx, val) in boundArgIndices:
          if idx < fact.relation.args.len and
             fact.relation.args[idx].kind == tkConstant and
             fact.relation.args[idx].value != val:
            matches = false
            break

        if matches:
          potentialFacts.add(fact)
    else:
      # No bound variables, use all facts for this time
      for fact in stateSeq[stateIndex].facts[condition.predicate]:
        if fact.time == targetTime:
          potentialFacts.add(fact)

    # Try to match against each selected fact
    var anyMatched = false
    debug("    Examining ", potentialFacts.len, " facts")
    for fact in potentialFacts:
      debug("    Trying to match fact: ", fact.relation.predicate,
            " at time ", fact.time)

      # Try to match
      var newEnv = env
      if matchRelation(condition, fact, newEnv):
        debug("      Matched! New env: ", newEnv)
        anyMatched = true

        # Add to matches if not negated
        if not condition.isNegated:
          # Continue with next condition
          let nextMatches = matchConditions(condIndex + 1, newEnv, currTime, stateSeq)
          for nextEnv in nextMatches:
            matchedEnvs.add(nextEnv)
      else:
        debug("      No match")

    # Handle negated conditions explicitly
    if condition.isNegated:
      debug("    Negated condition - checking if any facts matched")

      if anyMatched:
        # For negated conditions, if any facts matched with the current environment,
        # this branch fails
        debug("    Negated condition failed - matching facts found")
        return @[]
      else:
        # No facts matched, so the negated condition is satisfied
        debug("    Negated condition succeeded - no matching facts found")
        # We continue with the same environment since negation doesn't bind variables
        return matchConditions(condIndex + 1, env, currTime, stateSeq)

    return matchedEnvs

  # Get all matching environments by evaluating conditions
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
