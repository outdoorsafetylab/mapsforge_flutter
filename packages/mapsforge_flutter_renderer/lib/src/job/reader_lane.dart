import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mapsforge_flutter_renderer/src/job/job_request.dart';

/// Sends the requests of one kind (tiles or label blocks) to the reader, at most [slots] at a time.
///
/// The reader isolate works on every request it gets at once, so a request sent for a position the map already left
/// shares the CPU with the requests for the new one. The lane holds the requests back instead: waiting requests are
/// sent in their [JobRequest.order], and the ones whose job is cancelled meanwhile ([JobRequest.isCancelled]) are
/// dropped with a [JobCancelledException] without reaching the reader. A request already sent runs to its end.
class ReaderLane {
  /// The number of requests at most in the reader at the same time.
  final int slots;

  final List<_Waiting> _waiting = [];

  int _running = 0;

  /// Counts the arrived requests, requests of the same order are sent in the order they arrived.
  int _arrived = 0;

  bool _disposed = false;

  ReaderLane(this.slots) : assert(slots > 0);

  /// The number of requests sent and not yet done.
  @visibleForTesting
  int get running => _running;

  /// The number of requests waiting for a slot.
  @visibleForTesting
  int get waiting => _waiting.length;

  /// Runs [task] for [request] as soon as a slot is free, unless the request is cancelled before.
  Future<T> run<T>(JobRequest request, Future<T> Function() task) {
    if (_disposed) return Future.error(JobCancelledException(request.tile));
    _Waiting<T> waiting = _Waiting<T>(request, task, _arrived++);
    _waiting.add(waiting);
    _pump();
    return waiting.completer.future;
  }

  /// Drops the waiting requests, the requests already sent run to their end.
  void dispose() {
    _disposed = true;
    for (_Waiting waiting in _waiting) {
      waiting.cancel();
    }
    _waiting.clear();
  }

  void _pump() {
    // drop every cancelled request, not only the next one: each of them occupies a place in the task queue of its job
    // queue and so holds back the requests of the new job
    _waiting.removeWhere((waiting) {
      if (!waiting.cancelled) return false;
      waiting.cancel();
      return true;
    });
    while (_running < slots && _waiting.isNotEmpty) {
      _Waiting next = _waiting.reduce((a, b) => b.before(a) ? b : a);
      _waiting.remove(next);
      ++_running;
      unawaited(
        next.start().whenComplete(() {
          --_running;
          if (!_disposed) _pump();
        }),
      );
    }
  }
}

//////////////////////////////////////////////////////////////////////////////

class _Waiting<T> {
  final JobRequest request;

  final Future<T> Function() task;

  final int arrived;

  final Completer<T> completer = Completer<T>();

  _Waiting(this.request, this.task, this.arrived);

  bool get cancelled => request.isCancelled?.call() ?? false;

  bool before(_Waiting other) => request.order < other.request.order || (request.order == other.request.order && arrived < other.arrived);

  void cancel() => completer.completeError(JobCancelledException(request.tile));

  Future<void> start() async {
    try {
      completer.complete(await task());
    } catch (error, stacktrace) {
      completer.completeError(error, stacktrace);
    }
  }
}
