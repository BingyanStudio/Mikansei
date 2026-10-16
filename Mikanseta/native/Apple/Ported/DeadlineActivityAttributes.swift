import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct DeadlineActivityAttributes: ActivityAttributes {
    typealias ContentState = DeadlineActivitySnapshot
    let dayStart: Date
}
