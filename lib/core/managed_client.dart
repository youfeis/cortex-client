import 'dart:async';
import 'package:http/http.dart' as http;

/// Cancels active requests and waits for their native callbacks before closing.
class ManagedClient extends http.BaseClient {
  ManagedClient(this.inner);
  final http.Client inner;
  final _active = <_RequestWork>{};
  bool _closing = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closing) throw http.ClientException('Connection closed', request.url);
    final work = _RequestWork();
    _active.add(work);
    try {
      final outgoing =
          http.AbortableRequest(
              request.method,
              request.url,
              abortTrigger: work.abort.future,
            )
            ..followRedirects = request.followRedirects
            ..maxRedirects = request.maxRedirects
            ..headers.addAll(request.headers)
            ..bodyBytes = await request.finalize().toBytes();
      if (_closing) {
        throw http.ClientException('Connection closed', request.url);
      }
      final response = await inner.send(outgoing);
      return http.StreamedResponse(
        _read(response.stream, work),
        response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      _finish(work);
      rethrow;
    }
  }

  Stream<List<int>> _read(Stream<List<int>> stream, _RequestWork work) async* {
    try {
      yield* stream;
    } finally {
      _finish(work);
    }
  }

  void _finish(_RequestWork work) {
    _active.remove(work);
    if (!work.done.isCompleted) work.done.complete();
  }

  @override
  void close() {
    if (_closing) return;
    _closing = true;
    final pending = _active.toList();
    for (final work in pending) {
      if (!work.abort.isCompleted) work.abort.complete();
    }
    unawaited(
      Future.wait(pending.map((work) => work.done.future)).then((_) {
        inner.close();
      }),
    );
  }
}

class _RequestWork {
  final abort = Completer<void>();
  final done = Completer<void>();
}
