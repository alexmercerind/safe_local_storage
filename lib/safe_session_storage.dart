/// This file is a part of safe_session_storage (https://github.com/alexmercerind/safe_session_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';

import 'package:safe_session_storage/file_system.dart';
export 'package:safe_session_storage/file_system.dart';

/// SafeSessionStorage
/// ------------------
///
/// A safe transaction-based atomic, consistent & durable cache manager.
///
/// Pass [path] to the constructor to specify the location of the cache [File].
///
/// An attempt at implementing [ACID semantics](https://en.wikipedia.org/wiki/ACID).
///
/// **Methods:**
///
/// * [write]: Writes the [data] to the cache [File].
/// * [read]: Reads the cache [File] and returns the contents as `dynamic`.
///
/// **Features:**
///
/// * In case the cache [File] is found in corrupt state, the old [write] operations
///   performed on the [File] are looked-up & the cache is rolled-back to the state
///   before the corruption.
/// * No concurrent write operations on the cache. Isolation is maintained.
/// * No interleaving of write operations. Atomic transactions are maintained.
/// * [read] waits until on-going [write] operations are completely finished.
///
class SafeSessionStorage {
  SafeSessionStorage(
    String path, {
    this.fallback = const {},
  }) {
    _file = File(path);
  }

  /// Writes the [data] to the cache [File].
  Future<void> write(dynamic data) async {
    await _completer.future;
    _completer = Completer();
    await _file.write_(_kJsonEncoder.convert(data));
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Reads the cache [File] and returns the contents as `dynamic`.
  Future<dynamic> read() async {
    final temp = Directory(join(_file.parent.path, 'Temp'));
    // Used to determine if cache was missing or corrupt & show correct logs.
    var missing = false;
    var contents = <File>[];
    try {
      if (await _file.exists_()) {
        // Attempt to read & [jsonDecode] data from the actual file.
        final content = await _file.read_();
        if (content != null) {
          final data = jsonDecode(content);
          return data;
        } else {
          print('[SafeSessionStorage]: ${basename(_file.path)} found missing.');
          // Go to `catch` block if the [File] was in corrupt state.
          missing = false;
          goToCatchBlock();
        }
      } else {
        if (await temp.exists_()) {
          // Chances are [File] got deleted, then trying to retrieve from the older [write] operations.
          final contents = await temp.list_(
            checker: (file) =>
                basename(file.path).startsWith(basename(_file.path)),
          );
          // Sort by modification time in descending order.
          contents.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
          if (contents.isEmpty) {
            return fallback;
          } else {
            print(
                '[SafeSessionStorage]: ${basename(_file.path)} found missing.');
            // Go to `catch` block since there is no entry of [File] in history either.
            missing = false;
            goToCatchBlock();
          }
        } else {
          // No history of [File] & neither the actual [File], thus return the [fallback] data.
          return fallback;
        }
      }
    } catch (exception /* , stacktrace */) {
      if (!missing) {
        print('[SafeSessionStorage]: ${basename(_file.path)} found corrupt.');
      }
      // [File] was corrupted or couldn't be read.
      // Lookup in the older I/O transactions & rollback.
      if (await temp.exists_()) {
        if (contents.isEmpty) {
          contents = await temp.list_(
            checker: (file) =>
                basename(file.path).startsWith(basename(_file.path)),
          );
          // Sort by modification time in descending order.
          contents.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
        }
        () async {
          print(
              '[SafeSessionStorage]: ${contents.map((e) => e.path)} history versions found.');
        }();
        for (final file in contents) {
          print(
              '[SafeSessionStorage]: Attempting roll-back to ${basename(file.path)}.');
          try {
            final content = await file.read_();
            try {
              final data = jsonDecode(content!);
              // Update the existing original [File].
              //// No `await` needed because `write_` ensures no concurrent write operations.
              await _file.write_(
                content,
                keepTransactionInHistory: false,
              );
              print(
                  '[SafeSessionStorage]: roll-back to ${basename(file.path)} successful.');
              return data;
            } catch (exception, stacktrace) {
              print(exception.toString());
              print(stacktrace.toString());
              print(
                  '[SafeSessionStorage]: roll-back to ${basename(file.path)} failed.');
            }
          } catch (exception, stacktrace) {
            print(exception.toString());
            print(stacktrace.toString());
          }
        }
      }
    }
    return fallback;
  }

  void goToCatchBlock() => throw Exception();

  final dynamic fallback;
  late final File _file;
  Completer _completer = Completer()..complete();
  static const JsonEncoder _kJsonEncoder = JsonEncoder.withIndent('    ');
}
