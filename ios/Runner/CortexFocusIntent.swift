import AppIntents

@available(iOS 17.0, *)
struct CortexFocusActionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Update Cortex task"
  static var openAppWhenRun: Bool = false
  @Parameter(title: "Task") var taskID: String
  @Parameter(title: "Revision") var revision: Int
  @Parameter(title: "Action") var action: String
  @Parameter(title: "Minutes") var minutes: Int
  init() {}
  init(_ taskID: String, _ revision: Int, _ action: String, minutes: Int = 15) {
    self.taskID = taskID
    self.revision = revision
    self.action = action
    self.minutes = minutes
  }
  func perform() async throws -> some IntentResult {
    #if !CORTEX_WIDGET
      try await CortexFocus.shared.perform(
        id: taskID, revision: revision, action: action, minutes: minutes)
    #endif
    return .result()
  }
}

@available(iOS 17.0, *)
struct CortexFocusPageIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Show Cortex tasks"
  static var openAppWhenRun: Bool = false
  @Parameter(title: "Page") var page: Int
  init() {}
  init(_ page: Int) { self.page = page }
  func perform() async throws -> some IntentResult {
    #if !CORTEX_WIDGET
      try await CortexFocus.shared.showPage(page)
    #endif
    return .result()
  }
}
