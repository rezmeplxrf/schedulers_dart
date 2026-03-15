// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:schedulers/src/b_base.dart';

class TimeScheduler {
  final Map<InternalTask<dynamic>, Timer> _timers =
      <InternalTask<dynamic>, Timer>{};

  Task<R> run<R>(GetterFunc<R> func, DateTime time) {
    if (_disposed) {
      throw StateError('The object is disposed');
    }

    late final InternalTask<R> task;
    late final Timer timer;
    task = InternalTask<R>(
      func,
      onCancel: (_) {
        final removedTimer = _timers.remove(task);
        removedTimer?.cancel();
      },
    );
    timer = Timer(_computeDelay(time), () {
      _timers.remove(task);
      if (!_disposed) {
        unawaited(task.runIfNotCanceled());
      }
    });
    _timers[task] = timer;

    return task;
  }

  void dispose() {
    for (final task in _timers.keys.toList()) {
      task.willRun = false;
    }
    _timers.clear();
    _disposed = true;
  }

  bool _disposed = false;

  Duration _computeDelay(DateTime targetTime, {DateTime? now}) {
    now ??= DateTime.now();

    if (targetTime.isBefore(now)) {
      return Duration.zero;
    } else {
      final result = targetTime.difference(now);
      assert(!result.isNegative);
      return result;
    }
  }
}
