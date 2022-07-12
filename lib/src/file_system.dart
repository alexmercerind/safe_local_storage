/// This file is a part of safe_session_storage (https://github.com/alexmercerind/safe_session_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

/// This file contains various `extensions` on existing [Directory], [File] & [FileSystemEntity] classes from `dart:io`.
/// Apparently, existing I/O interface is very unsafe & fails in various cases.
///

extension DirectoryExtension on Directory {
  /// Recursively lists all the present [File]s inside the [Directory].
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Returns only [List] of [File]s.
  ///
  Future<List<File>> list_({
    List<String>? extensions,
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
        // Not a good way, but whatever for performance.
        // Explicitly restricting to [kSupportedFileTypes] for avoiding long iterations in later operations.
        if (event is File) {
          if (extensions != null) {
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
  /// Does not modify the contents of the original file, but
  /// creates a new randomly named file & copies it to the
  /// original [File]'s path for ensured safety & no possible
  /// corruption.
  ///
  /// Thanks to @raitonoberu for the idea.
  ///
  Future<void> write_(String content) async {
    try {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      final file = File(join(prefix + parent.path, 'Temp', const Uuid().v4()));
      if (!await file.exists_()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(content, flush: true);
      await file.rename_(prefix + path);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
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
    if (await exists_()) {
      final prefix = Platform.isWindows &&
              !path.startsWith('\\\\') &&
              !path.startsWith(r'\\?\')
          ? r'\\?\'
          : '';
      if (this is File) {
        await File(prefix + path).delete();
      } else if (this is Directory) {
        await Directory(prefix + path).delete();
      }
    }
  }

  /// Safely checks whether a [FileSystemEntity] exists or not.
  FutureOr<bool> exists_() {
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
      return false;
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

  void showInFileExplorer_() async {
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
