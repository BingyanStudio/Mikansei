import SwiftUI

@available(iOS 16.0, *)
struct FocusClock: View {
    let entry: Entry
    var body: some View {
        Group {
            if let started = entry.startedAt, !entry.isCompleted {
                Text(timerInterval: started.addingTimeInterval(-entry.elapsedSeconds)...Date.distantFuture,
                     countsDown: false, showsHours: true)
            } else { Text(entry.focusTimeLabel()) }
        }.monospacedDigit().lineLimit(1)
    }
}
