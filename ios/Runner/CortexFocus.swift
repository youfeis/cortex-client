import ActivityKit
import Flutter
import UIKit
import UserNotifications

// All mutations are serialized, including notification responses during startup.
@MainActor
final class CortexFocus: NSObject, UNUserNotificationCenterDelegate {
  static let shared = CortexFocus()
  static var changed: (() -> Void)?
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let prefix = "cortex.focus."
  private var work: Task<Void, Never>?
  private var item: [String: Any]? {
    get { defaults.dictionary(forKey: "cortex.focus.current") }
    set { defaults.set(newValue, forKey: "cortex.focus.current") }
  }
  private var pending: [[String: Any]] {
    get { defaults.array(forKey: "cortex.focus.pending") as? [[String: Any]] ?? [] }
    set { defaults.set(newValue, forKey: "cortex.focus.pending") }
  }
  func setup() {
    center.delegate = self
    let category = UNNotificationCategory(
      identifier: "CORTEX_FOCUS",
      actions: [
        UNNotificationAction(identifier: "complete", title: "Done", options: [.foreground]),
        UNNotificationAction(
          identifier: "extend", title: "Still working · +15 min", options: [.foreground]),
        UNNotificationAction(identifier: "pause", title: "Need a break", options: [.foreground]),
      ], intentIdentifiers: [])
    center.setNotificationCategories([category])
  }
  func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = work
    work = Task {
      await previous?.value
      await operation()
    }
  }
  func handle(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    enqueue {
      do {
        switch method {
        case "focusPermission":
          _ = try await self.center.requestAuthorization(options: [.alert, .sound])
        case "focusApply":
          if self.pending.isEmpty {
            if let incoming = args["focus"] as? [String: Any] {
              let current = self.item
              let newer = (incoming["revision"] as? Int ?? 0) >= (current?["revision"] as? Int ?? 0)
              if newer { self.item = incoming }
            } else {
              self.item = nil
            }
          }
          try await self.schedule()
        case "focusAction":
          try await self.act(args)
        case "focusAcknowledge":
          let id = args["requestId"] as? String ?? ""
          self.pending = self.pending.filter { $0["requestId"] as? String != id }
          // The server's authoritative state may have a lower revision after a conflict.
          if self.pending.isEmpty, args["discarded"] as? Bool == true { self.item = nil }
        default: break
        }
        result(await self.status())
      } catch {
        result(
          FlutterError(code: "task_checkin", message: error.localizedDescription, details: nil))
      }
    }
  }
  private func status() async -> [String: Any] {
    let permission = await center.notificationSettings()
    let requests = await center.pendingNotificationRequests().filter {
      $0.identifier.hasPrefix(prefix)
    }
    let delivered = await center.deliveredNotifications().filter {
      $0.request.identifier.hasPrefix(prefix)
    }.count
    let live: Bool
    let liveEnabled: Bool
    if #available(iOS 16.2, *) {
      live = Activity<CortexFocusAttributes>.activities.contains {
        $0.attributes.id == item?["id"] as? String
          && ($0.activityState == .active || $0.activityState == .stale)
      }
      liveEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    } else {
      live = false
      liveEnabled = false
    }
    let state: String
    switch permission.authorizationStatus {
    case .authorized: state = "authorized"
    case .provisional, .ephemeral: state = "quiet"
    case .denied: state = "denied"
    default: state = "notDetermined"
    }
    return [
      "permission": state, "liveEnabled": liveEnabled, "liveActive": live,
      "notificationCount": requests.count, "deliveredCount": delivered,
      "scheduledThrough": defaults.string(forKey: "cortex.focus.through") ?? "",
      "focus": item as Any? ?? NSNull(), "pending": pending,
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
    guard let f = item, f["status"] as? String == "active", let id = f["id"] as? String,
      let end = Self.date(f["expectedEnd"]), let start = Self.date(f["startedAt"])
    else {
      await clearNotifications()
      if #available(iOS 16.2, *) {
        for a in Activity<CortexFocusAttributes>.activities {
          await a.end(nil, dismissalPolicy: .immediate)
        }
      }
      defaults.removeObject(forKey: "cortex.focus.scheduledRevision")
      return
    }
    let revision = f["revision"] as? Int ?? 0
    let savedRevision = defaults.integer(forKey: "cortex.focus.scheduledRevision")
    let permission = await center.notificationSettings()
    let allowed =
      permission.authorizationStatus == .authorized
      || permission.authorizationStatus == .provisional
    let existing = await center.pendingNotificationRequests().filter {
      $0.identifier.hasPrefix(prefix)
    }
    // Refill only when needed, never reset reminder time on each server poll.
    let refresh =
      (!allowed && !existing.isEmpty) || savedRevision != revision || (allowed && existing.isEmpty)
      || (allowed && existing.count < 8)
    var through = Self.date(defaults.string(forKey: "cortex.focus.through")) ?? Date()
    if refresh {
      await clearNotifications()
      let now = Date()
      let interval = TimeInterval((f["intervalMinutes"] as? Int ?? 15) * 60)
      let horizon = max(now, end).addingTimeInterval(8 * 3600)
      // First check is after the expected finish. Missed checks are coalesced.
      var next = end.addingTimeInterval(interval)
      if next <= now {
        next = next.addingTimeInterval(
          (floor(now.timeIntervalSince(next) / interval) + 1) * interval)
      }
      var count = 0
      if allowed {
        while next <= horizon && count < 32 {
          let content = UNMutableNotificationContent()
          content.title = "Still working on \(f["title"] as? String ?? "your task")?"
          content.body = "Are you doing okay? You can finish, take more time, or have a break."
          content.sound = .default
          content.categoryIdentifier = "CORTEX_FOCUS"
          content.threadIdentifier = "cortex-current-task"
          content.userInfo = ["focusId": id, "revision": revision]
          let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, next.timeIntervalSinceNow), repeats: false)
          try await center.add(
            UNNotificationRequest(
              identifier: "\(prefix)\(id).\(revision).\(Int(next.timeIntervalSince1970))",
              content: content, trigger: trigger))
          through = next
          next = next.addingTimeInterval(interval)
          count += 1
        }
      }
      defaults.set(count > 0 ? Self.iso(through) : "", forKey: "cortex.focus.through")
      defaults.set(revision, forKey: "cortex.focus.scheduledRevision")
    }
    if #available(iOS 16.2, *) {
      let content = ActivityContent(
        state: CortexFocusAttributes.ContentState(
          expectedEnd: end, revision: revision, remindersUntil: through), staleDate: through)
      let activities = Activity<CortexFocusAttributes>.activities
      for a in activities where a.attributes.id != id {
        await a.end(nil, dismissalPolicy: .immediate)
      }
      if let a = activities.first(where: {
        $0.attributes.id == id && ($0.activityState == .active || $0.activityState == .stale)
      }) {
        if a.content.state != content.state { await a.update(content) }
      } else if UIApplication.shared.applicationState == .active
        && ActivityAuthorizationInfo().areActivitiesEnabled
      {
        // Do not undo the owner's swipe dismissal on every sync; resume explicitly to restore.
        let last = defaults.string(forKey: "cortex.focus.liveAttempt")
        let key = "\(id).\(revision)"
        if last != key {
          _ = try? Activity.request(
            attributes: CortexFocusAttributes(
              id: id, title: f["title"] as? String ?? "Current task", startedAt: start),
            content: content, pushType: nil)
          defaults.set(key, forKey: "cortex.focus.liveAttempt")
        }
      }
    }
  }
  private func act(_ args: [String: Any]) async throws {
    guard var f = item, let id = f["id"] as? String,
      args["id"] as? String == id,
      args["expectedRevision"] as? Int == f["revision"] as? Int,
      ["active", "paused"].contains(f["status"] as? String ?? ""),
      let action = args["action"] as? String,
      ["extend", "pause", "complete", "cancel"].contains(action)
    else {
      throw CortexNative.failure("That task has changed. Open Cortex to see your current task.")
    }
    let now = Date()
    let revision = f["revision"] as? Int ?? 0
    let request: [String: Any] = [
      "action": action, "id": id, "expectedRevision": revision, "requestId": UUID().uuidString,
      "expectedEnd": Self.iso(now.addingTimeInterval(15 * 60)), "actionAt": Self.iso(now),
    ]
    f["revision"] = revision + 1
    f["status"] =
      ["extend": "active", "pause": "paused", "complete": "done", "cancel": "cancelled"][action]
    if action == "extend" { f["expectedEnd"] = request["expectedEnd"] }
    item = f
    pending.append(request)
    // A break/done stops local alerts immediately, including without network access.
    try await schedule()
    Self.changed?()
  }
  func open(_ url: URL) -> Bool {
    guard url.scheme == "cortex", url.host == "focus" else { return false }
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ key: String) -> String? { parts.first { $0.name == key }?.value }
    let action = value("action") ?? "view"
    if action != "view" {
      let args: [String: Any] = [
        "id": value("id") ?? "", "expectedRevision": Int(value("revision") ?? "") ?? -1,
        "action": action,
      ]
      enqueue { do { try await self.act(args) } catch { Self.changed?() } }
    } else {
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
    await MainActor.run {
      if ["extend", "pause", "complete"].contains(action) {
        self.enqueue {
          try? await self.act([
            "id": info["focusId"] ?? "", "expectedRevision": info["revision"] ?? -1,
            "action": action,
          ])
        }
      } else {
        Self.changed?()
      }
    }
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
