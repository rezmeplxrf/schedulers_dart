// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:core';
import 'dart:async';

import 'package:schedulers/src/b_base.dart';
import 'package:test/test.dart';

void main() {
  test('compare by ids', () async {
    final a = PriorityTask(() {}, 5);
    final b = PriorityTask(() {}, 5);
    expect(a.compareTo(b), -1);
    expect(b.compareTo(a), 1);
  });

  test('compare by priorities', () async {
    final a = PriorityTask(() {}, 5);
    final b = PriorityTask(() {}, 7);
    expect(a.compareTo(b), 1);
    expect(b.compareTo(a), -1);
  });

  test(
    'canceling a queued task completes with TaskCanceled instance',
    () async {
      final task = InternalTask<int>(() => 1);
      task.willRun = false;

      await expectLater(
        task.result,
        throwsA(isA<TaskCanceled>()),
      );
    },
  );

  test('canceling after task start does not throw or replace result', () async {
    final started = Completer<void>();
    final unblock = Completer<void>();
    final task = InternalTask<int>(() async {
      started.complete();
      await unblock.future;
      return 7;
    });

    unawaited(task.runIfNotCanceled());
    await started.future;

    expect(() => task.willRun = false, returnsNormally);

    unblock.complete();
    expect(await task.result, 7);
  });

  test('late result read after task failure returns stored error', () async {
    final task = InternalTask<int>(() => throw StateError('boom'));

    Object? zonedError;
    await runZonedGuarded(
      () async {
        unawaited(task.runIfNotCanceled());
        await Future<void>.delayed(Duration.zero);
      },
      (error, _) {
        zonedError = error;
      },
    );

    expect(zonedError, isA<StateError>());
    await expectLater(task.result, throwsA(isA<StateError>()));
  });
}
