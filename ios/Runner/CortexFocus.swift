import ActivityKit
import CryptoKit
import Flutter
import Security
import UIKit
import UserNotifications

// All native writes share this queue, including Lock Screen actions before Flutter starts.
@MainActor
final class CortexFocus: NSObject, UNUserNotificationCenterDelegate {
  static let shared = CortexFocus()
  static var changed: (() -> Void)?
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let prefix = "cortex.focus."
  private var work: Task<Void, Never>?
  private var liveAttempt: String?
  private var restoration: Task<Void, Never>?
  private var restoreGeneration = UUID()
  private var liveWatchers: [String: Task<Void, Never>] = [:]
  private var tasks: [[String: Any]] {
    get {
      if let list = defaults.dictionary(forKey: "cortex.focus.envelope")?["tasks"]
        as? [[String: Any]]
      {
        return list
      }
      if let list = defaults.array(forKey: "cortex.focus.tasks") as? [[String: Any]] { return list }
      if let old = defaults.dictionary(forKey: "cortex.focus.current") { return [old] }
      return []
    }
    set {
      // Server results are sorted by last edit. Keep existing task positions so
      // adding time to one task does not swap the two sets of Lock Screen buttons.
      let previousIDs = tasks.compactMap { $0["id"] as? String }
      let retained = previousIDs.compactMap { id in newValue.first { $0["id"] as? String == id } }
      let added = newValue.filter { !previousIDs.contains($0["id"] as? String ?? "") }
      defaults.set(
        ["tasks": retained + added, "pending": pending], forKey: "cortex.focus.envelope")
    }
  }
  private var pending: [[String: Any]] {
    get {
      defaults.dictionary(forKey: "cortex.focus.envelope")?["pending"] as? [[String: Any]]
        ?? defaults.array(forKey: "cortex.focus.pending") as? [[String: Any]] ?? []
    }
    set { defaults.set(["tasks": tasks, "pending": newValue], forKey: "cortex.focus.envelope") }
  }
  private var openTasks: [[String: Any]] {
    tasks.filter { CortexTaskState(rawValue: $0["status"] as? String ?? "")?.isOpen == true }
  }
  private func activation(_ f: [String: Any]) -> Date {
    Self.date(f["activateAt"]) ?? Self.date(f["scheduledStart"])?.addingTimeInterval(-1800)
      ?? .distantPast
  }
  private func phase(_ f: [String: Any], at now: Date = Date()) -> String {
    let status = f["status"] as? String ?? ""
    return status == "pending" && activation(f) <= now ? "ready" : status
  }
  private var visible: [[String: Any]] { openTasks.filter { phase($0) != "pending" } }
  private var pagingTasks: [[String: Any]] {
    let now = Date()
    var start = now
    if #available(iOS 16.2, *),
      let current = Activity<CortexTaskBoardAttributes>.activities.first(where: {
        Self.ongoing($0.activityState)
      })
    {
      start = current.attributes.windowStart ?? now
    }
    return openTasks.filter {
      phase($0) != "pending" || activation($0) < start.addingTimeInterval(8 * 3600)
    }
  }
  private var lastPage: Int { max(0, (pagingTasks.count - 1) / 2) }
  private var boardPage: Int {
    max(0, min(defaults.integer(forKey: "cortex.focus.page"), lastPage))
  }
  private var selected: [String: Any]? {
    let id = defaults.string(forKey: "cortex.focus.selected")
    return visible.first { $0["id"] as? String == id } ?? visible.first
  }
  func setup() {
    center.delegate = self
    let postpone = UNTextInputNotificationAction(
      identifier: "postpone", title: "Postpone", options: [], textInputButtonTitle: "Rearrange",
      textInputPlaceholder: "Why? When would work better?")
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: "CORTEX_FOCUS",
        actions: [
          UNNotificationAction(identifier: "complete", title: "Completed!", options: []),
          UNNotificationAction(identifier: "extend", title: "+15 minutes", options: []), postpone,
          UNNotificationAction(identifier: "pause", title: "Take a break", options: []),
        ], intentIdentifiers: []),
      UNNotificationCategory(
        identifier: "CORTEX_FOCUS_READY",
        actions: [
          UNNotificationAction(identifier: "begin", title: "I’ve started", options: []), postpone,
        ], intentIdentifiers: []),
    ])
    if #available(iOS 16.2, *) {
      for activity in Activity<CortexTaskBoardAttributes>.activities
      where Self.ongoing(activity.activityState) || Self.scheduled(activity.activityState) {
        observe(activity)
      }
    }
  }
  func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = work
    work = Task {
      await previous?.value
      await operation()
    }
  }
  func restoreOnOpen() {
    restoration?.cancel()
    let generation = UUID()
    restoreGeneration = generation
    // Scene activation can precede ActivityKit readiness. Retry locally even when
    // the network is offline; do not keep recreating a card the owner swiped away.
    restoration = Task { [weak self] in
      guard let self else { return }
      defer { if self.restoreGeneration == generation { self.restoration = nil } }
      for delay in [0, 500, 1500, 3000] {
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
        guard !Task.isCancelled else { return }
        guard UIApplication.shared.applicationState == .active else { continue }
        let restored: Bool = await withCheckedContinuation { continuation in
          self.enqueue {
            guard self.restoreGeneration == generation else {
              continuation.resume(returning: true)
              return
            }
            self.liveAttempt = nil
            try? await self.schedule()
            Self.changed?()
            if #available(iOS 16.2, *) {
              continuation.resume(
                returning: self.visible.isEmpty
                  || !ActivityAuthorizationInfo().areActivitiesEnabled
                  || Activity<CortexTaskBoardAttributes>.activities.contains {
                    Self.ongoing($0.activityState)
                  })
            } else {
              continuation.resume(returning: true)
            }
          }
        }
        if restored { return }
      }
    }
  }

  @available(iOS 16.2, *)
  private func observe(_ activity: Activity<CortexTaskBoardAttributes>) {
    guard liveWatchers[activity.id] == nil else { return }
    liveWatchers[activity.id] = Task { [weak self] in
      for await state in activity.activityStateUpdates {
        guard let self, !Task.isCancelled else { return }
        if self.defaults.string(forKey: "cortex.focus.liveID") == activity.id {
          self.defaults.set(String(describing: state), forKey: "cortex.focus.liveState")
          Self.changed?()
          // Expiry is different from the owner dismissing the card. Renew an
          // expired card while foregrounded; reopening restores either case.
          if state == .ended && !self.visible.isEmpty
            && UIApplication.shared.applicationState == .active
          {
            self.restoreOnOpen()
          }
        }
        if state == .ended || state == .dismissed {
          self.liveWatchers.removeValue(forKey: activity.id)
          return
        }
      }
    }
  }
  func handle(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    enqueue {
      do {
        switch method {
        case "focusPermission":
          _ = try await self.center.requestAuthorization(options: [.alert, .sound])
          try await self.schedule()
        case "focusRestore":
          self.liveAttempt = nil
          try await self.schedule()
        case "focusApply":
          if let hours = args["quietHours"] as? [String: String] {
            self.defaults.set(hours, forKey: "cortex.focus.quietHours")
          }
          let incoming =
            args["focuses"] as? [[String: Any]] ?? (args["focus"] as? [String: Any]).map { [$0] }
            ?? []
          // Protect only tasks with unsent actions; other overlapping tasks can still refresh.
          let blocked = Set(self.pending.compactMap { $0["id"] as? String })
          var merged = incoming.filter { !blocked.contains($0["id"] as? String ?? "") }.map {
            remote in
            if let local = self.tasks.first(where: {
              $0["id"] as? String == remote["id"] as? String
            }), (local["revision"] as? Int ?? 0) > (remote["revision"] as? Int ?? 0) {
              return local
            }
            return remote
          }
          merged += self.tasks.filter { blocked.contains($0["id"] as? String ?? "") }
          self.tasks = merged
          try await self.schedule()
        case "focusPage":
          guard let page = args["page"] as? Int else {
            throw CortexNative.failure("Invalid task page.")
          }
          try await self.setPage(page)
        case "focusAction": try await self.act(args)
        case "focusAcknowledge":
          let id = args["requestId"] as? String ?? ""
          if args["discarded"] as? Bool == true,
            let rejected = self.pending.first(where: { $0["requestId"] as? String == id }),
            let taskID = rejected["id"] as? String
          {
            self.pending = self.pending.filter { $0["id"] as? String != taskID }
            self.tasks = self.tasks.filter { $0["id"] as? String != taskID }
          } else {
            self.pending = self.pending.filter { $0["requestId"] as? String != id }
          }
        case "focusPreview": self.requestPreview()
        case "focusPreviewAcknowledge":
          self.defaults.removeObject(forKey: "cortex.focus.previewRequest")
        case "focusOpenAcknowledge": self.defaults.removeObject(forKey: "cortex.focus.openRequest")
        #if targetEnvironment(simulator)
          case "focusTestExpire":
            // Expiry ends the activity but leaves its final card on the Lock Screen.
            // Immediate dismissal skips that state, just like removing the card.
            // This method is not present in physical iPhone builds.
            if #available(iOS 16.2, *) {
              for activity in Activity<CortexTaskBoardAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .default)
              }
            }
        #endif
        default: break
        }
        result(await self.status())
      } catch {
        result(
          FlutterError(code: "task_checkin", message: error.localizedDescription, details: nil))
      }
    }
  }
  func perform(id: String, revision: Int, action: String, minutes: Int) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      enqueue {
        do {
          try await self.act([
            "id": id, "expectedRevision": revision, "action": action, "minutes": minutes,
          ])
          if action != "select" { await self.syncInBackground() }
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  // Paging is local presentation state: no task edits, outbox entries or server calls.
  private func setPage(_ page: Int) async throws {
    defaults.set(max(0, min(page, lastPage)), forKey: "cortex.focus.page")
    try await schedule()
  }
  func showPage(_ page: Int) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      enqueue {
        do {
          try await self.setPage(page)
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  @available(iOS 16.2, *)
  private func coveredTasks(_ activity: Activity<CortexTaskBoardAttributes>) -> [String] {
    defaults.stringArray(forKey: "cortex.focus.coverage." + activity.id)
      ?? activity.content.state.tasks.map { $0.id }
  }
  private func status() async -> [String: Any] {
    let permission = await center.notificationSettings()
    let requests = await center.pendingNotificationRequests().filter {
      $0.identifier.hasPrefix(prefix)
    }
    let delivered = await center.deliveredNotifications().filter {
      $0.request.identifier.hasPrefix(prefix)
    }.count
    var live = false
    var enabled = false
    var liveCount = 0
    var liveID = ""
    var livePage = 0
    var livePages = 0
    var liveTaskIDs: [String] = []
    var scheduledBoards: [[String: Any]] = []
    var coveredIDs: [String] = []
    if #available(iOS 16.2, *) {
      let current = Activity<CortexTaskBoardAttributes>.activities.filter {
        Self.ongoing($0.activityState)
      }
      let all = Activity<CortexTaskBoardAttributes>.activities
      scheduledBoards = all.filter { Self.scheduled($0.activityState) }.map {
        [
          "id": $0.id, "start": $0.attributes.windowStart.map(Self.iso) ?? "",
          "taskIDs": coveredTasks($0),
        ]
      }
      coveredIDs = all.filter { Self.ongoing($0.activityState) || Self.scheduled($0.activityState) }
        .flatMap { coveredTasks($0) }
      enabled = ActivityAuthorizationInfo().areActivitiesEnabled
      liveCount = enabled ? current.count : 0
      live = enabled && !current.isEmpty
      liveID = live ? current.first?.id ?? "" : ""
      if live, let content = current.first?.content.state {
        livePage = content.pageIndex
        livePages = content.pageCount
        liveTaskIDs = content.visibleTasks.map { $0.id }
      }
    }
    let state: String
    switch permission.authorizationStatus {
    case .authorized: state = "authorized"
    case .provisional, .ephemeral: state = "quiet"
    case .denied: state = "denied"
    default: state = "notDetermined"
    }
    var taskNotifications: [String: [String: Any]] = [:]
    for f in tasks {
      let id = f["id"] as? String ?? ""
      let matching = requests.filter { $0.content.userInfo["focusId"] as? String == id }
      let through = matching.compactMap {
        ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
      }.max()
      taskNotifications[id] = ["count": matching.count, "through": through.map(Self.iso) ?? ""]
    }
    return [
      "taskNotifications": taskNotifications,
      "permission": state, "liveEnabled": enabled, "liveActive": live, "liveCount": liveCount,
      "liveActivityID": liveID, "scheduledBoards": scheduledBoards, "liveCoveredIDs": coveredIDs,
      "livePage": livePage, "livePages": livePages, "liveTaskIDs": liveTaskIDs,
      "liveState": live
        ? "active"
        : !scheduledBoards.isEmpty
          ? "scheduled"
          : openTasks.isEmpty
            ? "none"
            : !enabled
              ? "disabled"
              : defaults.string(forKey: "cortex.focus.liveState") ?? "missing",
      "notificationCount": requests.count, "deliveredCount": delivered,
      "scheduledThrough": defaults.string(forKey: "cortex.focus.through") ?? "",
      "focus": selected as Any? ?? NSNull(),
      "focuses": tasks.map { f in
        var v = f
        v["status"] = phase(f)
        return v
      }, "pending": pending,
      "previewRequest": defaults.dictionary(forKey: "cortex.focus.previewRequest") as Any?
        ?? NSNull(),
      "openRequest": defaults.dictionary(forKey: "cortex.focus.openRequest") as Any? ?? NSNull(),
    ]
  }
  private func clearNotifications() async {
    let ids = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
      .map(\.identifier)
    center.removePendingNotificationRequests(withIdentifiers: ids)
    let delivered = await center.deliveredNotifications().filter {
      $0.request.identifier.hasPrefix(prefix)
    }.map { $0.request.identifier }
    center.removeDeliveredNotifications(withIdentifiers: delivered)
    defaults.removeObject(forKey: "cortex.focus.through")
  }
  private func schedule() async throws {
    let tracked = openTasks.filter {
      ["pending", "active", "ready"].contains($0["status"] as? String ?? "")
    }
    let taskSignature = tracked.map { "\($0["id"] ?? "").\($0["revision"] ?? 0)" }.sorted().joined(
      separator: "/")
    let quiet = defaults.dictionary(forKey: "cortex.focus.quietHours") as? [String: String] ?? [:]
    func minute(_ text: String?) -> Int? {
      let parts = (text ?? "").split(separator: ":")
      guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h),
        (0...59).contains(m)
      else { return nil }
      return h * 60 + m
    }
    func awake(_ date: Date) -> Bool {
      guard let wake = minute(quiet["wake"]), let bed = minute(quiet["bedtime"]), bed > wake else {
        return true
      }
      let c = Calendar.current.dateComponents([.hour, .minute], from: date)
      let at = (c.hour ?? 0) * 60 + (c.minute ?? 0)
      return at >= wake && at < bed
    }
    let signature =
      taskSignature + "/" + (quiet["wake"] ?? "") + "/" + (quiet["bedtime"] ?? "") + "/"
      + TimeZone.current.identifier
    let settings = await center.notificationSettings()
    let allowed =
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    let existing = await center.pendingNotificationRequests().filter {
      $0.identifier.hasPrefix(prefix)
    }
    var through = Self.date(defaults.string(forKey: "cortex.focus.through")) ?? .distantPast
    if signature != defaults.string(forKey: "cortex.focus.scheduleSignature")
      || (!allowed && !existing.isEmpty) || (allowed && existing.count < 8)
    {
      await clearNotifications()
      through = .distantPast
      let now = Date()
      var candidates: [(Date, [String: Any])] = []
      for f in tracked {
        let ready = ["pending", "ready"].contains(f["status"] as? String ?? "")
        guard let anchor = Self.date(f[ready ? "scheduledStart" : "expectedEnd"]) else { continue }
        let interval = TimeInterval((f["intervalMinutes"] as? Int ?? 15) * 60)
        if ready && activation(f) > now { candidates.append((activation(f), f)) }
        if anchor > now { candidates.append((anchor, f)) }
        var next = anchor.addingTimeInterval(10 * 60)
        if next <= now {
          next = next.addingTimeInterval(
            (floor(now.timeIntervalSince(next) / interval) + 1) * interval)
        }
        for _ in 0..<32 {
          if next > max(now, anchor).addingTimeInterval(8 * 3600) { break }
          candidates.append((next, f))
          next = next.addingTimeInterval(interval)
        }
      }
      if allowed {
        for (date, f) in candidates.filter({ awake($0.0) }).sorted(by: { $0.0 < $1.0 }).prefix(40) {
          let ready = ["pending", "ready"].contains(f["status"] as? String ?? "")
          let content = UNMutableNotificationContent()
          content.title =
            ready
            ? "Ready for \(f["title"] ?? "your task")?"
            : "Still working on \(f["title"] ?? "your task")?"
          content.body =
            ready
            ? "Start when you’re ready, or tell me what changed."
            : "Are you doing okay? Finish, add time, or take a break."
          content.sound = .default
          content.categoryIdentifier = ready ? "CORTEX_FOCUS_READY" : "CORTEX_FOCUS"
          content.threadIdentifier = "cortex-task-board"
          content.userInfo = ["focusId": f["id"] ?? "", "revision": f["revision"] ?? 0]
          do {
            try await center.add(
              UNNotificationRequest(
                identifier:
                  "\(prefix)\(f["id"] ?? "").\(f["revision"] ?? 0).\(Int(date.timeIntervalSince1970))",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                  timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
          } catch {
            // A reminder scheduling failure must not hide the task card. Status
            // reports only notifications iOS actually accepted.
            continue
          }
          through = date
        }
      }
      defaults.set(
        through > .distantPast ? Self.iso(through) : "", forKey: "cortex.focus.through")
      defaults.set(signature, forKey: "cortex.focus.scheduleSignature")
    }
    if #available(iOS 16.2, *) {
      for old in Activity<CortexFocusAttributes>.activities {
        await old.end(nil, dismissalPolicy: .immediate)
      }
      await scheduleBoards(through: through)
      let queued = Activity<CortexTaskBoardAttributes>.activities.filter {
        Self.scheduled($0.activityState)
      }
      let duplicateAlerts = await center.pendingNotificationRequests().filter { request in
        guard request.identifier.hasPrefix(prefix),
          let id = request.content.userInfo["focusId"] as? String,
          let at = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return queued.contains { board in
          guard let start = board.attributes.windowStart, abs(start.timeIntervalSince(at)) < 2
          else { return false }
          return coveredTasks(board).contains(id)
        }
      }.map(\.identifier)
      center.removePendingNotificationRequests(withIdentifiers: duplicateAlerts)

    }
  }
  @available(iOS 16.2, *)
  private static func scheduled(_ state: ActivityState) -> Bool {
    if #available(iOS 26.0, *) { return state == .pending }
    return false
  }

  @available(iOS 16.2, *)
  private func scheduleBoards(through: Date) async {
    let now = Date()
    let activities = Activity<CortexTaskBoardAttributes>.activities
    guard !openTasks.isEmpty else {
      for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
      liveAttempt = nil
      defaults.set(0, forKey: "cortex.focus.page")
      defaults.set("none", forKey: "cortex.focus.liveState")
      return
    }
    // Once the last available task ends, a future-only schedule must wait for
    // its activation time instead of inheriting the old visible card.
    let current = visible.isEmpty ? nil : activities.first { Self.ongoing($0.activityState) }
    var remaining = openTasks
    var keep = Set<String>()
    // Queue a small rolling window. iOS limits both active and scheduled cards;
    // status reports only accepted requests, and ordinary notifications remain.
    for group in 0..<3 {
      guard !remaining.isEmpty else { break }
      let immediate = remaining.contains { phase($0) != "pending" }
      let firstActivation = remaining.map { activation($0) }.min() ?? now
      let at =
        group == 0 && current != nil
        ? (current!.attributes.windowStart ?? now)
        : (immediate ? now : max(now, firstActivation))
      let end = at.addingTimeInterval(8 * 3600)
      let candidates = remaining.filter { phase($0) != "pending" || activation($0) < end }
      let page = group == 0 ? min(boardPage, max(0, (candidates.count - 1) / 2)) : 0
      let chosen = Array(candidates.dropFirst(page * 2).prefix(2))
      let consumed = Set(candidates.compactMap { $0["id"] as? String })
      remaining.removeAll { consumed.contains($0["id"] as? String ?? "") }
      let key =
        group == 0 && current != nil
        ? current!.attributes.id : "board-\(Int(at.timeIntervalSince1970))"
      let cardTasks = chosen.compactMap { f -> CortexTaskBoardAttributes.TaskItem? in
        guard let finish = Self.date(f["expectedEnd"]), let id = f["id"] as? String else {
          return nil
        }
        let ready = ["pending", "ready"].contains(f["status"] as? String ?? "")
        // Keep the two-task payload below ActivityKit's 4 KB budget,
        // including multilingual titles. The app retains the full title.
        var title = ""
        for character in (f["title"] as? String ?? "Task") {
          if (title + String(character)).utf8.count > 72 { break }
          title.append(character)
        }
        return .init(
          id: id, title: title, status: phase(f),
          start: Self.date(f[ready ? "scheduledStart" : "startedAt"]) ?? now,
          end: finish, revision: f["revision"] as? Int ?? 0,
          preview: f["preview"] as? Bool ?? false, activateAt: ready ? activation(f) : nil)
      }
      guard !cardTasks.isEmpty else { continue }
      if group == 0 { defaults.set(page, forKey: "cortex.focus.page") }
      let content = ActivityContent(
        state: CortexTaskBoardAttributes.ContentState(
          tasks: cardTasks, selectedID: selected?["id"] as? String ?? cardTasks[0].id,
          remindersUntil: through, page: page, totalTaskCount: candidates.count), staleDate: end)
      let match =
        group == 0 && current != nil
        ? current
        : activities.first {
          $0.attributes.id == key
            && (Self.ongoing($0.activityState) || Self.scheduled($0.activityState))
        }
      if let match {
        keep.insert(match.id)
        defaults.set(Array(consumed).sorted(), forKey: "cortex.focus.coverage." + match.id)
        if match.content.state != content.state { await match.update(content) }
        observe(match)
        if Self.ongoing(match.activityState) {
          defaults.set(match.id, forKey: "cortex.focus.liveID")
        }
        continue
      }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else { continue }
      // Retire obsolete pending schedules before requesting replacements, freeing
      // the OS allowance after a Google event moves or is cancelled.
      for old in activities
      where !keep.contains(old.id) && Self.scheduled(old.activityState)
        && !remaining.contains(where: { f in
          coveredTasks(old).contains(f["id"] as? String ?? "")
        })
      {
        await old.end(nil, dismissalPolicy: .immediate)
      }
      do {
        let attributes = CortexTaskBoardAttributes(id: key, windowStart: at)
        let created: Activity<CortexTaskBoardAttributes>
        if at > now {
          if #available(iOS 26.0, *) {
            created = try Activity.request(
              attributes: attributes, content: content, pushType: nil,
              style: .standard,
              alertConfiguration: .init(
                title: "Your next task",
                body: "Starts in 30 minutes. Start when you’re ready, or postpone.", sound: .default
              ), start: at)
          } else {
            continue
          }
        } else {
          created = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        keep.insert(created.id)
        defaults.set(Array(consumed).sorted(), forKey: "cortex.focus.coverage." + created.id)
        observe(created)
        if at <= now { defaults.set(created.id, forKey: "cortex.focus.liveID") }
        defaults.set(at > now ? "scheduled" : "active", forKey: "cortex.focus.liveState")
      } catch {
        defaults.set("unavailable", forKey: "cortex.focus.liveState")
      }
    }
    for old in activities where !keep.contains(old.id) {
      await old.end(nil, dismissalPolicy: .immediate)
    }
  }

  private func act(_ args: [String: Any]) async throws {
    var list = tasks
    guard let id = args["id"] as? String,
      let index = list.firstIndex(where: { $0["id"] as? String == id }),
      let action = args["action"] as? String
    else { throw CortexNative.failure("That task has changed. Open Cortex to refresh.") }
    var f = list[index]
    guard args["expectedRevision"] as? Int == f["revision"] as? Int,
      CortexTaskState(rawValue: f["status"] as? String ?? "")?.allows(action) == true
    else { throw CortexNative.failure("That task has changed. Open Cortex to refresh.") }
    defaults.set(id, forKey: "cortex.focus.selected")
    if action == "select" {
      try await schedule()
      Self.changed?()
      return
    }
    let now = Date()
    let revision = f["revision"] as? Int ?? 0
    let minutes = args["minutes"] as? Int ?? 15
    var request: [String: Any] = [
      "action": action, "id": id, "expectedRevision": revision, "requestId": UUID().uuidString,
      "actionAt": Self.iso(now), "timezoneOffset": TimeZone.current.secondsFromGMT(for: now) / 60,
    ]
    switch action {
    case "begin":
      guard f["status"] as? String != "active" else {
        throw CortexNative.failure("This task has already started.")
      }
      f["startedAt"] = Self.iso(now)
      f["expectedEnd"] = Self.iso(
        now.addingTimeInterval(TimeInterval((f["durationMinutes"] as? Int ?? 25) * 60)))
      f["status"] = "active"
      request["expectedEnd"] = f["expectedEnd"]
    case "extend":
      guard ["active", "paused"].contains(f["status"] as? String ?? ""),
        [5, 10, 15].contains(minutes)
      else { throw CortexNative.failure("Start this task before adding time.") }
      if f["status"] as? String == "paused" { f["startedAt"] = Self.iso(now) }
      f["expectedEnd"] = Self.iso(
        max(now, Self.date(f["expectedEnd"]) ?? now).addingTimeInterval(TimeInterval(minutes * 60)))
      f["status"] = "active"
      request["expectedEnd"] = f["expectedEnd"]
      request["minutes"] = minutes
    case "postpone":
      let reason = (args["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !reason.isEmpty, reason.count <= 1000 else {
        throw CortexNative.failure("Tell me why or when would work better.")
      }
      if f["status"] as? String == "active" {
        f["durationMinutes"] = max(
          1, Int(ceil((Self.date(f["expectedEnd"]) ?? now).timeIntervalSince(now) / 60)))
      }
      f["status"] = "postponed"
      f["reason"] = reason
      request["reason"] = reason
    case "pause":
      if f["status"] as? String == "active" {
        f["durationMinutes"] = max(
          1, Int(ceil((Self.date(f["expectedEnd"]) ?? now).timeIntervalSince(now) / 60)))
      }
      f["status"] = "paused"
    case "complete":
      f["status"] = "done"
      f["completedAt"] = Self.iso(now)
    case "cancel": f["status"] = "cancelled"
    default: throw CortexNative.failure("Unknown task action.")
    }
    f["revision"] = revision + 1
    f["updated"] = Self.iso(now)
    list[index] = f
    // One persisted envelope prevents state/outbox mismatches when the process exits.
    defaults.set(["tasks": list, "pending": pending + [request]], forKey: "cortex.focus.envelope")
    try await schedule()
    Self.changed?()
  }
  private func requestPreview() {
    if defaults.dictionary(forKey: "cortex.focus.previewRequest") == nil {
      defaults.set(
        [
          "first": UUID().uuidString, "second": UUID().uuidString, "at": Self.iso(Date()),
          "timezoneOffset": TimeZone.current.secondsFromGMT() / 60,
        ], forKey: "cortex.focus.previewRequest")
    }
  }
  func open(_ url: URL) -> Bool {
    guard url.scheme == "cortex", url.host == "focus" else { return false }
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ key: String) -> String? { parts.first { $0.name == key }?.value }
    let action = value("action") ?? "view"
    enqueue {
      if action == "page", let page = value("page").flatMap(Int.init) {
        try? await self.setPage(page)
      } else if action == "preview" {
        self.requestPreview()
      } else if action == "postpone" || action == "view" {
        self.defaults.set(
          [
            "id": value("id") ?? "", "action": action,
            "revision": Int(value("revision") ?? "") ?? -1,
          ], forKey: "cortex.focus.openRequest")
      } else {
        try? await self.act([
          "id": value("id") ?? "", "expectedRevision": Int(value("revision") ?? "") ?? -1,
          "action": action, "minutes": Int(value("minutes") ?? "") ?? 15,
        ])
      }
      Self.changed?()
    }
    return true
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    if #available(iOS 14.0, *) { return [.banner, .list, .sound] }
    return [.alert, .sound]
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    let action = response.actionIdentifier
    let reason = (response as? UNTextInputNotificationResponse)?.userText ?? ""
    await MainActor.run {
      self.enqueue {
        if ["begin", "extend", "pause", "complete", "postpone"].contains(action) {
          try? await self.act([
            "id": info["focusId"] ?? "", "expectedRevision": info["revision"] ?? -1,
            "action": action, "minutes": 15, "reason": reason,
          ])
          await self.syncInBackground()
        } else {
          Self.changed?()
        }
      }
    }
  }
  // App Intent actions can reach the server without opening Flutter. If the phone
  // is locked/offline, its durable outbox is retried on the next foreground sync.
  private func syncInBackground() async {
    do {
      var discardedTasks = Set<String>()
      for input in pending.prefix(8) {
        let taskID = input["id"] as? String ?? ""
        if discardedTasks.contains(taskID) { continue }
        do { _ = try await request("POST", "/v1/focus/actions", input) } catch let error as NSError
          where error.domain == "CortexHTTP" && [400, 409].contains(error.code)
        {
          let id = input["id"] as? String
          discardedTasks.insert(taskID)
          pending = pending.filter { $0["id"] as? String != id }
          tasks = tasks.filter { $0["id"] as? String != id }
          continue
        }
        pending = pending.filter { $0["requestId"] as? String != input["requestId"] as? String }
      }
      let result = try await request("GET", "/v1/focus")
      if pending.isEmpty { tasks = result["focuses"] as? [[String: Any]] ?? [] }
      try await schedule()
      let nativeState = await status()
      let perTask = nativeState["taskNotifications"] as? [String: [String: Any]] ?? [:]
      for f in tasks {
        let id = f["id"] as? String ?? ""
        let tracked = ["ready", "active"].contains(f["status"] as? String ?? "")
        let count = perTask[id]?["count"] as? Int ?? 0
        let confirmation =
          !tracked
          ? "stopped"
          : count > 0
            ? (nativeState["liveActive"] as? Bool == true ? "scheduled" : "notifications_only")
            : "needs_permission"
        _ = try await request(
          "POST", "/v1/focus/ack",
          [
            "id": id, "revision": f["revision"] ?? 0, "status": confirmation,
            "scheduledThrough": perTask[id]?["through"] ?? "",
          ])
      }
    } catch { /* Never discard an offline or uncertain action. */  }
    Self.changed?()
  }
  private func request(_ method: String, _ path: String, _ value: [String: Any]? = nil) async throws
    -> [String: Any]
  {
    let data =
      try value.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
      ?? Data()
    let key = try CortexNative.key()
    guard let pub = SecKeyCopyPublicKey(key),
      let pubData = SecKeyCopyExternalRepresentation(pub, nil) as Data?
    else { throw CortexNative.failure("Unlock to sync task changes.") }
    func hash(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let timestamp = String(Int(Date().timeIntervalSince1970))
    let nonce = UUID().uuidString
    let text = ["cortex-v1", method, path, timestamp, nonce, hash(data)].joined(separator: "\n")
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        key, .ecdsaSignatureMessageX962SHA256, Data(text.utf8) as CFData, &error) as Data?
    else { throw CortexNative.failure("Unlock to sync task changes.") }
    var request = URLRequest(url: URL(string: "https://cortex.miaotutu.com" + path)!)
    request.httpMethod = method
    if method != "GET" { request.httpBody = data }
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (name, value) in [
      "X-Cortex-Key-ID": hash(pubData), "X-Cortex-Timestamp": timestamp, "X-Cortex-Nonce": nonce,
      "X-Cortex-Signature": signature.base64EncodedString(),
    ] { request.setValue(value, forHTTPHeaderField: name) }
    let session = URLSession(configuration: .ephemeral)
    defer { session.finishTasksAndInvalidate() }
    let (bytes, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
      throw NSError(domain: "CortexHTTP", code: (response as? HTTPURLResponse)?.statusCode ?? 503)
    }
    return try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
  }

  @available(iOS 16.2, *)
  static func ongoing(_ state: ActivityState) -> Bool {
    return state == .active || state == .stale
  }
  static func date(_ value: Any?) -> Date? {
    guard let s = value as? String else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = f.date(from: s) { return date }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
  }
  static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
