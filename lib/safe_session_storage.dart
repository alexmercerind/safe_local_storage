/// This file is a part of safe_session_storage (https://github.com/alexmercerind/safe_session_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:synchronized/synchronized.dart';

import 'package:safe_session_storage/isolates.dart';
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
    // NOTE: Even though, [File.write_] is made mutually exclusive using [Completer],
    // it still enters critical section at the same time, sometimes.
    // Using [Lock] from `package:synchronized` to prevent this.
    // Tests are not failing anymore.
    await lock.synchronized(() async {
      await _file.write_(
        _kJsonEncoder.convert(data),
        keepTransactionInHistory: true,
      );
      // Run in asynchronous suspension on another [Isolate].
      compute(
        _removeRedundantFileTransactionHistory,
        _file.path,
      );
    });
  }

  /// Reads the cache [File] and returns the contents as `dynamic`.
  Future<dynamic> read() {
    return lock.synchronized(() async {
      final temp = Directory(join(_file.parent.path, 'Temp'));
      // Used to determine if cache was missing or corrupt & show correct logs.
      var missing = false;
      var contents = <File>[];
      try {
        if (await _file.exists_()) {
          if (fileMutexes[_file.path] != null) {
            await fileMutexes[_file.path]!.future;
          }
          final data = await compute(_read, _file.path);
          if (data != null) {
            return data;
          } else {
            print(
              '[SafeSessionStorage]: Technically, this should never show up on the console.',
            );
            // Go to `catch` block if the [File] was missing after checking existence.
            missing = true;
            goToCatchBlock();
          }
        } else {
          if (await temp.exists_()) {
            // Chances are [File] got deleted, then trying to retrieve from the older [write] operations.
            final contents = await temp.list_(
              checker: (file) =>
                  basename(file.path).startsWith(basename(_file.path)) &&
                  !basename(file.path).endsWith('.src'),
            );
            // Sort by modification time in descending order.
            contents.sort(
              (a, b) => (int.tryParse(basename(b.path).split('.').last) ?? -1)
                  .compareTo(
                int.tryParse(basename(a.path).split('.').last) ?? -1,
              ),
            );
            if (contents.isEmpty) {
              return fallback;
            } else {
              print(
                  '[SafeSessionStorage]: ${basename(_file.path)} found missing.');
              // Go to `catch` block since there is no entry of [File] in history either.
              missing = true;
              goToCatchBlock();
            }
          } else {
            // No transaction-history of [File] & neither the actual [File], thus return the [fallback] data.
            return fallback;
          }
        }
      } catch (exception /* , stacktrace */) {
        // print(exception.toString());
        // print(stacktrace.toString());
        if (!missing) {
          print('[SafeSessionStorage]: ${basename(_file.path)} found corrupt.');
        }
        // [File] was corrupted or couldn't be read.
        // Lookup in the older I/O transactions & rollback.
        if (await temp.exists_()) {
          if (contents.isEmpty) {
            contents = await temp.list_(
              checker: (file) =>
                  basename(file.path).startsWith(basename(_file.path)) &&
                  !basename(file.path).endsWith('.src'),
            );
            // Sort by modification time in descending order.
            contents.sort(
              (a, b) => (int.tryParse(basename(b.path).split('.').last) ?? -1)
                  .compareTo(
                int.tryParse(basename(a.path).split('.').last) ?? -1,
              ),
            );
          }
          () async {
            print(
              '[SafeSessionStorage]: ${basename(_file.path)} history versions found:\n${contents.map((e) => e.path).join('\n')}\n',
            );
          }();
          for (final file in contents) {
            try {
              if (fileMutexes[_file.path] != null) {
                await fileMutexes[_file.path]!.future;
              }
              final data = await compute(
                _readRollback,
                [
                  file.path,
                  _file.path,
                ],
              );
              return data;
            } catch (exception /* , stacktrace */) {
              // print(exception.toString());
              // print(stacktrace.toString());
              print(
                  '[SafeSessionStorage]: roll-back to ${basename(file.path)} failed.');
            }
          }
        }
      }
      return fallback;
    });
  }

  void goToCatchBlock() => throw Exception();

  final dynamic fallback;
  late final File _file;
  final lock = Lock();
  static const JsonEncoder _kJsonEncoder = JsonEncoder.withIndent('    ');

  /// Following methods exist for `dart:isolate`.
  /// For avoiding heavy JSON parsing on the main thread,
  /// the [File] is read & deserialized in a separate [Isolate].
  ///
  /// Since, [fileMutexes] is globally shared to ensure the isolation, but [Isolate]s
  /// do not share global variables. So, explicitly the [Completer] is checked
  /// before the [compute] call.

  /// Reads the cache [File] given by [filePath] and returns the contents as `dynamic`.
  /// Returns `null` if the [File] is missing.
  static dynamic _read(String filePath) async {
    // Attempt to read & [jsonDecode] data from the actual [File].
    final content = await File(filePath).read_();
    if (content != null) {
      final data = jsonDecode(content);
      return data;
    }
    return null;
  }

  /// Attempts to read the history [File] at given by [filePaths]'s first element.
  /// If the deserialization is successful, then the original [File] is also updated
  /// to this rollback state (because it was corrupt).
  /// Here, original [File]'s path is given by [filePaths]'s second element.
  ///
  static dynamic _readRollback(List<String> filePaths) async {
    print(
        '[SafeSessionStorage]: Attempting roll-back to ${basename(filePaths.first)}.');
    final file = File(filePaths.first);
    final content = await file.read_();
    final data = jsonDecode(content!);
    print(
        '[SafeSessionStorage]: roll-back to ${basename(file.path)} successful.');
    // Update the existing original [File].
    await File(filePaths.last).write_(content);
    return data;
  }

  static void _removeRedundantFileTransactionHistory(String filePath) async {
    final temp = Directory(join(File(filePath).parent.path, 'Temp'));
    if (await temp.exists_()) {
      final contents = await temp.list_(
        checker: (file) => basename(file.path).startsWith(basename(filePath)),
      );
      if (contents.length > _kHistoryTransactionCount) {
        // Sort by modification time in descending order.
        contents.sort(
          (a, b) {
            // Make files ending with `.src` fall to the end.
            if (basename(b.path).contains('.src')) {
              return -1 << 32;
            } else if (basename(a.path).contains('.src')) {
              return 1 << 32;
            }
            // Actual sort.
            return (int.tryParse(basename(b.path).split('.').last) ?? -1)
                .compareTo(
              int.tryParse(basename(a.path).split('.').last) ?? -1,
            );
          },
        );
        await Future.wait<void>(
          contents
              .skip(_kHistoryTransactionCount)
              .map((file) => file.delete_()),
        );
      }
    }
  }

  static const int _kHistoryTransactionCount = 10;
}
