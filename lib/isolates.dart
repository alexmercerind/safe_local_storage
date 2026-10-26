import 'dart:async';
import 'dart:isolate';

/// Signature for the callback passed to [compute].
///
/// Instances of [ComputeCallback] must be functions that can be sent to an
/// isolate.
typedef ComputeCallback<Q, R> = FutureOr<R> Function(Q message);

/// Spawns an isolate, runs `callback` on that isolate, passes it `message`,
/// and (eventually) returns the value returned by `callback`.
///
/// The function used as `callback` must be one that can be sent to an isolate.
Future<R> compute<Q, R>(ComputeCallback<Q, R> callback, Q message) {
  return Isolate.run(() => callback(message));
}
