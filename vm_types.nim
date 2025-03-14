import std/[sets, tables]

# Basic term and constant types
type
  TermKind* = enum
    tkConstant, tkVariable

  Term* = object
    case kind*: TermKind
    of tkConstant:
      value*: string
    of tkVariable:
      name*: string

  # A relation with predicate and arguments
  Relation* = object
    predicate*: string
    args*: seq[Term]
    timeOffset*: int  # -1 for timeless, 0 for current time, -1 for previous, etc.
    isNegated*: bool  # For negated conditions like !predicate(...)

    # Optimization annotations
    keyArgIndices*: seq[int]  # Indices of args marked as [key]
    singleArgIndices*: seq[int]  # Indices of args marked as [single]
    accArgIndices*: seq[int]  # Indices of args marked as [acc]

  # A rule is a conclusion and a list of conditions
  Rule* = object
    conclusion*: Relation
    conditions*: seq[Relation]
    maxEvalCountPerTime*: int

  # A fact is a relation at a specific time
  Fact* = object
    relation*: Relation
    time*: int

  # State represents all facts at a particular time
  State* = object
    facts*: Table[string, seq[Fact]]
    time*: int
    factIndex*: Table[string, HashSet[string]]  # Maps predicate+arg hash to fact existence

# Equality comparison for Term
proc `==`*(a, b: Term): bool =
  if a.kind != b.kind:
    return false

  case a.kind:
  of tkConstant:
    return a.value == b.value
  of tkVariable:
    return a.name == b.name

# Equality comparison for Relation
proc `==`*(a, b: Relation): bool =
  if a.predicate != b.predicate or
     a.timeOffset != b.timeOffset or
     a.isNegated != b.isNegated or
     a.args.len != b.args.len:
    return false

  # Compare arguments
  for i in 0..<a.args.len:
    if a.args[i] != b.args[i]:
      return false

  # Compare optimization annotations (order matters)
  if a.keyArgIndices != b.keyArgIndices or
     a.singleArgIndices != b.singleArgIndices or
     a.accArgIndices != b.accArgIndices:
    return false

  return true

# Equality comparison for Fact
proc `==`*(a, b: Fact): bool =
  return a.relation == b.relation and a.time == b.time

proc factHash*(fact: Fact): string =
  result = fact.relation.predicate
  for arg in fact.relation.args:
    case arg.kind:
    of tkConstant:
      result.add(":" & arg.value)
    of tkVariable:
      result.add(":" & arg.name)
