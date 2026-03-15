// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'package:schedulers/schedulers.dart';
import 'package:test/test.dart';

void main() {
  // todo test tasks that throw exceptions

  test('lazy 1', () async {
    final scheduler = LazyScheduler(latency: const Duration(milliseconds: 100));

    int x = 0;
    int y = 0;
    int funcA() => x++;
    int funcB() => y++;

    for (int i = 0; i < 100; ++i) {
      scheduler.run(funcA);
    }

    expect(x, 0);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(x, 0);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(x, 1);

    for (int i = 0; i < 100; ++i) {
      scheduler.run(funcA);
      scheduler.run(funcB);
    }
    expect(x, 1);
    expect(y, 0);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(x, 1);
    expect(y, 1);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(x, 1);
    expect(y, 1);
  });

  test('latest callback wins during a burst', () async {
    final scheduler = LazyScheduler(latency: const Duration(milliseconds: 20));
    final calls = <String>[];

    scheduler.run(() => calls.add('a'));
    scheduler.run(() => calls.add('b'));
    scheduler.run(() => calls.add('c'));

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(calls, ['c']);
  });

  test('separated calls each run independently', () async {
    final scheduler = LazyScheduler(latency: const Duration(milliseconds: 20));
    var calls = 0;

    await scheduler.run(() => calls++);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await scheduler.run(() => calls++);

    expect(calls, 2);
  });

  test(
    'callEach periodically executes the latest callback during continuous bursts',
    () async {
      final scheduler = LazyScheduler(
        latency: const Duration(milliseconds: 20),
        callEach: 3,
      );
      final calls = <String>[];

      final futures = <Future<void>>[];
      for (var i = 0; i < 7; i++) {
        futures.add(scheduler.run(() => calls.add('latest')));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      await Future.wait(futures);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(calls.length, 3);
      expect(calls, everyElement('latest'));
    },
  );

  test('run awaits async callback completion', () async {
    final scheduler = LazyScheduler(latency: const Duration(milliseconds: 10));
    var finished = false;

    final future = scheduler.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      finished = true;
    });

    await future;

    expect(finished, isTrue);
  });

  test('run propagates callback errors', () async {
    final scheduler = LazyScheduler(latency: const Duration(milliseconds: 10));

    await expectLater(
      scheduler.run(() => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects non-positive callEach', () {
    expect(() => LazyScheduler(callEach: 0), throwsArgumentError);
    expect(() => LazyScheduler(callEach: -1), throwsArgumentError);
  });
}
