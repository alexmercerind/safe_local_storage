import 'dart:io';
import 'package:test/test.dart';
import 'package:safe_local_storage/safe_local_storage.dart';

void main() {
  group('file_system path utilities', () {
    if (Platform.isWindows) {
      test('addPrefix handles Windows drive roots', () {
        expect(addPrefix(r'C:\'), equals(r'\\?\C:\'));
        expect(addPrefix(r'C:'), equals(r'\\?\C:\'));
        expect(addPrefix(r'C:/'), equals(r'\\?\C:\'));
        expect(addPrefix(r'\\?\C:\'), equals(r'\\?\C:\'));
        expect(addPrefix(r'\\?\C:'), equals(r'\\?\C:\'));
        expect(addPrefix(r'c:\'), equals(r'\\?\c:\'));
      });

      test('addPrefix handles normal Windows directories and files', () {
        expect(addPrefix(r'C:\foo\bar'), equals(r'\\?\C:\foo\bar'));
        expect(addPrefix(r'C:\foo\bar\'), equals(r'\\?\C:\foo\bar'));
        expect(addPrefix(r'C:/foo/bar/'), equals(r'\\?\C:\foo\bar'));
      });

      test('removePrefix handles Windows drive roots', () {
        expect(removePrefix(r'\\?\C:\'), equals(r'C:\'));
        expect(removePrefix(r'\\?\C:'), equals(r'C:\'));
        expect(removePrefix(r'C:\'), equals(r'C:\'));
      });

      test('removePrefix handles normal Windows directories and files', () {
        expect(removePrefix(r'\\?\C:\foo\bar'), equals(r'C:\foo\bar'));
        expect(removePrefix(r'\\?\C:\foo\bar\'), equals(r'C:\foo\bar'));
      });

      test('removeTrailingSlash preserves Windows drive roots', () {
        expect(removeTrailingSlash(r'C:\'), equals(r'C:\'));
        expect(removeTrailingSlash(r'\\?\C:\'), equals(r'\\?\C:\'));
        expect(removeTrailingSlash(r'C:\foo\'), equals(r'C:\foo'));
      });
    }

    test('removeTrailingSlash preserves POSIX root', () {
      if (!Platform.isWindows) {
        expect(removeTrailingSlash('/'), equals('/'));
      }
    });
  });

  group('FileSystemEntityExtension exists_ & existsSync_', () {
    if (Platform.isWindows) {
      test('exists_ and existsSync_ on Windows drive roots', () async {
        final cDrive = Directory(r'C:\');
        expect(await cDrive.exists_(), isTrue);
        expect(cDrive.existsSync_(), isTrue);

        final cDriveWithoutSlash = Directory(r'C:');
        expect(await cDriveWithoutSlash.exists_(), isTrue);
        expect(cDriveWithoutSlash.existsSync_(), isTrue);

        final cDrivePrefixed = Directory(r'\\?\C:\');
        expect(await cDrivePrefixed.exists_(), isTrue);
        expect(cDrivePrefixed.existsSync_(), isTrue);
      });

      test('FS.type_ and FS.typeSync_ on Windows drive roots', () async {
        expect(await FS.type_(r'C:\'), equals(FileSystemEntityType.directory));
        expect(FS.typeSync_(r'C:\'), equals(FileSystemEntityType.directory));
        expect(await FS.type_(r'C:'), equals(FileSystemEntityType.directory));
        expect(FS.typeSync_(r'C:'), equals(FileSystemEntityType.directory));
      });
    }

    test('exists_ and existsSync_ on non-existent path returns false without throwing', () async {
      final nonExistent = Directory(Platform.isWindows
          ? r'\\?\Z:\non_existent_directory_safe_local_storage_test_123'
          : '/non_existent_directory_safe_local_storage_test_123');

      expect(await nonExistent.exists_(), isFalse);
      expect(nonExistent.existsSync_(), isFalse);
    });
  });
}
