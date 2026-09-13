import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct CortexFocusAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var expectedEnd: Date
    var revision: Int
    var remindersUntil: Date
  }
  var id: String
  var title: String
  var startedAt: Date
}
