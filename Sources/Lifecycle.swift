struct DetectionLifecycle {
    var manuallyPaused = false
    var sleeping = false
    var locked = false
    var shouldRun: Bool { !manuallyPaused && !sleeping && !locked }
}
