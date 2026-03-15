// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:schedulers/src/a_unlimited.dart';

typedef GetterFunc<R> = FutureOr<R> Function();

@internal
typedef CancelFunc = void Function(InternalTask<dynamic>);

class TaskCanceled implements Exception {
  @override
  String toString() => 'TaskCanceled';
}

abstract class Task<R> {
  Future<R> get result;

  /// Returns true before the task starts. Returns false if the task has already
  /// been completed.
  ///
  /// By setting this value to false, you can cancel the upcoming start of the
  /// task.
  bool get willRun;

  set willRun(bool x);
}

class InternalTask<R> extends Task<R> {
  InternalTask(this._block, {this.onCancel});

  final GetterFunc<R> _block;

  /// Called when used [cancel]s the task. It helps the scheduler to remove the
  /// task from the queue, if needed.
  @internal
  final CancelFunc? onCancel;

  @internal
  Future<void> runIfNotCanceled() async {
    if (!_willRun) {
      return;
    }
    _started = true;

    try {
      _readyResult = await _block();
      assert(!_haveResult);
      _haveResult = true;
      assert(_completer == null || !_completer!.isCompleted);
      _completer?.complete(_readyResult);
    } catch (e, stacktrace) {
      // when the _block throws error:
      //
      // (1) If user never asked for .result, we did not even created a
      // Completer. The exception will be rethrown to the Zone (and maybe never
      // handled). But we'll see it in the logs.
      //
      // (2a) If user asked for .result and started awaiting it, the Completer
      // will pass error the the waiting code. So the exception may be handled
      // by the user, if he `try { await task.result } catch { }`
      //
      // (2b) If the uses asked for .result, but not started awaiting it, we
      // created the Completer and will pass the exception to it. The Completer
      // knows that nobody awaits its future. So it throws the error to the Zone
      // (like if we never created the completer).
      //
      // In all three cases the exception is "thrown" somewhere: either to
      // the zone or to the awaiting code.
      //
      // In (1) and (2b) we just throw exception to the zone, with the
      // completer, or without it. So why don't we just create Completer
      // unconditionally and always pass results to it?
      //
      // That's because of canceling tasks. If user created a task, started
      // awaiting the result (2a), and then canceled the task, then he WANTS the
      // get a `TaskCanceled` error (instead of waiting forever). If he never
      // asked for result (1) we will not throw `TaskCanceled` anywhere - we
      // will cancel the task without an error. In rare case (2b) - when he
      // asked for future result, and stored it somewhere without awaiting...
      // He we probably get an unhandled `TaskCanceled`. To avoid this he
      // can just avoid canceling tasks, or storing their future results...

      _haveError = true;
      _readyError = e;
      _readyStackTrace = stacktrace;

      if (_completer != null) {
        assert(!_completer!.isCompleted);
        _completer!.completeError(e, stacktrace);
      } else {
        assert(_completer == null);
        rethrow;
      }
    } finally {
      _completed = true;
      _willRun = false; // todo unit test
    }
  }

  /// this completer is only initialized if user asks for [result] future before
  /// we have the result. If the user did not ask for result, no one is waiting
  /// for the result, so we can safely cancel the task without [completeError]
  Completer<R>? _completer;

  /// when the task completes, it initializes sets the following two field. If
  /// the user reads [result] property after that, we will just return the value
  /// instead messing with Completer
  bool _haveResult = false;
  late R _readyResult;
  bool _haveError = false;
  late Object _readyError;
  StackTrace? _readyStackTrace;
  bool _started = false;
  bool _completed = false;
  bool _canceled = false;

  @override
  Future<R> get result => _haveResult
      ? Future<R>.value(_readyResult)
      : _haveError
      ? Future<R>.error(_readyError, _readyStackTrace)
      : _canceled
      ? Future<R>.error(TaskCanceled())
      : (_completer ??= Completer<R>()).future;

  bool _willRun = true;

  @override
  bool get willRun => _willRun;

  @override
  set willRun(bool value) {
    if (_willRun == value) {
      return;
    }

    if (value) {
      throw StateError(
        'Cannot set willRun to true after it after it has been set to false',
      );
    }

    assert(_willRun);
    assert(!value);

    // Cancellation only applies while the task is still queued. Once started,
    // the task cannot be interrupted safely and should finish normally.
    if (_started || _completed) {
      return;
    }

    _willRun = false;
    _canceled = true;
    onCancel?.call(this);

    if (_completer?.isCompleted == false) {
      _completer!.completeError(TaskCanceled());
    }
  }
}

class PriorityTask<R> extends InternalTask<R>
    implements Comparable<PriorityTask<R>> {
  PriorityTask(super._block, this.priority, {super.onCancel});
  static Unlimited _idGenerator = Unlimited();

  final int priority;
  final Unlimited id = PriorityTask._idGenerator = PriorityTask._idGenerator
      .next();

  @override
  int compareTo(PriorityTask<dynamic> other) {
    // taskA<taskB if taskA has larger priority
    var x = -priority.compareTo(other.priority);

    // taskA<taskB if taskA created earlier (so taskA.id<taskB.id)
    if (x == 0) {
      x = id.compareTo(other.id);
    }

    return x;
  }
}

@internal
extension QueueExt on PriorityQueue<InternalTask<dynamic>> {
  /// Will throw if the task in not in queue.
  void removeOrThrow(InternalTask<dynamic> task) {
    final s = length;
    if (!remove(task)) {
      throw ArgumentError('Task not found.');
    }
    assert(length == s - 1);
  }
}

abstract class PriorityScheduler {
  Task<R> run<R>(GetterFunc<R> callback, [int priority = 0]);

  int get queueLength;
}
