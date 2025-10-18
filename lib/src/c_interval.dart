// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:collection/collection.dart';

import 'package:schedulers/src/b_base.dart';

/// Runs tasks asynchronously, maintaining a fixed time interval between starts.
///
/// For example, this allows to distribute many small tasks over time, so they
/// will not create a noticeable lag in the program interface. It is better to
/// run 100 tasks of 10 milliseconds each, redrawing frames between them, than
/// to run the tasks all at once, freezing the interface for a second.
class IntervalScheduler implements PriorityScheduler {
  IntervalScheduler({this.delay = const Duration(seconds: 1)});

  final _tasks = HeapPriorityQueue<PriorityTask<dynamic>>();
  final Duration delay;
  bool _scheduled = false;

  @override
  int get queueLength => _tasks.length;

  bool get isComplete => _tasks.length > 0;

  Completer<void> _completer = Completer();

  Future<void> get completed => _completer.future;

  /// Notifies the scheduler that it should run the callback sometime. The
  /// actual call will occur asynchronously at the time selected by the
  /// scheduler.
  @override
  Task<R> run<R>(GetterFunc<R> callback, [int priority = 0]) {
    if (_tasks.length <= 0) {
      _completer = Completer();
    }

    final newTask =
        PriorityTask(callback, priority, onCancel: _tasks.removeOrThrow);

    _tasks.add(newTask);
    _runRunnerLater();

    return newTask;
  }

  bool _disposed = false;
  void dispose() {
    _disposed = true;
    for (final t in _tasks.toList()) {
      t.willRun = false; // todo unit test
    }
    _tasks.clear();
  }

  void _runner() {
    _scheduled = false;

    if (_disposed) {
      if (!_completer.isCompleted) {
        _completer.complete();
      }
      return;
    }

    try {
      unawaited(_tasks.removeFirst().runIfNotCanceled());
    } finally {
      if (_tasks.length <= 0) {
        _completer.complete();
      }

      _runRunnerLater();
    }
  }

  void _runRunnerLater() {
    if (!_scheduled && _tasks.length > 0) {
      Future.delayed(delay, _runner);
      _scheduled = true;
    }
  }
}
