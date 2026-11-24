import Foundation
var state = DetectionLifecycle()
assert(state.shouldRun)
state.sleeping = true
assert(!state.shouldRun)
state.locked = true
state.sleeping = false
assert(!state.shouldRun)
state.locked = false
assert(state.shouldRun)
state.manuallyPaused = true
state.sleeping = true
state.locked = true
state.locked = false
state.sleeping = false
assert(!state.shouldRun)
state.manuallyPaused = false
assert(state.shouldRun)
print("Lifecycle tests passed")
