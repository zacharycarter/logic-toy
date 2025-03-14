import std/tables
import prolog_vm, rule_parser, rule_eval, vm_types, dsl

proc main() =
  # Create a VM using the DSL
  var vm = logicProgram:
    rule collide:
      collide[n](X, Y) :- position[n]([key]X, [single]P) . position[n](Y, [key]P)

    fact position("actor1", "\"vec2(0,0)\"")  # Quoted to force single argument
    fact position("actor2", "\"vec2(0,0)\"")
    fact position("actor3", "\"vec2(1,1)\"")
    # fact position("actor1", vec2(0, 0))
    # fact position("actor2", vec2(0, 0))
    # fact position("actor3", vec2(1, 1))

  # Run the VM
  vm.update()

  # Check for collisions
  let stateIndex = vm.currentTime - 1
  if "collide" in vm.states[stateIndex mod vm.states.len].facts:
    echo "Collisions detected:"
    for fact in vm.states[stateIndex mod vm.states.len].facts["collide"]:
      echo "  ", fact.relation.args[0].value, " collides with ", fact.relation.args[1].value
  else:
    echo "No collisions detected."

when isMainModule:
  main()

# import macros

# # Debug a simple rule expression
# dumpTree:
#   logicProgram:
#     rule collide:
#       collide[n](X, Y) :- position[n]([key]X, [single]P) . position[n](Y, [key]P)

#     fact position("actor1", vec2(0, 0))
