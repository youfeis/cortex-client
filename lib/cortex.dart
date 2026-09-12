import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
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
  final http.Client _http = http.Client();
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
  Entry(this.id, this.kind, this.data);
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['id'] as String,
    json['kind'] as String,
    Map<String, dynamic>.from(json['data'] as Map),
  );
}

class CortexModel extends ChangeNotifier {
  final CortexApi api;
  bool _disposed = false;
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
  Map<String, dynamic> chat = {'status': 'ready'};
  Map<String, dynamic>? account;
  int _streamGeneration = 0;
  Timer? _refreshTimer;
  final Map<String, Future<Uint8List>> _images = {};
  List<Entry> records(String kind) =>
      entries.where((e) => e.kind == kind).toList();
  bool get busy =>
      (chat['turnId'] as String? ?? '').isNotEmpty ||
      ['thinking', 'working', 'replying', 'steering'].contains(chat['status']);
  bool get loggedIn => account?['account'] != null;
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
    notifyListeners();
  }

  Future<void> refresh() async {
    if (refreshing) {
      return;
    }
    refreshing = true;
    try {
      final value = await api.call('GET', '/v1/snapshot') as Map;
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
    notifyListeners();
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
    await api.call('POST', '/v1/plan', input);
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

  Future<String> importHealth() async {
    final values = Map<String, dynamic>.from(
      await native.invokeMethod('readHealth') as Map,
    );
    final today = day();
    var count = 0;
    Future<void> add(String kind, Map<String, dynamic> data) async {
      await save(
        kind,
        {...data, 'date': today, 'source': 'appleHealth'},
        id: 'health-$kind-$today',
        reload: false,
      );
      count++;
    }

    if (values['steps'] != null) {
      await add('steps', {'count': (values['steps'] as num).round()});
    }
    if (values['kg'] != null) {
      await add('weight', {'kg': values['kg']});
    }
    if (values['systolic'] != null && values['diastolic'] != null) {
      await add('bp', {
        'systolic': (values['systolic'] as num).round(),
        'diastolic': (values['diastolic'] as num).round(),
      });
    }
    if (values['glucose'] is Map) {
      final glucose = Map<String, dynamic>.from(values['glucose'] as Map);
      final sampleID = glucose.remove('sampleId') as String;
      await save(
        'glucose',
        {...glucose, 'date': today, 'source': 'appleHealth'},
        id: 'health-glucose-$sampleID',
        reload: false,
      );
      count++;
    }
    if (values['activeKcal'] != null) {
      await add('activity', {
        'title': 'Apple Health active energy',
        'minutes': 0,
        'kcal': (values['activeKcal'] as num).round(),
      });
    }
    await refresh();
    return count == 0
        ? 'No shared Health data for today. Check Health permissions or enter it manually.'
        : 'Today’s available Health data is updated.';
  }

  Future<String> importCalendars() async {
    final rows = (await native.invokeMethod('readCalendars') as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ids = <String>{};
    final today = day();
    final end = day(DateTime.now().add(const Duration(days: 7)));
    for (final row in rows) {
      final id =
          'calendar-${sha256.convert(utf8.encode('${row['externalId']}-${row['date']}')).toString().substring(0, 32)}';
      ids.add(id);
      await save(
        'event',
        {...row, 'source': 'iphoneCalendar'},
        id: id,
        reload: false,
      );
    }
    for (final old in records('event')) {
      final date = old.data['date'] as String? ?? '';
      if (old.data['source'] == 'iphoneCalendar' &&
          date.compareTo(today) >= 0 &&
          date.compareTo(end) < 0 &&
          !ids.contains(old.id)) {
        await api.call('DELETE', '/v1/records/${old.id}');
      }
    }
    await refresh();
    return '${rows.length} calendar entries imported for the next 7 days.';
  }

  @override
  void dispose() {
    _disposed = true;
    _streamGeneration++;
    _refreshTimer?.cancel();
    api.close();
    super.dispose();
  }
}
