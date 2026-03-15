// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';

import 'package:schedulers/src/b_base.dart';

/// Runs no more than N tasks in a certain period of time.
///
/// For example, no more than three tasks per second. The first three will be
/// executed immediately, and the rest will wait, then the next three will be
/// executed - and so on.
///
/// The object is useful, for example, for accessing an API with a limit of "no
/// more than 5 requests per minute".
class RateScheduler implements PriorityScheduler {
  RateScheduler(this.n, this.per) {
    if (n <= 0) {
      throw ArgumentError.value(n, 'n', 'Must be greater than zero.');
    }
    if (per <= Duration.zero) {
      throw ArgumentError.value(
        per,
        'per',
        'Must be greater than Duration.zero.',
      );
    }
  }
  final _queue = HeapPriorityQueue<PriorityTask<dynamic>>();

  // todo add dispose

  @override
  int get queueLength => _queue.length;

  final int n;
  final Duration per;
  final Stopwatch _clock = Stopwatch()..start();
  final Queue<int> _recentStartTimesUs = Queue<int>();

  /// Notifies the scheduler that it should run the callback sometime. The
  /// actual call will occur asynchronously at the time selected by the
  /// scheduler.
  @override
  Task<R> run<R>(GetterFunc<R> callback, [int priority = 0]) {
    PriorityTask<R>? result;
    result = PriorityTask<R>(
      callback,
      priority,
      onCancel: _queue.removeOrThrow,
    );
    _queue.add(result);
    unawaited(_loopAsync());
    return result;
  }

  void runEmpty() => _loopAsync();

  bool _isLooping = false;

  void stop() {
    _breakLoopNow = true;
  }

  bool _breakLoopNow = false;

  Future<void> _loopAsync() async {
    // предотвращаем параллельную работу нескольких _loop
    if (_isLooping) {
      return;
    }

    _isLooping = true;

    try {
      while (_queue.length > 0) {
        if (_breakLoopNow) {
          _breakLoopNow = false;
          break;
        }

        if (_recentStartTimesUs.length >= n) {
          // we will wail the oldest task to become "too old"
          final elapsedUs =
              _clock.elapsedMicroseconds - _recentStartTimesUs.first;
          final delay = Duration(
            microseconds: per.inMicroseconds - elapsedUs,
          );
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
            // sometimes this pause ends a few milliseconds earlier than
            // expected (the actual delay is shorter than specified by the
            // argument).
            //
            // It's not a problem. The code below will just determine that it is
            // not ready to start tasks. We'll come back here again and pause
            // again.
          }
        }

        // removing too old tasks
        while (_recentStartTimesUs.isNotEmpty) {
          final elapsedUs =
              _clock.elapsedMicroseconds - _recentStartTimesUs.first;
          if (elapsedUs < per.inMicroseconds) {
            break;
          }
          _recentStartTimesUs.removeFirst();
        }

        while (_recentStartTimesUs.length < n && _queue.isNotEmpty) {
          // running new task
          final task = _queue.removeFirst();
          // remembering task start time
          _recentStartTimesUs.add(_clock.elapsedMicroseconds);
          unawaited(Future(task.runIfNotCanceled));
        }
      }
    } finally {
      _isLooping = false;
    }
  }
}
