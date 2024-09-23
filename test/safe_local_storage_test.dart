import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' hide equals;
import 'package:collection/collection.dart';

import 'package:safe_local_storage/safe_local_storage.dart';

Future<void> main() async {
  final directoryPath = Directory.systemTemp.path;
  final historyPath = join(directoryPath, '.History');
  final cachePath = join(directoryPath, 'Cache.JSON');
  const fallback = {'message': 'hello, world!'};

  Future<void> clearCacheFile() async {
    try {
      await File(cachePath).delete();
    } catch (_) {}
  }

  Future<void> clearCacheHistory() async {
    try {
      final historyDirectory = Directory(historyPath);
      for (final file in historyDirectory.listSync().cast<File>()) {
        await file.delete();
      }
      historyDirectory.delete();
    } catch (_) {}
  }

  Future<void> clear() => Future.wait([clearCacheFile(), clearCacheHistory()]);

  test('init', () async {
    await clear();
    SafeLocalStorage(cachePath);
  });
  test('empty-read', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
    expect(
      await Directory(historyPath).exists(),
      isFalse,
    );
  });
  test('write', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(1),
    );
    expect(
      Directory(historyPath).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(historyPath).listSync().first as File).readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('read', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(1),
    );
    expect(
      Directory(historyPath).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(historyPath).listSync().first as File).readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-missing', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clearCacheFile();
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(1),
    );
    expect(
      Directory(historyPath).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(historyPath).listSync().first as File).readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-corrupt', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(cachePath).writeAsString('Haha!');
    final data = await storage.read();
    expect(
      const MapEquality().equals(data, {'foo': 'bar'}),
      isTrue,
    );
    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(1),
    );
    expect(
      Directory(historyPath).listSync().first,
      TypeMatcher<File>(),
    );
    expect(
      await (Directory(historyPath).listSync().first as File).readAsString(),
      equals(json.encode({'foo': 'bar'})),
    );
  });
  test('rollback-after-cache-corrupt-history-corrupt', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
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
    await File(cachePath).writeAsString('haha!');
    // Corrupt last history entry.
    final files = Directory(historyPath).listSync();
    files.sort(
      (a, b) {
        final aId = int.parse(basename(a.path).split('.').last);
        final bId = int.parse(basename(b.path).split('.').last);
        return bId.compareTo(aId);
      },
    );
    final file = files.first as File;
    await file.writeAsString('haha!');

    final data = await storage.read();

    expect(
      const MapEquality().equals(data, {'foo': 'baz'}),
      isTrue,
    );
    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(3),
    );
  });
  test('fallback-after-cache-and-history-delete', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    await clear();
    expect(
      const MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  test('fallback-cache-missing-empty-history', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Delete cache file.
    await clearCacheFile();
    // Empty the history.
    await Future.wait(
      Directory(historyPath).listSync().map((e) {
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
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
    await storage.write({'foo': 'bar'});
    // Corrupt the file.
    await File(cachePath).writeAsString('haha!');
    // Empty the history.
    await Future.wait(
      Directory(historyPath).listSync().map((e) {
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
    final storage = SafeLocalStorage(cachePath, fallback: fallback);
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
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(3),
    );
  });
  test('history-transaction-limit', () async {
    await clear();
    final storage = SafeLocalStorage(cachePath, fallback: fallback);

    const count = 20;

    for (int i = 0; i < count; i++) {
      await storage.write({'foo': '$i'});
    }

    // Wait for the asynchronous suspension to complete.
    await Future.delayed(const Duration(milliseconds: 500));

    expect(
      await Directory(historyPath).exists(),
      isTrue,
    );
    expect(
      Directory(historyPath).listSync().length,
      equals(10),
    );
    final files = Directory(historyPath).listSync().cast<File>();
    files.sort(
      (a, b) {
        final aId = int.parse(basename(a.path).split('.').last);
        final bId = int.parse(basename(b.path).split('.').last);
        return bId.compareTo(aId);
      },
    );

    int i = count - 1;

    for (final file in files) {
      final content = json.decode(file.readAsStringSync());
      expect(
        const MapEquality().equals(
          content,
          {'foo': '$i'},
        ),
        isTrue,
      );
      i--;
    }
  });
}
