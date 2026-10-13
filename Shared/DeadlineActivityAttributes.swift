import ActivityKit
import Foundation

struct DeadlineActivityAttributes: ActivityAttributes {
    typealias ContentState = DeadlineActivitySnapshot
    let dayStart: Date
}
