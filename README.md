# [package:safe_local_storage](https://github.com/alexmercerind/safe_local_storage)

🗃️ A safe caching library to read/write values on local storage.

## Features

- **Atomic :** A `write` either succeeds completely or fails completely, cache is never left in corrupt state.
- **Safe to concurrency :** Multiple concurrent async `write` operations keep correct order & isolation is maintained.
- **Roll-back support :** In case of corruption, old state will be restored & saved values will remain safe. Safety to:
  - Closing application in the middle of on-going `write`.
  - Forcibly killing process.
  - Power failure.
- **Minimal :** 100% Dart, are no native calls. Just reads/writes your values in a very safe manner.
- **Customizable cache location :** You decide where your app's cache is kept, matching your project's model.
- **Isolate friendly :** Data is deserialized/serialized on another isolate during `read` or `write`.
- **Well tested :** [Learn more](https://github.com/harmonoid/safe_local_storage/blob/master/test/safe_local_storage_test.dart).
- **Correctly handles long file-paths on Windows :** [Learn more](https://github.com/dart-lang/sdk/issues/27825).

## Install

Add in your `pubspec.yaml`.

```yaml
dependencies:
  safe_local_storage: ^1.0.0
```

## Example

### Basics

A minimal example to get started.

```dart
/// Create a [SafeLocalStorage] object, decide where you want to keep your cache.
final storage = SafeLocalStorage('/path/to/your/cache/file.json');
/// Write your data, will be stored locally.
await storage.write(
  {
    'foo': 'bar',
  },
);
/// Perform read.
final data = await storage.read();
print(data);
/// {foo: bar}
```

### Fallback

Set the fallback value. This is returned by the `read` if:

- No existing cache is found.
- Cache was found in corrupt state & roll-back failed (never going to happen).

```dart
final storage = SafeLocalStorage(
  '/path/to/your/cache/file.json',
  /// Set the [fallback] value for this instance of cache storage.
  fallback: {
    'default_value': 0,
    'msg': 'No existing cache found.',
  },
);
print(await storage.read());
/// {default_value: 0, msg: No existing cache found.}
```

### Delete

Remove the cache file & clean-up the transaction records & history.

```dart
final storage = SafeLocalStorage(
  '/path/to/your/cache/file.json',
);
await storage.write(
  {
    'foo': 'bar',
  },
);
await storage.delete();
```

### Location

Giving raw control over the cache's location is a good thing for some.

Generally speaking, you can use this getter to get location for a new cache file in your app:

Still, it's not a good idea to store all the values in one single file.

```dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Create [SafeLocalStorage].
final storage = SafeLocalStorage(location);

/// A getter for default cache location, specific to your app.
String get location {
  switch (Platform.operatingSystem) {
    case 'windows':
      return join(
        Platform.environment['USERPROFILE']!,
        'AppData',
        'Roaming',
        'YOUR_APP_NAME',
        'cache.json',
      );
    case 'linux':
      return join(
        Platform.environment['HOME']!,
        '.config',
        'YOUR_APP_NAME',
        'cache.json',
      );
    case 'android':
      /// From `package:path_provider`.
      return getExternalStorageDirectory();
    default:
      throw Exception(
          'No implementation found for platform: ${Platform.operatingSystem}');
  }
}
```

## Why

First of all, this is built with requirements of [Harmonoid](https://github.com/harmonoid/harmonoid) in mind.

I'm aware there are _good_ solutions available like [`package:isar`](https://pub.dev/packages/isar) & many more.

It's quite hard to believe but [`package:shared_preferences`](https://pub.dev/packages/shared_preferences) on Windows & Linux, just [treats your cache like any normal text file](https://github.com/flutter/plugins/blob/main/packages/shared_preferences/shared_preferences_windows/lib/shared_preferences_windows.dart). This makes your app's cache very-very prone to get corrupted. Your saved values will eventually get corrupted (with higher chances if you store large amount data) & there will be no way to bring it back. Secondly, it just keeps all the values in one single file, making the matters even worse. There's no atomicity, isolation or roll-back support. It's a really bad choice when building something useful, atleast on Windows or Linux.

The [`package:isar`](https://pub.dev/packages/isar) is quite good & seems well built, but I don't need Rust (or additional shared libraries) for something as simple as storing non-relational data. Dart is a natively compiled language & quite fast for the purpose.

There are other packages which can be used to store data on local storage, but they don't provide other things [Harmonoid](https://github.com/harmonoid/harmonoid) wanted:

- Control over the location where app stores it's data or cache.
- Strong protection to cache corruption due to process-kill, closing app or power failure etc.
- No query support etc. Just read/write data & do it safely.
- Being as less platform-specific as possible.

Harmonoid's issues fixed by [`package:safe_local_storage`](https://github.com/harmonoid/safe_local_storage):

- [Harmonoid](https://github.com/harmonoid/harmonoid) caches user's huge large music library & other important configuration/settings.
- Cache needs to remain on disk persistently after first-time indexing.
- It needs to be updated after any new music files are added/deleted (which is quite often).
- Ensuring that the cache remains in readable (un-corrupt) state is quite important.
- User ability to manually edit the configuration files using a simple text-editor outside app.

## Performance

There are no query operations etc. It's just for saving persistent app data. Few things to keep in mind:

- Upon every `write` operation on a `SafeLocalStorage` instance, the data in it is updated & saved on disk atomically & permanently.
- A history of past 10 transactions in maintained to support roll-back. Upon any failure / corruption, this will be used to restore old state.
- The chunk of data (passed as argument to `write` method) is serialized on another `Isolate`.
- The deletion of redundant transaction history is done asynchronously in background on another `Isolate`.
- Due to additional operations involved in maintaining `write` history records, ensuring mutual exclusion & atomicity, there _can_ be some delay introduced compared to just writing into a [`File`](https://api.dart.dev/stable/2.18.1/dart-io/File-class.html). But, this trade-off is certainly better than having corrupted app-data.

## License

Copyright © 2022, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](https://github.com/harmonoid/safe_local_storage/blob/master/LICENSE) file.
