/// This file is a part of safe_local_storage (https://github.com/alexmercerind/safe_local_storage).
///
/// Copyright (c) 2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' hide equals;
import 'package:collection/collection.dart';

import 'package:safe_local_storage/safe_local_storage.dart';

Future<void> main() async {
  final cacheDirectoryPath = File(Platform.script.toFilePath()).parent.path;
  final cacheFilePath = join(
    cacheDirectoryPath,
    'cache.json',
  );
  const fallback = {'message': 'hello'};

  Future<void> clearCacheFile() async {
    await File(cacheFilePath).delete_();
  }

  Future<void> clearCacheHistory() async {
    await Directory(join(cacheDirectoryPath, 'Temp')).delete_();
  }

  Future<void> clear() => Future.wait([
        clearCacheFile(),
        clearCacheHistory(),
      ]);
  print('[test]: creation');
  test('creation', () async {
    await clear();
    SafeSessionStorage(cacheFilePath);
  });
  print('[test]: empty-read');
  test('empty-read', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isFalse,
    );
  });
  print('[test]: write');
  test('write', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(cacheDirectoryPath, 'Temp')).listSync().first
              as File)
          .readAsString(),
      equals(JsonEncoder.withIndent('    ').convert({'foo': 'bar'})),
    );
  });
  print('[test]: read');
  test('read', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(cacheDirectoryPath, 'Temp')).listSync().first
              as File)
          .readAsString(),
      equals(JsonEncoder.withIndent('    ').convert({'foo': 'bar'})),
    );
  });
  print('[test]: rollback-after-cache-missing');
  test('rollback-after-cache-missing', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clearCacheFile();
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(cacheDirectoryPath, 'Temp')).listSync().first
              as File)
          .readAsString(),
      equals(JsonEncoder.withIndent('    ').convert({'foo': 'bar'})),
    );
  });
  print('[test]: rollback-after-cache-corrupt');
  test('rollback-after-cache-corrupt', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(cacheFilePath).writeAsString('haha!');
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(cacheDirectoryPath, 'Temp')).listSync().first
              as File)
          .readAsString(),
      equals(JsonEncoder.withIndent('    ').convert({'foo': 'bar'})),
    );
  });
  print('[test]: fallback-after-cache-and-history-delete');
  test('fallback-after-cache-and-history-delete', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clear();
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  print('[test]: write-mutual-exclusion-and-sequencing');
  test('write-mutual-exclusion-and-sequencing', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    final completers = [
      Completer(),
      Completer(),
      Completer(),
    ];
    // No `await`. This tests the mutual exclusion of the [SafeSessionStorage.write] method.
    storage.write({'foo': 'bar'}).then((value) => completers[0].complete());
    storage.write({'foo': 'baz'}).then((value) => completers[1].complete());
    storage.write({'fizz': 'buzz'}).then((value) => completers[2].complete());
    await Future.wait(completers.map((e) => e.future));
    expect(
      const MapEquality().equals(await storage.read(), {'fizz': 'buzz'}),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(3),
    );
  });
  print('[test]: cache-rollback-history');
  test('cache-rollback-history', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    // Write data.
    final completers = [
      Completer(),
      Completer(),
      Completer(),
    ];
    storage.write({'foo': 'bar'}).then((value) => completers[0].complete());
    storage.write({'foo': 'baz'}).then((value) => completers[1].complete());
    storage.write({'fizz': 'buzz'}).then((value) => completers[2].complete());
    await Future.wait(completers.map((e) => e.future));
    // Corrupt file.
    await File(cacheFilePath).write_('haha!');
    // Corrupt latest [File] in the history.
    final contents =
        Directory(join(cacheDirectoryPath, 'Temp')).listSync().cast<File>();
    contents.sort(
      (a, b) => int.parse(basename(b.path).split('.').last).compareTo(
        int.parse(basename(a.path).split('.').last),
      ),
    );
    // Not using [FileExtension.write_] here because it's not meant to be used to
    // alter the history versions of the cache file.
    await contents.first.writeAsString('haha!');
    // Perform read.
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'baz'}),
      isTrue,
    );
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(3),
    );
  });
  print('[test]: fallback-cache-delete-empty-history');
  test('fallback-cache-delete-empty-history', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Delete cache file.
    await clearCacheFile();
    // Empty the history.
    await Future.wait(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().map((e) {
        if (e is File) {
          return e.delete();
        } else {
          return Future.value();
        }
      }),
    );
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  print('[test]: fallback-cache-corrupt-empty-history');
  test('fallback-cache-corrupt-empty-history', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(cacheFilePath).write_('haha!');
    // Empty the history.
    await Future.wait(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().map((e) {
        if (e is File) {
          return e.delete();
        } else {
          return Future.value();
        }
      }),
    );
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  print('[test]: history-transaction-limit');
  test('history-transaction-limit', () async {
    await clear();
    final storage = SafeSessionStorage(cacheFilePath, fallback: fallback);
    await Future.wait(
      List.generate(
        20,
        (index) => storage.write({'foo': 'bar'}),
      ),
    );
    // Wait for the asynchronous suspension to complete.
    await Future.delayed(const Duration(milliseconds: 100));
    expect(
      await Directory(join(cacheDirectoryPath, 'Temp')).exists_(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(10),
    );
    Directory(join(cacheDirectoryPath, 'Temp')).listSync().forEach(
          (e) => expect(
            const MapEquality().equals(
              jsonDecode((e as File).readAsStringSync()),
              {'foo': 'bar'},
            ),
            isTrue,
          ),
        );
  });
}
