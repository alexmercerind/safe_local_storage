/// This file is a part of safe_session_storage (https://github.com/alexmercerind/safe_session_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'package:path/path.dart';

extension DirectoryExtension on Directory {
  /// Recursively lists all the present [File]s inside the [Directory].
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Returns only [List] of [File]s.
  ///
  Future<List<File>> list_({
    // Not a good way, but whatever for performance.
    // Explicitly restricting to [kSupportedFileTypes] for avoiding long iterations in later operations.
    List<String>? extensions,
    bool Function(File)? checker,
  }) async {
    final prefix = Platform.isWindows &&
            !path.startsWith('\\\\') &&
            !path.startsWith(r'\\?\')
        ? r'\\?\'
        : '';
    final completer = Completer();
    final files = <File>[];
    Directory(prefix + path)
        .list(
      recursive: true,
      followLinks: false,
    )
        .listen(
      (event) async {
        if (event is File) {
          if (checker != null) {
            final file = File(event.path.substring(prefix.isNotEmpty ? 4 : 0));
            if (checker(file)) {
              files.add(file);
            }
          } else if (extensions != null) {
            if (extensions.contains(event.extension)) {
              if (await event.length() >
                  1024 * 1024 /* 1 MB or greater in size. */) {
                files
                    .add(File(event.path.substring(prefix.isNotEmpty ? 4 : 0)));
              }
            }
          } else {
            files.add(File(event.path.substring(prefix.isNotEmpty ? 4 : 0)));
          }
        }
      },
      onError: (error) {
        // For debugging. In case any future error is reported by the users.
        print(error.toString());
      },
      onDone: completer.complete,
    );
    await completer.future;
    return files;
  }

  /// Safely [create]s a [Directory] recursively.
  Future<void> create_() async {
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      await Directory(prefix + path).create(recursive: true);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }
}

extension FileExtension on File {
  /// Safely writes [String] [content] to a [File].
  ///
  /// * Does not modify the contents of the original file, but
  /// creates a new randomly named file & renames it to the
  /// original [File]'s path for ensured safety & no possible
  /// corruption. This helps in ensuring the atomicity of the
  /// transaction. Thanks to @raitonoberu for the idea.
  ///
  /// * Uses [Completer]s to ensure to concurrent transactions
  /// to the same file path. This helps in ensuring the
  /// isolation & correct sequence of the transaction.
  ///
  /// * Two files are created, one for keeping the history of
  /// the transaction & other is renamed to the original
  /// cache [File]'s path.
  ///
  Future<void> write_(
    dynamic content, {
    bool keepTransactionInHistory = false,
  }) async {
    if (fileMutexes[path] != null) {
      await fileMutexes[path]!.future;
    }
    fileMutexes[path] = Completer();
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      final id = DateTime.now().millisecondsSinceEpoch;
      final files = [
        // History.
        File(
          join(
            prefix + parent.path,
            'Temp',
            '${basename(path)}.$id',
          ),
        ),
        // Actual file that will be renamed to destination.
        File(
          join(
            prefix + parent.path,
            'Temp',
            '${basename(path)}.$id.src',
          ),
        )
      ];
      await Future.wait(files.asMap().entries.map((e) async {
        if (keepTransactionInHistory || e.key != 0) {
          await e.value.create_();
          if (content is String) {
            await e.value.writeAsString(
              content,
              flush: true,
            );
          } else if (content is List<int>) {
            await e.value.writeAsBytes(
              content,
              flush: true,
            );
          }
        }
      }));
      await files.last.rename_(prefix + path);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    if (!fileMutexes[path]!.isCompleted) {
      fileMutexes[path]!.complete();
    }
  }

  Future<String?> read_() async {
    if (fileMutexes[path] != null) {
      await fileMutexes[path]!.future;
    }
    if (await exists_()) {
      return await readAsString();
    }
    return null;
  }

  /// Safely [rename]s a [File].
  Future<void> rename_(String newPath) async {
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      final newPrefix = Platform.isWindows &&
              !newPath.startsWith('\\\\') &&
              !newPath.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      await File(prefix + path).rename(newPrefix + newPath);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Safely [copy] a [File].
  Future<void> copy_(String newPath) async {
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      final newPrefix = Platform.isWindows &&
              !newPath.startsWith('\\\\') &&
              !newPath.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      await File(prefix + path).copy(newPrefix + newPath);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Safely [create]s a [File] recursively.
  Future<void> create_() async {
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      await File(prefix + path).create(recursive: true);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }
}

extension FileSystemEntityExtension on FileSystemEntity {
  /// Safely deletes a [FileSystemEntity].
  Future<void> delete_() async {
    // Surround with try/catch instead of using [Directory.exists_],
    // because it confuses Windows into saying:
    // "The process cannot access the file because it is being used by another process."
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      if (this is File) {
        await File(prefix + path).delete(recursive: true);
      } else if (this is Directory) {
        final directory = Directory(prefix + path);
        // TODO: [Directory.delete] is not working with `recursive` as `true`.
        // Bug in [dart-lang/sdk](https://github.com/dart-lang/sdk/issues/38148).
        // Adding a workaround for now.
        if (await directory.exists_()) {
          final contents = directory.listSync(recursive: true).cast<File>();
          await Future.wait(
            contents.map((file) => file.delete_()),
          );
        }
        // This [Future.delayed] is needed for Windows.
        // Above [Directory.exists_] call confuses it and it returns error saying:
        // "The process cannot access the file because it is being used by another process."
        await Future.delayed(const Duration(milliseconds: 100));
        await directory.delete(recursive: true);
      }
    } catch (exception /* , stacktrace */) {
      // print(exception.toString());
      // print(stacktrace.toString());
    }
  }

  /// Safely checks whether a [FileSystemEntity] exists or not.
  Future<bool> exists_() {
    final prefix = Platform.isWindows &&
            !path.startsWith('\\\\') &&
            !path.startsWith(r'\\?\')
        ? r'\\?\'
        : '';
    if (this is File) {
      return File(prefix + path).exists();
    } else if (this is Directory) {
      return Directory(prefix + path).exists();
    } else {
      return Future.value(false);
    }
  }

  /// Safely checks whether a [FileSystemEntity] exists or not.
  bool existsSync_() {
    final prefix = Platform.isWindows &&
            !path.startsWith('\\\\') &&
            !path.startsWith(r'\\?\')
        ? r'\\?\'
        : '';
    if (this is File) {
      return File(prefix + path).existsSync();
    } else if (this is Directory) {
      return Directory(prefix + path).existsSync();
    } else {
      return false;
    }
  }

  void explore_() async {
    await Process.start(
      Platform.isWindows
          ? 'explorer.exe'
          : Platform.isLinux
              ? 'xdg-open'
              : 'open',
      Platform.isWindows ? ['/select,', path] : [parent.path],
      runInShell: true,
      includeParentEnvironment: true,
      mode: ProcessStartMode.detached,
    );
  }

  String get extension => basename(path).split('.').last.toUpperCase();
}

/// [Map] storing various instances of [Completer] for
/// mutual exclusion in [FileExtension.write_].
final Map<String, Completer> fileMutexes = <String, Completer>{};
