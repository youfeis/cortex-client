import AlarmKit
import Flutter
import SwiftUI

@available(iOS 26.0, *)
private struct CortexAlarmMetadata: AlarmMetadata { var title: String }

/// System alarms remain scheduled without the Flutter engine or a server connection.
@available(iOS 26.0, *)
@MainActor
enum CortexAlarms {
  static let manager = AlarmManager.shared
  static var watching = false
  static var changed: (() -> Void)?
  static let ledgerKey = "cortex.alarm.commands.v1"
  static let specsKey = "cortex.alarm.specs.v1"

  static func observe() {
    guard !watching else { return }
    watching = true
    Task { for await _ in manager.alarmUpdates { changed?() } }
    Task { for await _ in manager.authorizationUpdates { changed?() } }
  }

  static func permission() -> String {
    switch manager.authorizationState {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unavailable"
    }
  }

  static func status() throws -> [String: Any] {
    observe()
    let alarms = permission() == "authorized" ? try manager.alarms : []
    return ["permission": permission(), "scheduledIds": alarms.map { $0.id.uuidString.lowercased() },
            "states": Dictionary(uniqueKeysWithValues: alarms.map { ($0.id.uuidString.lowercased(), String(describing: $0.state)) })]
  }

  static func handle(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        switch method {
        case "alarmPermission":
          _ = try await manager.requestAuthorization()
          result(try status())
        case "alarmStatus": result(try status())
        case "alarmApply": result(try await apply(args))
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "alarm", message: "The iPhone could not complete this alarm request. Please try again.", details: nil))
      }
    }
  }

  static func apply(_ command: [String: Any]) async throws -> [String: Any] {
    guard let idText = command["id"] as? String, let id = UUID(uuidString: idText),
          let revision = command["revision"] as? Int, revision > 0,
          let action = command["action"] as? String else { throw CortexNative.failure("Invalid alarm command.") }
    // The first explicit alarm request may prompt; passive status checks never do.
    if manager.authorizationState == .notDetermined {
      _ = try await manager.requestAuthorization()
    }
    guard manager.authorizationState == .authorized else {
      return ["status": "needs_permission", "error": "Allow Alarms in Cortex settings to finish this request."]
    }
    var ledger = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Int] ?? [:]
    let existing = try manager.alarms.first { $0.id == id }
    let registered = existing != nil
    var specs = UserDefaults.standard.dictionary(forKey: specsKey) as? [String: [String: Any]] ?? [:]
    if let applied = ledger[idText], applied > revision {
      return ["status": "failed", "error": "A newer version of this alarm is already on your phone."]
    }
    if action == "cancel" {
      if registered { try manager.cancel(id: id) }
      guard try !manager.alarms.contains(where: { $0.id == id }) else { throw CortexNative.failure("Cancellation was not confirmed.") }
      ledger[idText] = revision
      UserDefaults.standard.set(ledger, forKey: ledgerKey)
      specs.removeValue(forKey: idText)
      UserDefaults.standard.set(specs, forKey: specsKey)
      return ["status": "cancelled"]
    }
    guard action == "schedule", let spec = command["spec"] as? [String: Any],
          let title = spec["title"] as? String, !title.isEmpty, title.count <= 160 else { throw CortexNative.failure("Invalid alarm details.") }
    // A lost server acknowledgement must not create a second alarm or re-arm a dismissed one.
    if ledger[idText] == revision {
      return registered ? ["status": "scheduled"] : ["status": "expired", "error": "This alarm has already ended or was removed on the phone."]
    }
    let schedule: Alarm.Schedule
    let weekdays = spec["weekdays"] as? [Int] ?? []
    if !weekdays.isEmpty {
      guard let hour = spec["hour"] as? Int, let minute = spec["minute"] as? Int,
            (0...23).contains(hour), (0...59).contains(minute), Set(weekdays).count == weekdays.count,
            weekdays.allSatisfy({ (1...7).contains($0) }) else { throw CortexNative.failure("Invalid weekly alarm.") }
      let days: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
      schedule = .relative(.init(time: .init(hour: hour, minute: minute), repeats: .weekly(weekdays.map { days[$0 - 1] })))
    } else {
      let formatter = ISO8601DateFormatter()
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let at = spec["at"] as? String, let date = formatter.date(from: at) ?? fractional.date(from: at) else { throw CortexNative.failure("Invalid alarm date.") }
      guard date > Date() else { return ["status": "expired", "error": "The requested alarm time has passed. Ask Cortex for a new time."] }
      schedule = .fixed(date)
    }
    if registered { try manager.cancel(id: id) }
    do {
      _ = try await manager.schedule(id: id, configuration: configuration(schedule, title))
    } catch {
      if let previous = existing?.schedule {
        do {
          let oldTitle = specs[idText]?["title"] as? String ?? "Cortex alarm"
          _ = try await manager.schedule(id: id, configuration: configuration(previous, oldTitle))
          return ["status": "failed", "error": "The change failed. Your previous alarm was restored on this iPhone."]
        } catch {
          return ["status": "failed", "error": "The change failed and the previous alarm could not be restored. Ask Cortex to set a new alarm."]
        }
      }
      return ["status": "failed", "error": "iOS could not schedule this alarm. Ask Cortex to retry."]
    }
    guard try manager.alarms.contains(where: { $0.id == id && $0.schedule == schedule }) else { throw CortexNative.failure("Alarm was not confirmed by iOS.") }
    ledger[idText] = revision
    specs[idText] = spec
    UserDefaults.standard.set(ledger, forKey: ledgerKey)
    UserDefaults.standard.set(specs, forKey: specsKey)
    return ["status": "scheduled"]
  }

  private static func configuration(_ schedule: Alarm.Schedule, _ title: String) -> AlarmManager.AlarmConfiguration<CortexAlarmMetadata> {
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = .init(title: LocalizedStringResource(stringLiteral: title))
    } else {
      alert = .init(title: LocalizedStringResource(stringLiteral: title), stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
    }
    let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: CortexAlarmMetadata(title: title), tintColor: Color(red: 0.18, green: 0.25, blue: 0.21))
    return .alarm(schedule: schedule, attributes: attributes)
  }
}
