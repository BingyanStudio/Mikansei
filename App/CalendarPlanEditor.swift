import EventKit
import EventKitUI
import SwiftUI

struct CalendarPlanSession: Identifiable {
    let id = UUID()
    let entryID: UUID
    let event: EKEvent
    let eventStore: EKEventStore
}

struct CalendarPlanEditor: UIViewControllerRepresentable {
    let session: CalendarPlanSession
    let finished: (EKEventEditViewAction, EKEvent?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = session.eventStore
        controller.event = session.event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let finished: (EKEventEditViewAction, EKEvent?) -> Void
        init(finished: @escaping (EKEventEditViewAction, EKEvent?) -> Void) { self.finished = finished }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            finished(action, controller.event)
        }
    }
}
