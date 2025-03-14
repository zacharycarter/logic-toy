import prolog_vm, dsl, vm_types, rule_parser
import std/[strutils, tables]

proc dumpState(vm: VirtualPrologMachine) =
  let stateIndex = vm.currentTime mod vm.states.len
  let state = vm.states[stateIndex]

  # Check egg states
  if "egg" in state.facts:
    echo "Eggs:"
    for fact in state.facts["egg"]:
      let eggId = fact.relation.args[0].value

      # Determine egg state
      var stateTags: seq[string] = @[]

      # Check all possible states
      for tag in ["broken", "stirred", "cooked"]:
        if tag in state.facts:
          for stateFact in state.facts[tag]:
            if stateFact.relation.args[0].value == eggId:
              stateTags.add(tag)

      # Check derived states
      var derivedState = ""
      if "omelette" in state.facts:
        for fact in state.facts["omelette"]:
          if fact.relation.args[0].value == eggId:
            derivedState = "omelette"

      if "friedEgg" in state.facts:
        for fact in state.facts["friedEgg"]:
          if fact.relation.args[0].value == eggId:
            derivedState = "fried egg"

      # Check capabilities
      var capabilities: seq[string] = @[]
      for capability in ["breakable", "stirrable", "cookable"]:
        if capability in state.facts:
          for capFact in state.facts[capability]:
            if capFact.relation.args[0].value == eggId:
              capabilities.add(capability)

      # Print state
      if derivedState != "":
        echo "  ", eggId, " - Type: ", derivedState, " (", stateTags.join(", "), ")"
      else:
        echo "  ", eggId, " - States: [", stateTags.join(", "), "] Can be: [", capabilities.join(", "), "]"

  # Show recent interactions
  if "use" in state.facts:
    echo "Recent interactions:"
    for fact in state.facts["use"]:
      echo "  ", fact.relation.args[0].value, " used ", fact.relation.args[1].value,
            " on ", fact.relation.args[2].value

# Extension of the basic state transition example
# This adds:
# 1. A stirrable state that requires being broken first
# 2. A cooking process with multiple state transitions
# 3. More complex interactions between states

proc main() =
  # Create a VM with more complex state transitions
  var vm = logicProgram:
    # Define basic type properties
    rule eggProperties:
      breakable[n](X) :- egg[n](X) . not broken[n](X)
      stirrable[n](X) :- egg[n](X) . broken[n](X) . not stirred[n](X)
      cookable[n](X) :- egg[n](X) . broken[n](X) | stirred[n](X) . not cooked[n](X)

    # State transition rules
    rule stateChanges:
      broken[n](X) :- breakable[n-1](X) . `break`[n-1](X)
      stirred[n](X) :- stirrable[n-1](X) . stir[n-1](X)
      cooked[n](X) :- cookable[n-1](X) . cook[n-1](X)

    # Derived states based on combination of properties
    rule derivedStates:
      omelette[n](X) :- egg[n](X) . stirred[n](X) . cooked[n](X)
      friedEgg[n](X) :- egg[n](X) . broken[n](X) . not stirred[n](X) . cooked[n](X)

    rule persistence:
      # States persist unless changed
      egg[n](X) :- egg[n-1](X) . alive[n-1](X)
      broken[n](X) :- broken[n-1](X) . alive[n-1](X)
      stirred[n](X) :- stirred[n-1](X) . alive[n-1](X)
      cooked[n](X) :- cooked[n-1](X) . alive[n-1](X)

    # Actions that cause state changes
    rule playerInteractions:
      `break`[n](X) :- use[n](Player, "fork", X) . player[n](Player) . breakable[n](X)
      stir[n](X) :- use[n](Player, "whisk", X) . player[n](Player) . stirrable[n](X)
      cook[n](X) :- use[n](Player, "pan", X) . player[n](Player) . cookable[n](X)

    # Initial facts
    fact egg("egg1")
    fact egg("egg2")
    fact player("chef")

  # Initialize the world
  echo "Initial state:"
  echo "-------------"
  dumpState(vm)

  # Simulate breaking the first egg
  vm.addFact(Fact(
    relation: parseRelation("use(chef, fork, egg1)"),
    time: vm.currentTime
  ))

  # Update VM
  vm.update()

  # Check state after breaking
  echo "\nState after breaking egg1:"
  echo "-------------------------"
  dumpState(vm)

  # Simulate stirring the broken egg
  vm.addFact(Fact(
    relation: parseRelation("use(chef, whisk, egg1)"),
    time: vm.currentTime
  ))

  # Update VM
  vm.update()

  # Check state after stirring
  echo "\nState after stirring egg1:"
  echo "-------------------------"
  dumpState(vm)

  # Break the second egg but don't stir it
  vm.addFact(Fact(
    relation: parseRelation("use(chef, fork, egg2)"),
    time: vm.currentTime
  ))

  # Update VM
  vm.update()

  # Cook both eggs
  vm.addFact(Fact(
    relation: parseRelation("use(chef, pan, egg1)"),
    time: vm.currentTime
  ))

  vm.addFact(Fact(
    relation: parseRelation("use(chef, pan, egg2)"),
    time: vm.currentTime
  ))

  # Update VM
  vm.update()

  # Check final state - we should have an omelette and a fried egg
  echo "\nFinal state after cooking:"
  echo "------------------------"
  dumpState(vm)

when isMainModule:
  main()
