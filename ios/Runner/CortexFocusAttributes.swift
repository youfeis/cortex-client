import ActivityKit
import Foundation

// Retain the old type so upgrades can retire its existing activities.
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

@available(iOS 16.2, *)
struct CortexTaskBoardAttributes: ActivityAttributes {
  struct TaskItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var status: String
    var start: Date
    var end: Date
    var revision: Int
    var preview: Bool
  }
  struct ContentState: Codable, Hashable {
    var tasks: [TaskItem]
    var selectedID: String
    var remindersUntil: Date
  }
  var id: String
}
