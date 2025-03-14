import std/[logging, strutils, sequtils, re],
       vm_types

# Process term annotations like [key], [single], [acc]
proc processAnnotations(term: var Term, annotation: string, relation: var Relation, argIndex: int) =
  case annotation
  of "key":
    relation.keyArgIndices.add(argIndex)
  of "single":
    relation.singleArgIndices.add(argIndex)
  of "acc":
    relation.accArgIndices.add(argIndex)
  else:
    discard

proc parseTerm(termStr: string, relation: var Relation, argIndex: int): Term =
  debug("    Parsing term: ", termStr)

  # Check for annotations
  if termStr.startsWith("["):
    let closeBracket = termStr.find(']')
    if closeBracket != -1:
      let annotation = termStr[1..<closeBracket]
      let actualTerm = termStr[closeBracket+1..^1].strip()

      debug("    Found annotation: ", annotation, " for term: ", actualTerm)

      var result = if actualTerm.len > 0: parseTerm(actualTerm, relation, argIndex)
                   else: Term(kind: tkConstant, value: "")

      processAnnotations(result, annotation, relation, argIndex)
      return result

  # Basic term parsing
  if termStr.len > 0 and (termStr[0].isUpperAscii() or termStr[0] == '_'):
    # Variables start with uppercase or underscore
    debug("    Creating variable: ", termStr)
    return Term(kind: tkVariable, name: termStr)
  else:
    # Constants are anything else
    debug("    Creating constant: ", termStr)
    return Term(kind: tkConstant, value: termStr)

# Helper to split arguments handling annotations, parentheses, and quotes
proc splitArgs(argsStr: string): seq[string] =
  result = @[]
  var currentArg = ""
  var parenDepth = 0
  var bracketDepth = 0
  var inQuote = false

  for c in argsStr:
    if c == ',' and parenDepth == 0 and bracketDepth == 0 and not inQuote:
      result.add(currentArg.strip())
      currentArg = ""
    elif c == '(' and not inQuote:
      parenDepth += 1
      currentArg.add(c)
    elif c == ')' and not inQuote:
      parenDepth -= 1
      currentArg.add(c)
    elif c == '[' and not inQuote:
      bracketDepth += 1
      currentArg.add(c)
    elif c == ']' and not inQuote:
      bracketDepth -= 1
      currentArg.add(c)
    elif c == '"':
      inQuote = not inQuote
      currentArg.add(c)
    else:
      currentArg.add(c)

  if currentArg.len > 0:
    result.add(currentArg.strip())

# Parse a relation like "predicate(arg1, arg2)" or "predicate[n](arg1, [key]arg2)"
proc parseRelation*(relStr: string): Relation =
  var result = Relation()
  debug("Parsing relation: ", relStr)

  # Check for negation
  if relStr.startsWith("!"):
    result.isNegated = true
    # Create a new relation string without the '!'
    let nonNegatedStr = relStr[1..^1]
    debug("Negated relation, processing: ", nonNegatedStr)

    # Parse the non-negated part
    var nonNegated = parseRelation(nonNegatedStr)

    # Copy properties from non-negated relation
    result.predicate = nonNegated.predicate
    result.args = nonNegated.args
    result.timeOffset = nonNegated.timeOffset
    result.keyArgIndices = nonNegated.keyArgIndices
    result.singleArgIndices = nonNegated.singleArgIndices
    result.accArgIndices = nonNegated.accArgIndices

    debug("Created negated relation: predicate=", result.predicate,
          " isNegated=", result.isNegated)
    return result

  # Extract predicate name and time offset
  var predicatePart = relStr
  var argsPart = ""

  let argsStart = relStr.find('(')
  if argsStart != -1:
    predicatePart = relStr[0..<argsStart]

    # Extract the full arguments part including nested parentheses
    var parenDepth = 0
    var i = argsStart
    while i < relStr.len:
      let c = relStr[i]
      if c == '(':
        parenDepth += 1
      elif c == ')':
        parenDepth -= 1
        if parenDepth == 0:
          argsPart = relStr[argsStart+1..<i]
          break
      i += 1

    debug("  Predicate: ", predicatePart)
    debug("  Args part: ", argsPart)

  # Parse time offset if present
  var timeOffsetStr = ""
  let timeStart = predicatePart.find('[')
  if timeStart != -1:
    let timeEnd = predicatePart.find(']')
    if timeEnd != -1:
      timeOffsetStr = predicatePart[timeStart+1..<timeEnd]
      predicatePart = predicatePart[0..<timeStart]

  # Set predicate name
  result.predicate = predicatePart.strip()

  # Set time offset
  if timeOffsetStr == "n":
    result.timeOffset = 0  # Current time
  elif timeOffsetStr == "n-1":
    result.timeOffset = -1  # Previous time
  elif timeOffsetStr == "n-2":
    result.timeOffset = -2  # Two steps back
  elif timeOffsetStr.len > 0:
    try:
      result.timeOffset = parseInt(timeOffsetStr)
    except:
      result.timeOffset = 0  # Default to current time
  else:
    result.timeOffset = 0  # Default to current time

  # Parse arguments using the robust splitArgs function
  if argsPart.len > 0:
    let args = splitArgs(argsPart)
    for i, arg in args:
      result.args.add(parseTerm(arg, result, i))

  debug("  Final relation: predicate=", result.predicate,
        " args=", result.args.len,
        " timeOffset=", result.timeOffset)

  return result

# Split conditions handling nested structures
proc splitConditions(conditionsStr: string): seq[string] =
  # Replace dot notation with commas for condition separation
  var fixedCondStr = conditionsStr.replace(".", ",")
  return splitArgs(fixedCondStr)

# Parse a rule like "conclusion :- condition1, condition2."
proc parseRule*(ruleStr: string): Rule =
  var result = Rule(maxEvalCountPerTime: 100)  # Default to high number

  # Split into conclusion and conditions
  let parts = ruleStr.split(":-").mapIt(it.strip())
  if parts.len == 0:
    raise newException(ValueError, "Invalid rule format")

  # Parse conclusion
  result.conclusion = parseRelation(parts[0])

  # Parse conditions if any
  if parts.len > 1:
    let conditionsStr = parts[1]
    var cleanCondStr = conditionsStr

    # Remove trailing period if present
    if cleanCondStr.endsWith("."):
      cleanCondStr = cleanCondStr[0..^2]

    # Split conditions handling nested parentheses
    let conditions = splitConditions(cleanCondStr)

    debug("Parsed conditions: ", $conditions)
    for cond in conditions:
      result.conditions.add(parseRelation(cond))

  return result
