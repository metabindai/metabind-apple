import Testing

/// Polls `condition` until it holds, recording an issue if it still doesn't
/// after `timeout`. Use this instead of a fixed sleep, which is either too
/// short for a loaded CI runner or wasted time everywhere else.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out after \(timeout) waiting for condition", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
