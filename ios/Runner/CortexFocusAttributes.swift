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
    var activateAt: Date? = nil
    var phase: String {
      status == "pending" && (activateAt ?? start.addingTimeInterval(-1800)) <= Date()
        ? "ready" : status
    }
  }
  struct ContentState: Codable, Hashable {
    var tasks: [TaskItem]
    var selectedID: String
    var remindersUntil: Date
    // Optional so a card created before paging was added still decodes.
    var page: Int?
    // New cards carry only the displayed pair. The remaining tasks stay in the
    // native cache, so calendar schedules do not hit ActivityKit's 4 KB limit.
    var totalTaskCount: Int? = nil
    var taskCount: Int { totalTaskCount ?? tasks.count }
    var pageCount: Int { max(1, (taskCount + 1) / 2) }
    var pageIndex: Int { max(0, min(page ?? 0, pageCount - 1)) }
    var visibleTasks: [TaskItem] {
      totalTaskCount == nil ? Array(tasks.dropFirst(pageIndex * 2).prefix(2)) : tasks
    }
  }
  var id: String
  var windowStart: Date? = nil
}

// Keep wire states compatible with existing server records and installed clients.
// Time can make pending work ready, but never start or finish it.
enum CortexTaskState: String {
  case pending, ready, active, paused, postponed, done, cancelled
  var isOpen: Bool { self != .done && self != .cancelled }
  func allows(_ action: String) -> Bool {
    switch action {
    case "begin": return [.pending, .ready, .paused, .postponed].contains(self)
    case "extend": return [.active, .paused].contains(self)
    case "postpone", "reschedule", "pause", "complete", "cancel", "select": return isOpen
    default: return false
    }
  }
}
