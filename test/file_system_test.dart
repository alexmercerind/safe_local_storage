import 'dart:io';
import 'package:path/path.dart' hide equals;
import 'package:test/test.dart';
import 'package:safe_local_storage/safe_local_storage.dart';

void main() {
  group('Windows', () {
    test('isDriveRoot', () {
      expect(isDriveRoot(r'C:\'), isTrue);
      expect(isDriveRoot(r'C:'), isTrue);
      expect(isDriveRoot(r'C:/'), isTrue);
      expect(isDriveRoot(r'c:\'), isTrue);
      expect(isDriveRoot(r'c:'), isTrue);
      expect(isDriveRoot(r'\\?\C:\'), isTrue);
      expect(isDriveRoot(r'\\?\C:'), isTrue);
      expect(isDriveRoot(r'\\?\c:/'), isTrue);

      expect(isDriveRoot(r'C:\foo'), isFalse);
      expect(isDriveRoot(r'C:\foo\'), isFalse);
      expect(isDriveRoot(r'\\?\C:\foo'), isFalse);
      expect(isDriveRoot(r'\\server\share'), isFalse);
      expect(isDriveRoot(r'\\server\share\'), isFalse);
      expect(isDriveRoot(''), isFalse);
    });

    test('addPrefix handles drive roots', () {
      expect(addPrefix(r'C:\'), equals(r'\\?\C:\'));
      expect(addPrefix(r'C:'), equals(r'\\?\C:\'));
      expect(addPrefix(r'C:/'), equals(r'\\?\C:\'));
      expect(addPrefix(r'\\?\C:\'), equals(r'\\?\C:\'));
      expect(addPrefix(r'\\?\C:'), equals(r'\\?\C:\'));
      expect(addPrefix(r'c:\'), equals(r'\\?\c:\'));
    });

    test('addPrefix handles directories and files', () {
      expect(addPrefix(r'C:\foo\bar'), equals(r'\\?\C:\foo\bar'));
      expect(addPrefix(r'C:\foo\bar\'), equals(r'\\?\C:\foo\bar'));
      expect(addPrefix(r'C:/foo/bar/'), equals(r'\\?\C:\foo\bar'));
    });

    test('removePrefix handles drive roots', () {
      expect(removePrefix(r'\\?\C:\'), equals(r'C:\'));
      expect(removePrefix(r'\\?\C:'), equals(r'C:\'));
      expect(removePrefix(r'C:\'), equals(r'C:\'));
      expect(removePrefix(r'C:'), equals(r'C:\'));
    });

    test('removePrefix handles directories and files', () {
      expect(removePrefix(r'\\?\C:\foo\bar'), equals(r'C:\foo\bar'));
      expect(removePrefix(r'\\?\C:\foo\bar\'), equals(r'C:\foo\bar'));
    });

    test('removeTrailingSlash preserves drive roots', () {
      expect(removeTrailingSlash(r'C:\'), equals(r'C:\'));
      expect(removeTrailingSlash(r'C:'), equals(r'C:\'));
      expect(removeTrailingSlash(r'\\?\C:\'), equals(r'\\?\C:\'));
      expect(removeTrailingSlash(r'\\?\C:'), equals(r'\\?\C:\'));
    });

    test('removeTrailingSlash handles directories and files', () {
      expect(removeTrailingSlash(r'C:\foo\bar\'), equals(r'C:\foo\bar'));
      expect(removeTrailingSlash(r'C:\foo\bar'), equals(r'C:\foo\bar'));
    });

    test('exists_ and existsSync_ on drive root', () async {
      expect(await Directory(r'C:\').exists_(), isTrue);
      expect(Directory(r'C:\').existsSync_(), isTrue);
      expect(await Directory(r'C:').exists_(), isTrue);
      expect(Directory(r'C:').existsSync_(), isTrue);
      expect(await Directory(r'\\?\C:\').exists_(), isTrue);
      expect(Directory(r'\\?\C:\').existsSync_(), isTrue);
    });

    test('FS.type_ and FS.typeSync_ on drive root', () async {
      expect(await FS.type_(r'C:\'), equals(FileSystemEntityType.directory));
      expect(FS.typeSync_(r'C:\'), equals(FileSystemEntityType.directory));
      expect(await FS.type_(r'C:'), equals(FileSystemEntityType.directory));
      expect(FS.typeSync_(r'C:'), equals(FileSystemEntityType.directory));
    });

    test('Directory.create_ on drive root', () async {
      await Directory(r'C:\').create_();
    });
  }, testOn: 'windows');

  group('POSIX', () {
    test('isDriveRoot', () {
      expect(isDriveRoot('/'), isFalse);
      expect(isDriveRoot('/foo/bar'), isFalse);
    });

    test('addPrefix handles root', () {
      expect(addPrefix('/'), equals('/'));
    });

    test('addPrefix handles directories and files', () {
      expect(addPrefix('/foo/bar'), equals('/foo/bar'));
      expect(addPrefix('/foo/bar/'), equals('/foo/bar'));
    });

    test('removePrefix handles root', () {
      expect(removePrefix('/'), equals('/'));
    });

    test('removePrefix handles directories and files', () {
      expect(removePrefix('/foo/bar'), equals('/foo/bar'));
      expect(removePrefix('/foo/bar/'), equals('/foo/bar'));
    });

    test('removeTrailingSlash preserves root', () {
      expect(removeTrailingSlash('/'), equals('/'));
    });

    test('removeTrailingSlash handles directories and files', () {
      expect(removeTrailingSlash('/foo/bar/'), equals('/foo/bar'));
      expect(removeTrailingSlash('/foo/bar'), equals('/foo/bar'));
    });

    test('exists_ and existsSync_ on root', () async {
      expect(await Directory('/').exists_(), isTrue);
      expect(Directory('/').existsSync_(), isTrue);
    });

    test('FS.type_ and FS.typeSync_ on root', () async {
      expect(await FS.type_('/'), equals(FileSystemEntityType.directory));
      expect(FS.typeSync_('/'), equals(FileSystemEntityType.directory));
    });

    test('Directory.create_ on root', () async {
      await Directory('/').create_();
    });
  }, testOn: 'posix');

  group('Directory.create_ and File.create_', () {
    test('Directory.create_ creates nested directories recursively', () async {
      final temp = Directory(join(
        Directory.systemTemp.path,
        'safe_local_storage_dir_${DateTime.now().microsecondsSinceEpoch}',
        'sub1',
        'sub2',
      ));
      try {
        expect(await temp.exists_(), isFalse);
        await temp.create_();
        expect(await temp.exists_(), isTrue);
        expect(temp.existsSync_(), isTrue);
        // Call create_ again on existing directory.
        await temp.create_();
      } finally {
        try {
          await temp.parent.parent.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('File.create_ creates nested files recursively', () async {
      final temp = File(join(
        Directory.systemTemp.path,
        'safe_local_storage_file_${DateTime.now().microsecondsSinceEpoch}',
        'sub1',
        'test.txt',
      ));
      try {
        expect(await temp.exists_(), isFalse);
        await temp.create_();
        expect(await temp.exists_(), isTrue);
        expect(temp.existsSync_(), isTrue);
        // Call create_ again on existing file.
        await temp.create_();
      } finally {
        try {
          await temp.parent.parent.delete(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('non-existent entity handling', () {
    test('exists_ and existsSync_ return false on non-existent paths without throwing', () async {
      final nonExistent = Directory(join(
        Directory.systemTemp.path,
        'non_existent_folder_${DateTime.now().microsecondsSinceEpoch}',
      ));
      expect(await nonExistent.exists_(), isFalse);
      expect(nonExistent.existsSync_(), isFalse);
    });
  });
}
