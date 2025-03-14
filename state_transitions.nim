import prolog_vm, dsl, vm_types, rule_parser
import std/tables

proc dumpState(vm: VirtualPrologMachine) =
  let stateIndex = vm.currentTime mod vm.states.len
  let state = vm.states[stateIndex]

  # Check egg state
  if "egg" in state.facts:
    echo "Eggs:"
    for fact in state.facts["egg"]:
      let eggId = fact.relation.args[0].value
      var status = "normal"

      # Check if egg is broken
      if "broken" in state.facts:
        for brokenFact in state.facts["broken"]:
          if brokenFact.relation.args[0].value == eggId:
            status = "broken"

      # Check if egg is breakable
      var isBreakable = false
      if "breakable" in state.facts:
        for breakableFact in state.facts["breakable"]:
          if breakableFact.relation.args[0].value == eggId:
            isBreakable = true

      echo "  ", eggId, " - Status: ", status, " (Breakable: ", isBreakable, ")"

  # Show recent interactions
  if "touch" in state.facts:
    echo "Recent interactions:"
    for fact in state.facts["touch"]:
      echo "  ", fact.relation.args[0].value, " touched ", fact.relation.args[1].value

proc main() =
  # Create a VM with logic for state transitions
  var vm = logicProgram:
    # Define basic types/states
    rule eggProperties:
      breakable[n](X) :- egg[n](X) . not broken[n](X)

    # State transition rules
    rule breakEgg:
      broken[n](X) :- breakable[n-1](X) . brk[n-1](X)

    # Manual state persistence rules
    rule persistence:
      # States persist unless changed
      egg[n](X) :- egg[n-1](X) . alive[n-1](X)
      broken[n](X) :- broken[n-1](X) . alive[n-1](X)
      # All eggs are alive by default
      alive[n](X) :- egg[n](X)

    # Actions that cause state changes
    rule playerInteractions:
      brk[n](X) :- touch[n](Player, X) . player[n](Player) . breakable[n](X)

    # Initial facts
    fact egg("egg1")
    fact player("player1")
    fact alive("egg1")

  # Initialize the world
  echo "Initial state:"
  echo "-------------"
  dumpState(vm)

  # Simulate touch event
  vm.addFact(Fact(
    relation: parseRelation("touch(player1, egg1)"),
    time: vm.currentTime
  ))

  # Update VM
  vm.update()

  # Check state after interaction
  echo "\nState after interaction:"
  echo "----------------------"
  dumpState(vm)

  # Update again without interaction
  vm.update()

  # Check that state persists
  echo "\nState after second update (persistence check):"
  echo "-------------------------------------------"
  dumpState(vm)
  echo "-------------------------------------------"


when isMainModule:
  main()
