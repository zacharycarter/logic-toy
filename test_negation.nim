import std/[logging, tables, strutils]
import prolog_vm, dsl, vm_types, rule_parser

# Set up detailed logging
# addHandler(newConsoleLogger(levelThreshold=lvlDebug))

proc dumpState(vm: VirtualPrologMachine) =
  let stateIndex = vm.currentTime mod vm.states.len
  let state = vm.states[stateIndex]

  echo "\n=== Facts at time ", vm.currentTime - 1, ": ==="
  for pred, facts in state.facts:
    echo "  ", pred, ":"
    for fact in facts:
      var argsStr = ""
      for arg in fact.relation.args:
        if arg.kind == tkConstant:
          argsStr.add(arg.value)
        else:
          argsStr.add(arg.name)
        argsStr.add(", ")
      if argsStr.len > 0: argsStr = argsStr[0..^3]  # Remove trailing ", "
      echo "    ", fact.relation.predicate, "(", argsStr, ") at time ", fact.time

proc main() =
  # Create a VM with a simple negation rule
  var vm = logicProgram:
    # Define rule with negation
    rule testNegation:
      breakable[n](X) :- egg[n](X) . not broken[n](X)

    # Add initial facts
    fact egg("egg1")        # An unbroken egg
    fact egg("egg2")        # A broken egg
    fact broken("egg2")

  echo "Initial state:"
  dumpState(vm)

  # Process rules
  vm.update()

  # Check result
  echo "\nAfter update:"
  dumpState(vm)

  # Add broken status to egg1
  vm.addFact(Fact(
    relation: parseRelation("broken(egg1)"),
    time: vm.currentTime
  ))

  # Process rules again
  vm.update()

  # Check final state - egg1 should no longer be breakable
  echo "\nAfter second update:"
  dumpState(vm)

when isMainModule:
  main()
