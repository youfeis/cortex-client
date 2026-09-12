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
      case "readCalendars": CortexNative.readCalendars(result)
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
    let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .bodyMass, .bloodPressureSystolic, .bloodPressureDiastolic]
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
      group.notify(queue: .main) { result(values) }
    }
  }

  static func readCalendars(_ result: @escaping FlutterResult) {
    func read(_ granted: Bool, _ error: Error?) {
      guard granted, error == nil else { DispatchQueue.main.async { result(FlutterError(code: "calendar", message: "Calendar access is off. You can add schedules manually.", details: nil)) }; return }
      let start = Calendar.current.startOfDay(for: Date())
      let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
      let events = calendar.events(matching: calendar.predicateForEvents(withStart: start, end: end, calendars: nil))
      let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
      var rows: [[String: Any]] = []
      for event in events {
        for offset in 0..<7 {
          let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
          let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
          guard event.startDate < next && event.endDate > day else { continue }
          let begin = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
          let finish = Calendar.current.dateComponents([.hour, .minute], from: event.endDate)
          let from = event.startDate < day ? 0 : (begin.hour ?? 0) * 60 + (begin.minute ?? 0)
          let to = event.endDate >= next ? 1440 : (finish.hour ?? 0) * 60 + (finish.minute ?? 0)
          rows.append(["externalId": event.eventIdentifier ?? "\(event.startDate)", "title": event.title ?? "Calendar event", "date": formatter.string(from: day), "start": from, "end": to, "allDay": event.isAllDay, "calendar": event.calendar.title])
        }
      }
      DispatchQueue.main.async { result(rows) }
    }
    if #available(iOS 17.0, *) { calendar.requestFullAccessToEvents(completion: read) }
    else { calendar.requestAccess(to: .event, completion: read) }
  }
}
