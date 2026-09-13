import Flutter
import UIKit
import Security
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    CortexFocus.shared.setup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if CortexFocus.shared.open(url) { return true }
    return super.application(app, open:url, options:options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CortexNative")!
    let channel = FlutterMethodChannel(name: "com.miaotutu.cortex/native", binaryMessenger: registrar.messenger())
    CortexFocus.changed = { channel.invokeMethod("focusChanged", arguments: nil) }
    CortexNative.healthChanged = { channel.invokeMethod("healthChanged", arguments: nil) }
    if #available(iOS 26.0, *) { CortexAlarms.changed = { channel.invokeMethod("alarmsChanged", arguments: nil) } }
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
      case "focusStatus", "focusPermission", "focusApply", "focusAction", "focusAcknowledge", "focusRestore", "focusPreview", "focusPreviewAcknowledge", "focusOpenAcknowledge":
        CortexFocus.shared.handle(call.method, call.arguments as? [String: Any] ?? [:], result)
#if DEBUG
      case "focusTestExpire":
        CortexFocus.shared.handle(call.method, [:], result)
#endif
      case "alarmStatus", "alarmPermission", "alarmApply":
        if #available(iOS 26.0, *) { CortexAlarms.handle(call.method, call.arguments as? [String: Any] ?? [:], result) }
        else { result(["permission": "unavailable", "scheduledIds": [], "status": "failed", "error": "Alarms require iOS 26 or later."]) }
      case "readHealth": CortexNative.readHealth(call.arguments as? [String: Any] ?? [:], result)
      case "calendarTimeZone": result(TimeZone.current.identifier)
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

  static var healthObservers: [HKObserverQuery] = []
  static var healthChanged: (() -> Void)?
  static let healthIdentifiers: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .bodyMass, .bloodPressureSystolic, .bloodPressureDiastolic, .bloodGlucose]
  static var healthTypes: Set<HKObjectType> { Set(healthIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }) }

  static func observeHealth() {
    guard healthObservers.isEmpty else { return }
    for type in healthTypes {
      guard let sampleType = type as? HKSampleType else { continue }
      let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
        if error == nil { DispatchQueue.main.async { healthChanged?() } }
        completion()
      }
      healthObservers.append(observer)
      health.execute(observer)
    }
  }

  static func readHealth(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else { result(["permission": "unavailable", "records": []]); return }
    health.getRequestStatusForAuthorization(toShare: [], read: healthTypes) { status, error in
      guard error == nil else { DispatchQueue.main.async { result(FlutterError(code: "health", message: "Health is unavailable. Unlock your iPhone and try again.", details: nil)) }; return }
      if args["requestAccess"] as? Bool == true {
        health.requestAuthorization(toShare: [], read: healthTypes) { completed, error in
          guard completed, error == nil else { DispatchQueue.main.async { result(FlutterError(code: "health", message: "Health access setup was not completed.", details: nil)) }; return }
          readHealthSamples(result)
        }
      } else if status == .shouldRequest {
        DispatchQueue.main.async { result(["permission": "setupNeeded", "records": []]) }
      } else {
        readHealthSamples(result)
      }
    }
  }

  static func readHealthSamples(_ result: @escaping FlutterResult) {
    observeHealth()
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let historyStart = cal.date(byAdding: .day, value: -90, to: today)!
    let predicate = HKQuery.predicateForSamples(withStart: historyStart, end: Date(), options: .strictStartDate)
    let group = DispatchGroup(), lock = NSLock()
    var rows: [[String: Any]] = []
    var failed = false
    func add(_ kind: String, _ id: String, _ date: Date, _ data: [String: Any], timed: Bool = true) {
      let formatter = DateFormatter(); formatter.calendar = cal; formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
      var fields = data; fields["date"] = formatter.string(from: date); fields["source"] = "appleHealth"
      if timed { fields["recordedAt"] = ISO8601DateFormatter().string(from: date) }
      lock.lock(); rows.append(["id": "health-\(kind)-\(id)", "kind": kind, "data": fields]); lock.unlock()
    }
    // Statistics combine overlapping phone/watch sources using HealthKit's aggregation.
    for (id, kind, unit) in [(HKQuantityTypeIdentifier.stepCount, "steps", HKUnit.count()), (.activeEnergyBurned, "activity", HKUnit.kilocalorie())] {
      let type = HKObjectType.quantityType(forIdentifier: id)!
      let start = cal.date(byAdding: .day, value: -7, to: today)!
      group.enter()
      let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()), options: .cumulativeSum, anchorDate: today, intervalComponents: DateComponents(day: 1))
      query.initialResultsHandler = { _, results, error in
        if error != nil { lock.lock(); failed = true; lock.unlock() }
        results?.enumerateStatistics(from: start, to: Date()) { statistics, _ in
          guard let quantity = statistics.sumQuantity() else { return }
          let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
          let value = quantity.doubleValue(for: unit).rounded()
          let fields: [String: Any] = kind == "steps" ? ["count": value] : ["title": "Apple Health active energy", "minutes": 0, "kcal": value]
          add(kind, formatter.string(from: statistics.startDate), statistics.startDate, fields, timed: false)
        }
        group.leave()
      }
      health.execute(query)
    }
    for (identifier, kind, unit, field) in [(HKQuantityTypeIdentifier.bodyMass, "weight", HKUnit.gramUnit(with: .kilo), "kg"), (.bloodGlucose, "glucose", HKUnit(from: "mg/dL"), "mgdl")] {
      let type = HKObjectType.quantityType(forIdentifier: identifier)!
      group.enter()
      health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
        if error != nil { lock.lock(); failed = true; lock.unlock() }
        for sample in (samples as? [HKQuantitySample] ?? []) {
          var fields: [String: Any] = [field: sample.quantity.doubleValue(for: unit)]
          if kind == "glucose" {
            let meal = (sample.metadata?[HKMetadataKeyBloodGlucoseMealTime] as? NSNumber)?.intValue
            fields["context"] = meal == HKBloodGlucoseMealTime.preprandial.rawValue ? "beforeMeal" : meal == HKBloodGlucoseMealTime.postprandial.rawValue ? "afterMeal" : "unspecified"
          }
          add(kind, sample.uuid.uuidString.lowercased(), sample.startDate, fields)
        }
        group.leave()
      })
    }
    if let type = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
      group.enter()
      health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
        if error != nil { lock.lock(); failed = true; lock.unlock() }
        for reading in (samples as? [HKCorrelation] ?? []) {
          let st = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!, dt = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!
          if let sys = reading.objects(for: st).first as? HKQuantitySample, let dia = reading.objects(for: dt).first as? HKQuantitySample {
            add("bp", reading.uuid.uuidString.lowercased(), reading.startDate, ["systolic": sys.quantity.doubleValue(for: .millimeterOfMercury()), "diastolic": dia.quantity.doubleValue(for: .millimeterOfMercury())])
          }
        }
        group.leave()
      })
    }
    group.notify(queue: .main) {
      // iOS deliberately does not disclose per-type read permission. Empty results
      // must never mean permission granted, or delete previously saved readings.
      result(["permission": "requested", "records": rows, "partial": failed])
    }
  }

}
