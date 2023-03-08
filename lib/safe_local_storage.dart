/// This file is a part of safe_local_storage (https://github.com/alexmercerind/safe_local_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:synchronized/synchronized.dart';

import 'package:safe_local_storage/isolates.dart';
import 'package:safe_local_storage/file_system.dart';
export 'package:safe_local_storage/file_system.dart';

/// SafeLocalStorage
/// ----------------
///
/// A safe transaction-based atomic, consistent & durable cache manager.
///
class SafeLocalStorage {
  SafeLocalStorage(
    String path, {
    this.fallback = const {},
  }) : _file = File(clean(path));

  /// Writes the [data] to the cache [File].
  Future<void> write(dynamic data) async {
    await _file.write_(_kJsonEncoder.convert(data), history: true);
    // Run in asynchronous suspension of another [Isolate].
    compute(
      _removeRedundantFileTransactionHistory,
      _file.path,
    );
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
          locks[_file.path] ??= Lock();
          final result = await locks[_file.path]?.synchronized(() async {
            final data = await compute(_read, _file.path);
            if (data != null) {
              return data;
            } else {
              print(
                '[SafeLocalStorage]: Technically, this should never show up on the console.',
              );
              // Go to `catch` block if the [File] was missing after checking existence.
              missing = true;
              throw Exception('This should never happen.');
            }
          });
          return result;
        } else {
          if (await temp.exists_()) {
            // Chances are [File] got deleted, then trying to retrieve from the older [write] operations.
            final contents = await temp.list_(
              predicate: (file) =>
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
                '[SafeLocalStorage]: ${basename(_file.path)} found missing.',
              );
              // Go to `catch` block since there is no entry of [File] in history either.
              missing = true;
              throw Exception('${_file.path} not found. Attempting roll-back.');
            }
          } else {
            // No transaction-history of [File] & neither the actual [File], thus return the [fallback] data.
            return fallback;
          }
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
        if (!missing) {
          print('[SafeLocalStorage]: ${basename(_file.path)} found corrupt.');
        }
        // [File] was corrupted or couldn't be read. Lookup in the older I/O transactions & rollback.
        if (await temp.exists_()) {
          if (contents.isEmpty) {
            contents = await temp.list_(
              predicate: (file) =>
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
              '[SafeLocalStorage]: ${basename(_file.path)} history versions found:\n${contents.map((e) => e.path).join('\n')}\n',
            );
          }();
          for (final file in contents) {
            try {
              locks[_file.path] ??= Lock();
              final result = await locks[_file.path]?.synchronized(() async {
                final data = await compute(
                  _readRollback,
                  [
                    file.path,
                    _file.path,
                  ],
                );
                return data;
              });
              return result;
            } catch (exception, stacktrace) {
              print(exception.toString());
              print(stacktrace.toString());
              print(
                  '[SafeLocalStorage]: roll-back to ${basename(file.path)} failed.');
            }
          }
        }
      }
      return fallback;
    });
  }

  /// Deletes the cache [File] as well as any transaction records.
  Future<void> delete() {
    return lock.synchronized(() async {
      try {
        await _delete(_file.path);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    });
  }

  /// The fallback data to be returned in case the cache [File] is missing or in un-recoverable corrupt state.
  final dynamic fallback;

  /// [Lock] for ensuring mutual exclusion of [read] & [write] operations.
  final lock = Lock();

  /// Initialized in the constructor.
  final File _file;

  // Following methods exist for `dart:isolate` compatibility.

  /// For avoiding heavy JSON parsing on the main thread, the [File] is read & deserialized in a separate [Isolate].
  ///
  /// Since, [mutexes] is globally shared to ensure the isolation, but [Isolate]s do not share global variables.
  /// So, explicitly the [Completer] is checked before the [compute] call.

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

  /// Attempts to read the history [File] at given by [paths]'s first element.
  /// If the deserialization is successful, then the original [File] is also updated to this rollback state (because it was corrupt).
  /// Here, original [File]'s path is given by [paths]'s second element.
  ///
  static dynamic _readRollback(List<String> paths) async {
    print(
        '[SafeLocalStorage]: Attempting roll-back to ${basename(paths.first)}.');
    final file = File(paths.first);
    final content = await file.read_();
    final data = jsonDecode(content!);
    print(
        '[SafeLocalStorage]: roll-back to ${basename(file.path)} successful.');
    // Update the existing original [File].
    await File(paths.last).write_(content);
    return data;
  }

  /// Limits the number of transaction-history files to [_kHistoryTransactionCount].
  static void _removeRedundantFileTransactionHistory(String path) async {
    final temp = Directory(join(File(path).parent.path, 'Temp'));
    if (await temp.exists_()) {
      final contents = await temp.list_(
        predicate: (file) => basename(file.path).startsWith(basename(path)),
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

  /// Deletes the cache [File] as well as any transaction records.
  static Future<void> _delete(String path) async {
    final file = File(path);
    await file.delete_();
    final temp = Directory(join(file.parent.path, 'Temp'));
    if (await temp.exists_()) {
      final contents = await temp.list_(
        predicate: (file) => basename(file.path).startsWith(basename(path)),
      );
      await Future.wait<void>(
        contents.map((file) => file.delete_()),
      );
    }
  }
}

const int _kHistoryTransactionCount = 10;
const JsonEncoder _kJsonEncoder = JsonEncoder.withIndent('    ');
