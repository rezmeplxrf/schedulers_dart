// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:schedulers/src/b_base.dart';

class TimeScheduler {
  Task<R> run<R>(GetterFunc<R> func, DateTime time) {
    if (_disposed) {
      throw StateError('The object is disposed');
    }

    final t = InternalTask<R>(func);
    Future.delayed(_computeDelay(time), () {
      if (!_disposed) {
        t.runIfNotCanceled();
      }
    });

    return t;
  }

  void dispose() {
    // todo cancel tasks
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
