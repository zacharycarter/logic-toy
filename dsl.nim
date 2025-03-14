import std/[macros, strutils, sequtils]
import vm_types, rule_parser, prolog_vm

# Helper to convert NimNode to string representation
proc nodeToString(node: NimNode): string =
  case node.kind
  of nnkIdent:
    if node.strVal == "not":
      return "!"
    return node.strVal
  of nnkStrLit..nnkTripleStrLit:
    return node.strVal
  of nnkInfix:
    # Handle infix operators like X + Y or conclusion :- condition
    let lhs = nodeToString(node[1])
    let op = node[0].strVal
    let rhs = nodeToString(node[2])
    return lhs & " " & op & " " & rhs
  of nnkBracketExpr:
    # Handle time offset notation [n], [n-1], etc.
    let name = nodeToString(node[0])
    var timeOffset = nodeToString(node[1])
    return name & "[" & timeOffset & "]"
  of nnkCall:
    # Handle function-like calls: pred(arg1, arg2)
    let name = nodeToString(node[0])
    var args = newSeq[string]()
    for i in 1..<node.len:
      args.add(nodeToString(node[i]))
    return name & "(" & args.join(", ") & ")"
  of nnkCommand:
    # Handle annotations like [key]X
    if node[0].kind == nnkBracket:
      let annotation = nodeToString(node[0])
      let target = nodeToString(node[1])
      return annotation & target
    else:
      return nodeToString(node[0]) & nodeToString(node[1])
  of nnkBracket:
    # Handle [key], [single], etc.
    var annots = newSeq[string]()
    for i in 0..<node.len:
      annots.add(nodeToString(node[i]))
    return "[" & annots.join(", ") & "]"
  of nnkDotExpr:
    # Handle dot notation for term separation (A.B becomes A, B)
    let lhs = nodeToString(node[0])
    let rhs = nodeToString(node[1])
    return lhs & ", " & rhs
  of nnkPrefix:
    # Handle negated predicates: !pred(...)
    if node[0].strVal == "!":
      return "!" & nodeToString(node[1])
    else:
      # Handle other prefixes
      return node[0].strVal & nodeToString(node[1])
  of nnkPar:
    # Handle parenthesized expressions
    var items = newSeq[string]()
    for i in 0..<node.len:
      items.add(nodeToString(node[i]))
    return "(" & items.join(", ") & ")"
  of nnkIntLit..nnkInt64Lit:
    return $node.intVal
  else:
    return $node

# Parse a rule definition node
proc parseRuleBody(ruleBody: NimNode): seq[string] =
  result = @[]

  if ruleBody.kind == nnkStmtList:
    for stmt in ruleBody:
      if stmt.kind == nnkInfix and stmt[0].strVal == ":-":
        let conclusion = nodeToString(stmt[1])
        let conditions = nodeToString(stmt[2])
        result.add(conclusion & " :- " & conditions & ".")
      else:
        # Single fact with no conditions
        result.add(nodeToString(stmt) & ".")

# Main logicProgram macro
macro logicProgram*(body: untyped): untyped =
  echo treeRepr body
  result = newStmtList()

  # Create VM instance
  let vmName = genSym(nskVar, "vm")
  result.add quote do:
    var `vmName` = newVirtualPrologMachine(lookbackWindow = 2)

  # Process each statement in the body
  for statement in body:
    case statement.kind
    of nnkCommand:
      let cmdName = statement[0]

      # Handle rule definitions
      if cmdName.eqIdent("rule"):
        let ruleName = statement[1]
        let ruleBody = statement[2]

        # Parse rule strings
        let ruleStrs = parseRuleBody(ruleBody)

        for ruleStr in ruleStrs:
          result.add quote do:
            `vmName`.addRuleFromString(`ruleStr`)

      # Handle fact definitions with command syntax
      elif cmdName.eqIdent("fact"):
        if statement.len >= 2:
          let factNode = statement[1]
          if factNode.kind == nnkCall:
            let predicate = factNode[0].strVal

            # Collect arguments
            var args = newSeq[string]()
            for i in 1..<factNode.len:
              args.add(nodeToString(factNode[i]))

            # Build the fact string
            let factStr = predicate & "(" & args.join(", ") & ")"

            # Add the fact to the VM
            result.add quote do:
              var factRel = parseRelation(`factStr`)
              var fact = Fact(
                relation: factRel,
                time: `vmName`.currentTime
              )
              `vmName`.addFact(fact)

    # Other kinds of statements might be handled here
    else:
      error("Unsupported statement kind: " & $statement.kind, statement)

  # Return the VM
  result.add quote do:
    `vmName`

  echo repr result

# Helper to create vec2 values
proc vec2*(x, y: int): string =
  "vec2(" & $x & "," & $y & ")"

# Create Bracket nodes for annotations
macro key*(arg: untyped): untyped =
  result = nnkBracket.newTree(ident("key"))

macro single*(arg: untyped): untyped =
  result = nnkBracket.newTree(ident("single"))

macro acc*(arg: untyped): untyped =
  result = nnkBracket.newTree(ident("acc"))
