import 'task_focus.dart';
import 'phone_alarms.dart';
import 'memory_notices.dart';
import '../remote_ui/layout_store.dart';
import 'managed_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const native = MethodChannel('com.miaotutu.cortex/native');
String day([DateTime? date]) =>
    (date ?? DateTime.now()).toIso8601String().substring(0, 10);
String clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class CortexApi {
  static const origin = 'https://cortex.miaotutu.com';
  final http.Client _http = ManagedClient(
    Platform.isIOS
        ? CupertinoClient.fromSessionConfiguration(
            URLSessionConfiguration.ephemeralSessionConfiguration(),
          )
        : http.Client(),
  );
  String? _publicKey;
  Future<String> publicKey() async =>
      _publicKey ??= (await native.invokeMethod<String>('publicKey'))!;
  Future<Map<String, String>> headers(
    String method,
    String path,
    List<int> body,
  ) async {
    final pub = await publicKey();
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final payload = [
      'cortex-v1',
      method,
      path,
      timestamp,
      nonce,
      sha256.convert(body).toString(),
    ].join('\n');
    final signature = await native.invokeMethod<String>('sign', {
      'payload': payload,
    });
    return {
      'Content-Type': 'application/json',
      'X-Cortex-Key-ID': sha256.convert(base64Decode(pub)).toString(),
      'X-Cortex-Timestamp': timestamp,
      'X-Cortex-Nonce': nonce,
      'X-Cortex-Signature': signature!,
    };
  }

  Future<dynamic> call(String method, String path, [Object? data]) async {
    final body = data == null ? <int>[] : utf8.encode(jsonEncode(data));
    final request = http.Request(method, Uri.parse('$origin$path'))
      ..bodyBytes = body
      ..headers.addAll(await headers(method, path, body));
    final response = await http.Response.fromStream(
      await _http.send(request),
    ).timeout(const Duration(seconds: 65));
    dynamic value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      value = null;
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        value is Map
            ? value['error']?.toString() ?? 'Please try again.'
            : 'The server is unavailable. Please try again.',
      );
    }
    return value;
  }

  Future<Uint8List> image(String id) async {
    final path = '/v1/images/$id';
    final response = await _http
        .get(Uri.parse('$origin$path'), headers: await headers('GET', path, []))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Photo unavailable');
    }
    return response.bodyBytes;
  }

  Future<String> upload(Uint8List bytes) async =>
      (await call('POST', '/v1/images', {'data': base64Encode(bytes)}))['id']
          as String;
  Stream<Map<String, dynamic>> events() async* {
    const path = '/v1/chat/events';
    final request = http.Request('GET', Uri.parse('$origin$path'))
      ..headers.addAll(await headers('GET', path, []));
    final response = await _http
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ApiException(response.statusCode, 'Chat connection interrupted');
    }
    await for (final line
        in response.stream
            .timeout(const Duration(seconds: 35))
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        yield Map<String, dynamic>.from(jsonDecode(line.substring(6)) as Map);
      }
    }
  }

  void close() => _http.close();
}

class Entry {
  final String id;
  final String kind;
  final Map<String, dynamic> data;
  final DateTime? updated;
  Entry(this.id, this.kind, this.data, {this.updated});
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['id'] as String,
    json['kind'] as String,
    Map<String, dynamic>.from(json['data'] as Map),
    updated: DateTime.tryParse(json['updated']?.toString() ?? ''),
  );
}

class CortexModel extends ChangeNotifier {
  final CortexApi api;
  bool _disposed = false;
  final memoryNotices = MemoryNotices();
  late final alarms = PhoneAlarms(
    api: api,
    changed: notifyListeners,
    canSync: () => !_disposed && paired && foreground,
  );
  late final taskFocus = TaskFocus(
    // An offline button press may finish syncing after its screen has refreshed.
    // Refresh canonical to-dos/routines once the completion actually commits.
    onCompletionSynced: () {
      if (!_disposed) unawaited(refresh().catchError((_) {}));
    },
    quietHours: () {
      final plans = entries.where((e) => e.kind == 'plan').toList()
        ..sort(
          (a, b) => (b.data['date'] as String? ?? '').compareTo(
            a.data['date'] as String? ?? '',
          ),
        );
      if (plans.isEmpty) return null;
      return {
        'wake': plans.first.data['wake'],
        'bedtime': plans.first.data['bedtime'],
      };
    },
    api: api,
    changed: notifyListeners,
    canSync: () => !_disposed && paired && foreground,
  );
  Timer? _alarmTimer;
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  CortexModel({CortexApi? api}) : api = api ?? CortexApi();
  bool initializing = true, paired = false, online = true, refreshing = false;
  String? startupError;
  List<Entry> entries = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic> routineStates = {};
  Map<String, dynamic> chat = {'status': 'ready'};
  Map<String, dynamic>? account;
  int _streamGeneration = 0;
  Timer? _refreshTimer, _servicesTimer;
  Map<String, dynamic>? quota;
  DateTime? quotaUpdated, _quotaAttempt;
  bool quotaLoading = false, quotaFailed = false, foreground = true;
  String calendarPermission = 'unknown';
  String? calendarError;
  DateTime? calendarSynced;
  List<Map<String, dynamic>> calendars = [];
  Set<String>? selectedCalendars;
  bool calendarSyncing = false;
  Future<void>? _calendarWork;
  bool get calendarGranted => calendarPermission == 'granted';
  final Map<String, Future<Uint8List>> _images = {};
  List<Entry> records(String kind) =>
      entries.where((e) => e.kind == kind).toList();
  bool get busy =>
      compressing ||
      (chat['turnId'] as String? ?? '').isNotEmpty ||
      ['thinking', 'working', 'replying', 'steering'].contains(chat['status']);
  bool get loggedIn => account?['account'] != null;

  bool compressionSubmitting = false;
  String? _compressionRequest, _compressionSource;
  bool get compressing => chat['status'] == 'compressing';

  Future<void> compressContext() async {
    if (compressionSubmitting || busy) return;
    compressionSubmitting = true;
    notifyListeners();
    try {
      final source = chat['threadId'] as String?;
      if (source == null || source.isEmpty) {
        throw ApiException(409, 'Refresh the conversation before compressing.');
      }
      if (_compressionSource != source) {
        _compressionRequest = null;
        _compressionSource = source;
      }
      final previous = chat['compaction'];
      if (previous is Map &&
          previous['id'] == _compressionRequest &&
          ['completed', 'failed'].contains(previous['status'])) {
        _compressionRequest = null;
      }
      // Preserve the key on network failure so Retry cannot rotate twice.
      _compressionRequest ??= newId();
      final job = Map<String, dynamic>.from(
        await api.call('POST', '/v1/chat/compact', {
              'requestId': _compressionRequest,
              'expectedSessionId': source,
            })
            as Map,
      );
      if (job['status'] == 'failed' || job['status'] == 'completed') {
        _compressionRequest = null;
      }
      chat = {
        ...chat,
        'compaction': job,
        'status': ['completed', 'failed'].contains(job['status'])
            ? 'ready'
            : 'compressing',
      };
      notifyListeners();
      await refresh();
    } finally {
      compressionSubmitting = false;
      notifyListeners();
    }
  }

  String? get ownerAvatarId {
    for (final entry in records('memory')) {
      if (entry.id == 'memory-owner-avatar') {
        final id = entry.data['avatarImageId'];
        if (id is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return id;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    initializing = true;
    startupError = null;
    notifyListeners();
    try {
      await api.call('GET', '/v1/me');
      paired = true;
      await refresh();
      await readAccount();
      startStream();
      startServices();
    } on ApiException catch (e) {
      if (e.status == 401) {
        paired = false;
      } else {
        startupError = e.message;
      }
    } catch (_) {
      startupError =
          'Could not connect. Check your internet connection, then try again.';
    }
    initializing = false;
    notifyListeners();
  }

  Future<void> pair(String code) async {
    await api.call('POST', '/v1/pair', {
      'code': code.trim(),
      'publicKey': await api.publicKey(),
      'name': 'My iPhone',
    });
    paired = true;
    await refresh();
    await readAccount();
    startStream();
    startServices();
    notifyListeners();
  }

  Future<void>? _refreshWork;
  bool _refreshAgain = false;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    // A request after a write must not reuse a snapshot started before it.
    _refreshAgain = true;
    return _refreshWork ??= _refreshSnapshots().whenComplete(
      () => _refreshWork = null,
    );
  }

  Future<void> _refreshSnapshots() async {
    refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final value =
            await api.call('GET', '/v1/snapshot?date=${day()}') as Map;
        if (_disposed) return;
        if (_refreshAgain) continue;
        routineStates = Map<String, dynamic>.from(
          value['routineStates'] as Map? ?? {},
        );
        await memoryNotices.receive(value['records'] as List);
        entries = (value['records'] as List)
            .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (value['fitnessRecords'] is List) {
          entries.removeWhere(
            (e) => ['weight', 'bp', 'glucose'].contains(e.kind),
          );
          entries.addAll(
            (value['fitnessRecords'] as List).map(
              (e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)),
            ),
          );
        }
        messages = (value['messages'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        sessions = ((value['sessions'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        chat = Map<String, dynamic>.from(value['chat'] as Map);
        online = true;
      } while (_refreshAgain && !_disposed);
    } on ApiException catch (e) {
      online = false;
      if (e.status == 401) {
        paired = false;
        _streamGeneration++;
      }
      rethrow;
    } catch (_) {
      online = false;
      rethrow;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> readAccount() async {
    account = Map<String, dynamic>.from(
      await api.call('GET', '/v1/account') as Map,
    );
    if (!loggedIn) {
      quota = null;
      quotaUpdated = null;
      _quotaAttempt = null;
    } else {
      unawaited(readQuota());
    }
    notifyListeners();
  }

  Future<void> readQuota({bool force = false}) async {
    if (_disposed || !paired || !loggedIn || quotaLoading) return;
    final now = DateTime.now();
    if (!force &&
        _quotaAttempt != null &&
        now.difference(_quotaAttempt!) < const Duration(seconds: 60)) {
      return;
    }
    _quotaAttempt = now;
    quotaLoading = true;
    notifyListeners();
    try {
      final result = Map<String, dynamic>.from(
        await api.call('GET', '/v1/account/limits') as Map,
      );
      if (loggedIn) {
        quota = result;
        quotaUpdated = DateTime.now();
        quotaFailed = false;
      }
    } catch (_) {
      quotaFailed = true;
    } finally {
      quotaLoading = false;
      notifyListeners();
    }
  }

  void startServices() {
    native.setMethodCallHandler((call) async {
      if (call.method == 'focusChanged') {
        unawaited(taskFocus.sync(afterAction: true));
      }
      if (call.method == 'alarmsChanged') {
        unawaited(alarms.sync());
      }
      if (call.method == 'healthChanged' &&
          foreground &&
          paired &&
          !_disposed) {
        _healthDebounce?.cancel();
        _healthDebounce = Timer(const Duration(seconds: 2), () => syncHealth());
      }
    });
    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground &&
          paired &&
          (busy ||
              taskFocus.checked == null ||
              DateTime.now().difference(taskFocus.checked!) >
                  const Duration(seconds: 30))) {
        unawaited(taskFocus.sync());
      }
      if (busy ||
          alarms.checked == null ||
          DateTime.now().difference(alarms.checked!) >
              const Duration(seconds: 30)) {
        unawaited(alarms.sync());
      }
    });
    unawaited(alarms.sync());
    unawaited(taskFocus.sync());
    _servicesTimer?.cancel();
    _servicesTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (foreground && paired) {
        unawaited(readAccount().catchError((_) {}));
        unawaited(syncCalendars());
        unawaited(layouts.refresh(this));
        unawaited(syncHealth());
        unawaited(readGoogleAccounts());
      }
    });
    unawaited(syncCalendars(refreshSources: true));
    unawaited(layouts.refresh(this));
    unawaited(syncHealth());
    unawaited(readGoogleAccounts());
  }

  void setForeground(bool active) {
    foreground = active;
    if (active && paired) {
      unawaited(taskFocus.sync());
      unawaited(alarms.sync());
      unawaited(refreshFitness().catchError((_) {}));
      unawaited(readAccount().catchError((_) {}));
      unawaited(syncCalendars(refreshSources: true));
      unawaited(layouts.refresh(this));
      unawaited(readGoogleAccounts());
    }
  }

  Future<void> save(
    String kind,
    Map<String, dynamic> data, {
    String? id,
    bool reload = true,
  }) async {
    id ??= newId();
    await api.call('PUT', '/v1/records/$id', {
      'id': id,
      'kind': kind,
      'data': data,
    });
    if (reload) {
      await refresh();
    }
  }

  Future<void> remove(Entry entry) async {
    await api.call('DELETE', '/v1/records/${entry.id}');
    await refresh();
  }

  Future<void> send(
    String text,
    List<String> images, {
    bool steer = false,
  }) async {
    await api.call('POST', '/v1/chat', {
      'text': text,
      'images': images,
      'mode': steer ? 'steer' : 'send',
      'localDate': day(),
      'localTime': clock(DateTime.now().hour * 60 + DateTime.now().minute),
      'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes,
    });
    await refresh();
  }

  Future<void> stop() async {
    await api.call('POST', '/v1/chat/stop');
    await refresh();
  }

  Future<void> arrange(Map<String, dynamic> input) async {
    await api.call('POST', '/v1/plan', {
      ...input,
      'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes,
    });
    await refresh();
  }

  Future<Uint8List> image(String id) =>
      _images.putIfAbsent(id, () => api.image(id));
  void startStream() {
    if (_disposed) {
      return;
    }
    final generation = ++_streamGeneration;
    () async {
      var failures = 0;
      while (paired && generation == _streamGeneration) {
        try {
          await for (final state in api.events()) {
            if (generation != _streamGeneration) {
              break;
            }
            chat = state;
            online = true;
            failures = 0;
            notifyListeners();
            if ((state['text'] as String? ?? '').isEmpty) {
              _refreshTimer?.cancel();
              _refreshTimer = Timer(const Duration(milliseconds: 400), () {
                refresh().catchError((_) {});
              });
            }
          }
        } catch (_) {
          if (_disposed || generation != _streamGeneration) {
            return;
          }
          online = false;
          failures++;
          notifyListeners();
        }
        if (generation != _streamGeneration) {
          break;
        }
        await Future<void>.delayed(
          Duration(seconds: min(15, 1 + failures * 2)),
        );
        if (paired) {
          try {
            await refresh();
          } catch (_) {}
        }
      }
    }();
  }

  List<Map<String, dynamic>> googleAccounts = [];
  String? googleError;
  bool _googleLoading = false;
  Future<void> readGoogleAccounts() async {
    if (_disposed || !paired || _googleLoading) return;
    _googleLoading = true;
    try {
      final response = await api.call('GET', '/v1/google/accounts') as Map;
      googleAccounts = (response['accounts'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      googleError = response['configured'] == true
          ? null
          : 'Google connection setup is still being completed.';
    } catch (_) {
      googleError = 'Could not check Google accounts. Will retry.';
    } finally {
      _googleLoading = false;
      notifyListeners();
    }
  }

  String healthPermission = 'checking';
  String? healthError;
  DateTime? healthSyncedAt;
  bool healthSyncing = false, healthHasData = false;
  Timer? _healthDebounce;
  String? _healthFingerprint;
  Future<void>? _healthWork;
  bool _healthAgain = false, _healthRequestAccess = false;

  Future<void> refreshFitness() async {
    // Keep chat/server data responsive while Health reads in parallel. If
    // Health uploads new readings, its refresh queues a snapshot after the write.
    await Future.wait([refresh(), syncHealth()]);
  }

  Future<String> importHealth() async {
    await syncHealth(requestAccess: true);
    return healthError ??
        (healthHasData
            ? 'Apple Health updates automatically.'
            : 'Access requested. Only the data you share can appear here.');
  }

  Future<void> syncHealth({bool requestAccess = false}) {
    if (_disposed || !paired) return Future.value();
    // Reopening during an earlier read must trigger another read of the phone.
    _healthAgain = true;
    _healthRequestAccess |= requestAccess;
    return _healthWork ??= _syncHealthReads().whenComplete(
      () => _healthWork = null,
    );
  }

  Future<void> _syncHealthReads() async {
    healthSyncing = true;
    notifyListeners();
    try {
      do {
        _healthAgain = false;
        final requestAccess = _healthRequestAccess;
        _healthRequestAccess = false;
        await _readAndSyncHealth(requestAccess);
      } while (_healthAgain && !_disposed && paired);
    } finally {
      healthSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _readAndSyncHealth(bool requestAccess) async {
    try {
      final value = Map<String, dynamic>.from(
        await native.invokeMethod('readHealth', {
              'requestAccess': requestAccess,
            })
            as Map,
      );
      if (_disposed || !paired) return;
      healthPermission = value['permission'] as String? ?? 'setupNeeded';
      final rows =
          (value['records'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
            ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      healthHasData = rows.isNotEmpty;
      healthError = value['partial'] == true
          ? 'Some Health readings are unavailable. Sync will retry.'
          : null;
      final fingerprint = jsonEncode(rows);
      if (rows.isNotEmpty && fingerprint != _healthFingerprint) {
        await api.call('POST', '/v1/health/sync', {'records': rows});
        await refresh();
        // Only acknowledge readings once they are also visible in the app.
        // A failed snapshot must be retried even when Health hasn't changed.
        _healthFingerprint = fingerprint;
      }
      if (healthPermission == 'requested' && value['partial'] != true) {
        healthSyncedAt = DateTime.now();
      }
    } catch (_) {
      healthError =
          'Health sync will retry. Unlock your iPhone and check Health access.';
    }
  }

  Future<void> chooseCalendars(Set<String> ids) async {
    await _calendarWork;
    await syncCalendars(selectedIds: ids, refreshSources: true);
  }

  Future<void> syncCalendars({
    bool refreshSources = false,
    Set<String>? selectedIds,
  }) {
    if (_disposed || !paired) return Future.value();
    if (_calendarWork != null) return _calendarWork!;
    final work = _syncCalendars(refreshSources, selectedIds);
    _calendarWork = work;
    return work.whenComplete(() => _calendarWork = null);
  }

  Future<void> _syncCalendars(bool force, Set<String>? selectedIds) async {
    calendarSyncing = true;
    notifyListeners();
    try {
      // Only the phone's time zone is needed. Calendar access comes from Google.
      final timeZone = await native.invokeMethod<String>('calendarTimeZone');
      final value =
          await api.call('POST', '/v1/google/sync', {
                'timeZone': ?timeZone,
                'force': force,
                if (selectedIds != null)
                  'selectedIds': selectedIds.toList()..sort(),
              })
              as Map;
      calendarPermission = value['status'] == 'needsLink'
          ? 'needsLink'
          : 'granted';
      calendarError = value['error'] as String?;
      calendars = (value['calendars'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      selectedCalendars = (value['selectedIds'] as List?)
          ?.cast<String>()
          .toSet();
      final synced = DateTime.tryParse(value['syncedAt'] as String? ?? '');
      if (synced != calendarSynced) {
        await refresh();
        calendarSynced = synced;
      }
    } catch (_) {
      calendarError = 'Google sync will retry. Your saved events are kept.';
    } finally {
      calendarSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _streamGeneration++;
    _refreshTimer?.cancel();
    _servicesTimer?.cancel();
    _healthDebounce?.cancel();
    _alarmTimer?.cancel();
    alarms.dispose();
    taskFocus.dispose();
    api.close();
    super.dispose();
  }
}
