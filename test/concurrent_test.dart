// SPDX-FileCopyrightText: (c) 2022 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:schedulers/src/b_base.dart';
import 'package:schedulers/src/c_concurrent.dart';
import 'package:test/test.dart';

class OmgError extends StateError {
  OmgError(final int x) : super(x.toString());
}

void waitOrCrash(final Iterable<Future<dynamic>> items) {}

void main() {
  test("one", () async {
    final r = Random();
    final pool = ParallelScheduler(4);
    final futures = List<Task<int>>.empty(growable: true);
    int maxEver = 0;
    for (int i = 0; i < 100; ++i) {
      final t = pool.run(() async {
        expect(pool.currentlyRunning, lessThanOrEqualTo(4));
        maxEver = max(maxEver, pool.currentlyRunning);
        await Future<void>.delayed(Duration(milliseconds: r.nextInt(50)));
        //sleep(Duration(milliseconds: r.nextInt(50)));

        if (i % 4 == 0) {
          throw OmgError(i);
        }

        expect(pool.currentlyRunning, lessThanOrEqualTo(4));
        maxEver = max(maxEver, pool.currentlyRunning);
        return 3;
      });
      futures.add(t);

      // we want to handle OmgError errors, and the only way to do this,
      // is to await results and catch the errors
      unawaited(
        Future.microtask(() async {
          try {
            await t.result;
          } catch (_) {}
        }),
      );
    }

    int success = 0;
    int errors = 0;

    for (final r in futures) {
      try {
        await r.result;
        success++;
      } on OmgError catch (_) {
        errors++;
      }
    }

    expect(maxEver, 4);
    expect(errors, 25);
    expect(success, 75);
    expect(pool.currentlyRunning, 0);
  });

  group("Unhandled exceptions", () {
    test("exception from block is thrown to the zone", () async {
      bool gotError = false;
      await runZonedGuarded(() async {
        final pool = ParallelScheduler(4);
        pool.run(() => throw "Oops!");
        await Future<void>.delayed(Duration(milliseconds: 100));
      }, (final _, final __) => gotError = true);
      expect(gotError, true);
    });

    test("the same without exception", () async {
      bool gotError = false;
      await runZonedGuarded(() async {
        final pool = ParallelScheduler(4);
        pool.run(() => 1);
        await Future<void>.delayed(Duration(milliseconds: 100));
      }, (final _, final __) => gotError = true);
      expect(gotError, false);
    });
  });

  test("million tasks", () async {
    // test whether too many tasks can lead to stack overflow
    final pool = ParallelScheduler(32);
    final futures = List<Future<int>>.empty(growable: true);
    for (int i = 0; i < 1000000; ++i) {
      futures.add(pool.run(() async => i).result);
    }
    final results = await Future.wait(futures);

    expect(results.fold(0, (final sum, final x) => sum + x), 499999500000);
  });

  test('rejects non-positive max concurrency', () {
    expect(() => ParallelScheduler(0), throwsArgumentError);
    expect(() => ParallelScheduler(-1), throwsArgumentError);
  });

  test('ParallelScheduler(1) serializes bursty tasks like a lock', () async {
    final pool = ParallelScheduler(1);
    var running = 0;
    var maxRunning = 0;
    final completions = <int>[];

    final futures = List.generate(20, (i) {
      return pool.run(() async {
        running++;
        maxRunning = max(maxRunning, running);
        expect(running, 1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        completions.add(i);
        running--;
        return i;
      }).result;
    });

    final results = await Future.wait(futures);

    expect(maxRunning, 1);
    expect(results, List.generate(20, (i) => i));
    expect(completions, List.generate(20, (i) => i));
  });

  test('ParallelScheduler(1) respects priority then FIFO order', () async {
    final pool = ParallelScheduler(1);
    final startOrder = <String>[];
    final unblockFirst = Completer<void>();

    final tasks = <Task<void>>[
      pool.run(() async {
        startOrder.add('first-running');
        await unblockFirst.future;
      }, 1),
      pool.run(() => startOrder.add('high-1'), 10),
      pool.run(() => startOrder.add('high-2'), 10),
      pool.run(() => startOrder.add('mid-1'), 5),
      pool.run(() => startOrder.add('low-1'), 1),
    ];

    unblockFirst.complete();

    await Future.wait(tasks.map((task) => task.result));

    expect(startOrder, ['first-running', 'high-1', 'high-2', 'mid-1', 'low-1']);
  });

  test(
    'ParallelScheduler queued cancellation does not block later tasks',
    () async {
      final pool = ParallelScheduler(1);
      final unblock = Completer<void>();
      final started = <String>[];

      final first = pool.run(() async {
        started.add('first');
        await unblock.future;
      });
      final canceled = pool.run(() {
        started.add('canceled');
      });
      final last = pool.run(() {
        started.add('last');
      });

      canceled.willRun = false;
      unblock.complete();

      await first.result;
      await expectLater(canceled.result, throwsA(isA<TaskCanceled>()));
      await last.result;

      expect(started, ['first', 'last']);
    },
  );
}
