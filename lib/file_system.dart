import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:synchronized/synchronized.dart';

/// System storage path prefix required on Windows for long file-path support.
/// Default implementation in dart:io does not support long file-path on Windows.
///
/// Reference: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=registry
const String kWindowsStoragePathPrefix = '\\\\?\\';

/// Network storage path have a \\ prefix on Windows.
/// For these paths, \\?\ prefix does not work correctly.
const String kWindowsNetworkPathPrefix = '\\\\';

String kPathSeparator = Platform.isWindows ? '\\' : '/';

/// Returns the file system path with the prefix added.
String addPrefix(String path) {
  String result;
  if (Platform.isWindows) {
    final hasStoragePrefix = path.startsWith(kWindowsStoragePathPrefix);
    final hasNetworkPrefix = path.startsWith(kWindowsNetworkPathPrefix);
    final hasPrefix = hasStoragePrefix || hasNetworkPrefix;
    final prefix = !hasPrefix ? kWindowsStoragePathPrefix : '';
    result = '$prefix${normalize(path.replaceAll('/', '\\'))}';
  } else {
    result = normalize(path);
  }

  return removeTrailingSlash(result);
}

/// Returns the file system path with the prefix removed.
String removePrefix(String path) {
  String result;
  if (Platform.isWindows && path.startsWith(kWindowsStoragePathPrefix)) {
    result = normalize(path.substring(kWindowsStoragePathPrefix.length));
  } else {
    result = normalize(path);
  }

  return removeTrailingSlash(result);
}

/// Adds a trailing slash to the path if it does not have one.
String addTrailingSlash(String path) {
  if (!path.endsWith(kPathSeparator)) {
    return '$path$kPathSeparator';
  }
  return path;
}

/// Removes a trailing slash from the path if it has one.
String removeTrailingSlash(String path) {
  if (path.endsWith(kPathSeparator)) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// Wrapper around dart:io's [FileSystemEntity] class.
abstract class FS {
  static Future<FileSystemEntityType> type_(String path) {
    return FileSystemEntity.type(addPrefix(path));
  }

  static FileSystemEntityType typeSync_(String path) {
    return FileSystemEntity.typeSync(addPrefix(path));
  }
}

/// Wrapper around dart:io's [Directory] class.
extension DirectoryExtension on Directory {
  /// Recursively lists all the [File]s present in the [Directory].
  ///
  /// * Safely handles long file-paths on Windows: https://github.com/dart-lang/sdk/issues/27825
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  Future<List<File>> list_({bool Function(File)? predicate}) async {
    final completer = Completer();
    final files = <File>[];
    try {
      Directory(addPrefix(path))
          .list(recursive: true, followLinks: false)
          .listen(
        (event) {
          if (event is File) {
            final file = File(removePrefix(event.path));
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
  /// * Safely handles long file-paths on Windows: https://github.com/dart-lang/sdk/issues/27825
  /// * Does not terminate on errors e.g. an encounter of `Access Is Denied`.
  /// * Does not follow links.
  Future<List<FileSystemEntity>> children_() async {
    final completer = Completer();
    final contents = <FileSystemEntity>[];
    try {
      Directory(addPrefix(path))
          .list(recursive: false, followLinks: false)
          .listen(
        (event) {
          switch (FS.typeSync_(event.path)) {
            case FileSystemEntityType.directory:
              contents.add(Directory(removePrefix(event.path)));
              break;
            case FileSystemEntityType.file:
              contents.add(File(removePrefix(event.path)));
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

  /// Creates the [Directory].
  Future<void> create_() async {
    if (Platform.isWindows) {
      // On Windows, \\?\ prefix causes issues if we use it to access a root volume without a trailing slash.
      // In other words, \\?\C: is not valid, but \\?\C:\ is valid. If we try to access \\?\C: without a trailing slash, following error is thrown by Windows:
      //
      // "\\?\C:" is not a recognized device.
      // The filename, directory name, or volume label syntax is incorrect.
      //
      // When recursively creating a [File] or [Directory] recursively using `dart:io`'s implementation, if the parent [Directory] does not exist, all the intermediate [Directory]s are created.
      // However, internal implementation of dart:io does not handle the case of \\?\C: (without a trailing slash) & fails with the above error.
      // To avoid this, we manually create the intermediate [Directory]s with the trailing slash.
      final directory = Directory(addPrefix(path));
      final parent = Directory(addTrailingSlash(this.parent.path));

      // Case A.
      if (await directory.exists_()) {
        return;
      }
      // Case B.
      if (await parent.exists_()) {
        await directory.create();
        return;
      }
      // Case C.
      final parts = removePrefix(directory.path).split(kPathSeparator);
      parts.removeLast();
      for (int i = 0; i < parts.length; i++) {
        final path = addTrailingSlash(
            addPrefix(parts.sublist(0, i + 1).join(kPathSeparator)));
        try {
          if (!await Directory(path).exists_()) {
            await Directory(path).create();
          }
        } catch (exception, stacktrace) {
          print(exception.toString());
          print(stacktrace.toString());
        }
      }
      await directory.create();
    } else {
      try {
        await Directory(addPrefix(path)).create(recursive: true);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    }
  }
}

/// Wrapper around dart:io's [File] class.
extension FileExtension on File {
  /// Writes the [content] to the [File].
  Future<void> write_(dynamic content, {bool history = false}) async {
    _locks[addPrefix(path)] ??= Lock();
    return _locks[addPrefix(path)]?.synchronized(() async {
      // Create the [File] if it does not exist.
      if (!await exists_()) {
        await create_();
      }
      try {
        final src = addPrefix(join(parent.path, '.${basename(path)}.src'));
        final dst = addPrefix(path);
        if (content is String) {
          await File(src).writeAsString(content, flush: true);
        } else if (content is Uint8List) {
          await File(src).writeAsBytes(content, flush: true);
        } else {
          throw FileSystemException(
            'Unsupported content type: ${content.runtimeType}',
            path,
          );
        }
        await File(src).rename_(dst);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    });
  }

  /// Reads the contents of the [File] as [String].
  /// Returns `null` if the [File] does not exist.
  FutureOr<String?> readAsString_() {
    _locks[addPrefix(path)] ??= Lock();
    return _locks[addPrefix(path)]?.synchronized(() async {
      final file = File(addPrefix(path));
      if (await file.exists_()) {
        return await file.readAsString();
      }
      return null;
    });
  }

  /// Reads the contents of the [File] as [Uint8List].
  /// Returns `null` if the [File] does not exist.
  FutureOr<Uint8List?> readAsBytes_() async {
    _locks[addPrefix(path)] ??= Lock();
    return _locks[addPrefix(path)]?.synchronized(() async {
      final file = File(addPrefix(path));
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
        if (await File(addPrefix(destination)).exists_()) {
          await File(addPrefix(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      try {
        if (await Directory(addPrefix(destination)).exists_()) {
          await Directory(addPrefix(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      await File(addPrefix(path)).rename(addPrefix(destination));
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
        if (await File(addPrefix(destination)).exists_()) {
          await File(addPrefix(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      try {
        if (await Directory(addPrefix(destination)).exists_()) {
          await Directory(addPrefix(destination)).delete_();
        }
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
      await File(addPrefix(path)).copy(addPrefix(destination));
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
      // However, internal implementation of dart:io does not handle the case of \\?\C: (without a trailing slash) & fails with the above error.
      // To avoid this, we manually create the intermediate [Directory]s with the trailing slash.
      final file = File(addPrefix(path));
      final parent = Directory(addTrailingSlash(this.parent.path));

      // Case A.
      if (await file.exists_()) {
        return;
      }
      // Case B.
      if (await parent.exists_()) {
        await file.create();
        return;
      }
      // Case C.
      final parts = removePrefix(file.path).split(kPathSeparator);
      parts.removeLast();
      for (int i = 0; i < parts.length; i++) {
        final path = addTrailingSlash(
            addPrefix(parts.sublist(0, i + 1).join(kPathSeparator)));
        try {
          if (!await Directory(path).exists_()) {
            await Directory(path).create();
          }
        } catch (exception, stacktrace) {
          print(exception.toString());
          print(stacktrace.toString());
        }
      }
      await file.create();
    } else {
      try {
        await File(addPrefix(path)).create(recursive: true);
      } catch (exception, stacktrace) {
        print(exception.toString());
        print(stacktrace.toString());
      }
    }
  }

  /// Returns size the [File] in bytes.
  /// Returns 0 if the [File] does not exist.
  FutureOr<int> length_() async {
    final file = File(addPrefix(path));
    try {
      if (await file.exists_()) {
        return file.length();
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    return 0;
  }

  /// Returns size the [File] in bytes.
  /// Returns 0 if the [File] does not exist.
  int lengthSync_() {
    final file = File(addPrefix(path));
    try {
      if (file.existsSync_()) {
        return file.lengthSync();
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
    return 0;
  }

  /// Returns last modified timestamp of the [File].
  /// Returns null if the [File] does not exist.
  FutureOr<DateTime?> lastModified_() async {
    final file = File(addPrefix(path));
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
  /// Returns null if the [File] does not exist.
  DateTime? lastModifiedSync_() {
    final file = File(addPrefix(path));
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

/// Wrapper around dart:io's [FileSystemEntity] class.
extension FileSystemEntityExtension on FileSystemEntity {
  /// Deletes the [FileSystemEntity].
  Future<void> delete_() async {
    // Surround with try/catch instead of using [Directory.exists_], because it confuses Windows into saying:
    // "The process cannot access the file because it is being used by another process."
    try {
      if (this is File) {
        await File(addPrefix(path)).delete(recursive: true);
      } else if (this is Directory) {
        final directory = Directory(addPrefix(path));
        // NOTE: [Directory.delete] is not working with recursive: true: https://github.com/dart-lang/sdk/issues/38148
        if (await directory.exists_()) {
          final contents = await directory.list_();
          await Future.wait(contents.map((file) => file.delete_()));
        }
        await directory.delete(recursive: true);
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
    }
  }

  /// Checks whether the [FileSystemEntity] exists or not.
  Future<bool> exists_() {
    try {
      if (this is File) {
        return File(addPrefix(path)).exists();
      } else if (this is Directory) {
        return Directory(addPrefix(path)).exists();
      } else {
        return Future.value(false);
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return Future.value(false);
    }
  }

  /// Checks whether the [FileSystemEntity] exists or not.
  bool existsSync_() {
    try {
      if (this is File) {
        return File(addPrefix(path)).existsSync();
      } else if (this is Directory) {
        return Directory(addPrefix(path)).existsSync();
      } else {
        return false;
      }
    } catch (exception, stacktrace) {
      print(exception.toString());
      print(stacktrace.toString());
      return false;
    }
  }

  /// Displays a [File] or [Directory] in the host operating system's file explorer.
  void explore_() async {
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
    if (Platform.isMacOS) {
      await Process.start(
        'open',
        [
          '-R',
          removePrefix(path),
        ],
        runInShell: true,
        includeParentEnvironment: true,
        mode: ProcessStartMode.detached,
      );
    }
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        [
          '/select,',
          removePrefix(path),
        ],
        runInShell: true,
        includeParentEnvironment: true,
        mode: ProcessStartMode.detached,
      );
    }
  }

  String get extension => basename(path).split('.').last.toUpperCase();
}

/// [Lock] instances to maintain mutual exclusion of file operations.
final HashMap<String, Lock> _locks = HashMap<String, Lock>();
