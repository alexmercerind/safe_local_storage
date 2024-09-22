import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:safe_local_storage/file_system.dart';
import 'package:synchronized/extension.dart';

import 'package:safe_local_storage/isolates.dart';

/// {@template safe_local_storage}
///
/// SafeLocalStorage
/// ----------------
/// A safe caching library to read/write values on local storage.
///
/// {@endtemplate}
class SafeLocalStorage {
  /// Path.
  final String path;

  /// Fallback.
  final dynamic fallback;

  /// {@macro safe_local_storage}
  SafeLocalStorage(this.path, {this.fallback = const <String, dynamic>{}});

  /// Writes.
  Future<void> write(dynamic data) => synchronized(() async {
        return compute(_write, _WriteData(path, fallback, data));
      });

  /// Reads.
  Future<dynamic> read() => synchronized(() async {
        return compute(_read, _ReadData(path, fallback));
      });

  static Future<void> _write(_WriteData data) async {
    final cachePath = data.path;
    final cacheFile = File(cachePath);
    final cacheFileName = basename(cachePath);

    final historyPath = join(dirname(cachePath), kHistoryDirectoryName);
    final historyDirectory = Directory(historyPath);

    try {
      await cacheFile.write_(json.encode(data.data));
    } catch (_) {}

    try {
      if (!await historyDirectory.exists_()) {
        await historyDirectory.create_();
      }
    } catch (_) {}

    final historyId = DateTime.now().millisecondsSinceEpoch;
    final historyEntryPath = join(historyPath, '$cacheFileName.$historyId');
    final historyEntryFile = File(historyEntryPath);
    await historyEntryFile.write_(json.encode(data.data));

    await _clearHistoryEntryFiles(_ClearHistoryEntryFiles(cachePath));
  }

  static Future<dynamic> _read(_ReadData data) async {
    final cachePath = data.path;
    final cacheFile = File(cachePath);

    try {
      final cacheFileContent = await cacheFile.readAsString_();
      return json.decode(cacheFileContent!);
    } catch (_) {}

    try {
      final historyEntryFiles =
          await _getHistoryEntryFiles(_GetHistoryEntryFiles(cachePath));

      for (final historyEntryFile in historyEntryFiles) {
        try {
          final historyEntryFileContent =
              await historyEntryFile.readAsString_();
          final historyEntryData = json.decode(historyEntryFileContent!);

          await cacheFile.write_(historyEntryFileContent);

          return historyEntryData;
        } catch (_) {}
      }
    } catch (_) {}

    return data.fallback;
  }

  static Future<List<File>> _getHistoryEntryFiles(
      _GetHistoryEntryFiles data) async {
    final cachePath = data.path;
    final cacheFileName = basename(cachePath);

    final historyPath = join(dirname(cachePath), kHistoryDirectoryName);
    final historyDirectory = Directory(historyPath);

    if (!await historyDirectory.exists_()) {
      return [];
    }

    final historyEntryFiles = await historyDirectory.list_();
    historyEntryFiles
      ..removeWhere((historyEntryFile) {
        final historyEntryFileName = basename(historyEntryFile.path);
        final historyEntryFileExtension = historyEntryFile.extension;

        if (!historyEntryFileName.startsWith('$cacheFileName.')) {
          return true;
        }
        if (int.tryParse(historyEntryFileExtension) == null) {
          return true;
        }

        return false;
      })
      ..sort((a, b) {
        final historyEntryAFileExtension = a.extension;
        final historyEntryAId = int.parse(historyEntryAFileExtension);

        final historyEntryBFileExtension = b.extension;
        final historyEntryBId = int.parse(historyEntryBFileExtension);

        return historyEntryBId.compareTo(historyEntryAId);
      });

    return historyEntryFiles;
  }

  static Future<void> _clearHistoryEntryFiles(
      _ClearHistoryEntryFiles data) async {
    final cachePath = data.path;

    final historyPath = join(dirname(cachePath), kHistoryDirectoryName);
    final historyDirectory = Directory(historyPath);

    try {
      if (!await historyDirectory.exists_()) {
        return;
      }
    } catch (_) {}

    try {
      final historyEntryFiles = await historyDirectory.list_();
      for (final historyEntryFile in historyEntryFiles.skip(kHistoryCount)) {
        await historyEntryFile.delete_();
      }
    } catch (_) {}
  }

  static const int kHistoryCount = 10;
  static const String kHistoryDirectoryName = '.History';
}

class _WriteData {
  final String path;
  final dynamic fallback;
  final dynamic data;

  _WriteData(this.path, this.fallback, this.data);
}

class _ReadData {
  final String path;
  final dynamic fallback;

  _ReadData(this.path, this.fallback);
}

class _GetHistoryEntryFiles {
  final String path;

  _GetHistoryEntryFiles(this.path);
}

class _ClearHistoryEntryFiles {
  final String path;

  _ClearHistoryEntryFiles(this.path);
}
