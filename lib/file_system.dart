/// This file is a part of safe_local_storage (https://github.com/alexmercerind/safe_local_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:path/path.dart';

/// Prefix needed on Windows for safely accessing local storage with long file path support.
const String _kWindowsLongFileSystemPathPrefix = '\\\\?\\';

/// Adds `\\?\` prefix to the path if it is not already added & ensures all separators are `\\` on Windows.
String _clean(String path) {
  // Network drives & NAS paths seem to start with `\\` & do not support `\\?\` prefix.
  final prefix = Platform.isWindows &&
          !path.startsWith('\\\\') &&
          !path.startsWith(_kWindowsLongFileSystemPathPrefix)
      ? _kWindowsLongFileSystemPathPrefix
      : '';
  if (Platform.isWindows) {
    path = path.replaceAll('/', '\\');
  }
  return prefix + path;
}

abstract class FS {
  static Future<FileSystemEntityType> type_(String path) {
    return FileSystemEntity.type(_clean(path));
  }

  static FileSystemEntityType typeSync_(String path) {
    return FileSystemEntity.typeSync(_clean(path));
  }
}

extension DirectoryExtension on Directory {
  /// Recursively lists all the present [File]s inside the [Directory].
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Returns only [List] of [File]s.
  ///
  /// The arguments [extensions], [checker] or [minimumFileSize] may be used to filter the resultings [File]s.
  ///
  Future<List<File>> list_({
    List<String>? extensions,
    bool Function(File)? checker,
    int minimumFileSize = 1024 * 1024,
  }) async {
    final completer = Completer();
    final files = <File>[];
    try {
      final directory = Directory(_clean(path));
      directory
          .list(
        recursive: true,
        followLinks: false,
      )
          .listen(
        (event) {
          if (event is File) {
            final file = File(
              event.path.substring(
                event.path.startsWith(_kWindowsLongFileSystemPathPrefix)
                    ? 4
                    : 0,
              ),
            );
            if (checker != null) {
              if (checker(file)) {
                files.add(file);
              }
            } else if (extensions != null) {
              if (extensions.contains(event.extension)) {
                if (event.sizeSync_() >= minimumFileSize) {
                  files.add(file);
                }
              }
            } else {
              files.add(file);
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
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return [];
    }
  }

  /// Lists the current directory and returns a [List] of [FileSystemEntity]s.
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Does not iterate recursively.
  /// * Returns [List] of [FileSystemEntity]s present in current [Directory].
  ///
  Future<List<FileSystemEntity>> children_() async {
    final completer = Completer();
    final contents = <FileSystemEntity>[];
    try {
      Directory(_clean(path))
          .list(
        recursive: false,
        followLinks: false,
      )
          .listen(
        (event) {
          switch (FS.typeSync_(event.path)) {
            case FileSystemEntityType.directory:
              contents.add(
                Directory(
                  event.path.substring(
                    event.path.startsWith(_kWindowsLongFileSystemPathPrefix)
                        ? 4
                        : 0,
                  ),
                ),
              );
              break;
            case FileSystemEntityType.file:
              contents.add(
                File(
                  event.path.substring(
                    event.path.startsWith(_kWindowsLongFileSystemPathPrefix)
                        ? 4
                        : 0,
                  ),
                ),
              );
              break;
            default:
              break;
          }
        },
        onError: (error) {
          // For debugging. In case any future error is reported by the users.
          print(error.toString());
        },
        onDone: completer.complete,
      );
      await completer.future;
      return contents;
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return [];
    }
  }

  /// Safely [create]s a [Directory] recursively.
  Future<void> create_() async {
    try {
      await Directory(_clean(path)).create(recursive: true);
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
      final id = DateTime.now().millisecondsSinceEpoch;
      final files = [
        // Transaction history file.
        File(
          join(
            _clean(parent.path),
            'Temp',
            '${basename(path)}.$id',
          ),
        ),
        // Actual file that will be renamed to destination.
        File(
          join(
            _clean(parent.path),
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
          } else if (content is Uint8List) {
            await e.value.writeAsBytes(
              content,
              flush: true,
            );
          }
        }
      }));
      // To ensure atomicity of the transaction.
      await files.last.rename_(_clean(path));
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    if (!fileMutexes[path]!.isCompleted) {
      fileMutexes[path]!.complete();
    }
  }

  /// Reads the contents of the [File] as [String].
  /// Respects the mutual exclusion lock, but does not enforce one itself.
  FutureOr<String?> read_() async {
    if (fileMutexes[path] != null) {
      await fileMutexes[path]!.future;
    }
    final file = File(_clean(path));
    if (await file.exists_()) {
      return file.readAsString();
    }
    return null;
  }

  /// Reads the contents of the [File] as [Uint8List].
  /// Respects the mutual exclusion lock, but does not enforce one itself.
  FutureOr<Uint8List?> readAsBytes_() async {
    if (fileMutexes[path] != null) {
      await fileMutexes[path]!.future;
    }
    final file = File(_clean(path));
    if (await file.exists_()) {
      return file.readAsBytes();
    }
    return null;
  }

  /// Safely [rename]s a [File].
  Future<void> rename_(String newPath) async {
    try {
      await File(_clean(path)).rename(_clean(newPath));
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Safely [copy] a [File].
  Future<void> copy_(String newPath) async {
    try {
      // Delete if some [File] or [Directory] already exists at the newly specified path.
      if (await File(_clean(newPath)).exists_()) {
        await File(_clean(newPath)).delete_();
      }
      await File(_clean(path)).copy(_clean(newPath));
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Safely [create]s a [File] recursively.
  Future<void> create_() async {
    try {
      await File(_clean(path)).create(recursive: true);
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Returns the size in bytes of a [File] as `int`.
  /// Returns `0` if the [File] does not exist.
  FutureOr<int> size_() async {
    final file = File(_clean(path));
    if (await file.exists_()) {
      return file.length();
    }
    return 0;
  }

  /// Returns the size in bytes of a [File] as `int`.
  /// Returns `0` if the [File] does not exist.
  int sizeSync_() {
    final file = File(_clean(path));
    if (file.existsSync_()) {
      return file.lengthSync();
    }
    return 0;
  }

  /// Returns the last modified time of a [File] as [DateTime].
  /// Returns `null` if the [File] does not exist.
  FutureOr<DateTime?> lastModified_() async {
    final file = File(_clean(path));
    try {
      if (await file.exists_()) {
        return file.lastModified();
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    return null;
  }

  /// Returns the last modified time of a [File] as [DateTime].
  /// Returns `null` if the [File] does not exist.
  DateTime? lastModifiedSync_() {
    final file = File(_clean(path));
    try {
      if (file.existsSync_()) {
        return file.lastModifiedSync();
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    return null;
  }
}

extension FileSystemEntityExtension on FileSystemEntity {
  /// Safely deletes a [FileSystemEntity].
  Future<void> delete_() async {
    // Surround with try/catch instead of using [Directory.exists_],
    // because it confuses Windows into saying:
    // "The process cannot access the file because it is being used by another process."
    try {
      if (this is File) {
        await File(_clean(path)).delete(recursive: true);
      } else if (this is Directory) {
        final directory = Directory(_clean(path));
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
    } catch (exception) {
      // NO;OP
    }
  }

  /// Safely checks whether a [FileSystemEntity] exists or not.
  Future<bool> exists_() {
    try {
      if (this is File) {
        return File(_clean(path)).exists();
      } else if (this is Directory) {
        return Directory(_clean(path)).exists();
      } else {
        return Future.value(false);
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return Future.value(false);
    }
  }

  /// Safely checks whether a [FileSystemEntity] exists or not.
  bool existsSync_() {
    try {
      if (this is File) {
        return File(_clean(path)).existsSync();
      } else if (this is Directory) {
        return Directory(_clean(path)).existsSync();
      } else {
        return false;
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return false;
    }
  }

  /// Shows a [FileSystemEntity] in the system's default file explorer.
  ///
  /// Opens a new external file explorer window with the [FileSystemEntity] selected.
  ///
  void explore_() async {
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        [
          '/select,',
          path.startsWith(_kWindowsLongFileSystemPathPrefix)
              ? path.substring(4)
              : path,
        ],
        runInShell: true,
        includeParentEnvironment: true,
        mode: ProcessStartMode.detached,
      );
    }
    if (Platform.isLinux) {
      await Process.start(
        'dbus-send',
        [
          '--session',
          '--print-reply',
          '--dest=org.freedesktop.FileManager1',
          '--type=method_call',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:$uri',
          'string:""',
        ],
        runInShell: true,
        includeParentEnvironment: true,
        mode: ProcessStartMode.detached,
      );
    }
    // TODO: Support other platforms.
  }

  String get extension => basename(path).split('.').last.toUpperCase();
}

/// [Map] storing various instances of [Completer] for
/// mutual exclusion in [FileExtension.write_].
final Map<String, Completer> fileMutexes = <String, Completer>{};
