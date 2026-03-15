// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'package:schedulers/src/a_unlimited.dart';
import 'package:schedulers/src/b_base.dart';

/// Runs only the last added task and only if no new tasks have been added during the time interval.
///
/// That is, if you add many tasks within a short period of time, then only one of them will be
/// executed: the last one added.
class LazyScheduler {
  // todo return Task from run
  // todo add dispose

  LazyScheduler({this.latency = const Duration(seconds: 1000), this.callEach}) {
    if (callEach != null && callEach! <= 0) {
      throw ArgumentError.value(
        callEach,
        'callEach',
        'Must be greater than zero when provided.',
      );
    }
  }
  int _ignored = 0;
  final int? callEach;
  late GetterFunc<void>? _callback;
  late Duration latency;

  Unlimited _newestRunId = Unlimited();

  /// Notifies the scheduler that it should run the callback sometime. The
  /// actual call will occur asynchronously at the time selected by the
  /// scheduler.
  Future<void> run(GetterFunc<void> callback) async {
    _callback = callback;

    _newestRunId = _newestRunId.next();
    final runId = _newestRunId;

    await Future<void>.delayed(latency);

    if (_newestRunId == runId) {
      await _callback!();
      _ignored = 0;
    } else if (callEach != null && ++_ignored >= callEach!) {
      await _callback!();
      _ignored = 0;
    }
  }
}
