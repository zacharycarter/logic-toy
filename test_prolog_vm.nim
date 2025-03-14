import std/tables,
       prolog_vm, rule_parser, rule_eval, vm_types

proc main() =
  # Create a VM
  var vm = newVirtualPrologMachine(lookbackWindow = 2)

  # Add a collision rule
  vm.addRuleFromString("collide[n](X, Y) :- position[n]([key]X, [single]P), position[n](Y, [key]P).")

  # Add some facts directly
  vm.addFact(Fact(
    relation: Relation(
      predicate: "position",
      args: @[
        Term(kind: tkConstant, value: "actor1"),
        Term(kind: tkConstant, value: "vec2(0,0)")
      ],
      timeOffset: 0
    ),
    time: vm.currentTime
  ))

  vm.addFact(Fact(
    relation: Relation(
      predicate: "position",
      args: @[
        Term(kind: tkConstant, value: "actor2"),
        Term(kind: tkConstant, value: "vec2(0,0)")
      ],
      timeOffset: 0
    ),
    time: vm.currentTime
  ))

  # Run the VM
  vm.update()

  # Check for collisions
  let stateIndex = vm.currentTime - 1
  echo vm.states
  if "collide" in vm.states[stateIndex].facts:
    echo "Collisions detected:"
    for fact in vm.states[stateIndex].facts["collide"]:
      echo "  ", fact.relation.args[0].value, " collides with ", fact.relation.args[1].value
  else:
    echo "No collisions detected."

when isMainModule:
  main()
