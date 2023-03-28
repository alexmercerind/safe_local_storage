/// This file is a part of safe_local_storage (https://github.com/alexmercerind/safe_local_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:synchronized/synchronized.dart';

// A general convention followed by the methods declared in this file is that a trailing underscore (_) is used.
// It indicates that the method is a wrapper around the original method of the same name & fixes the issues that the original method has.

/// Local storage [File] or [Directory] path prefix required on Windows for long file path support.
/// Default implementation in `dart:io` does not support long file paths on Windows.
/// Reference: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=registry
const String kWin32LocalPathPrefix = '\\\\?\\';

/// Network storage [File]s & [Directory]s path have a `\\` prefix on Windows.
/// For these paths, `\\?\` prefix is not supported.
const String kWin32NetworkPathPrefix = '\\\\';

/// Returns updated [File] or [Directory] [path] with the necessary changes.
String clean(String path) {
  if (Platform.isWindows) {
    final prefix = !path.startsWith(kWin32LocalPathPrefix) &&
            !path.startsWith(kWin32NetworkPathPrefix)
        ? kWin32LocalPathPrefix
        : '';
    return prefix + path.replaceAll('/', '\\');
  }
  return path;
}

/// Wrapper around `dart:io`'s [FileSystemEntity] class.
abstract class FS {
  static Future<FileSystemEntityType> type_(String path) {
    return FileSystemEntity.type(clean(path));
  }

  static FileSystemEntityType typeSync_(String path) {
    return FileSystemEntity.typeSync(clean(path));
  }
}

extension DirectoryExtension on Directory {
  /// Recursively lists all the [File]s present in the [Directory].
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Returns only [List] of [File]s.
  ///
  /// Optional argument [predicate] may be used to filter the [File]s.
  ///
  Future<List<File>> list_({
    bool Function(File)? predicate,
  }) async {
    final completer = Completer();
    final files = <File>[];
    try {
      Directory(clean(path)).list(recursive: true, followLinks: false).listen(
        (event) {
          if (event is File) {
            final file = File(
              event.path.substring(
                event.path.startsWith(kWin32LocalPathPrefix)
                    ? kWin32LocalPathPrefix.length
                    : 0,
              ),
            );
            if (predicate?.call(file) ?? true) {
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

  /// Lists all the [FileSystemEntity]s present in the [Directory].
  ///
  /// * Safely handles long file-paths on Windows (https://github.com/dart-lang/sdk/issues/27825).
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  /// * Does not iterate recursively.
  ///
  Future<List<FileSystemEntity>> children_() async {
    final completer = Completer();
    final contents = <FileSystemEntity>[];
    try {
      Directory(clean(path)).list(recursive: false, followLinks: false).listen(
        (event) {
          switch (FS.typeSync_(event.path)) {
            case FileSystemEntityType.directory:
              contents.add(
                Directory(
                  event.path.substring(
                    event.path.startsWith(kWin32LocalPathPrefix)
                        ? kWin32LocalPathPrefix.length
                        : 0,
                  ),
                ),
              );
              break;
            case FileSystemEntityType.file:
              contents.add(
                File(
                  event.path.substring(
                    event.path.startsWith(kWin32LocalPathPrefix)
                        ? kWin32LocalPathPrefix.length
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

  /// Creates the [Directory] on file system.
  Future<void> create_() async {
    if (Platform.isWindows) {
      // On Windows, \\?\ prefix causes issues if we use it to access a root volume without a trailing slash.
      // In other words, \\?\C: is not valid, but \\?\C:\ is valid. If we try to access \\?\C: without a trailing slash, following error is thrown by Windows:
      //
      // "\\?\C:" is not a recognized device.
      // The filename, directory name, or volume label syntax is incorrect.
      //
      // When recursively creating a [File] or [Directory] recursively using `dart:io`'s implementation, if the parent [Directory] does not exist, all the intermediate [Directory]s are created.
      // However, internal implementation of `dart:io` does not handle the case of \\?\C: (without a trailing slash) & fails with the above error.
      // To avoid this, we manually create the intermediate [Directory]s with the trailing slash.
      final directory = Directory(clean(path));
      Directory parent = directory.parent;
      // Add trailing slash if not present.
      if (!parent.path.endsWith('\\')) {
        parent = Directory('${parent.path}\\');
      }
      // [File] already exists.
      if (await directory.exists_()) {
        return;
      }
      // Parent [Directory] exists, no need to create intermediate [Directory]s. Just create the [File].
      else if (await parent.exists_()) {
        await directory.create();
      }
      // Parent [Directory] does not exist, create intermediate [Directory]s & then create the [File].
      else {
        String path = directory.path.startsWith(kWin32LocalPathPrefix)
            ? directory.path.substring(kWin32LocalPathPrefix.length)
            : directory.path;
        if (path.endsWith('\\')) {
          path = path.substring(0, path.length - 1);
        }
        final parts = path.split('\\');
        parts.removeLast();
        for (int i = 0; i < parts.length; i++) {
          final intermediate =
              '$kWin32LocalPathPrefix${parts.sublist(0, i + 1).join('\\')}\\';
          try {
            if (!await Directory(intermediate).exists_()) {
              await Directory(intermediate).create();
            }
          } catch (exception, stacktrace) {
            print(exception.toString());
            print(stacktrace.toString());
          }
        }
        // Finally create the [File].
        await directory.create();
      }
    } else {
      try {
        await Directory(clean(path)).create(recursive: true);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    }
  }
}

extension FileExtension on File {
  /// Safely writes [content] to the [File]. Passed [content] may be [String] or [Uint8List].
  ///
  /// * Does not modify the contents of the original [File], but creates a new [File], writes the [content] to it & then renames it to the original [File]'s path if writing is successful.
  ///   This ensures atomicity of the operation.
  ///
  /// * Uses [Completer]s to ensure to concurrent transactions to the same file path do not conflict.
  ///   This ensures mutual exclusion of the operation.
  ///
  /// Two [File]s are created, one for keeping history of the transaction & the other is renamed original [File]'s path.
  /// The creation of transaction history [File] may be disabled by passing [history] as `false`.
  ///
  Future<void> write_(
    dynamic content, {
    bool history = false,
  }) async {
    locks[clean(path)] ??= Lock();
    return locks[clean(path)]?.synchronized(() async {
      // Create the [File] if it does not exist.
      if (!await File(clean(path)).exists_()) {
        await File(clean(path)).create();
      }
      try {
        final id = DateTime.now().millisecondsSinceEpoch;
        final files = [
          // [File] used for keeping history of the transaction.
          File(
            join(
              clean(parent.path),
              'Temp',
              '${basename(path)}.$id',
            ),
          ),
          // [File] used for renaming to the original [File]'s path after successful write.
          File(
            join(
              clean(parent.path),
              'Temp',
              '${basename(path)}.$id.src',
            ),
          )
        ];
        await Future.wait(
          files.asMap().entries.map((e) async {
            if (history || e.key == 1) {
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
              } else {
                throw FileSystemException(
                  'Unsupported content type: ${content.runtimeType}',
                  path,
                );
              }
            }
          }),
        );
        // To ensure atomicity of the transaction.
        await files.last.rename_(clean(path));
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    });
  }

  /// Reads the contents of the [File] as [String].
  /// Returns `null` if the [File] does not exist.
  FutureOr<String?> read_() {
    locks[clean(path)] ??= Lock();
    return locks[clean(path)]?.synchronized(() async {
      final file = File(clean(path));
      if (await file.exists_()) {
        return await file.readAsString();
      }
      return null;
    });
  }

  /// Reads the contents of the [File] as [Uint8List].
  /// Returns `null` if the [File] does not exist.
  FutureOr<Uint8List?> readAsBytes_() async {
    locks[clean(path)] ??= Lock();
    return locks[clean(path)]?.synchronized(() async {
      final file = File(clean(path));
      if (await file.exists_()) {
        return await file.readAsBytes();
      }
      return null;
    });
  }

  /// Renames the [File] to the specified [destination].
  Future<void> rename_(String destination) async {
    try {
      // Delete if some [File] or [Directory] already exists at the [destination].
      try {
        if (await File(clean(destination)).exists_()) {
          await File(clean(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      try {
        if (await Directory(clean(destination)).exists_()) {
          await Directory(clean(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      await File(clean(path)).rename(clean(destination));
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Copies the [File] to the specified [destination].
  Future<void> copy_(String destination) async {
    try {
      // Delete if some [File] or [Directory] already exists at the [destination].
      try {
        if (await File(clean(destination)).exists_()) {
          await File(clean(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      try {
        if (await Directory(clean(destination)).exists_()) {
          await Directory(clean(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      await File(clean(path)).copy(clean(destination));
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Creates the [File].
  Future<void> create_() async {
    if (Platform.isWindows) {
      // On Windows, \\?\ prefix causes issues if we use it to access a root volume without a trailing slash.
      // In other words, \\?\C: is not valid, but \\?\C:\ is valid. If we try to access \\?\C: without a trailing slash, following error is thrown by Windows:
      //
      // "\\?\C:" is not a recognized device.
      // The filename, directory name, or volume label syntax is incorrect.
      //
      // When recursively creating a [File] or [Directory] recursively using `dart:io`'s implementation, if the parent [Directory] does not exist, all the intermediate [Directory]s are created.
      // However, internal implementation of `dart:io` does not handle the case of \\?\C: (without a trailing slash) & fails with the above error.
      // To avoid this, we manually create the intermediate [Directory]s with the trailing slash.
      final file = File(clean(path));
      Directory parent = file.parent;
      // Add trailing slash if not present.
      if (!parent.path.endsWith('\\')) {
        parent = Directory('${parent.path}\\');
      }
      // [File] already exists.
      if (await file.exists_()) {
        return;
      }
      // Parent [Directory] exists, no need to create intermediate [Directory]s. Just create the [File].
      else if (await parent.exists_()) {
        await file.create();
      }
      // Parent [Directory] does not exist, create intermediate [Directory]s & then create the [File].
      else {
        String path = file.path.startsWith(kWin32LocalPathPrefix)
            ? file.path.substring(kWin32LocalPathPrefix.length)
            : file.path;
        if (path.endsWith('\\')) {
          path = path.substring(0, path.length - 1);
        }
        final parts = path.split('\\');
        parts.removeLast();
        for (int i = 0; i < parts.length; i++) {
          final intermediate =
              '$kWin32LocalPathPrefix${parts.sublist(0, i + 1).join('\\')}\\';
          try {
            if (!await Directory(intermediate).exists_()) {
              await Directory(intermediate).create();
            }
          } catch (exception, stacktrace) {
            print(exception.toString());
            print(stacktrace.toString());
          }
        }
        // Finally create the [File].
        await file.create();
      }
    } else {
      try {
        await File(clean(path)).create(recursive: true);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    }
  }

  /// Returns size the [File] in bytes.
  /// Returns `0` if the [File] does not exist.
  FutureOr<int> length_() async {
    final file = File(clean(path));
    if (await file.exists_()) {
      return file.length();
    }
    return 0;
  }

  /// Returns size the [File] in bytes.
  /// Returns `0` if the [File] does not exist.
  int lengthSync_() {
    final file = File(clean(path));
    if (file.existsSync_()) {
      return file.lengthSync();
    }
    return 0;
  }

  /// Returns last modified timestamp of the [File].
  /// Returns `null` if the [File] does not exist.
  FutureOr<DateTime?> lastModified_() async {
    final file = File(clean(path));
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

  /// Returns last modified timestamp of the [File].
  /// Returns `null` if the [File] does not exist.
  DateTime? lastModifiedSync_() {
    final file = File(clean(path));
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

  /// Returns size the [File] in bytes.
  /// Returns `0` if the [File] does not exist.
  @Deprecated('Use [length_] instead.')
  FutureOr<int> size_() => length_();

  /// Returns size the [File] in bytes.
  /// Returns `0` if the [File] does not exist.
  @Deprecated('Use [lengthSync_] instead.')
  int sizeSync_() => lengthSync_();
}

extension FileSystemEntityExtension on FileSystemEntity {
  /// Deletes the [FileSystemEntity].
  Future<void> delete_() async {
    // Surround with try/catch instead of using [Directory.exists_],
    // because it confuses Windows into saying:
    // "The process cannot access the file because it is being used by another process."
    try {
      if (this is File) {
        await File(clean(path)).delete(recursive: true);
      } else if (this is Directory) {
        final directory = Directory(clean(path));
        // TODO: [Directory.delete] is not working with `recursive` as `true`.
        // Bug in [dart-lang/sdk](https://github.com/dart-lang/sdk/issues/38148).
        // Adding a workaround for now.
        if (await directory.exists_()) {
          final contents = await directory.list_();
          await Future.wait(
            contents.map((file) => file.delete_()),
          );
        }
        await directory.delete(recursive: true);
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Checks whether a [FileSystemEntity] exists or not.
  Future<bool> exists_() {
    try {
      if (this is File) {
        return File(clean(path)).exists();
      } else if (this is Directory) {
        return Directory(clean(path)).exists();
      } else {
        return Future.value(false);
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return Future.value(false);
    }
  }

  /// Checks whether a [FileSystemEntity] exists or not.
  bool existsSync_() {
    try {
      if (this is File) {
        return File(clean(path)).existsSync();
      } else if (this is Directory) {
        return Directory(clean(path)).existsSync();
      } else {
        return false;
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return false;
    }
  }

  /// Displays a [File] or [Directory] in host operating system's default file explorer.
  void explore_() async {
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        [
          '/select,',
          path.startsWith(kWin32LocalPathPrefix)
              ? path.substring(kWin32LocalPathPrefix.length)
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

/// [Map] for storing various instances of [Lock] to ensure mutual exclusion in [FileExtension.read_] & [FileExtension.write_].
final Map<String, Lock> locks = <String, Lock>{};
