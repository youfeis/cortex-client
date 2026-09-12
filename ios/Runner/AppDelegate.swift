import Flutter
import UIKit
import Security
import HealthKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CortexNative")!
    let channel = FlutterMethodChannel(name: "com.miaotutu.cortex/native", binaryMessenger: registrar.messenger())
    CortexNative.calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: CortexNative.calendar, queue: .main) { _ in
      channel.invokeMethod("calendarsChanged", arguments: nil)
    }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "publicKey", "sign":
        CortexNative.queue.async {
          do {
            let key = try CortexNative.key()
            let value: String
            if call.method == "publicKey" {
              guard let publicKey = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw CortexNative.failure("Could not read this device's key.") }
              value = data.base64EncodedString()
            } else {
              guard let args = call.arguments as? [String: Any], let text = args["payload"] as? String, let data = text.data(using: .utf8) else { throw CortexNative.failure("Invalid signing request.") }
              var error: Unmanaged<CFError>?
              guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, &error) as Data? else { if let error = error { throw error.takeRetainedValue() }; throw CortexNative.failure("Unlock your iPhone and try again.") }
              value = signature.base64EncodedString()
            }
            DispatchQueue.main.async { result(value) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "device_key", message: error.localizedDescription, details: nil)) }
          }
        }
      case "readHealth": CortexNative.readHealth(result)
      case "readCalendarSnapshot": CortexNative.readCalendarSnapshot(call.arguments as? [String: Any] ?? [:], result)
      case "openAppSettings":
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) { result($0) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

enum CortexNative {
  static let queue = DispatchQueue(label: "com.miaotutu.cortex.key")
  static let tag = "com.miaotutu.cortex.device-signing.v1".data(using: .utf8)!
  static let health = HKHealthStore()
  static let calendar = EKEventStore()
  static var calendarObserver: NSObjectProtocol?
  static let calendarQueue = DispatchQueue(label: "com.miaotutu.cortex.calendars")
  static func failure(_ message: String) -> NSError { NSError(domain: "Cortex", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

  static func key() throws -> SecKey {
    let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag, kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecReturnRef as String: true]
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecSuccess { return found as! SecKey }
    guard status == errSecItemNotFound else { throw failure("Unlock your iPhone to use Cortex.") }
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil) else { throw failure("Could not protect the device key.") }
    var attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits as String: 256, kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: tag, kSecAttrAccessControl as String: access]]
    #if !targetEnvironment(simulator)
    attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    #endif
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { if let error = error { throw error.takeRetainedValue() }; throw failure("Could not create a device key.") }
    return key
  }

  static func readHealth(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else { result(FlutterError(code: "health", message: "Health data is unavailable on this device.", details: nil)); return }
    let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .bodyMass, .bloodPressureSystolic, .bloodPressureDiastolic, .bloodGlucose]
    let types = Set(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
    health.requestAuthorization(toShare: [], read: types) { granted, error in
      guard granted, error == nil else { DispatchQueue.main.async { result(FlutterError(code: "health", message: "Health access was not completed. You can still enter records manually.", details: nil)) }; return }
      let start = Calendar.current.startOfDay(for: Date())
      let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
      let group = DispatchGroup()
      let lock = NSLock()
      var values: [String: Any] = [:]
      for (id, name, unit) in [(HKQuantityTypeIdentifier.stepCount, "steps", HKUnit.count()), (.activeEnergyBurned, "activeKcal", HKUnit.kilocalorie())] {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
        group.enter()
        health.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
          if let value = statistics?.sumQuantity()?.doubleValue(for: unit) { lock.lock(); values[name] = value; lock.unlock() }
          group.leave()
        })
      }
      for (id, name, unit) in [(HKQuantityTypeIdentifier.bodyMass, "kg", HKUnit.gramUnit(with: .kilo))] {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
        group.enter()
        health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
          if let sample = samples?.first as? HKQuantitySample { lock.lock(); values[name] = sample.quantity.doubleValue(for: unit); lock.unlock() }
          group.leave()
        })
      }
      if let type = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
        group.enter()
        health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
          if let reading = samples?.first as? HKCorrelation,
             let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
             let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
             let systolic = reading.objects(for: systolicType).first as? HKQuantitySample,
             let diastolic = reading.objects(for: diastolicType).first as? HKQuantitySample {
            lock.lock()
            values["systolic"] = systolic.quantity.doubleValue(for: .millimeterOfMercury())
            values["diastolic"] = diastolic.quantity.doubleValue(for: .millimeterOfMercury())
            lock.unlock()
          }
          group.leave()
        })
      }
      if let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) {
        group.enter()
        health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
          if let sample = samples?.first as? HKQuantitySample {
            let meal = (sample.metadata?[HKMetadataKeyBloodGlucoseMealTime] as? NSNumber)?.intValue
            // HealthKit before-meal metadata does not establish a fasting duration.
            let context = meal == HKBloodGlucoseMealTime.preprandial.rawValue ? "beforeMeal" : meal == HKBloodGlucoseMealTime.postprandial.rawValue ? "afterMeal" : "unspecified"
            let row: [String: Any] = ["mgdl": sample.quantity.doubleValue(for: HKUnit(from: "mg/dL")), "context": context, "sampleId": sample.uuid.uuidString.lowercased(), "recordedAt": ISO8601DateFormatter().string(from: sample.startDate)]
            lock.lock(); values["glucose"] = row; lock.unlock()
          }
          group.leave()
        })
      }
      group.notify(queue: .main) { result(values) }
    }
  }

  static func readCalendarSnapshot(_ args: [String: Any], _ result: @escaping FlutterResult) {
    func read() {
      let status = EKEventStore.authorizationStatus(for: .event)
      let full: Bool
      if #available(iOS 17.0, *) { full = status == .fullAccess }
      else { full = status == .authorized }
      guard full else {
        let permission = status == .notDetermined ? "notDetermined" : "denied"
        DispatchQueue.main.async { result(["permission": permission]) }
        return
      }
      calendarQueue.async {
        if args["refreshSources"] as? Bool == true { calendar.refreshSourcesIfNecessary() }
        let available = calendar.calendars(for: .event)
        let selectedIDs = args["selectedIds"] as? [String]
        let selected = available.filter { selectedIDs == nil || selectedIDs!.contains($0.calendarIdentifier) }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
        let events = selected.isEmpty ? [] : calendar.events(matching: calendar.predicateForEvents(withStart: start, end: end, calendars: selected))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        var rows: [[String: Any]] = []
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for event in events where event.status != .canceled {
          // Include the occurrence time: recurring occurrences can share an ID.
          let occurrence = event.occurrenceDate ?? event.startDate!
          let external = "\(event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier)|\(occurrence.timeIntervalSince1970)"
          for offset in 0..<30 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            guard event.startDate < next && event.endDate > day else { continue }
            let begin = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
            let finish = Calendar.current.dateComponents([.hour, .minute], from: event.endDate)
            let from = event.startDate < day ? 0 : (begin.hour ?? 0) * 60 + (begin.minute ?? 0)
            let to = event.endDate >= next ? 1440 : (finish.hour ?? 0) * 60 + (finish.minute ?? 0)
            guard to > from else { continue }
            let date = formatter.string(from: day)
            let identity = "\(event.calendar.calendarIdentifier)|\(external)|\(date)"
            guard seen.insert(identity).inserted else { continue }
            counts[event.calendar.calendarIdentifier, default: 0] += 1
            rows.append(["externalId": external, "title": event.title ?? "Calendar event", "date": date, "start": from, "end": to, "allDay": event.isAllDay, "calendar": event.calendar.title, "calendarId": event.calendar.calendarIdentifier, "account": event.calendar.source.title])
          }
        }
        let calendars: [[String: Any]] = available.map {
          ["id": $0.calendarIdentifier, "title": $0.title, "account": $0.source.title, "sourceId": $0.source.sourceIdentifier, "count": counts[$0.calendarIdentifier, default: 0]]
        }
        let snapshot: [String: Any] = ["permission": "granted", "calendars": calendars, "events": rows, "start": formatter.string(from: start), "end": formatter.string(from: end)]
        DispatchQueue.main.async { result(snapshot) }
      }
    }
    if args["requestAccess"] as? Bool == true && EKEventStore.authorizationStatus(for: .event) == .notDetermined {
      if #available(iOS 17.0, *) { calendar.requestFullAccessToEvents { _, _ in read() } }
      else { calendar.requestAccess(to: .event) { _, _ in read() } }
    } else { read() }
  }
}
