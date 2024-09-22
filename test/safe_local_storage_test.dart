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
  final directory = Directory.systemTemp.path;

  final path = join(directory, 'Cache.JSON');
  const fallback = {'message': 'hello, world!'};

  print(path);

  Future<void> clearCacheFile() async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> clearCacheHistory() async {
    final historyDirectory =
        Directory(join(directory, SafeLocalStorage.kHistoryDirectoryName));
    try {
      for (final file in historyDirectory.listSync()) {
        if (file is File) {
          await file.delete();
        }
      }
      historyDirectory.delete();
    } catch (_) {}
  }

  Future<void> clear() => Future.wait([clearCacheFile(), clearCacheHistory()]);

  test('init', () async {
    await clear();
    SafeLocalStorage(path);
  });
  test('empty-read', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isFalse,
    );
  });
  test('write', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(directory, '.History')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(directory, '.History')).listSync().first as File)
          .readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('read', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(directory, '.History')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(directory, '.History')).listSync().first as File)
          .readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-missing', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clearCacheFile();
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(directory, '.History')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(directory, '.History')).listSync().first as File)
          .readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-corrupt', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(path).writeAsString('Haha!');
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(1),
    );
    expect(
      Directory(join(directory, '.History')).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(join(directory, '.History')).listSync().first as File)
          .readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-corrupt-history-corrupt', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
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
    // Corrupt the file.
    await File(path).writeAsString('haha!');
    // Corrupt last history entry.
    final contents =
        Directory(join(directory, '.History')).listSync().cast<File>();
    contents.sort(
      (a, b) => int.parse(basename(b.path).split('.').last).compareTo(
        int.parse(basename(a.path).split('.').last),
      ),
    );
    await contents.first.writeAsString('haha!');

    final data = await storage.read();

    print(data);

    expect(
      const MapEquality().equals(data, {'foo': 'baz'}),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(3),
    );
  });
  test('fallback-after-cache-and-history-delete', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clear();
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  test('fallback-cache-missing-empty-history', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Delete cache file.
    await clearCacheFile();
    // Empty the history.
    await Future.wait(
      Directory(join(directory, '.History')).listSync().map((e) {
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
  test('fallback-cache-corrupt-empty-history', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(path).writeAsString('haha!');
    // Empty the history.
    await Future.wait(
      Directory(join(directory, '.History')).listSync().map((e) {
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
  test('write-mutual-exclusion-and-sequencing', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    final completers = [
      Completer(),
      Completer(),
      Completer(),
    ];
    // No `await`. This tests the mutual exclusion of the [SafeLocalStorage.write] method.
    storage.write({'foo': 'bar'}).then((value) => completers[0].complete());
    storage.write({'foo': 'baz'}).then((value) => completers[1].complete());
    storage.write({'fizz': 'buzz'}).then((value) => completers[2].complete());
    await Future.wait(completers.map((e) => e.future));
    expect(
      const MapEquality().equals(await storage.read(), {'fizz': 'buzz'}),
      isTrue,
    );
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(3),
    );
  });
  test('history-transaction-limit', () async {
    await clear();
    final storage = SafeLocalStorage(path, fallback: fallback);
    await Future.wait(
      List.generate(
        20,
        (index) => storage.write({'foo': 'bar'}),
      ),
    );
    // Wait for the asynchronous suspension to complete.
    await Future.delayed(const Duration(milliseconds: 500));
    expect(
      await Directory(join(directory, '.History')).exists(),
      isTrue,
    );
    expect(
      Directory(join(directory, '.History')).listSync().length,
      equals(10),
    );
    final files =
        Directory(join(directory, '.History')).listSync().cast<File>();
    for (final file in files) {
      expect(
        const MapEquality().equals(
          json.decode(file.readAsStringSync()),
          {'foo': 'bar'},
        ),
        isTrue,
      );
    }
  });
}
