import prolog_vm, dsl, vm_types, rule_parser
import std/[logging, tables]

proc dumpState(vm: VirtualPrologMachine) =
  # Find the state that contains our current time's facts
  var displayState: State
  var displayTime = vm.currentTime - 1  # We want previous time for most recent facts

  # Find the state with our facts
  for i in 0..<vm.states.len:
    if vm.states[i].time == displayTime:
      displayState = vm.states[i]

  echo "\n=== Facts at time ", displayTime, ": ==="
  for pred, facts in displayState.facts:
    if facts.len > 0:  # Only display if there are facts
      echo "  ", pred, ":"
      for fact in facts:
        var argsStr = ""
        for arg in fact.relation.args:
          if arg.kind == tkConstant:
            argsStr.add(arg.value)
          else:
            argsStr.add(arg.name)
        echo "    ", fact.relation.predicate, "(", argsStr, ")"

proc main() =
  # Create a simple VM with negation test
  var vm = logicProgram:
    # Test rule with negation
    rule testNegation:
      breakable[n](X) :- egg[n](X) . not broken[n](X)
      # Add explicit persistence rules for base facts
      egg[n](X) :- egg[n-1](X)
      broken[n](X) :- broken[n-1](X)

    # Simple fact rules
    fact egg("egg1")
    fact egg("egg2")
    fact broken("egg2")

  # Initialize the world
  echo "Initial state:"
  dumpState(vm)

  # Update VM
  vm.update()

  # Check first update
  echo "\nAfter first update:"
  dumpState(vm)

when isMainModule:
  main()
