// SPDX-FileCopyrightText: (c) 2021 Artsiom iG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'package:meta/meta.dart';

/// Unlimited numeric value that can be increased an infinite number of times.
/// Useful for creating identifiers that are unique in the course of the
/// program, and each subsequent one is larger than the previous one.
class Unlimited implements Comparable<Unlimited> {
  Unlimited() : _value = BigInt.zero;

  @visibleForTesting
  @internal
  Unlimited.fromBigInt(this._value);

  final BigInt _value;

  Unlimited next() {
    final result = Unlimited.fromBigInt(_value + BigInt.one);

    assert(result > this);
    assert(result >= this);
    assert(this < result);
    assert(this <= result);
    assert(compareTo(result) == -1);
    assert(result.compareTo(this) == 1);

    return result;
  }

  @override
  int compareTo(Unlimited other) {
    return _value.compareTo(other._value);
  }

  @override
  bool operator ==(Object other) =>
      (other is Unlimited) && _value == other._value;
  bool operator <(Object other) =>
      (other is Unlimited) && _value < other._value;
  bool operator >(Object other) =>
      (other is Unlimited) && _value > other._value;
  bool operator <=(Object other) =>
      (other is Unlimited) && _value <= other._value;
  bool operator >=(Object other) =>
      (other is Unlimited) && _value >= other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() {
    return _value.toRadixString(16);
  }
}
