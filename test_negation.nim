import std/[logging, tables, strutils]
import prolog_vm, dsl, vm_types, rule_parser

# Set up detailed logging
addHandler(newFileLogger("out.log", levelThreshold=lvlDebug))

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
  # Create a VM with a simple negation rule
  var vm = logicProgram:
    # Define rule with negation
    rule testNegation:
      breakable[n](X) :- egg[n](X) . not broken[n](X)
      # Add explicit persistence rules for base facts
      egg[n](X) :- egg[n-1](X)
      broken[n](X) :- broken[n-1](X)

    # Add initial facts
    fact egg("egg1")        # An unbroken egg
    fact egg("egg2")        # A broken egg
    fact broken("egg2")

  debug("STATE DUMP AFTER ADDING FACTS:")
  for i in 0..<vm.states.len:
    debug("  State[", i, "] time=", vm.states[i].time)
    for pred, facts in vm.states[i].facts:
      debug("    ", pred, ": ", facts.len, " facts")
      for fact in facts:
        debug("      ", fact.relation.predicate, "(", fact.relation.args[0].value, ")")

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
