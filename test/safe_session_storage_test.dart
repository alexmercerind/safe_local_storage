import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' hide equals;
import 'package:safe_session_storage/safe_session_storage.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final cacheDirectoryPath = File(Platform.script.toFilePath()).parent.path;
  final cacheFilePath = join(
    cacheDirectoryPath,
    'cache.json',
  );
  const fallback = {'message': 'hello'};
  final storage =
      SafeSessionStorage(cacheFilePath, fallback: {'message': 'hello'});
  test('creation', () async {
    SafeSessionStorage(cacheFilePath);
  });
  test('empty-read', () async {
    expect(
      MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  test('write', () async {
    await storage.write({'foo': 'bar'});
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).existsSync(),
      isTrue,
    );
    expect(
      Directory(join(cacheDirectoryPath, 'Temp')).listSync().length,
      equals(1),
    );
  });
  test('read', () async {
    expect(
      MapEquality().equals(await storage.read(), {'foo': 'bar'}),
      isTrue,
    );
  });
  test('cache-rollback-after-file-delete', () async {
    await File(cacheFilePath).delete(recursive: true);
    expect(
      MapEquality().equals(await storage.read(), {'foo': 'bar'}),
      isTrue,
    );
  });
  test('cache-rollback-after-file-corrupt', () async {
    await File(cacheFilePath).writeAsString('haha!');
    expect(
      MapEquality().equals(await storage.read(), {'foo': 'bar'}),
      isTrue,
    );
  });
  test('fallback-after-file-and-history-delete', () async {
    await Directory(join(cacheDirectoryPath, 'Temp')).delete(recursive: true);
    await File(cacheFilePath).delete(recursive: true);
    print(await storage.read());
    expect(
      MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  // TODO: Sometimes fail.
  test('multiple-write-and-read-isolation-test', () async {
    final completers = [
      Completer(),
      Completer(),
      Completer(),
    ];
    storage.write({'foo': 'bar'}).then((value) => completers[0].complete());
    storage.write({'foo': 'baz'}).then((value) => completers[1].complete());
    storage.write({'fizz': 'buzz'}).then((value) => completers[2].complete());
    await Future.wait(completers.map((e) => e.future));
    expect(
      MapEquality().equals(await storage.read(), {'fizz': 'buzz'}),
      isTrue,
    );
  });
  // TODO: Sometimes fail.
  test('cache-rollback-history', () async {
    await File(cacheFilePath).writeAsString('haha!');
    final contents =
        Directory(join(cacheDirectoryPath, 'Temp')).listSync().cast<File>();
    contents.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    await contents.first.delete();
    expect(
      MapEquality().equals(await storage.read(), {'foo': 'baz'}),
      isTrue,
    );
  });
  test('fallback-file-delete-empty-history', () async {
    await File(cacheFilePath).delete();
    for (final file in Directory(join(cacheDirectoryPath, 'Temp')).listSync()) {
      await file.delete();
    }
    expect(
      MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
  test('fallback-file-corrupt-empty-history', () async {
    await File(cacheFilePath).writeAsString('haha!');
    for (final file in Directory(join(cacheDirectoryPath, 'Temp')).listSync()) {
      await file.delete();
    }
    expect(
      MapEquality().equals(await storage.read(), fallback),
      isTrue,
    );
  });
}
