import prolog_vm, dsl, vm_types, rule_parser
import std/[logging, tables]

proc dumpState(vm: VirtualPrologMachine) =
  let stateIndex = vm.currentTime mod vm.states.len
  let state = vm.states[stateIndex]

  echo "Facts at time ", vm.currentTime - 1, ":"
  for pred, facts in state.facts:
    echo "  ", pred, ":"
    for fact in facts:
      var args = ""
      for arg in fact.relation.args:
        args.add(if arg.kind == tkConstant: arg.value else: arg.name)
        args.add(", ")
      if args.len > 0: args = args[0..^3]  # Remove trailing ", "
      echo "    ", fact.relation.predicate, "(", args, ") at time ", fact.time

  # Test specifically for breakable property
  if "breakable" in state.facts:
    echo "Breakable objects:"
    for fact in state.facts["breakable"]:
      echo "  ", fact.relation.args[0].value

proc main() =
  # Create a simple VM with negation test
  var vm = logicProgram:
    # Test rule with negation
    rule testNegation:
      breakable[n](X) :- egg[n](X) . not broken[n](X)

    # Simple fact rules
    fact egg("egg1")
    fact broken("egg2")
    fact egg("egg2")

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
